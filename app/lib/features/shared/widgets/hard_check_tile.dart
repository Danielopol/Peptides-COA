import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../models/models.dart';

/// One finding row driven by a hard check. Colour/icon come from the check's
/// status; the text is the backend's `message` (verbatim). `rule_results` have
/// no detail text, so hard checks are the source of human-readable findings.
///
/// HELIX styling: 26×26 leading icon plate (band wash), trailing mono rule ID.
/// Critical fails get the only allowed verdict-coloured background — a full
/// row wash + 1px border in vRed.
class HardCheckTile extends StatelessWidget {
  const HardCheckTile({super.key, required this.check, this.showDivider = true});

  final HardCheck check;
  final bool showDivider;

  static const _titles = {
    'mw_table': 'Molecular weight cross-check',
    'known_lab': 'Issuing laboratory',
    'janoshik': 'Janoshik verification',
    'verifiability': 'Independent verification',
    'doc_type': 'Report type',
    'assay_mass': 'Dose / mass vs label',
    'recency': 'COA age',
    'purity_sanity': 'Purity plausibility',
    'methods': 'Testing methods',
    'visual_lab': 'Lab template match',
    'multi_mass': 'Mass consistency',
    'metadata': 'Document metadata',
    'blur_tamper': 'Image tampering metrics',
  };

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final (color, icon) = _style(check, c);
    final title = _titles[check.name] ?? check.name;
    final body = check.message ?? check.reason ?? _statusWord(check.status);
    final critical = check.isFailing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: critical ? c.wash(c.vRed) : null,
        border: Border(
          top: showDivider ? BorderSide(color: c.line2) : BorderSide.none,
          left: critical ? BorderSide(color: c.vRed) : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: critical ? Colors.transparent : c.wash(color),
              borderRadius: BorderRadius.circular(7),
              border: critical ? Border.all(color: color) : null,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink)),
                    ),
                    _statusChip(check.status, color, c),
                  ],
                ),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontSize: 13, height: 1.45, color: critical ? c.ink : c.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, Color color, HelixColors c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.wash(color),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(_statusWord(status).toUpperCase(),
            style: GoogleFonts.ibmPlexMono(
                fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: color)),
      );

  static String _statusWord(String s) => switch (s) {
        'pass' => 'Pass',
        'fired' => 'Flag',
        'suspicious' => 'Caution',
        'no_match' => 'No match',
        'unrecognized_named' => 'Unverified',
        'no_issuer' => 'Missing',
        'pending_user_verification' => 'Verify',
        'verifiable' => 'Verifiable',
        'no_verification_path' => 'Unverifiable',
        'redacted' => 'Redacted',
        'third_party_lab' => 'Third-party',
        'manufacturer_qc' => 'In-house',
        'underdosed' => 'Underdosed',
        'overfilled' => 'Overfill',
        'stale' => 'Stale',
        'vague' => 'Vague',
        'too_perfect' => 'Too perfect',
        'multi' => 'Cross-verified',
        'single' => 'Single method',
        'none' => 'No method',
        'unknown' => 'Unknown',
        _ => s.replaceAll('_', ' '),
      };

  static (Color, IconData) _style(HardCheck check, HelixColors c) {
    if (check.isFailing) return (c.vRed, Icons.close);
    if (check.isWarning) return (c.vAmber, Icons.warning_amber_outlined);
    if (check.isPendingVerification) return (c.accent, Icons.open_in_new);
    if (check.isPassing) return (c.vGreen, Icons.check);
    return (c.ink3, Icons.help_outline);
  }
}
