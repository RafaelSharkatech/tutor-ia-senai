import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../chat/chat_repository.dart';
import '../chat/firestore_chat_repository.dart';
import '../config/app_config.dart';
import '../services/livekit_service.dart';

class LiveKitTokenInfo {
  final String token;
  final String serverUrl;
  final String identity;
  final String room;
  final int ttlSeconds;
  final DateTime? expiresAt;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> payload;

  const LiveKitTokenInfo({
    required this.token,
    required this.serverUrl,
    required this.identity,
    required this.room,
    required this.ttlSeconds,
    required this.expiresAt,
    required this.metadata,
    required this.payload,
  });
}

class AppSessionController extends ChangeNotifier {
  AppSessionController({ChatRepository? initialChatRepository}) {
    chatRepository =
        initialChatRepository ?? createDefaultChatRepository(this);
    _currentUser = _auth.currentUser;
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      _emailController.text = user.email!;
    }
    _authSub = _auth.authStateChanges().listen(
      (user) {
        _currentUser = user;
        _authError = null;
        _loginFormVisible = user == null;
        if (user?.email != null) {
          _emailController.text = user!.email!;
        }
        notifyListeners();
      },
      onError: (error, stackTrace) {
        debugPrint('authStateChanges error: $error');
        _authError = 'Erro ao escutar autenticacao';
        notifyListeners();
      },
    );
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LiveKitService liveKitService = LiveKitService();
  late final ChatRepository chatRepository;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  StreamSubscription<User?>? _authSub;
  User? _currentUser;
  bool _authInProgress = false;
  String? _authError;
  bool _loginFormVisible = true;

  bool _appCheckRefreshing = false;
  String _appCheckStatus = 'Verificando App Check...';

  bool _connectingBackend = false;
  bool _connected = false;
  String? _connectionError;

  bool _liveKitRequestInProgress = false;
  String? _liveKitError;
  LiveKitTokenInfo? _liveKitInfo;
  Map<String, dynamic>? _liveKitTokenPayload;
  bool _pendingAudioUnlock = false;

  String? _progressMessage;

  bool _disposed = false;

  User? get currentUser => _currentUser;
  bool get authInProgress => _authInProgress;
  bool get appCheckRefreshing => _appCheckRefreshing;
  bool get connectingBackend => _connectingBackend;
  bool get connected => _connected;
  bool get liveKitRequestInProgress => _liveKitRequestInProgress;
  LiveKitTokenInfo? get liveKitInfo => _liveKitInfo;
  Map<String, dynamic>? get liveKitTokenPayload => _liveKitTokenPayload;
  String? get liveKitError => _liveKitError;
  String? get connectionError => _connectionError;
  String? get authError => _authError;
  String get appCheckStatusLabel => _appCheckStatus;
  String? get progressMessage => _progressMessage;

  bool get isReadyForMain => _connected && _currentUser != null;
  bool get loginFormVisible => _loginFormVisible;
  TextEditingController get emailController => _emailController;
  TextEditingController get passwordController => _passwordController;

  String? get lastErrorMessage =>
      _connectionError ?? _liveKitError ?? _authError;

  String get authStatusLabel {
    if (_authInProgress) {
      return 'Autenticando...';
    }
    final user = _currentUser;
    if (user != null) {
      final uid = user.uid;
      final shortId = uid.length > 6 ? uid.substring(0, 6) : uid;
      return 'Autenticado - UID: $shortId...';
    }
    if (_authError != null) {
      return _authError!;
    }
    return 'Nao autenticado';
  }

  String get connectionStatusLabel {
    if (_connectingBackend || _liveKitRequestInProgress) {
      return 'Conectando...';
    }
    if (_connectionError != null) {
      return _connectionError!;
    }
    return _connected ? 'Conectado (backend verificado)' : 'Desconectado';
  }

  bool get busy =>
      _authInProgress || _connectingBackend || _liveKitRequestInProgress;

  Future<void> disposeAsync() async {
    _authSub?.cancel();
    _authSub = null;
    await liveKitService.dispose();
    _disposed = true;
  }

  @override
  void dispose() {
    if (!_disposed) {
      unawaited(disposeAsync());
    }
    super.dispose();
  }

