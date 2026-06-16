import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ludic.dart';
import '../../core/theme.dart';
import '../../core/verdict.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../onboarding/onboarding_controller.dart';
import '../onboarding/trust_profile.dart';
import '../onboarding/trust_profile_card.dart';
import '../shared/widgets/debug_panel.dart';
import '../shared/widgets/disclaimer.dart';
import '../shared/widgets/hard_check_tile.dart';
import '../shared/widgets/lab_badge.dart';
import '../shared/widgets/limitations_card.dart';
import '../shared/widgets/ludic_widgets.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';
import '../shared/widgets/score_gauge.dart';
import '../shared/widgets/verdict_tag.dart';
import 'synthesis_card.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(selectedResultProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: const _HelixBrand(),
      ),
      body: MoleculeBackground(
        child: result == null
            ? const _NoResult()
            : PageBody(child: _ResultBody(result: result)),
      ),
    );
  }
}

/// HELIX wordmark: accent scan plate + Space Grotesk title.
class _HelixBrand extends StatelessWidget {
  const _HelixBrand();

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Row(
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
        Text('HELIX',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: c.ink)),
      ],
    );
  }
}

class _NoResult extends StatelessWidget {
  const _NoResult();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No result to show.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => context.go('/'), child: const Text('Scan a COA')),
        ],
      ),
    );
  }
}

class _ResultBody extends ConsumerWidget {
  const _ResultBody({required this.result});
  final ScanResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final auth = result.authenticity;
    final authStyle = VerdictStyle.authenticity(auth.label, brightness);
    final knownLab = result.hardChecks.byName('known_lab');
    final janoshik = result.hardChecks.byName('janoshik');
    final verifiability = result.hardChecks.byName('verifiability');
    final docType = result.hardChecks.byName('doc_type');
    final findings = result.hardChecks.findings;
    // Phase C: additive + conditional — only when the user came through the
    // onboarding (answers exist). Standalone scans render exactly as before.
    final answers = ref.watch(onboardingControllerProvider);
    final showTrustProfile = answers.values.isNotEmpty;

    // Approved HELIX hierarchy: hero → verify → limitations → lab → chips →
    // completeness → findings → batch-match → trust profile → scan-another →
    // debug → disclaimer. Cards below the hero cascade in after the reveal.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _CaseHeader(result: result, docType: docType),
        const SizedBox(height: 12),
        _HeroCard(auth: auth, style: authStyle),
        _Cascade(
          delayMs: 1500,
          children: [
            // Synthesis: the plain-language conclusion across all three
            // categories + recommendation (replaces the old standalone alert
            // banner — null-result concerns now live in Values + the summary).
            if (result.synthesis != null) SynthesisCard(synthesis: result.synthesis!),
            if (janoshik != null &&
                janoshik.isPendingVerification &&
                janoshik.verificationUrl != null)
              _VerifyCta(
                  url: janoshik.verificationUrl!,
                  taskNumber: janoshik.taskNumber,
                  uniqueKey: janoshik.uniqueKey)
            else if (verifiability != null &&
                verifiability.status == 'verifiable' &&
                verifiability.verificationUrl != null)
              _VerifyCta(url: verifiability.verificationUrl!)
            else if (verifiability != null && verifiability.status == 'no_verification_path')
              const _NoVerifyPath(),
            if (result.limitations.isNotEmpty) LimitationsCard(items: result.limitations),
            ...result.notes.map((n) => _NoteBanner(text: n)),
            if (knownLab != null && knownLab.isPassing) LabBadge(knownLab: knownLab),
            // Category 3 — the measured values and their assessments.
            if (result.synthesis != null) ValuesCard(values: result.synthesis!.values),
            _DetectedChips(result: result),
            _CompletenessCard(comp: result.completeness),
            _FindingsCard(findings: findings),
            if (showTrustProfile)
              TrustProfileCard(
                profile: buildTrustProfile(answers, scan: result),
                title: 'Your trust profile · your answers + this COA',
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 16),
              label: Text(showTrustProfile ? 'Scan another COA (same profile)' : 'Scan another COA'),
              onPressed: () => context.go('/'),
            ),
            // A persisted trust profile is reconciled into every scan. Offer a
            // clean restart so a DIFFERENT product/vendor isn't judged against
            // the previous one's answers.
            if (showTrustProfile) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Different product — start a new trust guide'),
                onPressed: () {
                  ref.read(onboardingControllerProvider.notifier).reset();
                  context.go('/onboarding');
                },
              ),
            ],
            DebugPanel(result: result),
            const DisclaimerBanner(),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// "SCAN RESULT" microtag + mono filename + doc-type specimen chip.
