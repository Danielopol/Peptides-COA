import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/ludic.dart';
import '../../core/payments.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';
import '../results/not_a_coa_view.dart';
import '../results/scan_error_view.dart';

class ScanningScreen extends ConsumerWidget {
  const ScanningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate to results once the scan succeeds. XP is awarded exactly here —
    // one ScanDone transition per scan — and rewards the habit, not the verdict
    // (catching a red flag pays more than a clean scan).
    ref.listen<ScanState>(scanControllerProvider, (prev, next) {
      if (next is ScanDone && prev is! ScanDone) {
        // A pay-per-scan credit is burned only on a COMPLETED scan —
        // not-a-COA and failures don't consume it (simulated payments).
        ref.read(paymentsProvider.notifier).consumeCredit();
        ref.read(ludicProvider.notifier).awardScan(next.result.authenticity.label);
        ref.read(selectedResultProvider.notifier).set(next.result);
        context.go('/results');
      }
    });

    final state = ref.watch(scanControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(scanControllerProvider.notifier).cancel();
            ref.read(scanControllerProvider.notifier).reset();
            context.go('/');
          },
        ),
        title: const Text('ANALYZING'),
      ),
      body: MoleculeBackground(
        child: PageBody(
          child: switch (state) {
            ScanUploading(:final progress) => _BeamRitual(uploadProgress: progress),
            ScanAnalyzing() => const _BeamRitual(),
            ScanNotCoa(:final info) => NotACoaView(info: info),
            ScanFailed(:final message, :final statusCode) =>
              ScanErrorView(message: message, statusCode: statusCode),
            // ScanIdle / ScanDone are transient here.
            _ => const _BeamRitual(),
          },
        ),
      ),
    );
  }
}

/// The scan-beam ritual: a skeleton document swept by a glowing 2px reagent
/// beam while the rule counter ticks up and status copy rotates. Loops until
/// the backend answers. Reduced motion: static document, no sweep.
class _BeamRitual extends ConsumerStatefulWidget {
  const _BeamRitual({this.uploadProgress});

  /// 0..1 while uploading, null once the backend is analyzing.
  final double? uploadProgress;

  @override
  ConsumerState<_BeamRitual> createState() => _BeamRitualState();
}

class _BeamRitualState extends ConsumerState<_BeamRitual>
    with SingleTickerProviderStateMixin {
  static const _statusLines = [
    'READING DOCUMENT TEXT…',
    'MATCHING LAB TEMPLATES…',
    'CROSS-CHECKING MOLECULAR WEIGHTS…',
    'HUNTING FORGERY MARKERS…',
  ];

  late final AnimationController _beam =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  Timer? _ruleTimer;
  Timer? _statusTimer;
  final _rand = math.Random();
  int _rules = 0;
  int _statusIx = 0;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reduced = MediaQuery.of(context).disableAnimations;
      if (_reduced) {
        setState(() => _rules = 82);
        return;
      }
      _beam.repeat();
      // rule counter: ~90ms per increment, random 1–4 steps, capped at 82
      _ruleTimer = Timer.periodic(const Duration(milliseconds: 90), (t) {
        if (_rules >= 82) {
          t.cancel();
          return;
        }
        setState(() => _rules = math.min(82, _rules + 1 + _rand.nextInt(4)));
      });
      _statusTimer = Timer.periodic(const Duration(milliseconds: 950), (_) {
        setState(() => _statusIx = (_statusIx + 1) % _statusLines.length);
      });
    });
  }

  @override
  void dispose() {
    _beam.dispose();
    _ruleTimer?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final uploading = widget.uploadProgress != null;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        children: [
          // ---- skeleton document + sweeping beam --------------------------
          SizedBox(
            width: 230,
            height: 300,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: _SkeletonDoc(c: c)),
                if (!_reduced)
                  AnimatedBuilder(
                    animation: _beam,
                    builder: (context, _) {
                      // 8% → 88% → 8%, ease-in-out
                      final t = _beam.value < 0.5 ? _beam.value * 2 : (1 - _beam.value) * 2;
                      final eased = Curves.easeInOut.transform(t);
                      final top = 300 * (0.08 + 0.80 * eased);
                      return Positioned(
                        left: -8,
                        right: -8,
                        top: top,
                        child: Column(
                          children: [
                            Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: c.accent,
                                boxShadow: c.isDark
                                    ? [
                                        BoxShadow(
                                            color: c.accentGlow,
                                            blurRadius: 18,
                                            spreadRadius: 4)
                                      ]
                                    : null,
                              ),
                            ),
                            // gradient trail under the beam
                            Container(
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    c.accent.withValues(alpha: c.isDark ? 0.16 : 0.08),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          // ---- rule counter ------------------------------------------------
          Text.rich(
            TextSpan(
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 30, fontWeight: FontWeight.w700, color: c.ink),
              children: [
                TextSpan(text: '$_rules'),
                TextSpan(
                    text: ' / 82 RULES',
                    style: HelixText.microtag(c.ink3, size: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ---- rotating status copy ---------------------------------------
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Text(
              uploading
                  ? 'UPLOADING · ${(widget.uploadProgress! * 100).round()}%'
                  : _statusLines[_statusIx],
              key: ValueKey(uploading ? 'upload-${(widget.uploadProgress! * 20).round()}' : _statusIx),
              textAlign: TextAlign.center,
              style: HelixText.microtag(c.accent, size: 11),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This can take 5–20 seconds.',
            style: TextStyle(fontSize: 12.5, color: c.ink3),
          ),
          const SizedBox(height: 30),
          OutlinedButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
            onPressed: () {
              ref.read(scanControllerProvider.notifier).cancel();
            },
          ),
        ],
      ),
    );
  }
}

/// Greeked COA: header block, data rows, a table — what the beam sweeps.
class _SkeletonDoc extends StatelessWidget {
  const _SkeletonDoc({required this.c});
  final HelixColors c;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 7}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: c.surface3,
            borderRadius: BorderRadius.circular(3),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [bar(64, h: 10), bar(38)],
          ),
          const SizedBox(height: 16),
          bar(140, h: 9),
          const SizedBox(height: 8),
          bar(96),
          const SizedBox(height: 18),
          for (var i = 0; i < 5; i++) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [bar(70), bar(46)],
            ),
            const SizedBox(height: 9),
          ],
          const Spacer(),
          Container(height: 1, color: c.line2),
          const SizedBox(height: 10),
          bar(120),
          const SizedBox(height: 8),
          bar(88),
        ],
      ),
    );
  }
}
