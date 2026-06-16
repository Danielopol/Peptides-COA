import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/payments.dart';
import '../../core/theme.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';

/// SIMULATED paywall — shown the moment the user presses "check a COA" without
/// an active plan or credits. Three swipeable screens, one per option:
/// pay-per-scan $2 · monthly $7 · yearly $50 (orientative amounts).
/// The trust guide, trust profile and achievements stay free; only the scan
/// itself is gated. No real payment is processed at this stage.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );

  Future<void> _checkout(_PlanSpec spec) async {
    final c = HelixColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.line),
        ),
        title: Text('Simulated checkout',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 19, color: c.ink)),
        content: Text(
          '${spec.title} — ${spec.priceLabel}.\n\n'
          'This is a payment simulation: no real charge is made and no card is '
          'required. It only activates the plan inside the app.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Pay ${spec.priceLabel} (simulated)'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final payments = ref.read(paymentsProvider.notifier);
    switch (spec.plan) {
      case Plan.payPerScan:
        payments.buyScanCredit();
      case Plan.monthly:
      case Plan.yearly:
        payments.subscribe(spec.plan);
      case Plan.none:
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${spec.title} active (simulated) — you can scan now.')),
    );
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final state = ref.watch(paymentsProvider);

    final specs = [
      _PlanSpec(
        plan: Plan.payPerScan,
        tag: 'OPTION 1 · PAY PER SCAN',
        title: 'Pay per scan',
        price: '\$${Pricing.perScanUsd.toStringAsFixed(0)}',
        unit: '/ scan',
        priceLabel: '\$${Pricing.perScanUsd.toStringAsFixed(0)}',
        blurb: 'One credit, one full verification. The credit is only used when '
            'a scan completes — rejected files don’t burn it.',
        features: const [
          'Full authenticity + completeness verdict',
          'Findings with rule-level detail',
          'Lab verification link when available',
          'Credit never expires until used',
        ],
        cta: 'Continue — one scan',
      ),
      _PlanSpec(
        plan: Plan.monthly,
        tag: 'OPTION 2 · MONTHLY',
        title: 'Monthly',
        price: '\$${Pricing.monthlyUsd.toStringAsFixed(0)}',
        unit: '/ month',
        priceLabel: '\$${Pricing.monthlyUsd.toStringAsFixed(0)} / month',
        blurb: 'Unlimited scans while active. Made for an active research cycle '
            'with several vendors and batches to compare.',
        features: const [
          'Unlimited COA scans',
          'Everything in pay-per-scan',
          'Scan history across the period',
          'Cancel anytime (simulated)',
        ],
        cta: 'Start monthly',
      ),
      _PlanSpec(
        plan: Plan.yearly,
        tag: 'OPTION 3 · YEARLY',
        title: 'Yearly',
        price: '\$${Pricing.yearlyUsd.toStringAsFixed(0)}',
        unit: '/ year',
        priceLabel: '\$${Pricing.yearlyUsd.toStringAsFixed(0)} / year',
        blurb: 'The diligence habit, funded for a year — about '
            '\$${(Pricing.yearlyUsd / 12).toStringAsFixed(2)}/month.',
        features: const [
          'Unlimited COA scans for 12 months',
          'Everything in monthly',
          'Best value vs \$${84} of monthly renewals',
        ],
        cta: 'Start yearly',
        badge: 'BEST VALUE · SAVE 40%',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/')),
        title: const Text('HELIX'),
        actions: [
          if (state.plan != Plan.none)
            TextButton(
              onPressed: () {
                ref.read(paymentsProvider.notifier).clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Simulation reset — plan cleared.')),
                );
              },
              child: const Text('Reset (sim)'),
            ),
        ],
      ),
      body: MoleculeBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UNLOCK SCANNING · PAYMENT SIMULATION', style: HelixText.microtag(c.accent)),
                  const SizedBox(height: 8),
                  Text('The trust guide is free.\nScanning a COA is not.',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Pick how you want to pay for verification. Amounts are orientative — '
                    'no real charge is made in this preview.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
                  ),
                  if (state.canScan) ...[
                    const SizedBox(height: 10),
                    _CurrentPlanChip(state: state),
                  ],
                ],
              ),
            ),
            Expanded(
              // Mouse-drag swiping is off by default on Flutter web — enable
              // it so desktop users can move between the three plan screens.
              child: ScrollConfiguration(
                behavior: const MaterialScrollBehavior().copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: specs.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _PlanPage(
                    spec: specs[i],
                    onCheckout: () => _checkout(specs[i]),
                  ),
                ),
              ),
            ),
            // pager: chevrons + tappable dots
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
                            boxShadow: active && c.isDark
                                ? [BoxShadow(color: c.accentGlow, blurRadius: 8, spreadRadius: -2)]
                                : null,
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
    required this.priceLabel,
    required this.blurb,
    required this.features,
    required this.cta,
    this.badge,
  });

  final Plan plan;
  final String tag;
  final String title;
  final String price;
  final String unit;
  final String priceLabel;
  final String blurb;
  final List<String> features;
  final String cta;
  final String? badge;
}

class _PlanPage extends StatelessWidget {
  const _PlanPage({required this.spec, required this.onCheckout});

  final _PlanSpec spec;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return PageBody(
      maxWidth: 480,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: -1,
                          color: c.ink,
                          shadows: c.isDark
                              ? [Shadow(color: c.accentGlow, blurRadius: 18)]
                              : null)),
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
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: c.isDark
                      ? [BoxShadow(color: c.accentGlow, blurRadius: 22, spreadRadius: -4)]
                      : null,
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  onPressed: onCheckout,
                  child: Text(spec.cta),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text('SIMULATION · NO REAL CHARGE', style: HelixText.microtag(c.ink3, size: 9.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small status chip shown when something is already active (also reused on home).
class _CurrentPlanChip extends StatelessWidget {
  const _CurrentPlanChip({required this.state});
  final PaymentsState state;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final label = switch (state.plan) {
      Plan.payPerScan => '${state.credits} SCAN CREDIT${state.credits == 1 ? '' : 'S'} LEFT',
      Plan.monthly => 'MONTHLY ACTIVE · UNTIL ${_d(state.expiry)}',
      Plan.yearly => 'YEARLY ACTIVE · UNTIL ${_d(state.expiry)}',
      Plan.none => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.wash(c.vGreen),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.vGreen),
      ),
      child: Text(label, style: HelixText.microtag(c.vGreen, size: 9.5)),
    );
  }

  static String _d(DateTime? d) => d == null
      ? '—'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
