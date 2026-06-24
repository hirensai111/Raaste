class AppConfig {
  AppConfig._();

  static const String appName = 'Raaste';
  static const String appTagline = 'Your personal guide to India';

  // API
  static const String defaultBaseUrl = 'http://localhost:8000';
  static const Duration apiTimeout = Duration(seconds: 30);

  // Storage keys
  static const String tokenKey = 'auth_token';
  static const String profileKey = 'user_profile';
  static const String onboardingCompleteKey = 'onboarding_complete';

  // Feature flags
  static const bool enableCompanionAds = false;
  static const bool enableOfflineCompanion = true;
}
