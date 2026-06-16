import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';

/// HELIX NeonGauge — calibrated instrument dial. 270° arc starting at 135°,
/// 21 calibration ticks outside the arc, glowing fill in the verdict colour
/// (glow is dark-mode-only), counting numeral in Space Grotesk.
///
/// Reveal ritual: ticks fade in first (240ms, 12ms stagger — the instrument
/// "powers on"), then a single controller drives the arc sweep and numeral
/// count-up (1100ms, Cubic(0.16, 1, 0.3, 1)). Reduced motion jumps to the
/// final state.
class ScoreGauge extends StatefulWidget {
  const ScoreGauge({
    super.key,
    required this.score,
    required this.color,
    this.size = 200,
    this.label,
    this.icon,
    this.compact = false,
    this.animate = true,
  });

  final int score; // 0..100
  final Color color;
  final double size;
  final String? label; // microtag caption under the number
  final IconData? icon; // kept for API compatibility; the dial speaks numerals
  final bool compact;
  final bool animate; // false → draw the settled dial immediately (share card)

  @override
  State<ScoreGauge> createState() => _ScoreGaugeState();
}

class _ScoreGaugeState extends State<ScoreGauge> with SingleTickerProviderStateMixin {
  static const _ticksMs = 240;
  static const _arcMs = 1100;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _ticksMs + _arcMs),
  );
  late final Animation<double> _ticks = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, _ticksMs / (_ticksMs + _arcMs)),
  );
  late final Animation<double> _arc = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(_ticksMs / (_ticksMs + _arcMs), 1, curve: Cubic(0.16, 1, 0.3, 1)),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.animate || MediaQuery.of(context).disableAnimations) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final clamped = widget.score.clamp(0, 100);
    final stroke = widget.compact ? 7.0 : 10.0;
    final glow = c.isDark ? widget.color.withValues(alpha: 0.32) : Colors.transparent;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final shown = (clamped * _arc.value).round();
          return CustomPaint(
            painter: _NeonGaugePainter(
              fraction: clamped / 100 * _arc.value,
              tickReveal: _ticks.value,
              color: widget.color,
              glow: glow,
              track: c.surface3,
              majorTick: c.ink3,
              minorTick: c.line,
              stroke: stroke,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$shown',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: widget.size * (widget.compact ? 0.34 : 0.30),
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: widget.size * -0.006,
                      color: c.ink,
                      shadows: c.isDark && glow.a > 0
                          ? [Shadow(color: glow, blurRadius: 14)]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '/100',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: math.max(widget.size * 0.06, 9),
                      letterSpacing: widget.size * 0.0072,
                      color: c.ink3,
                    ),
                  ),
                  if (widget.label != null && !widget.compact) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        widget.label!.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: HelixText.microtag(c.ink2, size: 10.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NeonGaugePainter extends CustomPainter {
  _NeonGaugePainter({
    required this.fraction,
    required this.tickReveal,
    required this.color,
    required this.glow,
    required this.track,
    required this.majorTick,
    required this.minorTick,
    required this.stroke,
  });

  final double fraction; // 0..1 — animated fill
  final double tickReveal; // 0..1 — staggered tick fade-in
  final Color color;
  final Color glow;
  final Color track;
  final Color majorTick;
  final Color minorTick;
  final double stroke;

  static const _startDeg = 135.0;
  static const _sweepDeg = 270.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = (math.min(size.width, size.height) - stroke) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: r);
    final startRad = (_startDeg - 90) * math.pi / 180;
    final sweepRad = _sweepDeg * math.pi / 180;

    // 21 calibration ticks outside the arc, every 5th major, staggered reveal
    for (var i = 0; i <= 20; i++) {
      final reveal = ((tickReveal * 21) - i).clamp(0.0, 1.0);
      if (reveal <= 0) continue;
      final major = i % 5 == 0;
      final deg = _startDeg + _sweepDeg * i / 20;
      final a = (deg - 90) * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      final from = center + dir * (r + stroke / 2 + 5);
      final to = center + dir * (r + stroke / 2 + (major ? 12 : 8));
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = major ? 1.8 : 1.2
          ..color = (major ? majorTick : minorTick).withValues(alpha: reveal),
      );
    }

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, startRad, sweepRad, false, trackPaint);

    if (fraction <= 0) return;
    final fillSweep = math.max(sweepRad * fraction, 0.03);

    // glow pass first (dark only), then the crisp arc
    if (glow.a > 0) {
      canvas.drawArc(
        rect,
        startRad,
        fillSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawArc(
      rect,
      startRad,
      fillSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_NeonGaugePainter old) =>
      old.fraction != fraction ||
      old.tickReveal != tickReveal ||
      old.color != color ||
      old.track != track;
}
