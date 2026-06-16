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

  /// Client-side upload guard (the server enforces its own 20 MB limit).
  static const int maxUploadBytes = 20 * 1024 * 1024;

  /// Accepted file extensions (mirrors the backend's ALLOWED_SUFFIXES).
  static const List<String> allowedExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp'];
}
