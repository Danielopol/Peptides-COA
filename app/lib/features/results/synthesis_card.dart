import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/models.dart';

/// The synthesis card — the plain-language conclusion the user reads first:
/// three category lines ("Authentic because… · Complete because… · Values…")
/// and one evidence-framed recommendation. The detail cards below are the
/// drill-down evidence for each line.
class SynthesisCard extends StatelessWidget {
  const SynthesisCard({super.key, required this.synthesis});
  final Synthesis synthesis;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final rec = synthesis.recommendation;
    final recColor = _level(c, rec.level);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: recColor,
              boxShadow: c.isDark ? [BoxShadow(color: recColor.withValues(alpha: 0.32), blurRadius: 14)] : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SUMMARY', style: HelixText.microtag(c.ink3)),
                const SizedBox(height: 12),
                _CategoryBlock(
                  label: 'AUTHENTICITY',
                  verdict: synthesis.authenticity.verdict,
                  verdictColor: _authColor(c, synthesis.authenticity.verdict),
                  reasons: synthesis.authenticity.reasons,
                ),
                _divider(c),
                _CategoryBlock(
                  label: 'COMPLETENESS',
                  verdict: synthesis.completeness.verdict,
                  verdictColor: _compColor(c, synthesis.completeness.verdict),
                  reasons: synthesis.completeness.reasons,
                ),
                _divider(c),
                _CategoryBlock(
                  label: 'VALUES',
                  verdict: synthesis.values.verdict,
                  verdictColor: _valuesColor(c, synthesis.values.verdict),
                  reasons: synthesis.values.reasons,
                  emptyNote: synthesis.values.reasons.isEmpty
                      ? (synthesis.values.entries.isEmpty
                          ? 'No quantitative results reported.'
                          : 'Reported values look consistent.')
                      : null,
                ),
                const SizedBox(height: 16),
                // ---- recommendation ----
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: c.wash(recColor),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: recColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_recIcon(rec.level), size: 16, color: recColor),
                          const SizedBox(width: 7),
                          Text('RECOMMENDATION', style: HelixText.microtag(recColor)),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(rec.headline,
                          style: TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w700, color: c.ink)),
                      if (rec.detail.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(rec.detail, style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink2)),
                      ],
                      if (rec.actions.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        ...rec.actions.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.arrow_forward, size: 13, color: recColor),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(a, style: TextStyle(fontSize: 13, height: 1.4, color: c.ink))),
                                ],
                              ),
                            )),
                      ],
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

  Widget _divider(HelixColors c) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: c.line2));

  static Color _level(HelixColors c, String level) => switch (level) {
        'critical' => c.vRed,
        'caution' => c.vAmber,
        _ => c.vGreen,
      };
  static IconData _recIcon(String level) => switch (level) {
        'critical' => Icons.report_gmailerrorred_outlined,
        'caution' => Icons.warning_amber_outlined,
        _ => Icons.verified_outlined,
      };
  static Color _authColor(HelixColors c, String v) => switch (v) {
        'Authentic' => c.vGreen,
        'Verify recommended' => c.vAmber,
        'Suspicious' => c.vOrange,
        'Likely forged' => c.vRed,
        _ => c.ink3,
      };
  static Color _compColor(HelixColors c, String v) => switch (v) {
        'Comprehensive' => c.vGreen,
        'Partial' => c.vAmber,
        _ => c.vOrange,
      };
  static Color _valuesColor(HelixColors c, String v) => switch (v) {
        'Consistent' => c.vGreen,
        'Some caution' => c.vAmber,
        'Concerns' => c.vRed,
        _ => c.ink3,
      };
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.label,
    required this.verdict,
    required this.verdictColor,
    required this.reasons,
    this.emptyNote,
  });

  final String label;
  final String verdict;
  final Color verdictColor;
  final List<SynthReason> reasons;
  final String? emptyNote;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: HelixText.microtag(c.ink3)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.wash(verdictColor),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: verdictColor),
              ),
              child: Text(verdict.toUpperCase(),
                  style: GoogleFonts.ibmPlexMono(
                      fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: verdictColor)),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (reasons.isEmpty && emptyNote != null)
          Text(emptyNote!, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.ink2))
        else
          ...reasons.map((r) {
            final pos = r.polarity == 'pos';
            final col = pos ? c.vGreen : c.vAmber;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(pos ? Icons.check : Icons.remove, size: 14, color: col),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.text, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.ink))),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// "Measured values" evidence card — each reported analyte with its value and a
/// good/caution/suspicious/invalid assessment chip. The completeness card says
/// whether a test was run; this says what it reported.
class ValuesCard extends StatelessWidget {
  const ValuesCard({super.key, required this.values});
  final SynthValues values;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    if (values.entries.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('MEASURED VALUES', style: HelixText.microtag(c.ink3)),
          ),
          ...List.generate(values.entries.length, (i) {
            final e = values.entries[i];
            final col = _assess(c, e.assessment);
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.label,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink)),
                      ),
                      Text(e.value, style: HelixText.data(c.ink, size: 12.5, weight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.wash(col),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: col),
                        ),
                        child: Text(_assessLabel(e.assessment),
                            style: GoogleFonts.ibmPlexMono(
                                fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: col)),
                      ),
                    ],
                  ),
                  if (e.note.isNotEmpty && e.assessment != 'ok') ...[
                    const SizedBox(height: 4),
                    Text(e.note, style: TextStyle(fontSize: 12, height: 1.4, color: c.ink2)),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static Color _assess(HelixColors c, String a) => switch (a) {
        'ok' => c.vGreen,
        'caution' => c.vAmber,
        'suspicious' => c.vOrange,
        'invalid' => c.vRed,
        _ => c.ink3,
      };
  static String _assessLabel(String a) => switch (a) {
        'ok' => 'OK',
        'caution' => 'CAUTION',
        'suspicious' => 'SUSPICIOUS',
        'invalid' => 'INVALID',
        _ => a.toUpperCase(),
      };
}
