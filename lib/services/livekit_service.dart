// 1. Dart
import 'dart:async';
import 'dart:convert';

// 2. Packages
// 2.1. Flutter Packages
import 'package:flutter/foundation.dart';
// 2.2. Third-Party Packages
import 'package:livekit_client/livekit_client.dart' as lk;

// 3. Project
import '/config/app_config.dart';


// class LiveKitException implements Exception {
//   final String message;
//   LiveKitException(this.message);

//   @override
//   String toString() => '###>>> LiveKitException: $message';
// }

class LiveKitState {
  final bool connecting;
  final bool connected;
  final bool microphoneEnabled;
  final bool localMicrophonePublished;
  final int remoteAudioSubscribers;
  final bool remoteAudioPlaying;
  final String? assistantStage;
  final String? activeSegmentId;
  final String? error;
  final String? lastEvent;

  const LiveKitState({
    required this.connecting,
    required this.connected,
    required this.microphoneEnabled,
    required this.localMicrophonePublished,
    required this.remoteAudioSubscribers,
    required this.remoteAudioPlaying,
    this.assistantStage,
    this.activeSegmentId,
    this.error,
    this.lastEvent,
  });

  factory LiveKitState.initial() {
    return const LiveKitState(
      connecting: false,
      connected: false,
      microphoneEnabled: false,
      localMicrophonePublished: false,
      remoteAudioSubscribers: 0,
      remoteAudioPlaying: false,
      assistantStage: null,
      activeSegmentId: null,
      error: null,
      lastEvent: null,
    );
  }

  LiveKitState copyWith({
    bool? connecting,
    bool? connected,
    bool? microphoneEnabled,
    bool? localMicrophonePublished,
    int? remoteAudioSubscribers,
    bool? remoteAudioPlaying,
    String? assistantStage,
    String? activeSegmentId,
    String? error,
    bool clearError = false,
    bool clearAssistantStage = false,
    bool clearActiveSegment = false,
    String? lastEvent,
  }) {
    return LiveKitState(
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      localMicrophonePublished:
          localMicrophonePublished ?? this.localMicrophonePublished,
      remoteAudioSubscribers:
          remoteAudioSubscribers ?? this.remoteAudioSubscribers,
      remoteAudioPlaying: remoteAudioPlaying ?? this.remoteAudioPlaying,
      assistantStage: clearAssistantStage
          ? null
          : (assistantStage ?? this.assistantStage),
      activeSegmentId: clearActiveSegment
          ? null
          : (activeSegmentId ?? this.activeSegmentId),
      error: clearError ? null : (error ?? this.error),
      lastEvent: lastEvent ?? this.lastEvent,
    );
  }
}

class LiveKitDataMessage {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime receivedAt;
  final String? participantIdentity;

  const LiveKitDataMessage({
    required this.type,
    required this.payload,
    required this.receivedAt,
    this.participantIdentity,
  });
}

