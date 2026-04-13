// SenaiAeroAIApp

// 1. Dart
import 'dart:async';

// 2. Packages
// 2.1. Flutter Packages
import 'package:flutter/material.dart';
// 2.2. Third-Party Packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// 3. Project
import '/config/app_config.dart';
import '/chat/models/chat_models.dart';
import '/firebase_options.dart';
import '/services/audio_recorder_service.dart';
import '/services/livekit_service.dart';
import '/session/app_session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('\n===>>>Firebase initialized: ${Firebase.app().name}\n');

  // Try Activate Firebase App Check with reCAPTCHA v3
  try {
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaV3Provider(AppConfig.reCaptchaV3SiteKey),
    );
    debugPrint('\n===>>>Firebase App Check activated (ReCAPTCHA v3).\n');
  } catch (e, stackTrace) {
    debugPrint('\n===>>>Failed to activate Firebase App Check: $e\n');
    debugPrint(
      '\n===>>>Error activating Firebase App Check\ne: $e\nstackTrace: ${stackTrace.toString()}\n',
    );
  }

  runApp(const SenaiAeroAIApp());
}

class SenaiAeroAIApp extends StatefulWidget {
  const SenaiAeroAIApp({super.key});

  @override
  State<SenaiAeroAIApp> createState() => _SenaiAeroAIAppState();
}

class _SenaiAeroAIAppState extends State<SenaiAeroAIApp> {
  late final AppSessionController _sessionController;

