import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_models.dart';

const String _kSeenKey = 'onboarding_seen';

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
  OnboardingAnswers build() => const OnboardingAnswers();

  void setSingle(String stepId, String value) =>
      state = state.withSingle(stepId, value);

  void toggleMulti(String stepId, String value) =>
      state = state.withToggle(stepId, value);

  void reset() => state = const OnboardingAnswers();

  /// Mark onboarding complete/skipped so later launches open the scanner.
  Future<void> markSeen() async {
    await ref.read(sharedPrefsProvider).setBool(_kSeenKey, true);
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingAnswers>(OnboardingController.new);
