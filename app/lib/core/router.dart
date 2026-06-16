import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/about/about_screen.dart';
import '../features/achievements/achievements_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/prepurchase_checklist_screen.dart';
import '../features/onboarding/summary_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/results/results_screen.dart';
import '../features/results/share_card.dart';
import '../features/scanning/scanning_screen.dart';

/// Plain routes — no auth gating in this MVP. First launch opens the (skippable)
/// onboarding; once seen, it opens the scanner. The scanner/results routes are
/// unchanged and fully usable on their own.
final routerProvider = Provider<GoRouter>((ref) {
  final seen = ref.watch(onboardingSeenProvider);
  return GoRouter(
    initialLocation: seen ? '/' : '/onboarding',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/onboarding/summary', builder: (context, state) => const OnboardingSummaryScreen()),
      GoRoute(path: '/onboarding/checklist', builder: (context, state) => const PrePurchaseChecklistScreen()),
      GoRoute(path: '/paywall', builder: (context, state) => const PaywallScreen()),
      GoRoute(path: '/scanning', builder: (context, state) => const ScanningScreen()),
      GoRoute(path: '/results', builder: (context, state) => const ResultsScreen()),
      GoRoute(path: '/share', builder: (context, state) => const ShareCardScreen()),
      GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
      GoRoute(path: '/achievements', builder: (context, state) => const AchievementsScreen()),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
    ],
  );
});
