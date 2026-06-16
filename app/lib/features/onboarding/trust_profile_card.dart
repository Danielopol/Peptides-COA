import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'trust_profile.dart';

/// Renders a [TrustProfile] — a verdict banner + the green/amber/red signal list.
/// Reused on the onboarding summary (Phase B) and the results screen (Phase C).
/// HELIX styling: mono microtag header, glowing signal dots, signal colours
/// from the reserved verdict palette (they describe trust signals, not chrome).
class TrustProfileCard extends StatelessWidget {
  const TrustProfileCard({super.key, required this.profile, this.title = 'Your trust profile'});

  final TrustProfile profile;
  final String title;

  static Color color(BuildContext context, TrustLevel l) {
    final c = HelixColors.of(context);
    return switch (l) {
      TrustLevel.green => c.vGreen,
      TrustLevel.amber => c.vAmber,
      TrustLevel.red => c.vRed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final vc = color(context, profile.verdictLevel);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: HelixText.microtag(c.ink3)),
            const SizedBox(height: 10),
            // Verdict banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.wash(vc),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: vc.withValues(alpha: 0.5)),
              ),
              child: Text(profile.verdict,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: c.ink)),
            ),
            const SizedBox(height: 6),
            ...profile.signals.map((sig) {
              final sc = color(context, sig.level);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        color: sc,
                        shape: BoxShape.circle,
                        boxShadow: c.isDark
                            ? [BoxShadow(color: sc.withValues(alpha: 0.45), blurRadius: 6)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sig.label,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13.5, color: c.ink)),
                          const SizedBox(height: 2),
                          Text(sig.note,
                              style: TextStyle(fontSize: 12.5, height: 1.35, color: c.ink2)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
