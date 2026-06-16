import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/ludic.dart';
import '../../../core/theme.dart';

/// Wraps any ludic-layer widget with the energy gate: clinical hides it,
/// balanced mutes it (desaturated, 40% opacity), arcade shows it at full lime.
class LudicGate extends StatelessWidget {
  const LudicGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    switch (kLudicEnergy) {
      case LudicEnergy.clinical:
        return const SizedBox.shrink();
      case LudicEnergy.balanced:
        return Opacity(
          opacity: 0.4,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.4127, 0.5470, 0.0403, 0, 0, //
              0.1127, 0.8470, 0.0403, 0, 0,
              0.1127, 0.5470, 0.3403, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: child,
          ),
        );
      case LudicEnergy.arcade:
        return child;
    }
  }
}

/// Rank + XP progress: 5px lime track with glow, mono "1240 / 2000 XP" right.
/// Pass [onTap] to make it an entry point (e.g. home → achievements).
class RankBar extends ConsumerWidget {
  const RankBar({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    final ludic = ref.watch(ludicProvider);
    final next = Ludic.nextRankFor(ludic.totalXp);
    final progress = next == null ? 1.0 : (ludic.totalXp / next.$1).clamp(0.0, 1.0);
    final bar = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('◇ ${ludic.rank.toUpperCase()}',
                  style: GoogleFonts.ibmPlexMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.26,
                      color: c.xp)),
              Text(
                next == null
                    ? '${ludic.totalXp} XP · MAX RANK'
                    : '${ludic.totalXp} / ${next.$1} XP → ${next.$2.toUpperCase()}',
                style: HelixText.data(c.ink3, size: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(color: c.surface3),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.xp,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: c.isDark
                            ? [BoxShadow(color: c.xp.withValues(alpha: 0.25), blurRadius: 10, spreadRadius: -2)]
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    return LudicGate(
      child: onTap == null
          ? bar
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: bar,
            ),
    );
  }
}

/// Streak card: lime day-count plate + 7 segment pips.
class StreakBar extends ConsumerWidget {
  const StreakBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    final ludic = ref.watch(ludicProvider);
    if (ludic.scans == 0) return const SizedBox.shrink();
    return LudicGate(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.xp.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('${ludic.streakDays}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 15, fontWeight: FontWeight.w700, color: c.xp)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('day verification streak',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 1),
                    Text('${ludic.scans} document${ludic.scans == 1 ? '' : 's'} checked',
                        style: TextStyle(fontSize: 12, color: c.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: List.generate(7, (i) {
                  return Container(
                    width: 6,
                    height: 16,
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                    decoration: BoxDecoration(
                      color: i < ludic.streakDays ? c.xp : c.surface3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 58×58 badge plate. Earned: accent border + glow on an accent wash. Locked:
/// surface3 at 38% opacity. Pop animation for unlock moments.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    this.earned = true,
    this.pop = false,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool earned;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final badge = Opacity(
      opacity: earned ? 1 : 0.38,
      child: SizedBox(
        width: 96,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: earned ? c.accentDim : c.surface3,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: earned ? c.accent : c.line, width: 1.5),
                boxShadow: earned && c.isDark
                    ? [BoxShadow(color: c.accentGlow, blurRadius: 18, spreadRadius: -6)]
                    : null,
              ),
              child: Icon(icon, size: 24, color: earned ? c.accent : c.ink3),
            ),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.25, color: c.ink)),
            const SizedBox(height: 3),
            Text(sub.toUpperCase(),
                textAlign: TextAlign.center,
                style: HelixText.microtag(c.ink3, size: 8.5)),
          ],
        ),
      ),
    );
    if (!pop || MediaQuery.of(context).disableAnimations) return LudicGate(child: badge);
    return LudicGate(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: const Cubic(0.2, 1.4, 0.4, 1),
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: Opacity(opacity: t.clamp(0, 1), child: child)),
        ),
        child: badge,
      ),
    );
  }
}

/// Lime mono XP line, e.g. "+120 XP · RED FLAG SPOTTED — NICE CATCH".
/// Effort-coloured, never verdict-coloured.
class XpLine extends StatelessWidget {
  const XpLine({super.key, required this.xp, required this.caption});

  final int xp;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    return LudicGate(
      child: Text(
        '+$xp XP · $caption',
        textAlign: TextAlign.center,
        style: GoogleFonts.ibmPlexMono(
            fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 1.05, color: c.xp),
      ),
    );
  }
}
