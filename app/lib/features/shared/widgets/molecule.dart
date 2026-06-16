import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Faint hex-lattice "molecule grid" texture behind dark screens, plus a
/// radial top wash. Light mode renders the child untouched — the lattice is
/// a dark-mode-only privilege (clinical paper has no texture).
class MoleculeBackground extends StatelessWidget {
  const MoleculeBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    if (!c.isDark) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _LatticePainter(line: c.line)),
        ),
        child,
      ],
    );
  }
}

class _LatticePainter extends CustomPainter {
  _LatticePainter({required this.line});

  final Color line;

  // Tile geometry from the design SVG: 56×97 hex cells.
  static const double _w = 56;
  static const double _h = 97;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line.withValues(alpha: 0.38);
    final dot = Paint()..color = line.withValues(alpha: 0.38);

    for (double ox = 0; ox < size.width + _w; ox += _w) {
      for (double oy = 0; oy < size.height + _h; oy += _h) {
        final path = Path()
          ..moveTo(ox + 28, oy + 17)
          ..lineTo(ox, oy + 33)
          ..lineTo(ox, oy + 65)
          ..lineTo(ox + 28, oy + 81)
          ..lineTo(ox + 56, oy + 65)
          ..lineTo(ox + 56, oy + 33)
          ..close()
          // bond lines between cells
          ..moveTo(ox + 28, oy + 17)
          ..lineTo(ox + 28, oy)
          ..moveTo(ox, oy + 65)
          ..lineTo(ox, oy + 97)
          ..moveTo(ox + 56, oy + 65)
          ..lineTo(ox + 56, oy + 97);
        canvas.drawPath(path, stroke);
        canvas.drawCircle(Offset(ox + 28, oy + 17), 1.6, dot);
        canvas.drawCircle(Offset(ox, oy + 65), 1.6, dot);
        canvas.drawCircle(Offset(ox + 56, oy + 65), 1.6, dot);
      }
    }

    // faint radial wash at the top
    final wash = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -1.2),
        radius: 1.1,
        colors: [const Color(0x220D2A42), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, wash);
  }

  @override
  bool shouldRepaint(_LatticePainter old) => old.line != line;
}

/// Celebration for authentic verdicts only: ~18 falling hex outlines in brand
/// colours (cyan/green/lime/teal). Plays once; skipped entirely under reduced
/// motion or clinical ludic energy. Never used for any other verdict.
class MoleculeConfetti extends StatefulWidget {
  const MoleculeConfetti({super.key, this.count = 18, this.height = 290});

  final int count;
  final double height;

  @override
  State<MoleculeConfetti> createState() => _MoleculeConfettiState();
}

class _MoleculeConfettiState extends State<MoleculeConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400), // max delay 900 + max fall 2500
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) return;
      _ctrl.forward();
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
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(
            t: _ctrl.value * 3400,
            count: widget.count,
            fall: widget.height,
            colors: [c.accent, c.vGreen, c.xp, c.cTeal],
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.t,
    required this.count,
    required this.fall,
    required this.colors,
  });

  final double t; // elapsed ms
  final int count;
  final double fall;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < count; i++) {
      // deterministic pseudo-random spread (matches the design prototype)
      final left = ((i * 53 + 13) % 100) / 100 * size.width;
      final delay = (i * 137) % 900;
      final dur = 1600 + ((i * 211) % 900);
      final sizePx = 7.0 + ((i * 71) % 9);
      final p = ((t - delay) / dur).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;

      final eased = Curves.easeIn.transform(p);
      final opacity = p < 0.1 ? p / 0.1 : (1 - p);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = colors[i % colors.length].withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(left, -12 + eased * fall);
      canvas.rotate(eased * 3 * math.pi); // 540°
      final s = sizePx / 10;
      final hex = Path()
        ..moveTo(0, -4.2 * s)
        ..lineTo(3.7 * s, -2 * s)
        ..lineTo(3.7 * s, 2 * s)
        ..lineTo(0, 4.2 * s)
        ..lineTo(-3.7 * s, 2 * s)
        ..lineTo(-3.7 * s, -2 * s)
        ..close();
      canvas.drawPath(hex, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
