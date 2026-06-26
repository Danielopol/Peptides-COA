import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';
import 'onboarding_controller.dart';

/// First-run welcome: explains, top-to-bottom, how the whole app works before
/// the trust guide. Shown once (marks onboarding "seen" on leave), then the app
/// opens straight on the trust guide / scanner for returning users.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _leave(WidgetRef ref, BuildContext context, String route) async {
    await ref.read(onboardingControllerProvider.notifier).markSeen();
    if (context.mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    return Scaffold(
      body: MoleculeBackground(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Brand hero
              Row(
                children: [
                  Image.asset('assets/logo.png', width: 34, height: 34),
                  const SizedBox(width: 11),
                  Text('Pep Trust',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: c.ink)),
                ],
              ),
              const SizedBox(height: 18),
              Text('Know what’s really in the vial',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 26, height: 1.15, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 10),
              Text(
                'The research-peptide market is largely unregulated. A Certificate of '
                'Analysis (COA) is the main evidence that what’s in the vial matches the '
                'label — but only if you can read and verify it. Here’s how Pep Trust '
                'walks you through it.',
                style: TextStyle(fontSize: 14, height: 1.55, color: c.ink2),
              ),
              const SizedBox(height: 22),

              _WelcomeCard(
                icon: Icons.groups_outlined,
                tag: 'WHO IT’S FOR',
                title: 'Anyone checking a peptide COA',
                body: 'Whether you’re buying from a vendor or running your own test, you '
                    'don’t need a chemistry background. Pep Trust translates the COA into '
                    'plain language so you can decide whether to trust it.',
              ),
              _WelcomeCard(
                icon: Icons.checklist_rtl,
                tag: 'STEP 1 · THE TRUST GUIDE',
                title: 'A few quick questions',
                body: 'A short, guided set of questions about your compound and its '
                    'paperwork. As you go, we point out what to check and the red flags to '
                    'avoid — so you learn what matters while you answer.',
              ),
              _WelcomeCard(
                icon: Icons.alt_route,
                tag: 'TAILORED TO YOU',
                title: 'The questions adapt to your COA’s origin',
                body: 'Tell us where the COA came from and the path changes: a vendor’s '
                    'report gets extra source-trust questions (who sold it, how it was '
                    'shared), while a test you commissioned yourself skips those — the '
                    'source is already you.',
                accent: c.cTeal,
              ),
              _WelcomeCard(
                icon: Icons.fast_forward_outlined,
                tag: 'NO TIME?',
                title: 'Skip straight to the scan',
                body: 'In a hurry or already know the basics? You can jump directly to the '
                    'COA scan from the welcome screen or any question — the guide is helpful, '
                    'never mandatory.',
              ),
              _WelcomeCard(
                icon: Icons.shield_outlined,
                tag: 'STEP 2 · YOUR PROFILE',
                title: 'Get a personal trust profile',
                body: 'After the questions, you get a trust profile that sums up your '
                    'situation, highlights what to watch for, and points you to the next '
                    'thing to verify.',
              ),
              _WelcomeCard(
                icon: Icons.document_scanner_outlined,
                tag: 'STEP 3 · THE SCAN',
                title: 'Scan the COA, get a clear diagnostic',
                body: 'Upload the COA (PDF or image). You get two scores — how authentic the '
                    'document looks and how complete the testing is — plus a plain-language '
                    'breakdown of every red flag. If the file isn’t a COA at all, we tell you.',
              ),
              _WelcomeCard(
                icon: Icons.card_giftcard_outlined,
                tag: 'ON THE HOUSE',
                title: 'Your first scan is free',
                body: 'Try the full diagnostic at no cost — no commitment. See exactly what '
                    'Pep Trust finds before deciding anything.',
                accent: c.xp,
              ),

              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                onPressed: () => _leave(ref, context, '/onboarding'),
                child: const Text('Start the trust guide'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                onPressed: () => _leave(ref, context, '/'),
                child: const Text('Skip to the COA scan'),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('RESEARCH USE ONLY', style: HelixText.microtag(c.ink3, size: 10.5)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// One explanation card in the top-down flow: accent icon plate + mono tag +
/// Space Grotesk title + body. Mirrors the home scan card / onboarding look.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.icon,
    required this.tag,
    required this.title,
    required this.body,
    this.accent,
  });

  final IconData icon;
  final String tag;
  final String title;
  final String body;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final a = accent ?? c.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: a.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: a.withValues(alpha: 0.5)),
              ),
              child: Icon(icon, size: 20, color: a),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tag, style: HelixText.microtag(a)),
                  const SizedBox(height: 5),
                  Text(title,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 16, fontWeight: FontWeight.w700, height: 1.2, color: c.ink)),
                  const SizedBox(height: 6),
                  Text(body, style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
