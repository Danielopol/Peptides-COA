import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'fixtures.dart';

/// Returns canned fixtures so the UI runs without a backend. Picks a fixture by
/// filename keyword (so you can demo any path on purpose), and simulates upload
/// progress + analysis latency.
class MockApiClient implements ApiClient {
  @override
  Future<bool> health() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return true;
  }

  @override
  Future<ScanOutcome> scan({
    required List<int> bytes,
    required String filename,
    String origin = 'vendor',
    UploadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Simulate upload progress.
    for (var p = 0; p <= 10; p++) {
      if (cancelToken?.isCancelled ?? false) throw const ScanCancelled();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      onProgress?.call(p, 10);
    }
    // Simulate analysis time.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (cancelToken?.isCancelled ?? false) throw const ScanCancelled();

    final name = filename.toLowerCase();
    if (name.contains('blank') || name.contains('notacoa') || name.contains('empty')) {
      return ScanNotACoaOutcome(
          NotACoa.fromJson(jsonDecode(kFixtureNotACoa) as Map<String, dynamic>));
    }
    if (name.contains('fake') || name.contains('forged') || name.contains('highrisk')) {
      return _success(kFixtureHighRisk);
    }
    if (name.contains('caution') || name.contains('suspicious') || name.contains('mw')) {
      return _success(kFixtureCaution);
    }
    if (name.contains('toolarge') || name.contains('big')) {
      throw const ApiException(
          message: 'That file is over the 20 MB limit. Try a smaller file.', statusCode: 413);
    }
    return _success(kFixtureAuthentic);
  }

  ScanSuccess _success(String fixture) {
    final json = jsonDecode(fixture) as Map<String, dynamic>;
    json['filename'] = json['filename']; // keep fixture's own name
    return ScanSuccess(ScanResult.fromJson(json));
  }
}
