import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ludic.dart';
import '../../core/theme.dart';
import '../shared/widgets/ludic_widgets.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';
import 'onboarding_controller.dart';
import 'onboarding_models.dart';

/// The "Trust Journey": a skippable, educational question flow that ends at the
/// COA scanner. Purely additive — the scanner ('/') remains fully standalone.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _index = 0;

  // Self-testers (own independent lab COA) skip the vendor-purchase questions —
  // source trust is moot when you commissioned the test yourself.
  static const _selfSkip = {'vendor', 'coa_source', 'options'};

  List<OnboardingStep> get _steps {
    // ref.read (not watch): build() already watches the controller, so the step
    // list recomputes on answer changes; callbacks (_next/_back) can read safely.
    final self = ref.read(onboardingControllerProvider).single('coa_origin') == 'self';
    if (!self) return kOnboardingSteps;
    return kOnboardingSteps.where((s) => !_selfSkip.contains(s.id)).toList();
  }

  Future<void> _leaveToScanner() async {
    await ref.read(onboardingControllerProvider.notifier).markSeen();
    if (mounted) context.go('/');
  }

  Future<void> _finishToSummary() async {
    await ref.read(onboardingControllerProvider.notifier).markSeen();
    if (mounted) context.go('/onboarding/summary');
  }

  void _next() {
    if (_index < _steps.length - 1) {
      setState(() => _index++);
    } else {
      _finishToSummary();
    }
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final step = _steps[_index];
    final answers = ref.watch(onboardingControllerProvider);
    final answered = answers.isAnswered(step);
    final isLast = _index == _steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _index > 0
            ? IconButton(icon: const Icon(Icons.chevron_left), onPressed: _back)
            : null,
        title: const SizedBox.shrink(),
        actions: [
          TextButton(
            onPressed: _leaveToScanner,
            child: const Text('Skip to COA check'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: _SegmentedProgress(step: _index + 1, total: _steps.length),
        ),
      ),
      body: MoleculeBackground(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(step.title, style: Theme.of(context).textTheme.headlineSmall),
              if (step.subtitle != null) ...[
                const SizedBox(height: 8),
                Text(step.subtitle!,
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2)),
              ],
              const SizedBox(height: 16),

              if (step.kind == StepKind.single)
                ...step.options.map((o) => _OptionTile(
                      label: o.label,
                      selected: answers.single(step.id) == o.value,
                      multi: false,
                      onTap: () {
                        ref
                            .read(onboardingControllerProvider.notifier)
                            .setSingle(step.id, o.value);
                        // Actually comparing the vial to the COA (lot or cap
                        // photo) is a verification habit — Batch Matcher badge.
                        if ((step.id == 'batch' || step.id == 'cap_match') &&
                            (o.value == 'matches' || o.value == 'different')) {
                          ref.read(ludicProvider.notifier).awardBatchCheck();
                        }
                      },
                    )),
              if (step.kind == StepKind.multi)
                ...step.options.map((o) => _OptionTile(
                      label: o.label,
                      selected: answers.multi(step.id).contains(o.value),
                      multi: true,
                      onTap: () => ref
                          .read(onboardingControllerProvider.notifier)
                          .toggleMulti(step.id, o.value),
                    )),

              if (step.whyBody.isNotEmpty) ...[
                const SizedBox(height: 8),
                _WhyCard(title: step.whyTitle, body: step.whyBody, redFlags: step.redFlags),
              ],

              const SizedBox(height: 24),
              Row(
                children: [
                  if (_index > 0) OutlinedButton(onPressed: _back, child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    onPressed: answered ? _next : null,
                    child: Text(isLast ? 'See my trust profile' : 'Continue'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented progress bars (4px, accent fill + glow) with the mono trust-guide
/// counter and the lime "+10 XP / ANSWER" incentive.
class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        children: [
          Row(
            children: List.generate(total, (i) {
              final filled = i < step;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: filled ? c.accent : c.surface3,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: filled && c.isDark
                        ? [BoxShadow(color: c.accentGlow, blurRadius: 8, spreadRadius: -2)]
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TRUST GUIDE · $step OF $total', style: HelixText.microtag(c.ink3)),
              LudicGate(
                child: Text('+${Ludic.xpPerAnswer} XP / ANSWER',
                    style: HelixText.microtag(c.xp)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.multi, required this.onTap});
  final String label;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? c.accentDim : c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.accent : c.line, width: 1.5),
            boxShadow: selected && c.isDark
                ? [BoxShadow(color: c.accentGlow, blurRadius: 18, spreadRadius: -8)]
                : null,
          ),
          child: Row(
            children: [
              // custom radio / check marker
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: multi ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: multi ? BorderRadius.circular(5) : null,
                  border: Border.all(color: selected ? c.accent : c.ink3, width: 1.5),
                  color: multi && selected ? c.accent : null,
                ),
                child: selected
                    ? multi
                        ? Icon(Icons.check, size: 12, color: c.accentInk)
                        : Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: c.ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Teaching card: teal border + "⌬ WHY THIS MATTERS" microtag; red flags carry
/// the amber caution mark (educational, not alarmist).
class _WhyCard extends StatelessWidget {
  const _WhyCard({required this.title, required this.body, required this.redFlags});
  final String title;
  final String body;
  final List<String> redFlags;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cTeal),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⌬ ${title.toUpperCase()}', style: HelixText.microtag(c.cTeal)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(fontSize: 13, height: 1.55, color: c.ink2)),
          if (redFlags.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...redFlags.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 13, color: c.vAmber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Red flag: $r',
                            style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink2)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
