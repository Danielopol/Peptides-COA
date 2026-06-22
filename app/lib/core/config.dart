/// App configuration, read from `--dart-define` at build/run time.
///
/// Examples:
///   flutter run -d chrome \
///     --dart-define=API_BASE_URL=http://localhost:8000 \
///     --dart-define=USE_MOCK=false
class AppConfig {
  const AppConfig._();

  /// Base URL of the FastAPI backend. Defaults to the local uvicorn server.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// When true, use [MockApiClient] (canned fixtures, no backend needed).
  /// Defaults to false so the app talks to the real local backend.
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// DEV ONLY: skip the sign-in + entitlement/paywall gates so scanning works
  /// against a local backend (which has REQUIRE_AUTH=false) without Supabase auth
  /// or Stripe. Defaults to false — production builds are unaffected. Enable with
  /// `--dart-define=DEV_BYPASS_PAYWALL=true`.
  static const bool devBypassPaywall =
      bool.fromEnvironment('DEV_BYPASS_PAYWALL', defaultValue: false);

  /// Supabase project URL + anon (public) key. Safe to ship in the client — the
  /// anon key is designed to be public and is gated by Row Level Security.
  /// Overridable via --dart-define for other environments.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://cbqkdlnehslhaoclyqsn.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNicWtkbG5laHNsaGFvY2x5cXNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4ODkzNTIsImV4cCI6MjA5NzQ2NTM1Mn0.fQN3XwkJMhy1qMW-H1rJYL4rjWqgslybEjJcl-K4BHY',
  );

  /// Client-side upload guard (the server enforces its own 20 MB limit).
  static const int maxUploadBytes = 20 * 1024 * 1024;

  /// Accepted file extensions (mirrors the backend's ALLOWED_SUFFIXES).
  static const List<String> allowedExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp'];
}
