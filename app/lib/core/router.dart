import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../features/about/about_screen.dart';
import '../features/achievements/achievements_screen.dart';
import '../features/auth/sign_in_screen.dart';
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

/// Routes that don't require a signed-in session. Everything else (the scanner,
/// results, history, paywall, achievements) redirects to /sign-in when signed
/// out. The onboarding "trust guide" and About stay public so users can explore
/// before creating an account.
const _publicPrefixes = ['/sign-in', '/onboarding', '/about'];

bool _isPublic(String loc) =>
    _publicPrefixes.any((p) => loc == p || loc.startsWith('$p/'));

final routerProvider = Provider<GoRouter>((ref) {
  final seen = ref.watch(onboardingSeenProvider);
  final refresh = GoRouterRefreshStream(supabase.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: seen ? '/' : '/onboarding',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = supabase.auth.currentSession != null;
      final loc = state.matchedLocation;
      if (!loggedIn && !_isPublic(loc)) return '/sign-in';
      if (loggedIn && loc == '/sign-in') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
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
