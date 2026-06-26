import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/about/about_screen.dart';
import '../features/achievements/achievements_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/legal/legal_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/prepurchase_checklist_screen.dart';
import '../features/onboarding/summary_screen.dart';
import '../features/onboarding/trust_profile_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/results/results_screen.dart';
import '../features/results/share_card.dart';
import '../features/scanning/scanning_screen.dart';

/// The app is public — anyone can browse, run the trust guide, and (for now)
/// scan. Sign-in is offered, not forced; the entitlement gate (free scan /
/// credits / subscription) is enforced later, together with Stripe. The only
/// redirect: after signing in, return the user to wherever they came from
/// (`?from=`), so the upcoming "sign in to reveal / to scan" prompts feel
/// seamless.
/// Where the app opens:
/// - Returning from Google OAuth → the saved destination (`?from=`).
/// - Returning from Stripe Checkout → home (for the success toast).
/// - Signed-in returning users → the scanner (home).
/// - First-time signed-out users → the welcome explainer (shown once).
/// - Returning signed-out users → the onboarding trust guide.
String _initialLocation(bool onboardingSeen) {
  final from = launchFromParam;
  if (from != null && from.isNotEmpty && from != '/') return from;
  if (launchCheckoutParam == 'success') return '/';
  if (supabase.auth.currentSession != null) return '/';
  return onboardingSeen ? '/onboarding' : '/welcome';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = GoRouterRefreshStream(supabase.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: _initialLocation(ref.read(onboardingSeenProvider)),
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = supabase.auth.currentSession != null;
      if (loggedIn && state.matchedLocation == '/sign-in') {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.isNotEmpty) ? from : '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/onboarding/summary', builder: (context, state) => const OnboardingSummaryScreen()),
      GoRoute(path: '/onboarding/checklist', builder: (context, state) => const PrePurchaseChecklistScreen()),
      GoRoute(path: '/trust-profile', builder: (context, state) => const TrustProfileScreen()),
      GoRoute(path: '/paywall', builder: (context, state) => const PaywallScreen()),
      GoRoute(path: '/scanning', builder: (context, state) => const ScanningScreen()),
      GoRoute(path: '/results', builder: (context, state) => const ResultsScreen()),
      GoRoute(path: '/share', builder: (context, state) => const ShareCardScreen()),
      GoRoute(path: '/history', builder: (context, state) => const HistoryScreen()),
      GoRoute(path: '/achievements', builder: (context, state) => const AchievementsScreen()),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(path: '/terms', builder: (context, state) => const LegalScreen(docKey: 'terms')),
      GoRoute(path: '/privacy', builder: (context, state) => const LegalScreen(docKey: 'privacy')),
      GoRoute(path: '/refund', builder: (context, state) => const LegalScreen(docKey: 'refund')),
    ],
  );
});
