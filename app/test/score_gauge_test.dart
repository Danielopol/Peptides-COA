import 'package:coa_scanner/core/verdict.dart';
import 'package:coa_scanner/features/shared/widgets/score_gauge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VerdictStyle.authenticity colour mapping', () {
    test('maps each authenticity band to its HELIX neon colour (dark-first)', () {
      expect(VerdictStyle.authenticity('likely_authentic').color, const Color(0xFF3BF08C));
      expect(VerdictStyle.authenticity('verify_recommended').color, const Color(0xFFFFC247));
      expect(VerdictStyle.authenticity('suspicious').color, const Color(0xFFFF8A50));
      expect(VerdictStyle.authenticity('likely_forged').color, const Color(0xFFFF5468));
    });

    test('light brightness swaps to the clinical-paper palette', () {
      expect(VerdictStyle.authenticity('likely_authentic', Brightness.light).color,
          const Color(0xFF177D45));
      expect(VerdictStyle.authenticity('likely_forged', Brightness.light).color,
          const Color(0xFFBC3A42));
    });

    test('unknown label falls back to neutral/inconclusive', () {
      final s = VerdictStyle.authenticity('something_new');
      expect(s.color, const Color(0xFF557396)); // ink3 — never a verdict colour
      expect(s.shortLabel, 'Inconclusive');
    });

    test('never exposes the raw label as user copy', () {
      // The short label must be soft wording, not the internal enum.
      expect(VerdictStyle.authenticity('likely_forged').shortLabel, isNot(contains('forged')));
    });
  });

  testWidgets('ScoreGauge renders the score and animates to final value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ScoreGauge(score: 78, color: Color(0xFF3BF08C), label: 'Appears authentic'),
          ),
        ),
      ),
    );

    // Mid-animation a partial value is shown; after settling it reads 78.
    await tester.pumpAndSettle();
    expect(find.text('78'), findsOneWidget);
    expect(find.text('/100'), findsOneWidget);
    // the caption renders as an uppercase mono microtag
    expect(find.text('APPEARS AUTHENTIC'), findsOneWidget);
  });

  testWidgets('ScoreGauge clamps out-of-range scores', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScoreGauge(score: 140, color: Color(0xFF3BF08C))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('100'), findsOneWidget);
  });
}
