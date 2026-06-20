import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../core/config.dart';
import '../core/entitlement.dart';
import '../data/api_client.dart';
import '../data/http_api_client.dart';
import '../data/mock_api_client.dart';
import '../models/models.dart';

/// Selected API client (mock vs real) per [AppConfig.useMock].
final apiClientProvider = Provider<ApiClient>((ref) {
  return AppConfig.useMock ? MockApiClient() : HttpApiClient(baseUrl: AppConfig.apiBaseUrl);
});

/// Backend reachability. Refresh by invalidating this provider.
final healthProvider = FutureProvider<bool>((ref) async {
  return ref.watch(apiClientProvider).health();
});

/// The signed-in user's scan entitlement (null when signed out). Refetches on
/// auth change; invalidate after a scan or a successful purchase to refresh.
final entitlementProvider = FutureProvider<Entitlement?>((ref) async {
  ref.watch(authStateProvider);
  if (supabase.auth.currentSession == null) return null;
  final raw = await ref.watch(apiClientProvider).me();
  return Entitlement.fromJson(raw);
});

// ---------------------------------------------------------------------------
// Scan state machine
// ---------------------------------------------------------------------------

sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanUploading extends ScanState {
  final double progress; // 0..1
  const ScanUploading(this.progress);
}

class ScanAnalyzing extends ScanState {
  const ScanAnalyzing();
}

class ScanDone extends ScanState {
  final ScanResult result;
  const ScanDone(this.result);
}

class ScanNotCoa extends ScanState {
  final NotACoa info;
  const ScanNotCoa(this.info);
}

class ScanFailed extends ScanState {
  final String message;
  final int? statusCode;
  const ScanFailed(this.message, this.statusCode);
}

class ScanController extends Notifier<ScanState> {
  CancelToken? _cancelToken;

  @override
  ScanState build() => const ScanIdle();

  Future<void> scan({required List<int> bytes, required String filename, String origin = 'vendor'}) async {
    final api = ref.read(apiClientProvider);
    _cancelToken = CancelToken();
    state = const ScanUploading(0);
    try {
      final outcome = await api.scan(
        bytes: bytes,
        filename: filename,
        origin: origin,
        cancelToken: _cancelToken,
        onProgress: (sent, total) {
          if (total <= 0) return;
          if (sent >= total) {
            state = const ScanAnalyzing();
          } else {
            state = ScanUploading(sent / total);
          }
        },
      );
      switch (outcome) {
        case ScanSuccess(:final result):
          // History + entitlement live server-side now; the backend recorded
          // this scan and consumed a free scan/credit — refetch both.
          ref.invalidate(historyProvider);
          ref.invalidate(entitlementProvider);
          state = ScanDone(result);
        case ScanNotACoaOutcome(:final info):
          state = ScanNotCoa(info);
      }
    } on ScanCancelled {
      state = const ScanIdle();
    } on ApiException catch (e) {
      state = ScanFailed(e.message, e.statusCode);
    } catch (e) {
      state = ScanFailed('Something went wrong: $e', null);
    }
  }

  void cancel() => _cancelToken?.cancel('user_cancelled');

  void reset() => state = const ScanIdle();
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanState>(ScanController.new);

// ---------------------------------------------------------------------------
// Scan history — persisted server-side in the Supabase `scans` table (RLS
// returns only the signed-in user's rows). Survives sign-out / reload / device.
// ---------------------------------------------------------------------------

final historyProvider = FutureProvider<List<ScanResult>>((ref) async {
  ref.watch(authStateProvider);
  if (supabase.auth.currentSession == null) return const [];
  final rows = await supabase
      .from('scans')
      .select('result')
      .order('created_at', ascending: false)
      .limit(100);
  final out = <ScanResult>[];
  for (final row in rows as List) {
    final res = row['result'];
    if (res is Map) {
      try {
        out.add(ScanResult.fromJson(Map<String, dynamic>.from(res)));
      } catch (_) {
        // Skip any row whose stored payload doesn't parse.
      }
    }
  }
  return out;
});

/// The result currently being viewed on the results screen.
class SelectedResultNotifier extends Notifier<ScanResult?> {
  @override
  ScanResult? build() => null;
  void set(ScanResult? r) => state = r;
}

final selectedResultProvider =
    NotifierProvider<SelectedResultNotifier, ScanResult?>(SelectedResultNotifier.new);
