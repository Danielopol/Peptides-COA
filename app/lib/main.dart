import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth.dart';
import 'core/config.dart';
import 'features/onboarding/onboarding_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture launch query params before Supabase.initialize rewrites the URL
  // during OAuth session detection (it strips the query string).
  launchFromParam = Uri.base.queryParameters['from'];
  launchCheckoutParam = Uri.base.queryParameters['checkout'];

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Ensure a `profiles` row exists for the signed-in user. This replaces the
  // auth.users DB trigger (which the SQL editor can't create due to auth-schema
  // permissions). Idempotent — runs on sign-in, initial session, and updates.
  supabase.auth.onAuthStateChange.listen((data) {
    final user = data.session?.user;
    if (user == null) return;
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.initialSession ||
        data.event == AuthChangeEvent.userUpdated) {
      supabase
          .from('profiles')
          .upsert({'id': user.id, 'email': user.email}).then(
        (_) {},
        onError: (Object _) {}, // best-effort; never block startup
      );
    }
  });

  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getBool('onboarding_seen') ?? false;
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        onboardingSeenProvider.overrideWithValue(seen),
      ],
      child: const CoaScannerApp(),
    ),
  );
}
