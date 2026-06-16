import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/verdict.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/image_saver.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/score_gauge.dart';
import '../shared/widgets/verdict_tag.dart';

/// The shareable verdict card — the viral asset. A self-contained, screenshot-
/// ready summary of one scan: the dial, the verdict tag, identity chips, and a
/// permanent "Verified ≠ safe" footer so a screenshot can never be passed off
/// as a safety endorsement. Exports to PNG (web download).
class ShareCardScreen extends ConsumerStatefulWidget {
  const ShareCardScreen({super.key});

  @override
  ConsumerState<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends ConsumerState<ShareCardScreen> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // let the current frame settle before capturing
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('encode failed');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final saved =
          await savePng(data.buffer.asUint8List(), 'helix-verdict-$stamp.png');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved
              ? 'Verdict card saved as PNG.'
              : 'Screenshot this card to share it.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export — screenshot the card instead.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final result = ref.watch(selectedResultProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: const Text('Share verdict'),
      ),
      body: MoleculeBackground(
        child: result == null
            ? const Center(child: Text('No scan to share.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  children: [
                    Text('SCREENSHOT-READY · VERIFIED ≠ SAFE BUILT IN',
                        style: HelixText.microtag(c.ink3)),
                    const SizedBox(height: 16),
                    // RepaintBoundary holds exactly the exported pixels.
                    Center(
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: ShareCard(result: result),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: c.isDark
                                  ? [BoxShadow(color: c.accentGlow, blurRadius: 22, spreadRadius: -4)]
                                  : null,
                            ),
                            child: FilledButton.icon(
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.download, size: 18),
                              label: Text(_busy ? 'Exporting…' : 'Save as image'),
                              onPressed: _busy ? null : _save,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Back to result'),
                            onPressed: () => context.pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The card itself — fixed 340px wide, painted on solid surface (no transparency)
/// so the exported PNG looks identical to the on-screen card.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final auth = result.authenticity;
    final style = VerdictStyle.authenticity(auth.label, Theme.of(context).brightness);
    final janoshik = result.hardChecks.byName('janoshik');
    final verifiability = result.hardChecks.byName('verifiability');
    final lab = result.hardChecks.byName('known_lab')?.labName;
    final peptide = result.summary.peptideDetected;
    final task = janoshik?.taskNumber;
    final key = janoshik?.uniqueKey;
    final verifyUrl = janoshik?.verificationUrl ?? verifiability?.verificationUrl;
    final host = verifyUrl == null ? null : Uri.tryParse(verifyUrl)?.host.replaceFirst('www.', '');

    final chips = <String>[
      if (peptide != null) peptide.toUpperCase(),
      if (lab != null) lab.toUpperCase(),
      if (task != null) 'TASK #$task',
    ];

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: style.color,
              boxShadow: c.isDark ? [BoxShadow(color: style.glowOn(c), blurRadius: 14)] : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              children: [
                // header: brand · date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: c.accentDim,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: c.accent),
                          ),
                          child: Icon(Icons.qr_code_scanner, size: 11, color: c.accent),
                        ),
                        const SizedBox(width: 7),
                        Text('HELIX',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
                      ],
                    ),
                    Text(_fmtDate(result.scannedAt), style: HelixText.data(c.ink3, size: 10)),
                  ],
                ),
                const SizedBox(height: 14),
                ScoreGauge(score: auth.score, color: style.color, size: 168, animate: false),
                const SizedBox(height: 12),
                VerdictTag(color: style.color, icon: style.icon, label: style.shortLabel),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: chips.map((label) => _chip(c, label)).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VERIFIED ≠ SAFE', style: HelixText.microtag(c.vAmber)),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11, height: 1.5, color: c.ink3),
                          children: [
                            const TextSpan(
                                text: 'A document score, not a product guarantee. '),
                            if (host != null && key != null)
                              TextSpan(children: [
                                const TextSpan(text: 'Verify it yourself: '),
                                TextSpan(
                                    text: '$host · $key',
                                    style: GoogleFonts.ibmPlexMono(fontSize: 10.5, color: c.ink2)),
                              ])
                            else
                              const TextSpan(
                                  text: 'Always confirm with the issuing lab and vendor.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(HelixColors c, String label) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface3,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.line),
        ),
        child: Text(label,
            style: GoogleFonts.ibmPlexMono(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: c.ink2)),
      );

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
