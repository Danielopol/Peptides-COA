import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/onboarding/onboarding_controller.dart' show sharedPrefsProvider;

/// HELIX ludic layer — XP, ranks, streaks, badges. All lime, all rewarding the
/// HABIT of verifying (scans, source checks, batch matches, fine print read) —
/// never the verdict. There is deliberately no badge for "authentic result":
/// catching a red flag pays MORE than good news, so diligence is the game.
enum LudicEnergy { clinical, balanced, arcade }

/// Stand-in for the remote flag from the design handoff ("Ludic energy" tweak:
/// clinical strips the layer, balanced mutes it, arcade is full lime glow).
const LudicEnergy kLudicEnergy = LudicEnergy.arcade;

class Ludic {
  const Ludic._();

  // XP values — catching problems must pay best.
  static const int xpCleanScan = 40; // likely_authentic
  static const int xpCaution = 60; // verify_recommended
  static const int xpRedFlagCaught = 120; // suspicious / likely_forged
  static const int xpPerAnswer = 10; // trust-guide answers
  static const int xpGuideComplete = 80;
  static const int xpSourceCheck = 20; // opened the lab's verification page
  static const int xpBatchMatch = 20; // compared the vial to the COA (once)

  /// Source Checker badge unlocks after this many lab verifications.
  static const int sourceCheckerTarget = 5;

  /// Archivist badge unlocks at this many scans.
  static const int archivistTarget = 25;

  /// XP awarded for completing a scan, by authenticity band.
  static int xpForBand(String label) => switch (label) {
        'likely_authentic' => xpCleanScan,
        'verify_recommended' => xpCaution,
        'suspicious' || 'likely_forged' => xpRedFlagCaught,
        _ => xpCaution,
      };

  /// Mono caps caption shown next to the XP award on the results hero.
  static String captionForBand(String label) => switch (label) {
        'likely_authentic' => 'CLEAN SCAN',
        'verify_recommended' => 'CAUTION LOGGED',
        'suspicious' || 'likely_forged' => 'RED FLAG SPOTTED — NICE CATCH',
        _ => 'SCAN LOGGED',
      };

  // Rank ladder (xp threshold → title).
  static const List<(int, String)> ranks = [
    (0, 'Lab Tech'),
    (250, 'Analyst I'),
    (1000, 'Analyst II'),
    (2000, 'Senior Analyst'),
    (4000, 'Lead Analyst'),
  ];

  static String rankFor(int xp) {
    var title = ranks.first.$2;
    for (final (threshold, name) in ranks) {
      if (xp >= threshold) title = name;
    }
    return title;
  }

  /// (next threshold, next rank title) — null when maxed out.
  static (int, String)? nextRankFor(int xp) {
    for (final (threshold, name) in ranks) {
      if (xp < threshold) return (threshold, name);
    }
    return null;
  }
}

class LudicState {
  const LudicState({
    this.totalXp = 0,
    this.scans = 0,
    this.streakDays = 0,
    this.sourceChecks = 0,
    this.badges = const {},
    this.guideCompleted = false,
  });

  final int totalXp;
  final int scans;
  final int streakDays;
  final int sourceChecks; // lab verification pages opened
  final Set<String> badges; // 'first_scan', 'first_catch', 'fine_print', ...
  final bool guideCompleted;

  String get rank => Ludic.rankFor(totalXp);

  LudicState copyWith({
    int? totalXp,
    int? scans,
    int? streakDays,
    int? sourceChecks,
    Set<String>? badges,
    bool? guideCompleted,
  }) =>
      LudicState(
        totalXp: totalXp ?? this.totalXp,
        scans: scans ?? this.scans,
        streakDays: streakDays ?? this.streakDays,
        sourceChecks: sourceChecks ?? this.sourceChecks,
        badges: badges ?? this.badges,
        guideCompleted: guideCompleted ?? this.guideCompleted,
      );
}

