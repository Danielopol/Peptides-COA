import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../shared/widgets/disclaimer.dart';
import '../shared/widgets/page_body.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: const Text('How it works'),
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.school_outlined),
              label: const Text('Replay the trust guide'),
              onPressed: () => context.go('/onboarding'),
            ),
            const SizedBox(height: 20),
            Text('What this tool does',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'You upload a peptide Certificate of Analysis (COA). We extract its text, '
              'then run a rule engine plus targeted cross-checks and (for ambiguous cases) '
              'a visual review. You get two scores:',
              style: TextStyle(height: 1.5, color: scheme.onSurface),
            ),
            const SizedBox(height: 16),
            _Axis(
              color: HelixColors.of(context).vGreen,
              title: 'Authenticity',
              body: 'How genuine the document looks — does it match a known lab template, '
                  'do the molecular weights line up, are there signs of tampering or '
                  'missing verification fields?',
            ),
            _Axis(
              color: HelixColors.of(context).cTeal,
              title: 'Completeness',
              body: 'How thorough the report is — purity, mass-spec identity, methods, '
                  'accreditation and other expected detail. A real but bare-bones COA can '
                  'score high on authenticity yet low on completeness.',
            ),
            const SizedBox(height: 16),
            Text(
              'When a COA has a lab verification key (for example Janoshik), we surface a '
              '“verify with the lab” link so you can confirm it at the source. The single '
              'most trustworthy signal is confirming the COA directly with the issuing lab.',
              style: TextStyle(height: 1.5, color: scheme.onSurface),
            ),

            const SizedBox(height: 28),
            Text('Key terms',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ..._glossary.map((t) => _Term(term: t.$1, body: t.$2)),

            const SizedBox(height: 20),
            Text('Staying safer',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Harm-reduction basics the research community repeats. Not medical advice.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ..._safety.map((s) => _Bullet(text: s)),

            const SizedBox(height: 24),
            const DisclaimerBanner(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Plain-language glossary of the COA terms people most often misread.
const List<(String, String)> _glossary = [
  ('Identity confirmation (mass spec)',
      'Proof the compound really is what’s claimed — normally by mass spectrometry '
      '(ESI/MALDI/LC-MS). HPLC purity alone does NOT confirm identity: something '
      'else eluting at the same time would look identical, so you can have high '
      'purity of the wrong compound. A COA with only HPLC purity/quantity (no MS) '
      'is flagged as missing identity confirmation — even if a peak is labelled '
      'with the peptide name.'),
  ('Purity vs. assay/mass',
      'Purity (HPLC %) is how much of the peptide present is the right compound. '
      'Assay/mass is how many mg are actually in the vial vs the label. A vial can '
      'be 99% pure and still underdosed — read both, not just the purity.'),
  ('Purity vs. potency',
      'Purity is not potency. A peptide can be highly pure yet denatured, '
      'misfolded, or degraded — and therefore biologically inactive. Proving it '
      'actually works needs a bioassay, which these COAs almost never include.'),
  ('Impurity breakdown',
      'A thorough COA lists the impurities (main peak + named impurity peaks), not '
      'just a single purity number — so you can judge whether the non-peptide '
      'fraction is benign or concerning.'),
  ('Endotoxin (EU/mg)',
      'Bacterial breakdown products. They must be very low for anything injected — '
      'high endotoxin causes fever and injection-site reactions. Rarely tested on '
      'grey-market COAs.'),
  ('Sterility / microbial',
      'Whether the product is free of viable microbes. Purity testing does not '
      'cover this; it needs a separate test.'),
  ('Heavy metals',
      'Lead, arsenic, cadmium, mercury contamination. "ND" / "Non-Detect" is good.'),
  ('Residual solvents / TFA',
      'Leftover synthesis chemicals (e.g. trifluoroacetic acid). A separate line '
      'from purity; usually reported as a small percentage.'),
  ('Third-party vs in-house COA',
      'Third-party = an independent lab tested it. In-house / manufacturer QC = the '
      'seller’s own report (storage instructions on the page are a tell). The '
      'community treats in-house COAs as weak evidence.'),
  ('Batch / lot number',
      'An identifier that should match between the COA and your vial — but resellers '
      'can reuse or relabel it, so a match is reassuring, not proof.'),
  ('TB-500 vs TB-4',
      'Most “TB-500” on the market is actually TB-4 (full Thymosin Beta-4), not the '
      'TB-500 fragment — they’re dosed differently. Check the CAS number on the COA: '
      'TB-4 is 77591-33-4, the TB-500 fragment is 885340-08-9.'),
];

/// Harm-reduction basics echoed across the community.
const List<String> _safety = [
  'Start any new peptide at a low test dose before a full dose.',
  'Don’t inject a brand-new compound late at night or alone — have someone around.',
  'Consider sterile-filtering reconstituted product into a fresh sterile vial.',
  'The most reliable check is independent or group testing of your own vial.',
  'No COA — even a genuine, verifiable one — proves what is in your specific vial.',
];

class _Term extends StatelessWidget {
  const _Term({required this.term, required this.body});
  final String term;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(term, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(fontSize: 13.5, height: 1.45, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(height: 1.4, color: scheme.onSurfaceVariant)),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _Axis extends StatelessWidget {
  const _Axis({required this.color, required this.title, required this.body});
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 6, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 13.5, height: 1.45, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
