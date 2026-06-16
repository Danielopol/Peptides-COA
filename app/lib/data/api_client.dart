import 'package:dio/dio.dart';

import '../models/models.dart';

typedef UploadProgress = void Function(int sent, int total);

/// The only interface to the backend. Two implementations:
/// [HttpApiClient] (real, default) and [MockApiClient] (fixtures).
abstract class ApiClient {
  /// GET /api/health → true if the backend reports {"status":"ok"}.
  Future<bool> health();

  /// POST /api/scan (multipart). Returns a [ScanOutcome] for 200 responses
  /// (success or not-a-COA), throws [ApiException] for 400/413/network errors,
  /// and throws [ScanCancelled] if cancelled.
  Future<ScanOutcome> scan({
    required List<int> bytes,
    required String filename,
    String origin = 'vendor', // 'vendor' | 'self' (own independent test)
    UploadProgress? onProgress,
    CancelToken? cancelToken,
  });
}
