import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// HELIX — "Biotech Neon" design tokens. Lab-at-night: abyssal navy surfaces,
/// one electric reagent-cyan accent, mono for everything read off the document.
/// Verdict colours (green/amber/orange/red) live in [VerdictStyle] and are
/// reserved strictly for the authenticity signal; the lime XP colour is for
/// the ludic layer (effort) and may never describe the document.
class HelixColors {
  const HelixColors._({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.accent,
    required this.accentInk,
    required this.accentDim,
    required this.accentGlow,
    required this.vGreen,
    required this.vAmber,
    required this.vOrange,
    required this.vRed,
    required this.cTeal,
    required this.xp,
    required this.isDark,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color line2;
  final Color accent; // reagent cyan — interactive only, never verdicts
  final Color accentInk; // text on accent
  final Color accentDim; // accent wash
  final Color accentGlow; // glow shadow (dark only)
  final Color vGreen;
  final Color vAmber;
  final Color vOrange;
  final Color vRed;
  final Color cTeal; // completeness — an inventory, not a judgment
  final Color xp; // LUDIC ONLY: streaks, XP, ranks, badges
  final bool isDark;

  /// Verdict-tinted wash (~11% alpha) — signal backgrounds on tags/plates only.
  Color wash(Color c) => c.withValues(alpha: 0.11);

  /// Glow shadow colour for a verdict/accent colour. Transparent in light mode
  /// — glow is a dark-mode-only privilege.
  Color glow(Color c) => isDark ? c.withValues(alpha: 0.32) : Colors.transparent;

  static const dark = HelixColors._(
    bg: Color(0xFF050D18),
    surface: Color(0xFF0A1726),
    surface2: Color(0xFF0F1F33),
    surface3: Color(0xFF16293F),
    ink: Color(0xFFE8F4FC),
    ink2: Color(0xFF8FABC4),
    ink3: Color(0xFF557396),
    line: Color(0xFF1B3450),
    line2: Color(0x9E16293F),
    accent: Color(0xFF2BE4FF),
    accentInk: Color(0xFF04131E),
    accentDim: Color(0x1F2BE4FF),
    accentGlow: Color(0x592BE4FF),
    vGreen: Color(0xFF3BF08C),
    vAmber: Color(0xFFFFC247),
    vOrange: Color(0xFFFF8A50),
    vRed: Color(0xFFFF5468),
    cTeal: Color(0xFF46D6C4),
    xp: Color(0xFFC0FF4D),
    isDark: true,
  );

  static const light = HelixColors._(
    bg: Color(0xFFF4F5F4),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F8F8),
    surface3: Color(0xFFEEF0F1),
    ink: Color(0xFF1A2129),
    ink2: Color(0xFF5A6673),
    ink3: Color(0xFF939DA8),
    line: Color(0xFFDEE2E6),
    line2: Color(0xFFE9ECEF),
    accent: Color(0xFF0E7490),
    accentInk: Color(0xFFFFFFFF),
    accentDim: Color(0x140E7490),
    accentGlow: Colors.transparent,
    vGreen: Color(0xFF177D45),
    vAmber: Color(0xFF91670F),
    vOrange: Color(0xFFB4470F),
    vRed: Color(0xFFBC3A42),
    cTeal: Color(0xFF0E7066),
    xp: Color(0xFF5C7A12),
    isDark: false,
  );

  static HelixColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Text styles outside the Material TextTheme slots — the system's two extra
/// voices: mono "specimen tag" microtags and mono data.
class HelixText {
  const HelixText._();

  /// Uppercase mono micro-label (letter-spacing +14%). Pass the colour.
  static TextStyle microtag(Color color, {double size = 10.5}) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size * 0.14,
        color: color,
      );

  /// Mono data — anything read off the document (filenames, lots, %, dates).
  static TextStyle data(Color color, {double size = 12, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: weight, color: color);

  /// Space Grotesk display — headlines and score numerals.
  static TextStyle display(Color color, {double size = 27, FontWeight weight = FontWeight.w700, double height = 1.16}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: -0.01 * size,
        color: color,
      );
}

class HelixTheme {
  const HelixTheme._();

  static ThemeData dark() => _build(HelixColors.dark);
  static ThemeData light() => _build(HelixColors.light);

  static ThemeData _build(HelixColors c) {
    final base = c.isDark ? const ColorScheme.dark() : const ColorScheme.light();
    final scheme = base.copyWith(
      surface: c.bg,
      surfaceContainer: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainerHigh: c.surface2,
      surfaceContainerHighest: c.surface3,
      primary: c.accent,
      onPrimary: c.accentInk,
      secondary: c.cTeal,
      onSecondary: c.accentInk,
      onSurface: c.ink,
      onSurfaceVariant: c.ink2,
      outline: c.line,
      outlineVariant: c.line2,
      error: c.vRed,
    );
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
    );
    return baseTheme.copyWith(
      textTheme: _textTheme(baseTheme.textTheme, c),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        titleTextStyle: GoogleFonts.spaceGrotesk(
            fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: c.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: c.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: c.accent,
          foregroundColor: c.accentInk,
          textStyle: GoogleFonts.archivo(fontSize: 15.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: c.ink,
          side: BorderSide(color: c.line),
          textStyle: GoogleFonts.archivo(fontSize: 15.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: GoogleFonts.archivo(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line2, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        // specimen-tag chips: squarish, mono
        backgroundColor: c.surface3,
        side: BorderSide(color: c.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: GoogleFonts.ibmPlexMono(
            fontSize: 11, fontWeight: FontWeight.w500, color: c.ink2),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surface3,
        circularTrackColor: c.surface3,
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: c.ink3, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface3,
        contentTextStyle: GoogleFonts.archivo(fontSize: 13.5, color: c.ink),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, HelixColors c) {
    final grotesk = GoogleFonts.spaceGroteskTextTheme(base);
    final archivo = GoogleFonts.archivoTextTheme(base);
    return base.copyWith(
      // score numeral (the gauge draws its own)
      displayLarge: grotesk.displayLarge?.copyWith(
          fontSize: 56, fontWeight: FontWeight.w700, height: 1.0, letterSpacing: -1.12, color: c.ink),
      // display
      headlineMedium: grotesk.headlineMedium?.copyWith(
          fontSize: 27, fontWeight: FontWeight.w700, height: 1.16, letterSpacing: -0.27, color: c.ink),
      headlineSmall: grotesk.headlineSmall?.copyWith(
          fontSize: 24, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.24, color: c.ink),
      // title
      titleLarge: grotesk.titleLarge?.copyWith(
          fontSize: 19, fontWeight: FontWeight.w700, height: 1.25, color: c.ink),
      titleMedium: grotesk.titleMedium?.copyWith(
          fontSize: 16, fontWeight: FontWeight.w700, height: 1.3, color: c.ink),
      titleSmall: grotesk.titleSmall?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: c.ink),
      // body
      bodyLarge: archivo.bodyLarge?.copyWith(fontSize: 15, height: 1.45, color: c.ink),
      bodyMedium: archivo.bodyMedium?.copyWith(fontSize: 13, height: 1.5, color: c.ink),
      bodySmall: archivo.bodySmall?.copyWith(fontSize: 12, height: 1.45, color: c.ink2),
      // data (mono rule: read off the document)
      labelLarge: GoogleFonts.ibmPlexMono(
          fontSize: 12, fontWeight: FontWeight.w500, height: 1.4, color: c.ink2),
      // microtag
      labelSmall: GoogleFonts.ibmPlexMono(
          fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 1.47, color: c.ink3),
    );
  }
}
