import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth.dart';
import '../../core/config.dart';
import '../../core/entitlement.dart';
import '../../core/theme.dart';
import '../onboarding/onboarding_controller.dart';
import '../../providers/providers.dart';
import '../../services/file_input.dart';
import '../shared/widgets/ludic_widgets.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';

/// These fire once per page load (client-side nav back to home shouldn't
/// re-trigger them); the launch params are captured in main().
bool _checkoutSuccessHandled = false;
bool _fromRedirectHandled = false;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();

    // Returning from Google OAuth with a saved destination (e.g. the trust
    // profile teaser): route there instead of leaving the user on the scanner.
    if (!_fromRedirectHandled) {
      final from = launchFromParam;
      if (from != null && from.isNotEmpty && from != '/') {
        _fromRedirectHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(from);
        });
      }
    }

    // Returning from Stripe Checkout (success_url = /?checkout=success).
    if (!_checkoutSuccessHandled && launchCheckoutParam == 'success') {
      _checkoutSuccessHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment successful — activating your scans…'),
        ));
        _refreshAfterCheckout();
      });
    }
  }

  /// The Stripe webhook can land a moment after the redirect, so poll the
  /// entitlement a few times until the purchase shows up — no manual reload.
  Future<void> _refreshAfterCheckout() async {
    for (var i = 0; i < 6; i++) {
      ref.invalidate(entitlementProvider);
      Entitlement? ent;
      try {
        ent = await ref.read(entitlementProvider.future);
      } catch (_) {
        ent = null;
      }
      if (!mounted) return;
      if (ent != null && ent.canScan) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your scans are ready.')));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }

  Future<void> _pick(Future<PickedFile?> Function() picker) async {
    // Must be signed in to scan.
    if (ref.read(currentUserProvider) == null) {
      context.go('/sign-in?from=/');
      return;
    }
    // Entitlement gate: free monthly scan / credits / active subscription.
    Entitlement? ent;
    try {
      ent = await ref.read(entitlementProvider.future);
    } catch (_) {
      ent = null;
    }
    if (!mounted) return;
    if (ent == null || !ent.canScan) {
      context.go('/paywall');
      return;
    }
    try {
      final file = await picker();
      if (file == null) return; // cancelled
      // Self-testers (own independent lab COA) get origin='self' so results say
      // "ask the lab" not "ask the vendor"; default vendor otherwise.
      final origin = ref.read(onboardingControllerProvider).single('coa_origin') == 'self'
          ? 'self'
          : 'vendor';
      ref.read(scanControllerProvider.notifier).scan(bytes: file.bytes, filename: file.name, origin: origin);
      if (mounted) context.go('/scanning');
    } on FileInputException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: c.accentDim,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.accent),
              ),
              child: Icon(Icons.qr_code_scanner, size: 12, color: c.accent),
            ),
            const SizedBox(width: 9),
            const Text('Pep Trust'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => context.go('/history'),
          ),
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.go('/about'),
          ),
          Consumer(builder: (context, ref, _) {
            final user = ref.watch(currentUserProvider);
            if (user == null) {
              return TextButton(
                onPressed: () => context.go('/sign-in'),
                child: const Text('Sign in'),
              );
            }
            return PopupMenuButton<String>(
              tooltip: 'Account',
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (v) async {
                if (v == 'signout') await ref.read(authControllerProvider).signOut();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(user.email ?? 'Signed in',
                      style: TextStyle(fontSize: 12, color: c.ink3)),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(value: 'signout', child: Text('Sign out')),
              ],
            );
          }),
        ],
      ),
      body: MoleculeBackground(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              RankBar(onTap: () => context.go('/achievements')),
              const SizedBox(height: 18),
              Text('Trust the data,\nnot the label.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                      letterSpacing: -0.26,
                      color: c.ink)),
              const SizedBox(height: 8),
              Text(
                'Upload a peptide COA (PDF or image). We read it, cross-check the lab '
                'and known peptide masses, and score how authentic and complete it looks.',
                style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
              ),
              const SizedBox(height: 16),
              _ScanCard(
                onPickFile: () => _pick(FileInput.pickDocument),
                onPickPhoto: kIsWeb ? null : () => _pick(FileInput.pickPhoto),
              ),
              const SizedBox(height: 10),
              const _EntitlementStatus(),
              const SizedBox(height: 14),
              const StreakBar(),
              const SizedBox(height: 24),
              const _StatusFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dashed-accent scan dropzone: glowing icon plate + the two pickers.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onPickFile, this.onPickPhoto});

  final VoidCallback onPickFile;
  final VoidCallback? onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return CustomPaint(
      painter: _DashedBorderPainter(color: c.accent, radius: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        decoration: BoxDecoration(
          color: c.accentDim,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.line),
                boxShadow: c.isDark
                    ? [BoxShadow(color: c.accentGlow, blurRadius: 22, spreadRadius: -6)]
                    : null,
              ),
              child: Icon(Icons.qr_code_scanner, size: 22, color: c.accent),
            ),
            const SizedBox(height: 12),
            Text('Scan a COA',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 3),
            Text('PDF, PNG, JPG or WEBP · up to 20 MB',
                style: TextStyle(fontSize: 13, color: c.ink2)),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: c.isDark
                    ? [BoxShadow(color: c.accentGlow, blurRadius: 22, spreadRadius: -4)]
                    : null,
              ),
              child: FilledButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Choose a file'),
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                onPressed: onPickFile,
              ),
            ),
            if (onPickPhoto != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take a photo'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                onPressed: onPickPhoto,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect.deflate(0.5));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Scan entitlement status under the scan card — free scan / credits /
/// subscription. Tappable → paywall. Hidden when signed out.
class _EntitlementStatus extends ConsumerWidget {
  const _EntitlementStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    if (ref.watch(currentUserProvider) == null) return const SizedBox.shrink();
    final (Color color, String label) = ref.watch(entitlementProvider).when(
      data: (e) {
        if (e == null) return (c.ink3, '');
        if (e.subscriptionActive) {
          return (c.vGreen, '● ${(e.plan ?? 'PLAN').toUpperCase()} ACTIVE · UNLIMITED SCANS');
        }
        if (e.credits > 0) {
          return (c.vGreen, '● ${e.credits} SCAN CREDIT${e.credits == 1 ? '' : 'S'} LEFT');
        }
        if (e.freeScanAvailable) return (c.vGreen, '● 1 FREE SCAN THIS MONTH');
        return (c.ink3, 'NO SCANS LEFT · CHOOSE A PLAN →');
      },
      loading: () => (c.ink3, '…'),
      error: (_, _) => (c.ink3, ''),
    );
    if (label.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => context.go('/paywall'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(child: Text(label, style: HelixText.microtag(color, size: 10))),
      ),
    );
  }
}

