import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';

/// Specimen-tag verdict chip: mono caps, band colour as text + border on a
/// ~12% band wash. The only words it ever shows are the soft band labels —
/// never the raw backend label.
class VerdictTag extends StatelessWidget {
  const VerdictTag({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    this.large = true,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Container(
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.wash(color),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: large ? 14 : 12, color: color),
          SizedBox(width: large ? 8 : 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ibmPlexMono(
                fontSize: large ? 12.5 : 11,
                fontWeight: FontWeight.w600,
                letterSpacing: large ? 1.25 : 1.1,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
