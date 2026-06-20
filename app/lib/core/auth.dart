import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Convenience accessor for the singleton Supabase client.
SupabaseClient get supabase => Supabase.instance.client;

/// Query params captured in main() BEFORE `Supabase.initialize` rewrites the URL
/// while detecting the OAuth session (which strips the query). Consumed once by
/// the home screen to handle a post-checkout / post-OAuth return.
String? launchFromParam;
String? launchCheckoutParam;

/// Emits on every auth change (sign-in, sign-out, token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// The current signed-in user, or null. Rebuilds when [authStateProvider] ticks.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return supabase.auth.currentUser;
});

/// Auth actions. Methods throw [AuthException] on failure — surface
/// `e.message` to the user.
class AuthController {
  Future<void> signInWithPassword(String email, String password) =>
      supabase.auth.signInWithPassword(email: email.trim(), password: password);

  Future<AuthResponse> signUp(String email, String password) =>
      supabase.auth.signUp(email: email.trim(), password: password);

  /// Web: redirects back to the current origin (optionally with `?from=` so the
  /// app can return the user to where they started, e.g. the trust profile).
  /// Native: uses a custom scheme (wire the deep link when a mobile build ships).
  Future<void> signInWithGoogle({String? returnTo}) {
    String redirect;
    if (kIsWeb) {
      redirect = Uri.base.origin;
      if (returnTo != null && returnTo.isNotEmpty) {
        redirect = '$redirect/?from=${Uri.encodeComponent(returnTo)}';
      }
    } else {
      redirect = 'io.peptidestrust://login-callback';
    }
    return supabase.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirect);
  }

  Future<void> signOut() => supabase.auth.signOut();
}

final authControllerProvider = Provider<AuthController>((ref) => AuthController());

/// Adapts a [Stream] into a [Listenable] so GoRouter can re-run its redirect
/// whenever auth state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
