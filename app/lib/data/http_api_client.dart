import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../models/models.dart';
import 'api_client.dart';

/// Real backend client over `dio`. Attaches the signed-in user's Supabase
/// access token when present (the backend uses it for the entitlement gate).
///
/// `validateStatus` is permissive so 4xx/413 responses don't throw — we read
/// the body and map to a friendly [ApiException] ourselves.
class HttpApiClient implements ApiClient {
  HttpApiClient({required String baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 120), // OCR+rules+LLM can be slow
          validateStatus: (_) => true,
        )),
        _baseUrl = baseUrl;

  final Dio _dio;
  final String _baseUrl;

  /// Bearer token of the current Supabase session, or null when signed out.
  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;

  Options? _authOptions() {
    final t = _token;
    return t == null ? null : Options(headers: {'Authorization': 'Bearer $t'});
  }

  @override
  Future<bool> health() async {
    try {
      final r = await _dio.get('/api/health');
      return r.statusCode == 200 && r.data is Map && (r.data as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ScanOutcome> scan({
    required List<int> bytes,
    required String filename,
    String origin = 'vendor',
    UploadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'origin': origin,
    });

    Response resp;
    try {
      resp = await _dio.post(
        '/api/scan',
        data: form,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
        options: _authOptions(),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const ScanCancelled();
      throw ApiException(
        message: "Can't reach the backend at $_baseUrl. Is it running?",
        statusCode: null,
      );
    }

    final code = resp.statusCode ?? 0;
    final data = resp.data;

    if (code == 200) {
      if (data is Map && data['error'] == 'input_not_coa') {
        return ScanNotACoaOutcome(NotACoa.fromJson(Map<String, dynamic>.from(data)));
      }
      if (data is Map) {
        return ScanSuccess(ScanResult.fromJson(Map<String, dynamic>.from(data)));
      }
      throw const ApiException(message: 'Unexpected response from the server.', statusCode: 200);
    }

    final detail = (data is Map && data['detail'] is String) ? data['detail'] as String : null;
    throw ApiException(statusCode: code, message: _mapError(code, detail));
  }

  @override
  Future<Map<String, dynamic>> me() async {
    final Response r;
    try {
      r = await _dio.get('/api/me', options: _authOptions());
    } on DioException {
      throw ApiException(message: "Can't reach the backend.", statusCode: null);
    }
    if (r.statusCode == 200 && r.data is Map) {
      return Map<String, dynamic>.from(r.data as Map);
    }
    throw ApiException(statusCode: r.statusCode, message: _mapError(r.statusCode ?? 0, _detail(r.data)));
  }

  @override
  Future<String> createCheckout(String plan) async {
    final Response r;
    try {
      r = await _dio.post('/api/checkout', data: {'plan': plan}, options: _authOptions());
    } on DioException {
      throw ApiException(message: "Can't reach the backend.", statusCode: null);
    }
    if (r.statusCode == 200 && r.data is Map && (r.data as Map)['url'] is String) {
      return (r.data as Map)['url'] as String;
    }
    throw ApiException(statusCode: r.statusCode, message: _mapError(r.statusCode ?? 0, _detail(r.data)));
  }

  String? _detail(Object? data) =>
      (data is Map && data['detail'] is String) ? data['detail'] as String : null;

  String _mapError(int code, String? detail) {
    switch (code) {
      case 400:
        return detail ?? 'This file could not be processed (wrong type or too small).';
      case 401:
        return detail ?? 'Please sign in to scan.';
      case 402:
        return detail ?? 'No scans remaining — choose a plan to continue.';
      case 413:
        return 'That file is over the 20 MB limit. Try a smaller file.';
      default:
        return detail ?? 'The server returned an error ($code).';
    }
  }
}