class LiveKitService {
  LiveKitService()
    : _room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: false,
          dynacast: true,
          defaultAudioCaptureOptions: lk.AudioCaptureOptions(
            echoCancellation: true,
            autoGainControl: true,
            noiseSuppression: true,
          ),
          defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true),
          defaultVideoPublishOptions: lk.VideoPublishOptions(simulcast: false),
        ),
      );

  final lk.Room _room;
  lk.CancelListenFunc? _roomEventsCancel;
  final StreamController<LiveKitDataMessage> _dataController =
      StreamController<LiveKitDataMessage>.broadcast();
  bool _audioPlaybackUnlocked = false;
  bool _audioUnlockInProgress = false;
  bool _remoteAudioMuted = false;
  Timer? _micWatchdog;
  bool _micPublishInProgress = false;

  final ValueNotifier<LiveKitState> state = ValueNotifier<LiveKitState>(
    LiveKitState.initial(),
  );

  bool get isConnected => _room.connectionState == lk.ConnectionState.connected;
  Stream<LiveKitDataMessage> get dataStream => _dataController.stream;

  Future<void> connect({required String url, required String token}) async {
    if (state.value.connecting) {
      return;
    }
    state.value = state.value.copyWith(
      connecting: true,
      clearError: true,
      lastEvent: 'Conectando ao LiveKit...',
    );

    try {
      await _room.connect(
        url,
        token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: false),
      );
      await _observeRoomEvents();
      await _enforceSubscriptions();

      final localParticipant = _room.localParticipant;
      final micEnabled = localParticipant?.isMicrophoneEnabled() ?? false;
      final micPublished = _isLocalMicrophonePublished();
      state.value = state.value.copyWith(
        connecting: false,
        connected: true,
        microphoneEnabled: micEnabled,
        localMicrophonePublished: micPublished,
        remoteAudioSubscribers: _countRemoteAudioTracks(),
        lastEvent: 'Conectado a sala ${_room.name ?? '-'}',
        clearError: true,
      );
    } catch (error, stackTrace) {
      debugPrint('LiveKit connect error: $error');
      debugPrint(stackTrace.toString());
      state.value = state.value.copyWith(
        connecting: false,
        connected: false,
        microphoneEnabled: false,
        localMicrophonePublished: false,
        error: 'Falha ao conectar no LiveKit: $error',
        lastEvent: 'Erro: $error',
      );
      rethrow;
    }
  }

  Future<void> _ensureLocalMicrophonePublished({
    bool forceToggle = false,
  }) async {
    final localParticipant = _room.localParticipant;
    if (localParticipant == null || _micPublishInProgress) {
      return;
    }
    final hasPublication = localParticipant.audioTrackPublications.isNotEmpty;
    final micEnabled = localParticipant.isMicrophoneEnabled();
    if (hasPublication && micEnabled) {
      state.value = state.value.copyWith(
        microphoneEnabled: true,
        localMicrophonePublished: true,
      );
      return;
    }
    _micPublishInProgress = true;
    try {
      if (forceToggle && micEnabled) {
        await localParticipant.setMicrophoneEnabled(false);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!micEnabled || forceToggle) {
        await localParticipant.setMicrophoneEnabled(true);
      }
      try {
        await _room.events.waitFor<lk.LocalTrackPublishedEvent>(
          duration: const Duration(seconds: 4),
        );
      } catch (_) {}

      final published = localParticipant.audioTrackPublications.isNotEmpty;
      final enabledNow = localParticipant.isMicrophoneEnabled();
      state.value = state.value.copyWith(
        microphoneEnabled: enabledNow,
        localMicrophonePublished: published,
        lastEvent: published
            ? 'Microfone publicado no LiveKit.'
            : 'Microfone nao publicado. Toque em "Ativar mic".',
      );
    } catch (error) {
      state.value = state.value.copyWith(
        lastEvent: 'Falha ao publicar microfone: $error',
        microphoneEnabled: false,
        localMicrophonePublished: false,
      );
    } finally {
      _micPublishInProgress = false;
    }
  }

  Future<void> disconnect() async {
    _stopMicrophoneWatchdog();
    final cancel = _roomEventsCancel;
    _roomEventsCancel = null;
    cancel?.call();
    if (isConnected) {
      await _room.disconnect();
    }
    state.value = LiveKitState.initial().copyWith(
      lastEvent: 'Desconectado da sala.',
      clearError: true,
    );
    _audioPlaybackUnlocked = false;
    _remoteAudioMuted = false;
  }

  Future<void> ensureAudioPlayback() async {
    if (_audioPlaybackUnlocked || _audioUnlockInProgress) {
      return;
    }
    _audioUnlockInProgress = true;
    try {
      await _room.startAudio();
    } catch (error) {
      debugPrint('LiveKit startAudio error: $error');
      state.value = state.value.copyWith(
        lastEvent: 'Permissao de audio falhou: $error',
      );
    } finally {
      _audioUnlockInProgress = false;
    }
  }

  Future<void> sendData(
    Map<String, dynamic> message, {
    bool reliable = true,
  }) async {
    final participant = _room.localParticipant;
    if (participant == null) {
      return;
    }
    try {
      final encoded = jsonEncode(message);
      final buffer = Uint8List.fromList(utf8.encode(encoded));
      await participant.publishData(
        buffer,
        reliable: reliable,
      );
    } catch (error, stackTrace) {
      debugPrint('LiveKit sendData error: $error');
      debugPrint(stackTrace.toString());
    }
  }

  Future<void> toggleMicrophone(bool enabled) async {
    if (!isConnected) return;
    final localParticipant = _room.localParticipant;
    if (localParticipant == null) return;

    await localParticipant.setMicrophoneEnabled(enabled);
    if (enabled) {
      await _ensureLocalMicrophonePublished(forceToggle: true);
      _startMicrophoneWatchdog();
    } else {
      _stopMicrophoneWatchdog();
    }

    state.value = state.value.copyWith(
      microphoneEnabled: enabled,
      localMicrophonePublished: enabled
          ? _isLocalMicrophonePublished()
          : false,
      lastEvent: enabled
          ? 'Microfone publicado no LiveKit.'
          : 'Microfone pausado no LiveKit.',
    );
  }

  Future<void> setRemoteAudioMuted(bool muted) async {
    if (_remoteAudioMuted == muted) {
      return;
    }
    _remoteAudioMuted = muted;
    for (final participant in _room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track is lk.RemoteAudioTrack) {
          track.mediaStreamTrack.enabled = !muted;
        }
      }
    }
    state.value = state.value.copyWith(
      lastEvent: muted
          ? 'Audio remoto silenciado (usuario falando).'
          : 'Audio remoto reativado.',
    );
  }

  Future<void> _observeRoomEvents() async {
    final cancelPrevious = _roomEventsCancel;
    if (cancelPrevious != null) {
      await Future.sync(cancelPrevious);
    }
    _roomEventsCancel = _room.events.listen(
      (event) => unawaited(_handleRoomEvent(event)),
    );
  }

  Map<String, dynamic>? _decodeDataMessage(List<int> data) {
    try {
      final jsonText = utf8.decode(data);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (error) {
      debugPrint('Falha ao decodificar mensagem LiveKit: $error');
    }
    return null;
  }

  Map<String, dynamic> _ensureMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  void _handleAssistantStatus(Map<String, dynamic> payload) {
    final stage = payload['stage'] as String?;
    final segmentId = payload['segmentId'] as String?;
    if (stage == null) {
      return;
    }

    final current = state.value;
    String? nextSegmentId = current.activeSegmentId;
    if (stage == 'idle' ||
        stage == 'completed' ||
        stage == 'error' ||
        stage == 'skipped') {
      nextSegmentId = null;
    } else if (segmentId != null && segmentId.isNotEmpty) {
      nextSegmentId = segmentId;
    }

    final previousStage = current.assistantStage;
    final bool nextAudioPlaying = stage == 'speaking'
        ? true
        : (stage == 'idle' || stage == 'error' || stage == 'completed')
        ? false
        : current.remoteAudioPlaying;

    final nextState = current.copyWith(
      assistantStage: stage,
      activeSegmentId: nextSegmentId,
      remoteAudioPlaying: nextAudioPlaying,
      lastEvent: stage != previousStage
          ? 'Assistente: $stage'
          : current.lastEvent,
    );
    state.value = nextState;
  }

  Future<void> _handleRoomEvent(lk.RoomEvent event) async {
    if (event is lk.TrackSubscribedEvent) {
      if (event.publication.kind == lk.TrackType.AUDIO) {
        if (_isAssistant(event.participant)) {
          await ensureAudioPlayback();
          await event.track.start();
        } else {
          await event.publication.unsubscribe();
        }
      }
    }

    if (event is lk.TrackPublishedEvent) {
      if (event.publication.kind == lk.TrackType.AUDIO) {
        await _enforceSubscriptions();
        state.value = state.value.copyWith(
          remoteAudioSubscribers: _countRemoteAudioTracks(),
        );
      }
    }

    if (event is lk.LocalTrackPublishedEvent) {
      if (event.publication.kind == lk.TrackType.AUDIO) {
        state.value = state.value.copyWith(
          microphoneEnabled: true,
          localMicrophonePublished: true,
          lastEvent: 'Microfone publicado no LiveKit.',
        );
      }
    }

    if (event is lk.LocalTrackUnpublishedEvent) {
      if (event.publication.kind == lk.TrackType.AUDIO) {
        state.value = state.value.copyWith(
          microphoneEnabled: false,
          localMicrophonePublished: false,
          lastEvent: 'Microfone removido do LiveKit.',
        );
      }
    }

    if (event is lk.DataReceivedEvent) {
      final decoded = _decodeDataMessage(event.data);
      if (decoded == null) {
        return;
      }
      final type = decoded['type'] as String? ?? 'unknown';
      final payload = _ensureMap(decoded['payload']);
      final message = LiveKitDataMessage(
        type: type,
        payload: payload,
        participantIdentity: event.participant?.identity,
        receivedAt: DateTime.now(),
      );
      if (!_dataController.isClosed) {
        _dataController.add(message);
      }
      if (type == 'assistant_status') {
        _handleAssistantStatus(payload);
      }
      return;
    }

    if (event is lk.AudioPlaybackStatusChanged) {
      _audioPlaybackUnlocked = event.isPlaying;
      state.value = state.value.copyWith(
        remoteAudioPlaying: event.isPlaying,
        lastEvent: event.isPlaying
            ? 'Navegador reproduzindo audio remoto.'
            : 'Reproducao de audio remoto bloqueada.',
      );
    }

    if (event is lk.ParticipantConnectedEvent) {
      state.value = state.value.copyWith(
        lastEvent: 'Participante entrou: ${event.participant.identity}',
      );
    }

    if (event is lk.ParticipantDisconnectedEvent) {
      state.value = state.value.copyWith(
        lastEvent: 'Participante saiu: ${event.participant.identity}',
      );
    }

    if (event is lk.RoomDisconnectedEvent) {
      _stopMicrophoneWatchdog();
      state.value = state.value.copyWith(
        connected: false,
        connecting: false,
        microphoneEnabled: false,
        localMicrophonePublished: false,
        remoteAudioSubscribers: 0,
        remoteAudioPlaying: false,
        clearAssistantStage: true,
        clearActiveSegment: true,
        lastEvent:
            'Sala desconectada (${event.reason?.toString() ?? 'motivo desconhecido'})',
      );
      return;
    }

    if (event is lk.TrackSubscribedEvent ||
        event is lk.TrackUnsubscribedEvent ||
        event is lk.TrackPublishedEvent ||
        event is lk.ParticipantConnectedEvent ||
        event is lk.ParticipantDisconnectedEvent) {
      await _enforceSubscriptions();
      state.value = state.value.copyWith(
        remoteAudioSubscribers: _countRemoteAudioTracks(),
      );
    }
  }

  bool _isLocalMicrophonePublished() {
    final localParticipant = _room.localParticipant;
    if (localParticipant == null) {
      return false;
    }
    return localParticipant.audioTrackPublications.isNotEmpty;
  }

  void _startMicrophoneWatchdog() {
    _micWatchdog?.cancel();
    _micWatchdog = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!isConnected || _micPublishInProgress) {
        return;
      }
      final localParticipant = _room.localParticipant;
      if (localParticipant == null) {
        return;
      }
      if (!localParticipant.isMicrophoneEnabled()) {
        return;
      }
      if (localParticipant.audioTrackPublications.isNotEmpty) {
        return;
      }
      await _ensureLocalMicrophonePublished(forceToggle: true);
    });
  }

  void _stopMicrophoneWatchdog() {
    _micWatchdog?.cancel();
    _micWatchdog = null;
  }

  bool _isAssistant(lk.Participant? participant) {
    return participant?.identity == AppConfig.assistantIdentity;
  }

  Future<void> _enforceSubscriptions() async {
    // Unsubscribe from any non-assistant audio tracks
    for (final participant in _room.remoteParticipants.values) {
      final isAssistant = _isAssistant(participant);
      for (final pub in participant.audioTrackPublications) {
        if (isAssistant && !pub.subscribed) {
          await pub.subscribe();
        } else if (!isAssistant && pub.subscribed) {
          await pub.unsubscribe();
        }
      }
    }
  }

  int _countRemoteAudioTracks() {
    var count = 0;
    for (final participant in _room.remoteParticipants.values) {
      count += participant.audioTrackPublications
          .where((pub) => pub.subscribed)
          .length;
    }
    return count;
  }

  Future<void> dispose() async {
    _stopMicrophoneWatchdog();
    final cancel = _roomEventsCancel;
    _roomEventsCancel = null;
    cancel?.call();
    await _room.dispose();
    await _dataController.close();
    state.dispose();
  }
}
