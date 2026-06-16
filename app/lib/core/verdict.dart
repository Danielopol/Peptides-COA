import 'package:flutter/material.dart';

import 'theme.dart';

/// Maps backend authenticity/completeness band labels to semantic colour + icon.
///
/// IMPORTANT (legal/safety): we map the label to colour/icon ONLY. The words
/// shown to the user always come from the backend's `copy`/`message` strings —
/// never the raw label, and never "Forged"/"Fake".
///
/// Palette laws (HELIX): ① verdict colours colour the signal only (tag, icon,
/// arc, purity chip) — never card backgrounds or chrome; ② completeness stays
/// teal — an inventory, not a judgment; ③ the lime XP colour is for effort and
/// may never appear on anything describing the document.
class VerdictStyle {
  final Color color;
  final IconData icon;
  final String shortLabel; // soft, non-alarmist heading

  const VerdictStyle(this.color, this.icon, this.shortLabel);

  /// Glow shadow colour (dark-mode only — completeness/grey never glow).
  Color glowOn(HelixColors c) {
    if (!c.isDark) return Colors.transparent;
    if (color == c.cTeal || color == _tealDim(c) || color == _grey(c)) {
      return Colors.transparent;
    }
    return color.withValues(alpha: 0.32);
  }

  /// Authenticity bands: likely_authentic / verify_recommended / suspicious / likely_forged.
  /// Dark-first by default; pass [Brightness.light] for the clinical-paper palette.
  static VerdictStyle authenticity(String label, [Brightness brightness = Brightness.dark]) {
    final c = brightness == Brightness.dark ? HelixColors.dark : HelixColors.light;
    switch (label) {
      case 'likely_authentic':
        return VerdictStyle(c.vGreen, Icons.verified_outlined, 'Appears authentic');
      case 'verify_recommended':
        return VerdictStyle(c.vAmber, Icons.help_outline, 'Verify recommended');
      case 'suspicious':
        return VerdictStyle(c.vOrange, Icons.warning_amber_outlined, 'Multiple red flags');
      case 'likely_forged':
        return VerdictStyle(c.vRed, Icons.report_gmailerrorred_outlined, 'Strong red flags');
      default:
        return VerdictStyle(_grey(c), Icons.help_outline, 'Inconclusive');
    }
  }

  /// Completeness bands: full_report / partial_report / minimal_report / skeletal.
  /// Completeness is informational — kept neutral (teal), NOT the verdict palette.
  static VerdictStyle completeness(String label, [Brightness brightness = Brightness.dark]) {
    final c = brightness == Brightness.dark ? HelixColors.dark : HelixColors.light;
    switch (label) {
      case 'full_report':
        return VerdictStyle(c.cTeal, Icons.fact_check_outlined, 'Comprehensive');
      case 'partial_report':
        return VerdictStyle(c.cTeal, Icons.description_outlined, 'Partial');
      case 'minimal_report':
        return VerdictStyle(_tealDim(c), Icons.short_text, 'Minimal');
      case 'skeletal':
        return VerdictStyle(_tealDim(c), Icons.remove_circle_outline, 'Skeletal');
      default:
        return VerdictStyle(_grey(c), Icons.help_outline, 'Unknown');
    }
  }

  static Color _tealDim(HelixColors c) => Color.lerp(c.cTeal, c.ink3, 0.45)!;
  static Color _grey(HelixColors c) => c.ink3;
}
