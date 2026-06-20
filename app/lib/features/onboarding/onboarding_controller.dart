import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_models.dart';

const String _kSeenKey = 'onboarding_seen';
const String _kAnswersKey = 'onboarding_answers';

/// SharedPreferences instance — overridden in main() after async init.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden in main'),
);

/// Whether the user has already seen/skipped onboarding (read once at startup,
/// used only to pick the router's initial location). Overridden in main().
final onboardingSeenProvider = Provider<bool>((ref) => false);

/// Holds the user's onboarding answers for the session and persists the
/// "seen" flag. Purely additive — touches nothing in the scan flow.
class OnboardingController extends Notifier<OnboardingAnswers> {
  @override
  OnboardingAnswers build() => _load();

  /// Restore persisted answers (survives reloads, incl. the OAuth round-trip).
  OnboardingAnswers _load() {
    final raw = ref.read(sharedPrefsProvider).getString(_kAnswersKey);
    if (raw == null) return const OnboardingAnswers();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final values = <String, Object>{};
      m.forEach((k, v) {
        if (v is String) {
          values[k] = v;
        } else if (v is List) {
          values[k] = v.map((e) => e.toString()).toSet();
        }
      });
      return OnboardingAnswers(values);
    } catch (_) {
      return const OnboardingAnswers();
    }
  }

  void setSingle(String stepId, String value) {
    state = state.withSingle(stepId, value);
    _persist();
  }

  void toggleMulti(String stepId, String value) {
    state = state.withToggle(stepId, value);
    _persist();
  }

  void reset() {
    state = const OnboardingAnswers();
    ref.read(sharedPrefsProvider).remove(_kAnswersKey);
  }

  void _persist() {
    final encodable = <String, Object>{};
    state.values.forEach((k, v) {
      encodable[k] = v is Set ? v.toList() : v;
    });
    ref.read(sharedPrefsProvider).setString(_kAnswersKey, jsonEncode(encodable));
  }

  /// Mark onboarding complete/skipped so later launches open the scanner.
  Future<void> markSeen() async {
    await ref.read(sharedPrefsProvider).setBool(_kSeenKey, true);
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingAnswers>(OnboardingController.new);