/// Mono instrument footer: SERVICE ONLINE dot (live backend health, tap to
/// re-check) + RESEARCH USE ONLY. Same data as the old status pill.
class _StatusFooter extends ConsumerWidget {
  const _StatusFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    final health = ref.watch(healthProvider);
    final (ui.Color dot, String text, bool spin) = health.when(
      data: (ok) => ok ? (c.vGreen, 'SERVICE ONLINE', false) : (c.vRed, 'SERVICE UNREACHABLE', false),
      loading: () => (c.ink3, 'CHECKING SERVICE…', true),
      error: (_, _) => (c.vRed, 'SERVICE UNREACHABLE', false),
    );
    final label = AppConfig.useMock ? 'MOCK MODE (NO BACKEND)' : text;
    final dotColor = AppConfig.useMock ? c.vAmber : dot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => ref.invalidate(healthProvider),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (spin)
                    const SizedBox(
                        width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        boxShadow: c.isDark
                            ? [BoxShadow(color: dotColor.withValues(alpha: 0.6), blurRadius: 8)]
                            : null,
                      ),
                    ),
                  const SizedBox(width: 7),
                  Text(label, style: HelixText.microtag(c.ink3, size: 10.5)),
                  const SizedBox(width: 5),
                  Icon(Icons.refresh, size: 12, color: c.ink3),
                ],
              ),
            ),
            Text('RESEARCH USE ONLY', style: HelixText.microtag(c.ink3, size: 10.5)),
          ],
        ),
        const SizedBox(height: 6),
        Text(AppConfig.useMock ? '' : AppConfig.apiBaseUrl,
            style: HelixText.data(c.ink3, size: 10)),
      ],
    );
  }
}