  Future<void> startSession({bool userInitiated = false}) async {
    if (busy) {
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        _authError = 'Informe email e senha.';
        notifyListeners();
        return;
      }
      await _authenticateWithEmail(email, password);
      if (_auth.currentUser == null) {
        return;
      }
    }
    if (userInitiated) {
      _pendingAudioUnlock = true;
    }
    _loginFormVisible = false;
    _progressMessage = 'Validando App Check...';
    notifyListeners();
    await refreshAppCheckStatus();
    _progressMessage = 'Conectando aos servicos...';
    notifyListeners();
    try {
      await _connectBackend(contextLabel: 'bootstrap');
      _progressMessage = 'Sessao pronta. Conectado ao assistente.';
    } catch (error) {
      debugPrint('startSession error: $error');
      _progressMessage = 'Falha ao iniciar: $error';
    } finally {
      notifyListeners();
    }
  }

  Future<void> refreshAppCheckStatus() async {
    _appCheckRefreshing = true;
    notifyListeners();
    try {
      final token = await FirebaseAppCheck.instance.getToken(true);
      final tokenValue = token ?? 'sem token';
      final shortened = tokenValue.length > 6
          ? '${tokenValue.substring(0, 6)}...'
          : tokenValue;
      _appCheckStatus = 'App Check ativo (token: $shortened)';
    } catch (error) {
      debugPrint('Falha ao obter token App Check: $error');
      _appCheckStatus = 'App Check indisponivel';
    } finally {
      _appCheckRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshLivekitToken({String contextLabel = 'manual-refresh'}) async {
    if (_liveKitRequestInProgress) {
      return;
    }
    try {
      await _requestAndApplyLivekitToken(contextLabel: contextLabel);
    } catch (error) {
      debugPrint('Erro ao renovar token LiveKit: $error');
    }
  }

  Future<void> _authenticateWithEmail(String email, String password) async {
    _authInProgress = true;
    _authError = null;
    notifyListeners();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _currentUser = credential.user;
      return;
    } on FirebaseAuthException catch (error) {
      _authError = _mapAuthError(error);
    } catch (error) {
      _authError = 'Falha ao autenticar: $error';
    } finally {
      _authInProgress = false;
      notifyListeners();
    }
  }

  String _mapAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'wrong-password':
        return 'Senha incorreta.';
      case 'invalid-email':
        return 'Email invalido.';
      case 'user-disabled':
        return 'Usuario desativado.';
      default:
        return 'Falha na autenticacao (${error.code}).';
    }
  }

  Future<void> _connectBackend({required String contextLabel}) async {
    if (_connectingBackend) {
      return;
    }
    _connectingBackend = true;
    _connectionError = null;
    notifyListeners();

    try {
      final user = _currentUser ?? _auth.currentUser;
      if (user == null) {
        throw StateError('Usuario nao autenticado');
      }

      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw StateError('Token de usuario ausente');
      }
      final fetchedAppCheckToken = await FirebaseAppCheck.instance.getToken(true);
      if (fetchedAppCheckToken == null) {
        throw StateError('Token App Check ausente');
      }

      await _pingBackend(idToken: idToken, appCheckToken: fetchedAppCheckToken);
      await _requestAndApplyLivekitToken(
        idToken: idToken,
        appCheckToken: fetchedAppCheckToken,
        contextLabel: contextLabel,
      );
      _connected = true;
    } catch (error) {
      debugPrint('Falha ao conectar backend: $error');
      _connectionError = 'Falha ao conectar: $error';
      _connected = false;
      unawaited(liveKitService.disconnect());
    } finally {
      _connectingBackend = false;
      notifyListeners();
    }
  }

  Future<void> _pingBackend({
    required String idToken,
    required String appCheckToken,
  }) async {
    final uri = _buildFunctionsUri('ping');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
        'X-Firebase-AppCheck': appCheckToken,
      },
      body: jsonEncode({
        'clientTime': DateTime.now().toIso8601String(),
        'debug': kDebugMode,
      }),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw StateError('Resposta inesperada do backend');
    }
  }

  Future<void> _requestAndApplyLivekitToken({
    String? idToken,
    String? appCheckToken,
    required String contextLabel,
  }) async {
    final user = _currentUser ?? _auth.currentUser;
    if (user == null) {
      throw StateError('Usuario nao autenticado');
    }
    final effectiveIdToken = idToken ?? await user.getIdToken();
    if (effectiveIdToken == null) {
      throw StateError('Token de usuario ausente');
    }
    final effectiveAppCheckToken =
        appCheckToken ?? await FirebaseAppCheck.instance.getToken(true);
    if (effectiveAppCheckToken == null) {
      throw StateError('Token App Check ausente');
    }

    _liveKitRequestInProgress = true;
    _liveKitError = null;
    notifyListeners();

    try {
      final tokenInfo = await _requestLivekitToken(
        idToken: effectiveIdToken,
        appCheckToken: effectiveAppCheckToken,
        roomName: _buildLiveKitRoomName(),
        contextLabel: contextLabel,
      );
      if (liveKitService.state.value.connected) {
        await liveKitService.disconnect();
      }
      await liveKitService.connect(
        url: tokenInfo.serverUrl,
        token: tokenInfo.token,
      );
      if (_pendingAudioUnlock) {
        try {
          await liveKitService.ensureAudioPlayback();
        } catch (error) {
          debugPrint('ensureAudioPlayback error: $error');
        }
        _pendingAudioUnlock = false;
      }
      _liveKitInfo = tokenInfo;
      _liveKitTokenPayload = tokenInfo.payload;
      _liveKitError = null;
      _connected = true;
    } catch (error) {
      _liveKitError = 'Erro ao solicitar token LiveKit: $error';
      _connected = false;
      rethrow;
    } finally {
      _liveKitRequestInProgress = false;
      notifyListeners();
    }
  }

  Uri _buildFunctionsUri(String functionName) {
    if (AppConfig.useFunctionsEmulator) {
      return Uri.parse(
        'http://localhost:5001/${AppConfig.firebaseProjectId}/${AppConfig.firebaseFunctionsRegion}/$functionName',
      );
    }
    const host =
        '${AppConfig.firebaseFunctionsRegion}-${AppConfig.firebaseProjectId}.cloudfunctions.net';
    return Uri.https(host, '/$functionName');
  }

  String _buildLiveKitRoomName() {
    final uid = _currentUser?.uid ?? 'guest';
    final safe = uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    return 'room-$safe';
  }

  Future<LiveKitTokenInfo> _requestLivekitToken({
    required String idToken,
    required String appCheckToken,
    required String roomName,
    required String contextLabel,
  }) async {
    final currentUid = _currentUser?.uid ?? 'guest';
    final shortUid = currentUid.length > 6 ? currentUid.substring(0, 6) : currentUid;
    final displayName = _currentUser?.displayName?.trim();
    final participantName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : 'web-$shortUid';

    final uri = _buildFunctionsUri(AppConfig.livekitTokenFunctionName);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
        'X-Firebase-AppCheck': appCheckToken,
      },
      body: jsonEncode({
        'roomName': roomName,
        'participantName': participantName,
        'metadata': {
          'context': contextLabel,
          'clientTime': DateTime.now().toIso8601String(),
          'platform': defaultTargetPlatform.name,
          'isWeb': kIsWeb,
          'buildMode': kDebugMode ? 'debug' : 'release',
        },
      }),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Falha ao obter token LiveKit (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } catch (error) {
      throw StateError('Resposta invalida do emissor de token LiveKit: $error');
    }

    final token = decoded['token'] as String?;
    final serverUrl =
        decoded['serverUrl'] as String? ?? decoded['url'] as String?;
    final identity = decoded['identity'] as String? ?? _currentUser?.uid;
    final room = decoded['room'] as String? ?? roomName;
    final ttlSeconds = (decoded['ttlSeconds'] as num?)?.toInt() ?? 0;
    final expiresAtIso = decoded['expiresAt'] as String?;
    final expiresAt =
        expiresAtIso != null ? DateTime.tryParse(expiresAtIso) : null;
    final metadata = (decoded['metadata'] is Map<String, dynamic>)
        ? decoded['metadata'] as Map<String, dynamic>
        : decoded['metadata'] is Map
            ? (decoded['metadata'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

    if (token == null || serverUrl == null || identity == null) {
      throw StateError('Resposta LiveKit incompleta: $decoded');
    }

    final payload = _decodeJwtPayload(token);

    return LiveKitTokenInfo(
      token: token,
      serverUrl: serverUrl,
      identity: identity,
      room: room,
      ttlSeconds: ttlSeconds,
      expiresAt: expiresAt,
      metadata: metadata,
      payload: payload,
    );
  }

  Map<String, dynamic> _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException('JWT invalido: formato inesperado');
    }
    final payloadPart = parts[1];
    try {
      final normalized = base64Url.normalize(payloadPart);
      final decoded = utf8.decode(
        base64Url.decode(normalized),
        allowMalformed: false,
      );
      final payload = jsonDecode(decoded);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
      throw const FormatException('Payload do JWT nao eh um objeto JSON');
    } catch (error) {
      throw FormatException('Falha ao decodificar payload JWT: $error');
    }
  }
}
