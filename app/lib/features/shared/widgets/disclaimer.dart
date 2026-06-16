import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Required legal/safety copy — verbatim, used on Results and About.
/// Do not soften or remove. HELIX styling: quiet ink3 text with the key phrase
/// in ink2, above a 1px hairline top border — structural, not decorative.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  static const String text =
      'This result is an indicator, not legal or medical advice. It does not '
      'confirm a product is safe to use. Always verify directly with the issuing '
      'lab and vendor before making any decision.';

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 12, height: 1.55, color: c.ink3),
          children: [
            TextSpan(
                text: 'This result is an indicator, not legal or medical advice. ',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink2)),
            const TextSpan(
                text: 'It does not confirm a product is safe to use. Always verify directly '
                    'with the issuing lab and vendor before making any decision.'),
          ],
        ),
      ),
    );
  }
}
