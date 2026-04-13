class AppConfig {
  AppConfig._();

  static const String firebaseProjectId = 'YOUR_FIREBASE_PROJECT_ID';
  static const String firebaseFunctionsRegion = 'YOUR_FIREBASE_FUNCTIONS_REGION';
  static const String reCaptchaV3SiteKey =
      'YOUR_RECAPTCHA_V3_SITE_KEY';

  static const bool useFunctionsEmulator = bool.fromEnvironment(
    'USE_FUNCTIONS_EMULATOR',
    defaultValue: true,
  );

  static const String defaultLivekitRoom = 'room-placeholder';
  static const String livekitTokenFunctionName = 'livekitToken';
  static const String assistantIdentity = 'assistant-bot';
}
