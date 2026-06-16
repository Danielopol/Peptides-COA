import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ludic.dart';
import '../../core/theme.dart';
import '../shared/widgets/limitations_card.dart' show HatchPattern;
import '../shared/widgets/ludic_widgets.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';

/// HELIX badge case — "Lab record". Badges reward verification HABITS (scans,
/// source checks, batch matches, reading the fine print) — never the verdicts
/// themselves. There is deliberately no badge for an "authentic result".
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    final ludic = ref.watch(ludicProvider);

    final badges = <_BadgeSpec>[
      _BadgeSpec(
        icon: Icons.qr_code_scanner,
        title: 'First Scan',
        earned: ludic.badges.contains('first_scan') || ludic.scans > 0,
        earnedSub: 'earned',
        lockedSub: 'scan a COA',
      ),
      _BadgeSpec(
        icon: Icons.warning_amber_outlined,
        title: 'First Catch',
        earned: ludic.badges.contains('first_catch'),
        earnedSub: 'spotted a forgery',
        lockedSub: 'spot a forgery',
      ),
      _BadgeSpec(
        icon: Icons.open_in_new,
        title: 'Source Checker',
        earned: ludic.badges.contains('source_checker'),
        earnedSub: 'verified with lab ×${Ludic.sourceCheckerTarget}',
        lockedSub: 'verify with lab ${ludic.sourceChecks}/${Ludic.sourceCheckerTarget}',
      ),
      _BadgeSpec(
        icon: Icons.visibility_outlined,
        title: 'Fine Print',
        earned: ludic.badges.contains('fine_print'),
        earnedSub: 'trust guide complete',
        lockedSub: 'finish the trust guide',
      ),
      _BadgeSpec(
        icon: Icons.description_outlined,
        title: 'Archivist',
        earned: ludic.badges.contains('archivist'),
        earnedSub: '${Ludic.archivistTarget} scans',
        lockedSub: '${ludic.scans}/${Ludic.archivistTarget} scans',
      ),
      _BadgeSpec(
        icon: Icons.science_outlined,
        title: 'Batch Matcher',
        earned: ludic.badges.contains('batch_matcher'),
        earnedSub: 'matched a vial',
        lockedSub: 'locked',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: const Text('HELIX'),
      ),
      body: MoleculeBackground(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text('LAB RECORD', style: HelixText.microtag(c.ink3)),
              const SizedBox(height: 6),
              Text('Achievements', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Badges reward verification habits — never the verdicts themselves. '
                'You earn for diligence, not for "good news".',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink2),
              ),
              const SizedBox(height: 16),
              const RankBar(),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 18,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  for (final b in badges)
                    AchievementBadge(
                      icon: b.icon,
                      title: b.title,
                      sub: b.earned ? b.earnedSub : b.lockedSub,
                      earned: b.earned,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: HatchPattern(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    child: Container(
                      color: c.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'No badge exists for "authentic result" — we never gamify the verdict, only the habit of checking.',
                        style: TextStyle(fontSize: 12.5, height: 1.55, color: c.ink2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeSpec {
  const _BadgeSpec({
    required this.icon,
    required this.title,
    required this.earned,
    required this.earnedSub,
    required this.lockedSub,
  });

  final IconData icon;
  final String title;
  final bool earned;
  final String earnedSub;
  final String lockedSub;
}
