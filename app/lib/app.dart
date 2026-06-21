import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

class CoaScannerApp extends ConsumerWidget {
  const CoaScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Pep Trust — Peptide COA Scanner',
      debugShowCheckedModeBanner: false,
      theme: HelixTheme.light(),
      darkTheme: HelixTheme.dark(),
      // Dark-first: HELIX is a lab-at-night instrument; light mode is the
      // clinical-paper fallback (no glow, no lattice) kept for printouts.
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