/// Persistent XP/streak/badge store. Gated UI-side by [kLudicEnergy] —
/// clinical mode never renders any of this, but the data keeps accruing.
class LudicController extends Notifier<LudicState> {
  static const _kXp = 'ludic_xp';
  static const _kScans = 'ludic_scans';
  static const _kStreak = 'ludic_streak';
  static const _kLastDay = 'ludic_last_scan_day';
  static const _kSourceChecks = 'ludic_source_checks';
  static const _kBadges = 'ludic_badges';
  static const _kGuide = 'ludic_guide_completed';

  @override
  LudicState build() {
    final prefs = ref.read(sharedPrefsProvider);
    return LudicState(
      totalXp: prefs.getInt(_kXp) ?? 0,
      scans: prefs.getInt(_kScans) ?? 0,
      streakDays: prefs.getInt(_kStreak) ?? 0,
      sourceChecks: prefs.getInt(_kSourceChecks) ?? 0,
      badges: (prefs.getStringList(_kBadges) ?? const []).toSet(),
      guideCompleted: prefs.getBool(_kGuide) ?? false,
    );
  }

  /// Award XP for a finished scan (call exactly once per ScanDone transition).
  void awardScan(String authenticityLabel) {
    final prefs = ref.read(sharedPrefsProvider);
    final today = DateTime.now();
    final dayKey = '${today.year}-${today.month}-${today.day}';
    final lastDay = prefs.getString(_kLastDay);
    var streak = state.streakDays;
    if (lastDay != dayKey) {
      final yesterday = today.subtract(const Duration(days: 1));
      final yKey = '${yesterday.year}-${yesterday.month}-${yesterday.day}';
      streak = lastDay == yKey ? streak + 1 : 1;
      prefs.setString(_kLastDay, dayKey);
    }

    final badges = {...state.badges, 'first_scan'};
    if (authenticityLabel == 'suspicious' || authenticityLabel == 'likely_forged') {
      badges.add('first_catch');
    }
    if (state.scans + 1 >= Ludic.archivistTarget) badges.add('archivist');

    state = state.copyWith(
      totalXp: state.totalXp + Ludic.xpForBand(authenticityLabel),
      scans: state.scans + 1,
      streakDays: streak,
      badges: badges,
    );
    _persist();
  }

  /// The user opened the lab's verification page — a source check. Counts
  /// toward the Source Checker badge (×5).
  void awardSourceCheck() {
    final checks = state.sourceChecks + 1;
    state = state.copyWith(
      totalXp: state.totalXp + Ludic.xpSourceCheck,
      sourceChecks: checks,
      badges: {
        ...state.badges,
        if (checks >= Ludic.sourceCheckerTarget) 'source_checker',
      },
    );
    _persist();
  }

  /// The user actually compared the vial to the COA (batch lot or cap/photo) —
  /// one-time badge + XP. Answering "haven't checked" never triggers this.
  void awardBatchCheck() {
    if (state.badges.contains('batch_matcher')) return;
    state = state.copyWith(
      totalXp: state.totalXp + Ludic.xpBatchMatch,
      badges: {...state.badges, 'batch_matcher'},
    );
    _persist();
  }

  /// One-time +80 XP + Fine Print badge for finishing the trust guide.
  void awardGuideComplete(int answeredSteps) {
    if (state.guideCompleted) return;
    state = state.copyWith(
      totalXp: state.totalXp + Ludic.xpGuideComplete + answeredSteps * Ludic.xpPerAnswer,
      badges: {...state.badges, 'fine_print'},
      guideCompleted: true,
    );
    _persist();
  }

  void _persist() {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setInt(_kXp, state.totalXp);
    prefs.setInt(_kScans, state.scans);
    prefs.setInt(_kStreak, state.streakDays);
    prefs.setInt(_kSourceChecks, state.sourceChecks);
    prefs.setStringList(_kBadges, state.badges.toList());
    prefs.setBool(_kGuide, state.guideCompleted);
  }
}

final ludicProvider = NotifierProvider<LudicController, LudicState>(LudicController.new);