class _CaseHeader extends StatelessWidget {
  const _CaseHeader({required this.result, required this.docType});
  final ScanResult result;
  final HardCheck? docType;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final isThirdParty = docType?.status == 'third_party_lab';
    final showDocChip =
        docType != null && (isThirdParty || docType!.status == 'manufacturer_qc');
    final chipColor = isThirdParty ? c.vGreen : c.vAmber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SCAN RESULT', style: HelixText.microtag(c.ink3)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(result.filename,
                style: HelixText.data(c.ink, size: 13, weight: FontWeight.w600)),
            if (showDocChip)
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: chipColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isThirdParty ? Icons.science_outlined : Icons.inventory_2_outlined,
                        size: 11, color: chipColor),
                    const SizedBox(width: 6),
                    Text(isThirdParty ? 'THIRD-PARTY LAB' : 'MANUFACTURER / IN-HOUSE QC',
                        style: GoogleFonts.ibmPlexMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.44,
                            color: chipColor)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Hero card: 3px glowing verdict strip, NeonGauge ritual, verdict tag stamping
/// in with a single light haptic, backend copy verbatim, lime XP line.
/// Molecule confetti for authentic verdicts only.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.auth, required this.style});
  final AxisScore auth;
  final VerdictStyle style;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final authentic = auth.label == 'likely_authentic';
    return Card(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: style.color,
                  boxShadow: c.isDark
                      ? [BoxShadow(color: style.glowOn(c), blurRadius: 14)]
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 19, 16, 18),
                child: Column(
                  children: [
                    Text('DOCUMENT AUTHENTICITY', style: HelixText.microtag(c.ink3)),
                    const SizedBox(height: 12),
                    ScoreGauge(score: auth.score, color: style.color, size: 200),
                    const SizedBox(height: 12),
                    _VerdictReveal(
                      child: VerdictTag(
                          color: style.color, icon: style.icon, label: style.shortLabel),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Text(auth.copy,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14.5, height: 1.5, color: c.ink)),
                    ),
                    const SizedBox(height: 10),
                    _Delayed(
                      delayMs: 1720, // 120ms after the verdict copy settles
                      child: XpLine(
                          xp: Ludic.xpForBand(auth.label),
                          caption: Ludic.captionForBand(auth.label)),
                    ),
                    const SizedBox(height: 12),
                    _Delayed(
                      delayMs: 1900,
                      child: TextButton.icon(
                        icon: Icon(Icons.ios_share, size: 16, color: c.ink2),
                        label: Text('Share verdict card',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: c.ink2)),
                        onPressed: () => context.push('/share'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (authentic && kLudicEnergy != LudicEnergy.clinical)
            const Positioned.fill(
              child: _Delayed(delayMs: 1340, child: MoleculeConfetti()),
            ),
        ],
      ),
    );
  }
}

/// Stamp-settle reveal for the verdict tag: scale 1.06→1.0 + fade, 260ms,
/// with exactly one light haptic — here and nowhere else.
class _VerdictReveal extends StatefulWidget {
  const _VerdictReveal({required this.child});
  final Widget child;

  @override
  State<_VerdictReveal> createState() => _VerdictRevealState();
}

class _VerdictRevealState extends State<_VerdictReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
  late final Animation<double> _anim =
      CurvedAnimation(parent: _ctrl, curve: const Cubic(0.2, 1.3, 0.4, 1));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _ctrl.value = 1;
        return;
      }
      // land as the gauge arc finishes (240ms ticks + 1100ms sweep)
      await Future<void>.delayed(const Duration(milliseconds: 1340));
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(
        opacity: _anim.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 1.06 - 0.06 * _anim.value, child: child),
      ),
      child: widget.child,
    );
  }
}

/// Shows [child] after [delayMs] (immediately under reduced motion), fading in.
class _Delayed extends StatefulWidget {
  const _Delayed({required this.delayMs, required this.child});
  final int delayMs;
  final Widget child;

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        setState(() => _show = true);
        return;
      }
      Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) setState(() => _show = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: _show ? widget.child : Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: widget.child),
    );
  }
}

/// Staggered entrance for the cards below the hero: 12px slide-up + fade,
/// 320ms each, 70ms stagger, top-to-bottom, after the verdict has stamped.
class _Cascade extends StatefulWidget {
  const _Cascade({required this.children, this.delayMs = 0});
  final List<Widget> children;
  final int delayMs;

  @override
  State<_Cascade> createState() => _CascadeState();
}

class _CascadeState extends State<_Cascade> with SingleTickerProviderStateMixin {
  static const _itemMs = 320;
  static const _staggerMs = 70;

  late final int _totalMs =
      _itemMs + _staggerMs * (widget.children.length - 1).clamp(0, 100);
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: Duration(milliseconds: _totalMs));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _ctrl.value = 1;
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: widget.delayMs));
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final start = i * _staggerMs / _totalMs;
              final end = (i * _staggerMs + _itemMs) / _totalMs;
              final t = Curves.easeOut.transform(
                  ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0));
              return Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: widget.children[i],
            ),
          ),
      ],
    );
  }
}

