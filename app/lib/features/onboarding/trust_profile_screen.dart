import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../shared/widgets/molecule.dart';
import '../shared/widgets/page_body.dart';
import 'onboarding_controller.dart';
import 'onboarding_models.dart';
import 'trust_profile.dart';
import 'trust_profile_card.dart';

/// Standalone, always-available view of the user's answer-based Trust Profile,
/// reachable from the top bar. It rebuilds from the saved onboarding answers, so
/// retaking the trust guide updates it automatically — and it's independent of
/// any COA scan.
class TrustProfileScreen extends ConsumerWidget {
  const TrustProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = HelixColors.of(context);
    final answers = ref.watch(onboardingControllerProvider);
    final taken = answers.values.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: const Text('Trust profile'),
      ),
      body: MoleculeBackground(
        child: PageBody(
          child: taken ? _profile(context, c, answers) : _empty(context, c),
        ),
      ),
    );
  }

  Widget _profile(BuildContext context, HelixColors c, OnboardingAnswers answers) {
    final profile = buildTrustProfile(answers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('YOUR TRUST PROFILE', style: HelixText.microtag(c.ink3)),
        const SizedBox(height: 8),
        Text(
          'Built from your trust-guide answers. Retake the guide anytime to update '
          'it, or verify a COA — a scan can confirm or contradict these signals.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
        ),
        const SizedBox(height: 16),
        TrustProfileCard(profile: profile),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retake the trust guide'),
          onPressed: () => context.go('/onboarding'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Verify a COA'),
          onPressed: () => context.go('/'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _empty(BuildContext context, HelixColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.shield_outlined, size: 64, color: c.ink3),
          const SizedBox(height: 16),
          Text('No trust profile yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'Take the quick trust guide and we’ll build a profile from your answers — '
            'what looks solid and what to watch for.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.ink2, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/onboarding'),
            child: const Text('Take the trust guide'),
          ),
        ],
      ),
    );
  }
}
