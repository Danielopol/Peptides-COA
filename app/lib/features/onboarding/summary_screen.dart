import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ludic.dart';
import '../../core/theme.dart';
import '../shared/widgets/disclaimer.dart';
import '../shared/widgets/limitations_card.dart' show HatchPattern;
import '../shared/widgets/ludic_widgets.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';
import 'onboarding_controller.dart';
import 'onboarding_models.dart';
import 'trust_profile.dart';
import 'trust_profile_card.dart';

/// End of the trust journey: shows the answer-based Trust Profile, the Fine
/// Print badge unlock (+80 XP, once), then offers both endings — verify a COA,
/// or get the pre-purchase checklist.
class OnboardingSummaryScreen extends ConsumerStatefulWidget {
  const OnboardingSummaryScreen({super.key});

  @override
  ConsumerState<OnboardingSummaryScreen> createState() => _OnboardingSummaryScreenState();
}

class _OnboardingSummaryScreenState extends ConsumerState<OnboardingSummaryScreen> {
  @override
  void initState() {
    super.initState();
    // One-time completion award — the controller ignores repeat calls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final answers = ref.read(onboardingControllerProvider);
      final answeredSteps = kOnboardingSteps.where(answers.isAnswered).length;
      ref.read(ludicProvider.notifier).awardGuideComplete(answeredSteps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = HelixColors.of(context);
    final answers = ref.watch(onboardingControllerProvider);
    final profile = buildTrustProfile(answers);
    // "Just researching" users have no vial yet — lead with the checklist.
    final researching = !answers.hasProduct;

    final uploadBtn = FilledButton.icon(
      icon: const Icon(Icons.upload_file, size: 18),
      label: const Text('Verify a COA'),
      onPressed: () => context.go('/'),
    );
    final checklistBtn = OutlinedButton.icon(
      icon: const Icon(Icons.fact_check_outlined, size: 18),
      label: const Text('Pre-purchase checklist'),
      onPressed: () => context.go('/onboarding/checklist'),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const SizedBox.shrink(),
        actions: [
          TextButton(onPressed: () => context.go('/'), child: const Text('Skip to COA check')),
        ],
      ),
      body: MoleculeBackground(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TRUST GUIDE · COMPLETE', style: HelixText.microtag(c.ink3)),
                  LudicGate(
                    child: Text('+${Ludic.xpGuideComplete} XP EARNED',
                        style: HelixText.microtag(c.xp)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Your trust profile', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                researching
                    ? 'Here’s what to weigh before you buy. Run any vendor’s public COA through verification, or take the checklist.'
                    : 'Based on your answers. Next, verify the COA itself — it can confirm or contradict these signals.',
                style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
              ),
              const SizedBox(height: 16),
              TrustProfileCard(profile: profile),
              const SizedBox(height: 18),
              const Center(
                child: AchievementBadge(
                  icon: Icons.visibility_outlined,
                  title: 'Fine Print',
                  sub: 'track unlocked',
                  pop: true,
                ),
              ),
              const SizedBox(height: 18),
              // hatched caveat — a perfect profile still isn't proof
              Card(
                child: HatchPattern(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    child: Container(
                      color: c.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Even a perfect profile can’t prove what’s in your vial — only independent testing of that vial can.',
                        style: TextStyle(fontSize: 12.5, height: 1.55, color: c.ink2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Dual ending — primary depends on whether they have a product.
              if (researching) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Pre-purchase checklist'),
                  onPressed: () => context.go('/onboarding/checklist'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Verify a COA'),
                  onPressed: () => context.go('/'),
                ),
              ] else ...[
                uploadBtn,
                const SizedBox(height: 10),
                checklistBtn,
              ],
              const SizedBox(height: 20),
              const DisclaimerBanner(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