/// Primary verify CTA with the neon halo and a mono sub-line (task # · key).
/// Opening the lab's page counts as a source check (Source Checker badge).
class _VerifyCta extends ConsumerWidget {
  const _VerifyCta({required this.url, this.taskNumber, this.uniqueKey});
  final String url;
  final String? taskNumber;
  final String? uniqueKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '');
    final sub = [
      if (taskNumber != null) 'TASK #$taskNumber',
      if (uniqueKey != null) 'KEY $uniqueKey',
    ].join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: c.isDark
            ? [BoxShadow(color: c.accentGlow, blurRadius: 22, spreadRadius: -4)]
            : null,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10)),
        onPressed: () async {
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) {
            ref.read(ludicProvider.notifier).awardSourceCheck();
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open $url')),
            );
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.open_in_new, size: 15),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(host != null ? 'Verify on $host' : 'Verify with the lab',
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: GoogleFonts.ibmPlexMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.63,
                      color: c.accentInk.withValues(alpha: 0.75))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quiet hairline row when the backend found no independent verification path.
class _NoVerifyPath extends StatelessWidget {
  const _NoVerifyPath();

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.close, size: 13, color: c.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Text('No independent verification path found',
                style: TextStyle(fontSize: 13.5, color: c.ink2)),
          ),
        ],
      ),
    );
  }
}

class _CompletenessCard extends StatelessWidget {
  const _CompletenessCard({required this.comp});
  final AxisScore comp;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final style = VerdictStyle.completeness(comp.label, Theme.of(context).brightness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // linear meter — visually subordinate to the dial; teal = inventory
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('REPORT COMPLETENESS · ${style.shortLabel}',
                      style: HelixText.microtag(c.ink2)),
                ),
                Text.rich(
                  TextSpan(
                    style: HelixText.data(c.cTeal, size: 13, weight: FontWeight.w600),
                    children: [
                      TextSpan(text: '${comp.score}'),
                      TextSpan(
                          text: '/100',
                          style: HelixText.data(c.ink3, size: 13, weight: FontWeight.w400)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(color: c.surface3),
                    FractionallySizedBox(
                      widthFactor: (comp.score / 100).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                            color: c.cTeal, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(comp.copy, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.ink2)),
            if (comp.checklist.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: c.line2),
              const SizedBox(height: 12),
              _ChecklistGrid(items: comp.checklist),
            ],
          ],
        ),
      ),
    );
  }
}

/// Present/absent grid of expected COA sections — the "what to look for" view.
class _ChecklistGrid extends StatelessWidget {
  const _ChecklistGrid({required this.items});
  final List<ChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final present = items.where((i) => i.present).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('$present OF ${items.length} SECTIONS PRESENT',
                  style: HelixText.microtag(c.ink3)),
            ),
            Text("missing isn't proof of a problem",
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: c.ink3)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: items.map((i) {
            return SizedBox(
              width: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: i.present ? c.wash(c.cTeal) : c.surface3,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(i.present ? Icons.check : Icons.close,
                        size: 11, color: i.present ? c.cTeal : c.ink3),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(i.label,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: i.present ? c.ink : c.ink3)),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text('Missing sections aren’t proof of a problem — ask the vendor for them.',
            style: TextStyle(fontSize: 11.5, height: 1.3, color: c.ink2)),
      ],
    );
  }
}

/// Single findings card: header with ✓/⚠/✕ counts, hairline-divided check rows.
class _FindingsCard extends StatelessWidget {
  const _FindingsCard({required this.findings});
  final List<HardCheck> findings;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final pass = findings.where((f) => f.isPassing).length;
    final warn = findings.where((f) => f.isWarning).length;
    final fail = findings.where((f) => f.isFailing).length;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('CHECKS ON THIS DOCUMENT', style: HelixText.microtag(c.ink3)),
                ),
                Text('$pass✓ · $warn⚠ · $fail✕', style: HelixText.data(c.ink3, size: 10.5)),
              ],
            ),
          ),
          if (findings.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text('No notable findings.', style: TextStyle(color: c.ink2)),
            )
          else
            ...findings.map((f) => HardCheckTile(check: f)),
        ],
      ),
    );
  }
}

/// Specimen-tag chips for detected document facts — all mono, squarish.
class _DetectedChips extends StatelessWidget {
  const _DetectedChips({required this.result});
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final s = result.summary;
    // Detected facts only — quantitative values (purity %, measured mass) now
    // live in the Measured Values card with their assessments.
    final chips = <Widget>[
      if (s.peptideDetected != null) _chip(c, s.peptideDetected!.toUpperCase()),
      if (s.msTechniqueDetected != null) _chip(c, s.msTechniqueDetected!.toUpperCase()),
      _chip(c, '${result.inputType.toUpperCase()} INPUT'),
    ];
    return Wrap(spacing: 7, runSpacing: 7, children: chips);
  }

  Widget _chip(HelixColors c, String label) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface3,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Text(label,
          style: GoogleFonts.ibmPlexMono(
              fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.44, color: c.ink2)),
    );
  }
}

class _NoteBanner extends StatelessWidget {
  const _NoteBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: c.ink2),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(text, style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink2))),
        ],
      ),
    );
  }
}