  @override
  void initState() {
    super.initState();
    _sessionController = AppSessionController();
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'senAI Simulador Aerogerador',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: AppRoot(session: _sessionController),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppRoot extends StatelessWidget {
  final AppSessionController session;
  const AppRoot({required this.session, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, child) {
        if (session.isReadyForMain) {
          return ConversationScreen(session: session);
        }
        return LoginScreen(session: session);
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  final AppSessionController session;
  const LoginScreen({required this.session, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final progress = session.progressMessage ?? 'Preparando ambiente...';
    final error = session.lastErrorMessage;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mentora senAI - Sim. VR',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _LoginStatusRow(
                    label: 'Autenticacao',
                    value: session.authStatusLabel,
                  ),
                  const SizedBox(height: 8),
                  _LoginStatusRow(
                    label: 'App Check',
                    value: session.appCheckStatusLabel,
                  ),
                  const SizedBox(height: 8),
                  _LoginStatusRow(
                    label: 'Conexoes',
                    value: session.connectionStatusLabel,
                  ),
                  const SizedBox(height: 16),
                  if (session.loginFormVisible) ...[
                    TextField(
                      controller: session.emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: session.passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Se nao existir conta para este email, ela sera criada automaticamente.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(progress),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: session.busy
                          ? null
                          : () => session.startSession(userInitiated: true),
                      child: session.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Efetue o login utilizando o provedor habilitado no Firebase antes de continuar. O app avancara automaticamente apos a autenticacao e a conexao com os servicos.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginStatusRow extends StatelessWidget {
  final String label;
  final String value;
  const _LoginStatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Expanded(child: Text(value, maxLines: 2)),
      ],
    );
  }
}

class ConversationScreen extends StatefulWidget {
  final AppSessionController session;
  const ConversationScreen({required this.session, super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final AppSessionController _session;
  LiveKitState _liveKitState = LiveKitState.initial();
  StreamSubscription<LiveKitDataMessage>? _liveKitDataSub;
  bool? _pendingLiveKitMicEnabled;
  String? _lastLiveKitEventLogged;
  Map<String, dynamic>? _lastAssistantStatus;
  final Map<String, DateTime> _segmentStartTimes = {};
  Duration? _lastAssistantSegmentDuration;
  final ScrollController _chatScrollController = ScrollController();
  final List<ChatSession> _chatSessions = [];
  ChatSession? _activeChat;
  List<ChatMessage> _chatMessages = [];
  bool _chatListLoading = true;
  bool _messagesLoading = true;
  bool _drawerOpen = false;
  StreamSubscription<List<ChatSession>>? _chatListSubscription;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  String? _messageSubscriptionChatId;
  String? _chatUserId;
  final TextEditingController _sceneController = TextEditingController();
  bool _sendingScene = false;
  void Function(void Function())? _sceneSheetSetState;

  // ---------------------------------------------------------------------------
  // Chat persistence + drawer state
  // ---------------------------------------------------------------------------

  void _listenForChats() {
    final user = _session.currentUser;
    if (user == null) {
      return;
    }
    if (_chatUserId == user.uid && _chatListSubscription != null) {
      return;
    }
    _chatUserId = user.uid;
    _messageSubscription?.cancel();
    _chatListSubscription?.cancel();
    setState(() {
      _chatListLoading = true;
    });
    _chatListSubscription = _session.chatRepository
        .watchChats(userId: user.uid)
        .listen(
          (sessions) {
            ChatSession? updatedActive;
            if (_activeChat != null) {
              updatedActive = _locateSession(sessions, _activeChat!.id);
            }
            updatedActive ??= sessions.isNotEmpty ? sessions.first : null;
            setState(() {
              _chatSessions
                ..clear()
                ..addAll(sessions);
              _activeChat = updatedActive;
              _chatListLoading = false;
            });
            if (updatedActive != null) {
              _subscribeToMessages(updatedActive);
            } else {
              _messageSubscription?.cancel();
              setState(() {
                _chatMessages = [];
                _messagesLoading = false;
              });
            }
          },
          onError: (error) {
            debugPrint('Chat list stream error: $error');
            setState(() {
              _chatListLoading = false;
            });
          },
        );
  }

  void _subscribeToMessages(ChatSession session) {
    final user = _session.currentUser;
    if (user == null) {
      return;
    }
    if (_messageSubscriptionChatId == session.id) {
      return;
    }
    _messageSubscription?.cancel();
    _messageSubscriptionChatId = session.id;
    setState(() {
      _messagesLoading = true;
    });
    _messageSubscription = _session.chatRepository
        .watchMessages(userId: user.uid, chatId: session.id)
        .listen(
          (messages) {
            setState(() {
              _chatMessages = messages;
              _messagesLoading = false;
            });
            _scrollMessagesToEnd();
            unawaited(_sendChatContextToWorker());
          },
          onError: (error) {
            debugPrint('Messages stream error: $error');
            setState(() {
              _messagesLoading = false;
            });
          },
        );
  }

  Future<void> _setActiveChat(ChatSession session) async {
    setState(() {
      _activeChat = session;
      _drawerOpen = false;
      _chatMessages = [];
    });
    _subscribeToMessages(session);
  }

  Future<void> _startNewChat() async {
    final user = _session.currentUser;
    if (user == null) {
      return;
    }
    setState(() {
      _messagesLoading = true;
    });
    try {
      final chat = await _session.chatRepository.createChat(userId: user.uid);
      setState(() {
        _activeChat = chat;
        _drawerOpen = false;
        _chatMessages = [];
      });
      _subscribeToMessages(chat);
    } catch (error) {
      debugPrint('Falha ao criar chat: $error');
      setState(() {
        _messagesLoading = false;
      });
    }
  }

  Future<ChatSession?> _ensureActiveChat() async {
    final user = _session.currentUser;
    if (user == null) {
      return null;
    }
    if (_activeChat != null) {
      return _activeChat;
    }
    try {
      final chat = await _session.chatRepository.createChat(userId: user.uid);
      setState(() {
        _activeChat = chat;
        _chatMessages = [];
      });
      _subscribeToMessages(chat);
      return chat;
    } catch (error) {
      debugPrint('Falha ao garantir chat ativo: $error');
      return null;
    }
  }

  Future<void> _persistChatMessage(
    ChatRole role,
    String text, {
    Map<String, dynamic>? metadata,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final user = _session.currentUser;
    if (user == null) {
      return;
    }
    final chat = await _ensureActiveChat();
    if (chat == null) {
      return;
    }
    try {
      await _session.chatRepository.appendMessage(
        userId: user.uid,
        chatId: chat.id,
        message: ChatMessage(
          id: '',
          role: role,
          text: trimmed,
          createdAt: DateTime.now(),
          metadata: metadata,
        ),
      );
    } catch (error) {
      debugPrint('Falha ao salvar mensagem: $error');
    }
  }

  void _toggleDrawer([bool? open]) {
    setState(() {
      _drawerOpen = open ?? !_drawerOpen;
    });
  }

  void _scrollMessagesToEnd() {
    if (!_chatScrollController.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) {
        return;
      }
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  ChatSession? _locateSession(List<ChatSession> sessions, String id) {
    for (final chat in sessions) {
      if (chat.id == id) {
        return chat;
      }
    }
    return null;
  }

  Future<void> _sendChatContextToWorker() async {
    if (!_session.connected) {
      return;
    }
    final chat = _activeChat;
    if (chat == null) {
      return;
    }
    final messages = _buildContextMessages();
    final payload = {
      'type': 'chat_context',
      'payload': {'chatId': chat.id, 'messages': messages},
    };
    try {
      await _session.liveKitService.sendData(payload);
    } catch (error, stackTrace) {
      debugPrint('Falha ao enviar contexto ao worker: $error');
      debugPrint(stackTrace.toString());
    }
  }

  List<Map<String, String>> _buildContextMessages() {
    const maxMessages = 120;
    final filtered = _chatMessages
        .where((m) => m.role != ChatRole.system)
        .toList(growable: false);
    final start = filtered.length > maxMessages
        ? filtered.length - maxMessages
        : 0;
    final slice = filtered.sublist(start);
    return slice
        .map(
          (message) => {
            'role': message.role.name,
            'text': message.text.length > 1200
                ? message.text.substring(0, 1200)
                : message.text,
          },
        )
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Device microphone + audio control
  // ---------------------------------------------------------------------------
  final AudioRecorderService _audioRecorder = AudioRecorderService();
  bool _isRecording = false;
  bool _micBusy = false;
  String? _micError;
  Duration? _lastRecordingDuration;
  bool _firstUserGestureHandled = false;

  // ---------------------------------------------------------------------------
  // UI + conversation state (Flutter-only)
  // ---------------------------------------------------------------------------
  final List<_Message> _messages = [
    const _Message(role: 'system', text: 'Bem-vindo! Preparando o app...'),
  ];

  // ---------------------------------------------------------------------------
  // Lifecycle wiring (links Flutter lifecycle with the external services)
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _liveKitState = _session.liveKitService.state.value;
    _session.liveKitService.state.addListener(_onLiveKitStateChanged);
    _session.addListener(_handleSessionChanged);
    _liveKitDataSub = _session.liveKitService.dataStream.listen(
      _handleLiveKitData,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForChats());
  }

  @override
  void dispose() {
    _session.removeListener(_handleSessionChanged);
    unawaited(_audioRecorder.dispose());
    final dataSub = _liveKitDataSub;
    if (dataSub != null) {
      unawaited(dataSub.cancel());
    }
    _session.liveKitService.state.removeListener(_onLiveKitStateChanged);
    _chatListSubscription?.cancel();
    _messageSubscription?.cancel();
    _chatScrollController.dispose();
    _sceneController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Firebase Auth + App Check (external dependency)
  // ---------------------------------------------------------------------------

  /// Mirrors LiveKit SDK state into the widget tree and logs main events.
  void _onLiveKitStateChanged() {
    if (!mounted) return;
    final newState = _session.liveKitService.state.value;
    setState(() {
      _liveKitState = newState;
      if (!newState.connected) {
        _pendingLiveKitMicEnabled = null;
        _firstUserGestureHandled = false;
      } else if (_pendingLiveKitMicEnabled != null) {
        final pending = _pendingLiveKitMicEnabled!;
        if (pending) {
          if (newState.microphoneEnabled && newState.localMicrophonePublished) {
            _pendingLiveKitMicEnabled = null;
          }
        } else {
          if (!newState.microphoneEnabled &&
              !newState.localMicrophonePublished) {
            _pendingLiveKitMicEnabled = null;
          }
        }
      }
    });
    final event = newState.lastEvent;
    if (event != null && event != _lastLiveKitEventLogged) {
      _lastLiveKitEventLogged = event;
      _appendMessage('system', 'LiveKit: $event');
    }
  }

  /// Consumes data messages sent by the assistant (status, transcript, etc.).
  void _handleLiveKitData(LiveKitDataMessage message) {
    if (!mounted) return;
    switch (message.type) {
      case 'assistant_status':
        final stage = message.payload['stage'] as String?;
        final segmentId = message.payload['segmentId'] as String?;
        String? errorDetail;
        setState(() {
          _lastAssistantStatus = message.payload;
          if (stage == 'processing' && segmentId != null) {
            _segmentStartTimes[segmentId] = message.receivedAt;
          }
          if (stage == 'completed' || stage == 'idle') {
            final totalMs = (message.payload['totalDurationMs'] as num?)
                ?.toDouble();
            Duration? computedDuration;
            if (totalMs != null) {
              computedDuration = Duration(milliseconds: totalMs.round());
            } else if (segmentId != null) {
              final startedAt = _segmentStartTimes[segmentId];
              if (startedAt != null) {
                computedDuration = message.receivedAt.difference(startedAt);
              }
            }
            if (computedDuration != null) {
              _lastAssistantSegmentDuration = computedDuration;
            }
          }
          if (segmentId != null &&
              (stage == 'completed' ||
                  stage == 'idle' ||
                  stage == 'error' ||
                  stage == 'skipped')) {
            _segmentStartTimes.remove(segmentId);
          }
          if (stage == 'error') {
            errorDetail =
                (message.payload['error'] as String?) ??
                (message.payload['message'] as String?) ??
                (message.payload['errorMessage'] as String?);
          }
        });
        if (stage == 'speaking' ||
            stage == 'generated' ||
            stage == 'synthesizing' ||
            stage == 'idle' ||
            stage == 'completed') {
          unawaited(_session.liveKitService.setRemoteAudioMuted(false));
        }
        if (errorDetail != null && errorDetail!.isNotEmpty) {
          _appendMessage('system', 'Assistente erro: $errorDetail');
        }
        break;
      case 'assistant_transcript':
        final transcript = message.payload['transcript'] as String?;
        if (transcript != null && transcript.trim().isNotEmpty) {
          unawaited(_persistChatMessage(ChatRole.user, transcript.trim()));
        }
        break;
      case 'assistant_response':
        final text = message.payload['text'] as String?;
        if (text != null && text.trim().isNotEmpty) {
          unawaited(
            _persistChatMessage(
              ChatRole.assistant,
              text.trim(),
              metadata: message.payload,
            ),
          );
        }
        break;
      case 'assistant_error':
        final errText =
            (message.payload['message'] as String?) ??
            (message.payload['error'] as String?) ??
            (message.payload['errorMessage'] as String?) ??
            'Erro desconhecido';
        _appendMessage('system', 'Assistente erro: $errText');
        break;
      default:
        break;
    }
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    final String? currentUid = _session.currentUser?.uid;
    if (currentUid == null) {
      _chatListSubscription?.cancel();
      _messageSubscription?.cancel();
      setState(() {
        _chatUserId = null;
        _chatSessions.clear();
        _activeChat = null;
        _chatMessages = [];
      });
      return;
    }
    if (_chatUserId != currentUid && _session.isReadyForMain) {
      _listenForChats();
    }
    setState(() {});
  }

  /// When a toggle is in flight returns the optimistic microphone state.
  bool _effectiveLiveKitMicEnabled() =>
      _pendingLiveKitMicEnabled ?? _liveKitState.microphoneEnabled;

  bool _effectiveLiveKitMicPublished() {
    if (_pendingLiveKitMicEnabled == false) {
      return false;
    }
    return _liveKitState.localMicrophonePublished;
  }

  Future<void> _handleFirstUserGesture() async {
    if (_firstUserGestureHandled) {
      return;
    }
    if (!_session.connected || !_liveKitState.connected) {
      return;
    }
    _firstUserGestureHandled = true;
    if (_micBusy) {
      return;
    }
    setState(() {
      _micBusy = true;
      _micError = null;
    });
    try {
      await _session.liveKitService.ensureAudioPlayback();
      final shouldPublishMic =
          !_liveKitState.localMicrophonePublished ||
          !_liveKitState.microphoneEnabled;
      if (shouldPublishMic) {
        if (mounted) {
          setState(() {
            _pendingLiveKitMicEnabled = true;
          });
        }
        await _session.liveKitService.toggleMicrophone(true);
      }
    } catch (error, stackTrace) {
      debugPrint('Erro no gesto inicial do usuario: $error');
      debugPrint(stackTrace.toString());
      if (mounted) {
        setState(() {
          _micError = 'Erro ao ativar microfone: $error';
          _pendingLiveKitMicEnabled = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _micBusy = false;
        });
      }
    }
  }

  bool _isAssistantReady() {
    if (_session.currentUser == null) {
      return true;
    }
    if (!_session.connected) {
      return false;
    }
    if (!_liveKitState.connected) {
      return false;
    }
    if (_liveKitState.remoteAudioSubscribers == 0) {
      return false;
    }
    if (_session.liveKitError != null || _liveKitState.error != null) {
      return false;
    }
    return true;
  }

  String _assistantConnectingHint() {
    if (_session.liveKitRequestInProgress || _liveKitState.connecting) {
      return 'Conectando ao LiveKit...';
    }
    if (_liveKitState.connected && _liveKitState.remoteAudioSubscribers == 0) {
      return 'Iniciando worker e preparando audio...';
    }
    return 'Preparando a IA...';
  }

  Widget _buildAssistantConnectingOverlay(BuildContext context) {
    final bool showOverlay =
        !_isAssistantReady() &&
        _session.currentUser != null &&
        _session.liveKitError == null &&
        _liveKitState.error == null;
    if (!showOverlay) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_handleFirstUserGesture()),
        child: Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Conectando-se à IA do SENAI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _assistantConnectingHint(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds a human readable status line summarising the LiveKit session.
  String _livekitStatusLabel() {
    final error = _session.liveKitError ?? _liveKitState.error;
    if (error != null) {
      return error;
    }
    if (_session.liveKitRequestInProgress || _liveKitState.connecting) {
      return 'Conectando ao LiveKit...';
    }
    final info = _session.liveKitInfo;
    if (info == null) {
      return 'Token LiveKit indisponivel';
    }
    final buffer = StringBuffer('Sala ${info.room}');
    final micEnabled = _effectiveLiveKitMicEnabled();
    final micPublished = _effectiveLiveKitMicPublished();
    if (_liveKitState.connected) {
      buffer.write(' - conectado');
      if (!micEnabled) {
        buffer.write(' - microfone mutado');
      } else if (micPublished) {
        buffer.write(' - microfone ativo');
      } else {
        buffer.write(' - microfone pendente');
      }
      if (_liveKitState.remoteAudioSubscribers > 0) {
        buffer.write(
          ' - ouvindo ${_liveKitState.remoteAudioSubscribers} fluxo(s) remoto(s)',
        );
      } else {
        buffer.write(' - aguardando audio remoto');
      }
    } else {
      buffer.write(' - aguardando conexao');
    }
    DateTime? expiresAt = info.expiresAt;
    final payloadExpSeconds = (_session.liveKitTokenPayload?['exp'] as num?)
        ?.toInt();
    if (expiresAt == null && payloadExpSeconds != null) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(payloadExpSeconds * 1000);
    }
    if (expiresAt != null) {
      final remaining = expiresAt.difference(DateTime.now());
      final minutes = remaining.inMinutes;
      if (minutes >= 1) {
        buffer.write(' - expira em ~$minutes min');
      } else if (remaining.inSeconds > 0) {
        buffer.write(' - expira em menos de 1 min');
      } else {
        buffer.write(' - token expirado');
      }
    }
    return buffer.toString();
  }

  /// Compact summary showing which server/identity is active.
  String _livekitSummaryLine() {
    final info = _session.liveKitInfo;
    if (info == null) {
      return 'LiveKit aguardando detalhes de token.';
    }
    final serverUrl = info.serverUrl.trim();
    final identity = info.identity.trim();
    final host = serverUrl.isEmpty
        ? '-'
        : (Uri.tryParse(serverUrl)?.host ?? serverUrl);
    final shortId = identity.isEmpty
        ? '-'
        : identity.length > 6
        ? identity.substring(0, 6)
        : identity;
    final status = _liveKitState.connected ? 'conectado' : 'offline';
    return 'Servidor: $host - Identity: $shortId - Estado: $status';
  }

  /// Extracts human friendly metadata shared when requesting the token.
  String? _livekitMetadataSummary() {
    final metadata = _session.liveKitInfo?.metadata;
    if (metadata == null || metadata.isEmpty) {
      return null;
    }
    final provided = metadata['providedMetadata'];
    if (provided is Map<String, dynamic>) {
      final context = provided['context'];
      final platform = provided['platform'];
      final clientTime = provided['clientTime'];
      return 'Contexto: ${context ?? '-'} - Plataforma: ${platform ?? '-'} - Cliente: ${clientTime ?? '-'}';
    }
    return null;
  }

  /// Lists LiveKit-specific indicators (mic state, remote streams, metadata).
  List<Widget> _buildLivekitMetadataWidgets(BuildContext context) {
    final widgets = <Widget>[];
    final textStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final micEnabled = _effectiveLiveKitMicEnabled();
    final micPublished = _effectiveLiveKitMicPublished();
    final pendingTarget = _pendingLiveKitMicEnabled;

    if (_liveKitState.connected) {
      widgets.add(
        Text(
          !micEnabled
              ? 'Microfone LiveKit silenciado.'
              : micPublished
              ? 'Microfone LiveKit ativo.'
              : 'Microfone LiveKit pendente (publicando).',
          style: textStyle,
        ),
      );
      if (pendingTarget != null) {
        widgets.add(
          Text(
            pendingTarget
                ? 'Ativando microfone (aguardando confirmacao)...'
                : 'Silenciando microfone (aguardando confirmacao)...',
            style: textStyle,
          ),
        );
      }
      final remotes = _liveKitState.remoteAudioSubscribers;
      widgets.add(
        Text(
          remotes > 0
              ? 'Recebendo $remotes fluxo(s) de audio remoto.'
              : 'Nenhum audio remoto recebido ainda.',
          style: textStyle,
        ),
      );
    }

    final summary = _livekitMetadataSummary();
    if (summary != null) {
      widgets.add(Text(summary, style: textStyle));
    }
    return widgets;
  }

  // ---------------------------------------------------------------------------
  // Microphone + audio capture (device functionality)
  // ---------------------------------------------------------------------------

  bool get _hasRecording => _audioRecorder.hasRecording;

  /// Toggles the local recorder that captures audio segments before sending
  /// them to the Gemini + LiveKit backend.
  Future<void> _toggleRecording() async {
    if (!_session.connected) {
      setState(() {
        _micError = 'Conecte-se ao backend antes de gravar.';
      });
      return;
    }
    if (_micBusy) {
      return;
    }

    setState(() {
      _micBusy = true;
      _micError = null;
    });

    try {
      await _session.liveKitService.ensureAudioPlayback();
      if (_isRecording) {
        final result = await _audioRecorder.stop();
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _lastRecordingDuration = result.duration;
        });
        _appendMessage(
          'system',
          'Gravacao concluida (${result.duration.inSeconds}s aprox.).',
        );
        debugPrint('Gravacao salva em ${result.uri}');
      } else {
        await _audioRecorder.start();
        if (!mounted) return;
        setState(() {
          _isRecording = true;
        });
        _appendMessage('system', 'Microfone gravando...');
      }
    } catch (e, stackTrace) {
      debugPrint('Erro no microfone: $e');
      debugPrint(stackTrace.toString());
      if (!mounted) return;
      setState(() {
        _micError = 'Erro no microfone: $e';
        _isRecording = false;
      });
      _appendMessage('system', 'Erro no microfone: $e');
    } finally {
      if (mounted) {
        setState(() {
          _micBusy = false;
        });
      }
    }
  }

  /// Toggles the LiveKit microphone state (mute/unmute) without touching the
  /// local recorder.
  Future<void> _toggleLiveKitMicrophone() async {
    if (_micBusy) {
      return;
    }
    setState(() {
      _micBusy = true;
      _micError = null;
    });
    try {
      await _session.liveKitService.ensureAudioPlayback();
      await _session.liveKitService.toggleMicrophone(
        !_liveKitState.microphoneEnabled,
      );
    } catch (error, stackTrace) {
      debugPrint('Erro ao alternar microfone LiveKit: $error');
      debugPrint(stackTrace.toString());
      if (!mounted) return;
      setState(() {
        _micError = 'Erro ao alternar microfone LiveKit: $error';
      });
      _appendMessage('system', 'LiveKit microfone: $error');
    } finally {
      if (mounted) {
        setState(() {
          _micBusy = false;
        });
      }
    }
  }

  /// Plays back the most recent local recording so the user can review before
  /// re-sending it.
  // Future<void> _playLastRecording() async {
  //   if (!_audioRecorder.hasRecording) {
  //     setState(() {
  //       _micError = 'Nenhuma gravacao disponivel.';
  //     });
  //     return;
  //   }
  //   if (_micBusy) return;
  //   setState(() {
  //     _micBusy = true;
  //     _micError = null;
  //   });
  //   try {
  //     await _audioRecorder.playLastRecording();
  //     _appendMessage('system', 'Reproduzindo ultima gravacao.');
  //   } catch (e, stackTrace) {
  //     debugPrint('Falha ao reproduzir audio: $e');
  //     debugPrint(stackTrace.toString());
  //     if (!mounted) return;
  //     setState(() {
  //       _micError = 'Falha ao reproduzir audio: $e';
  //     });
  //   } finally {
  //     if (mounted) {
  //       setState(() {
  //         _micBusy = false;
  //       });
  //     }
  //   }
  // }

  /// Derives the current microphone status text shown in the UI.
  String _buildMicStatusText(BuildContext context) {
    if (!_session.connected) {
      return 'Conecte-se ao backend para habilitar o microfone.';
    }
    if (_micError != null) {
      return _micError!;
    }
    if (_micBusy) {
      return _liveKitState.connected
          ? 'Atualizando microfone LiveKit...'
          : 'Processando audio...';
    }
    if (_liveKitState.connected) {
      final remoteCount = _liveKitState.remoteAudioSubscribers;
      final remotePlaying = _liveKitState.remoteAudioPlaying;
      final remoteText = remotePlaying
          ? 'Assistente reproduzindo audio remoto.'
          : remoteCount > 0
          ? 'Recebendo $remoteCount fluxo(s) remoto(s).'
          : 'Nenhum audio remoto recebido ainda.';
      final micEnabled = _effectiveLiveKitMicEnabled();
      final micPublished = _effectiveLiveKitMicPublished();
      final micText = !micEnabled
          ? 'Microfone LiveKit silenciado.'
          : micPublished
          ? 'Microfone LiveKit ativo.'
          : 'Microfone LiveKit pendente (publicando).';
      return '$micText $remoteText';
    }
    if (_isRecording) {
      return 'Gravando audio... toque em Parar para finalizar.';
    }
    if (_hasRecording) {
      if (_lastRecordingDuration != null) {
        final seconds = _lastRecordingDuration!.inMilliseconds / 1000;
        final formatted = seconds < 10
            ? seconds.toStringAsFixed(1)
            : seconds.toStringAsFixed(0);
        return 'Ultima gravacao ~${formatted}s. Toque em Reproduzir para ouvir.';
      }
      return 'Ultima gravacao pronta para reproduzir.';
    }
    return 'Pronto para gravar uma nova mensagem.';
  }

  // ---------------------------------------------------------------------------
  // UI helpers (Flutter presentation layer)
  // ---------------------------------------------------------------------------

  /// Appends a new entry to the local timeline so the user sees status updates.
  void _appendMessage(String role, String text) {
    setState(() {
      _messages.add(_Message(role: role, text: text));
    });
  }

  /// Maps assistant stages (Gemini pipeline) into localized hints.
  String? _assistantStatusLabel() {
    final stage = _liveKitState.assistantStage;
    final speaking = _liveKitState.remoteAudioPlaying;
    if (speaking && stage == null) {
      return 'Assistente reproduzindo audio remoto.';
    }
    if (stage == null) {
      return null;
    }
    switch (stage) {
      case 'listening':
        return 'Assistente ouvindo.';
      case 'user_speaking':
        return 'Usuario falando...';
      case 'processing':
        return 'Processando captura de audio.';
      case 'transcribing':
        return 'Transcrevendo voz...';
      case 'transcribed':
        return 'Transcricao pronta.';
      case 'generating':
        return 'Gerando resposta da IA...';
      case 'generated':
        return 'Resposta pronta para sintetizar.';
      case 'synthesizing':
        return 'Sintetizando audio da resposta...';
      case 'speaking':
        return 'Assistente respondendo com audio.';
      case 'completed':
        if (_lastAssistantSegmentDuration != null) {
          return 'Segmento concluido em ${_formatDuration(_lastAssistantSegmentDuration!)}.';
        }
        return 'Segmento concluido.';
      case 'idle':
        return 'Assistente pronto.';
      case 'skipped':
        return 'Entrada ignorada.';
      case 'error':
        final errorText =
            (_lastAssistantStatus?['error'] as String?) ??
            (_lastAssistantStatus?['message'] as String?);
        if (errorText != null && errorText.isNotEmpty) {
          return 'Erro do assistente: $errorText';
        }
        return 'Erro do assistente.';
      default:
        return 'Assistente: $stage';
    }
  }

  /// Convenience helper to know when LiveKit/Gemini is still processing audio.
  bool _assistantStageIsBusy(String? stage) {
    const busyStages = <String>{
      'processing',
      'transcribing',
      'generating',
      'synthesizing',
    };
    return stage != null && busyStages.contains(stage);
  }

  /// Friendly formatter for assistant segment and recording durations.
  String _formatDuration(Duration duration) {
    final totalMs = duration.inMilliseconds;
    if (totalMs < 1000) {
      return '${totalMs}ms';
    }
    final seconds = totalMs / 1000;
    if (seconds < 60) {
      return seconds < 10
          ? '${seconds.toStringAsFixed(1)}s'
          : '${seconds.toStringAsFixed(0)}s';
    }
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds % 60;
    if (remainingSeconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${remainingSeconds}s';
  }

  Widget _buildChatBody(BuildContext context) {
    if (_chatListLoading && _chatSessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_activeChat == null) {
      return _buildEmptyChatState(
        context,
        message: 'Nenhum chat encontrado. Toque em "Novo chat" para iniciar.',
      );
    }
    if (_messagesLoading && _chatMessages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_chatMessages.isEmpty) {
      return _buildEmptyChatState(
        context,
        message: 'Este chat ainda nao possui mensagens.',
      );
    }
    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: _chatMessages.length,
      itemBuilder: (context, index) {
        final message = _chatMessages[index];
        return _buildMessageBubble(context, message);
      },
    );
  }

  Widget _buildEmptyChatState(BuildContext context, {required String message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    final bool isUser = message.role == ChatRole.user;
    final Alignment alignment = isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final Color background = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final Color foreground = isUser
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: foreground,
            fontWeight: isUser ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context, {
    required bool micButtonDisabled,
    required bool liveKitActive,
    required bool effectiveMicEnabled,
    required bool assistantReady,
    required String? assistantLabel,
    required bool assistantBusy,
    required bool assistantSpeaking,
    required Color assistantStatusColor,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _showLogsDialog,
              icon: const Icon(Icons.list_alt),
              label: const Text('Logs'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _buildMicStatusText(context),
                    style: TextStyle(
                      color: _micError != null
                          ? Colors.redAccent
                          : _session.connected
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                  if (assistantLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (assistantBusy)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            assistantSpeaking
                                ? Icons.graphic_eq
                                : Icons.headset_mic_outlined,
                            size: 18,
                            color: assistantStatusColor,
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            assistantLabel,
                            maxLines: 2,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: assistantStatusColor,
                                ) ??
                                TextStyle(
                                  color: assistantStatusColor,
                                  fontSize: 12,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: micButtonDisabled
                      ? null
                      : liveKitActive
                      ? () => _toggleLiveKitMicrophone()
                      : () => _toggleRecording(),
                  icon: _micBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : liveKitActive
                      ? Icon(effectiveMicEnabled ? Icons.mic : Icons.mic_off)
                      : _isRecording
                      ? const Icon(Icons.stop)
                      : const Icon(Icons.mic),
                  label: Text(
                    liveKitActive
                        ? (effectiveMicEnabled ? 'Silenciar' : 'Ativar mic')
                        : (_isRecording ? 'Parar' : 'Gravar'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _sendingScene || !assistantReady
                      ? null
                      : _showSceneDialog,
                  icon: _sendingScene
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.theaters),
                  label: const Text('Cena VR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSceneDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            _sceneSheetSetState = sheetSetState;
            return Padding(
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Simular cena/etapa VR',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              IconButton(
                                tooltip: 'Fechar',
                                onPressed: () {
                                  _sceneSheetSetState = null;
                                  Navigator.of(context).pop();
                                },
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _sceneController,
                            maxLines: 4,
                            minLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Descreva a cena ou etapa',
                              hintText:
                                  'Ex.: Usuário chegou à base da torre e iniciou checklist de EPI...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  _sceneSheetSetState = null;
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Cancelar'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _sendingScene
                                    ? null
                                    : _handleSendScene,
                                icon: _sendingScene
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send),
                                label: const Text('Enviar Cena'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleSendScene() async {
    if (!_session.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conecte-se ao backend antes de enviar.')),
      );
      return;
    }
    final text = _sceneController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a cena ou etapa para enviar.')),
      );
      return;
    }
    setState(() => _sendingScene = true);
    try {
      final chat = await _ensureActiveChat();
      if (chat != null) {
        await _persistChatMessage(
          ChatRole.user,
          'Cena VR: $text',
          metadata: {'sceneEvent': true},
        );
      }

      final payload = {
        'type': 'scene_event',
        'payload': {
          'description': text,
          'chatId': chat?.id,
        },
      };
      await _session.liveKitService.sendData(payload);
      _sceneController.clear();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      debugPrint('Falha ao enviar cena: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao enviar cena: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _sendingScene = false);
      }
    }
  }

  void _showLogsDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logs e status'),
          content: SizedBox(width: 420, child: _buildLogsContent(context)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogsContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final entries = <Map<String, String>>[
      {'label': 'Conexao', 'value': _session.connectionStatusLabel},
      {'label': 'Autenticacao', 'value': _session.authStatusLabel},
      {'label': 'App Check', 'value': _session.appCheckStatusLabel},
      {'label': 'LiveKit', 'value': _livekitStatusLabel()},
      {'label': 'Resumo', 'value': _livekitSummaryLine()},
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry['label']!, style: textTheme.labelSmall),
                  Text(entry['value']!),
                ],
              ),
            ),
          const SizedBox(height: 8),
          ..._buildLivekitMetadataWidgets(context),
          const SizedBox(height: 16),
          if (_messages.isNotEmpty) ...[
            Text('Eventos recentes', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final log in _messages.reversed.take(30))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('[${log.role}] ${log.text}'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawerOverlay(BuildContext context) {
    return IgnorePointer(
      ignoring: !_drawerOpen,
      child: AnimatedOpacity(
        opacity: _drawerOpen ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _toggleDrawer(false),
                child: Container(color: Colors.black54),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              left: _drawerOpen ? 0 : -260,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 250,
                child: Material(
                  elevation: 8,
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(child: _buildDrawerContent(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerContent(BuildContext context) {
    final email = _session.currentUser?.email ?? 'Usuario convidado';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _startNewChat,
            icon: const Icon(Icons.add_comment),
            label: const Text('Novo chat'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _chatListLoading && _chatSessions.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _chatSessions.isEmpty
                ? const Center(child: Text('Nenhum chat criado ainda.'))
                : ListView.builder(
                    itemCount: _chatSessions.length,
                    itemBuilder: (context, index) {
                      final chat = _chatSessions[index];
                      return _buildChatListItem(context, chat);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatListItem(BuildContext context, ChatSession session) {
    final bool isActive = _activeChat?.id == session.id;
    final subtitle = session.lastMessageSnippet?.isNotEmpty == true
        ? session.lastMessageSnippet!
        : 'Sem mensagens.';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      selected: isActive,
      selectedColor: Theme.of(context).colorScheme.primary,
      iconColor: Theme.of(context).colorScheme.primary,
      leading: Icon(isActive ? Icons.chat_bubble : Icons.chat_bubble_outline),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isActive
            ? Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)
            : null,
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${session.messageCount}'),
          IconButton(
            tooltip: 'Apagar chat',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDeleteChat(session),
          ),
        ],
      ),
      onTap: () => _setActiveChat(session),
    );
  }

  Future<void> _confirmDeleteChat(ChatSession session) async {
    final user = _session.currentUser;
    if (user == null) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Apagar chat'),
          content: const Text(
            'Voce tem certeza que deseja apagar este chat e todas as suas mensagens para sempre?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apagar chat'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    try {
      await _session.chatRepository.deleteChat(
        userId: user.uid,
        chatId: session.id,
      );
      if (_activeChat?.id == session.id) {
        setState(() {
          _activeChat = null;
          _chatMessages = [];
        });
      }
    } catch (error) {
      debugPrint('Falha ao apagar chat: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao apagar chat. Tente novamente.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool liveKitActive = _liveKitState.connected;
    final bool pendingMicToggle = _pendingLiveKitMicEnabled != null;
    final bool assistantReady = _isAssistantReady();
    final bool micButtonDisabled =
        !_session.connected ||
        _micBusy ||
        _liveKitState.connecting ||
        _session.liveKitRequestInProgress ||
        !assistantReady ||
        pendingMicToggle;
    final bool effectiveMicEnabled = _effectiveLiveKitMicEnabled();
    final String? assistantStage = _liveKitState.assistantStage;
    final String? assistantLabel = _assistantStatusLabel();
    final bool assistantBusy = _assistantStageIsBusy(assistantStage);
    final bool assistantSpeaking =
        _liveKitState.remoteAudioPlaying || assistantStage == 'speaking';
    final Color assistantStatusColor = assistantStage == 'error'
        ? Colors.redAccent
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Abrir painel de chats',
          icon: Icon(_drawerOpen ? Icons.close : Icons.menu),
          onPressed: _toggleDrawer,
        ),
        title: const Text('Mentora senAI - Sim. VR'),
      ),
      body: Column(
        children: [
          Expanded(child: _buildChatBody(context)),
          _buildBottomBar(
            context,
            micButtonDisabled: micButtonDisabled,
            liveKitActive: liveKitActive,
            effectiveMicEnabled: effectiveMicEnabled,
            assistantReady: assistantReady,
            assistantLabel: assistantLabel,
            assistantBusy: assistantBusy,
            assistantSpeaking: assistantSpeaking,
            assistantStatusColor: assistantStatusColor,
          ),
        ],
      ),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => unawaited(_handleFirstUserGesture()),
      child: Stack(
        children: [
          scaffold,
          _buildDrawerOverlay(context),
          _buildAssistantConnectingOverlay(context),
        ],
      ),
    );
  }
}

class _Message {
  final String role;
  final String text;
  const _Message({required this.role, required this.text});
}
