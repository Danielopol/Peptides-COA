import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/models.dart' show ApiException;
import '../../providers/providers.dart';
import '../legal/legal_screen.dart' show legalLink;
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';

/// Paywall — shown when a signed-in user is out of scans (no free scan this
/// month, no credits, no active subscription). Four options; each starts a real
/// Stripe Checkout session and redirects the browser to Stripe.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;
  String? _busyPlan;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(page,
      duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  Future<void> _checkout(String plan) async {
    setState(() => _busyPlan = plan);
    try {
      final url = await ref.read(apiClientProvider).createCheckout(plan);
      // Same-tab redirect to Stripe Checkout (web).
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not start checkout. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    const specs = [
      _PlanSpec(
        plan: 'pack3',
        tag: 'PAY AS YOU GO',
        title: '3-Scan Pack',
        price: '\$5.99',
        unit: '3 scans',
        blurb: 'Three full verifications. Credits never expire and are only used '
            'when a scan completes — rejected files don’t burn one.',
        features: [
          '3 COA scans',
          'Credits never expire',
          'Full authenticity + completeness verdict',
        ],
        cta: 'Buy 3 scans',
      ),
      _PlanSpec(
        plan: 'pack10',
        tag: 'PAY AS YOU GO',
        title: '10-Scan Pack',
        price: '\$17.99',
        unit: '10 scans',
        blurb: 'Ten verifications at the best per-scan price. Credits never expire.',
        features: [
          '10 COA scans',
          'Best per-scan value',
          'Credits never expire',
        ],
        cta: 'Buy 10 scans',
      ),
      _PlanSpec(
        plan: 'monthly',
        tag: 'SUBSCRIPTION',
        title: 'Monthly',
        price: '\$6.99',
        unit: '/ month',
        blurb: 'Unlimited scans while active. For an active research cycle with '
            'several vendors and batches to compare.',
        features: [
          'Unlimited COA scans',
          'Auto-renews monthly',
          'Cancel anytime',
        ],
        cta: 'Start monthly',
      ),
      _PlanSpec(
        plan: 'yearly',
        tag: 'SUBSCRIPTION',
        title: 'Yearly',
        price: '\$49.99',
        unit: '/ year',
        blurb: 'Unlimited scans for a year — about \$4.17/month.',
        features: [
          'Unlimited COA scans',
          'Auto-renews yearly',
          'Best value vs monthly',
        ],
        cta: 'Start yearly',
        badge: 'BEST VALUE',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/')),
        title: const Text('Pep Trust'),
      ),
      body: MoleculeBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UNLOCK SCANNING', style: HelixText.microtag(c.accent)),
                  const SizedBox(height: 8),
                  Text('You’re out of scans.\nChoose how to continue.',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Everyone gets 1 free scan a month. For more, grab a credit pack '
                    'or go unlimited with a subscription.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: const MaterialScrollBehavior().copyWith(dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                }),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: specs.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _PlanPage(
                    spec: specs[i],
                    busy: _busyPlan == specs[i].plan,
                    anyBusy: _busyPlan != null,
                    onCheckout: () => _checkout(specs[i].plan),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: _page > 0 ? c.ink2 : c.surface3),
                    onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  ),
                  ...List.generate(specs.length, (i) {
                    final active = i == _page;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _goTo(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: active ? 22 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: active ? c.accent : c.surface3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    );
                  }),
                  IconButton(
                    icon: Icon(Icons.chevron_right,
                        color: _page < specs.length - 1 ? c.ink2 : c.surface3),
                    onPressed: _page < specs.length - 1 ? () => _goTo(_page + 1) : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14, left: 16, right: 16),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('By purchasing you agree to the ',
                      style: TextStyle(fontSize: 11.5, color: c.ink3)),
                  legalLink(context, 'Terms', '/terms', c.accent),
                  Text(' & ', style: TextStyle(fontSize: 11.5, color: c.ink3)),
                  legalLink(context, 'Refund Policy', '/refund', c.accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSpec {
  const _PlanSpec({
    required this.plan,
    required this.tag,
    required this.title,
    required this.price,
    required this.unit,
    required this.blurb,
    required this.features,
    required this.cta,
    this.badge,
  });

  final String plan; // 'pack3' | 'pack10' | 'monthly' | 'yearly'
  final String tag;
  final String title;
  final String price;
  final String unit;
  final String blurb;
  final List<String> features;
  final String cta;
  final String? badge;
}

class _PlanPage extends StatelessWidget {
  const _PlanPage({
    required this.spec,
    required this.busy,
    required this.anyBusy,
    required this.onCheckout,
  });

  final _PlanSpec spec;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return PageBody(
      maxWidth: 480,
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(spec.tag, style: HelixText.microtag(c.ink3))),
                  if (spec.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.xp.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.xp),
                      ),
                      child: Text(spec.badge!, style: HelixText.microtag(c.xp, size: 9.5)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(spec.price,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: -1,
                          color: c.ink)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(spec.unit.toUpperCase(), style: HelixText.data(c.ink3, size: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(spec.title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 19, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 8),
              Text(spec.blurb, style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2)),
              const SizedBox(height: 14),
              Divider(height: 1, color: c.line2),
              const SizedBox(height: 12),
              ...spec.features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: c.accentDim,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(Icons.check, size: 11, color: c.accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(f,
                              style: TextStyle(fontSize: 13.5, height: 1.35, color: c.ink)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                onPressed: anyBusy ? null : onCheckout,
                child: busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(spec.cta),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text('SECURE CHECKOUT VIA STRIPE', style: HelixText.microtag(c.ink3, size: 9.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
