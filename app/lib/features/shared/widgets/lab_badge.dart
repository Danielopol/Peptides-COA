import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/models.dart';

/// "Recognized lab" row from hard_checks.known_lab (status == pass), tinted by
/// the registry trust tier. Shows an `untrusted` issuer as a red warning, and
/// surfaces any lab-specific `caveat` (e.g. documented accuracy issues) —
/// a recognized lab is not automatically a trustworthy one.
///
/// HELIX styling: 34×34 flask plate on a tier wash; tier line is a mono
/// microtag in the tier colour. Tiers: trusted=vGreen, recognized=cTeal,
/// flagged=vAmber, unknown=ink3.
class LabBadge extends StatelessWidget {
  const LabBadge({super.key, required this.knownLab});

  final HardCheck knownLab;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final trust = knownLab.trust ?? '';
    final (color, tierLabel, icon) = _tier(trust, c);
    final name = knownLab.labName ?? 'Recognized lab';
    final caveat = knownLab.caveat;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.wash(color),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(
                    trust.isEmpty
                        ? tierLabel.toUpperCase()
                        : '${tierLabel.toUpperCase()} · ${trust.replaceAll('_', ' ').toUpperCase()}',
                    style: HelixText.microtag(color),
                  ),
                  if (caveat != null && caveat.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(caveat,
                        style: TextStyle(fontSize: 12, height: 1.35, color: c.ink2)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// (color, tier label, icon) for a registry trust value.
  static (Color, String, IconData) _tier(String trust, HelixColors c) {
    switch (trust) {
      case 'untrusted':
        return (c.vRed, 'Flagged lab', Icons.gpp_bad_outlined);
      case 'high':
      case 'established_pharma_cro':
      case 'established_cro':
        return (c.vGreen, 'Recognized lab · high trust', Icons.science_outlined);
      case 'moderate':
      case 'emerging':
        return (c.vAmber, 'Recognized · verify further', Icons.science_outlined);
      default:
        return (c.cTeal, 'Recognized lab', Icons.science_outlined);
    }
  }
}
