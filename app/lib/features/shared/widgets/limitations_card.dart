import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';

/// 45° hazard-hatch texture (neutral, not alarmist) — 1px [line] stripes on a
/// 7px period. Used as the LimitationsCard top strip and caveat-card fill.
class HatchPattern extends StatelessWidget {
  const HatchPattern({super.key, this.height, this.child});

  final double? height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _HatchPainter(line: c.line), child: child),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.line});
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    const period = 7.0;
    for (double x = -size.height; x < size.width; x += period) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.line != line;
}

/// "Verified ≠ safe" — the document-vs-product reframe. Structural, never
/// collapsible, docked under the verify CTA in every results state. The clause
/// strings come from the backend contract verbatim; design only stages them.
class LimitationsCard extends StatelessWidget {
  const LimitationsCard({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: const HatchPattern(height: 8),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                        children: [
                          const TextSpan(text: 'Verified '),
                          TextSpan(text: '≠', style: TextStyle(color: c.vAmber)),
                          const TextSpan(text: ' safe'),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text("WHAT THIS CAN'T TELL YOU",
                          style: HelixText.microtag(c.ink3)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...List.generate(items.length, (i) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text((i + 1).toString().padLeft(2, '0'),
                              style: HelixText.data(c.ink3, size: 11)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(items[i],
                              style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
