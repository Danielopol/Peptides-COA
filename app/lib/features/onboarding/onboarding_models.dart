/// Onboarding "Trust Journey" — data model + step config.
///
/// Research-Use-Only (RUO) framing: research-reagent language, no inject/dose
/// wording. Answers are stored generically (single -> String, multi -> Set) keyed
/// by step id, with typed getters the Trust Profile (Phase B/C) reads.
library;

/// One selectable option on a step.
class StepOption {
  final String value;
  final String label;
  const StepOption(this.value, this.label);
}

enum StepKind { info, single, multi }

/// A single onboarding screen definition.
class OnboardingStep {
  final String id;
  final StepKind kind;
  final String title;
  final String? subtitle;
  final List<StepOption> options;
  final String whyTitle;
  final String whyBody;
  final List<String> redFlags;

  const OnboardingStep({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.options = const [],
    this.whyTitle = 'Why this matters',
    this.whyBody = '',
    this.redFlags = const [],
  });
}

/// Immutable answer set. `values[stepId]` is a String (single) or a `Set<String>` (multi).
class OnboardingAnswers {
  final Map<String, Object> values;
  const OnboardingAnswers([this.values = const {}]);

  String? single(String id) {
    final v = values[id];
    return v is String ? v : null;
  }

  Set<String> multi(String id) {
    final v = values[id];
    return v is Set<String> ? v : <String>{};
  }

  /// "just researching" path has no physical product to scan.
  bool get hasProduct => single('vendor') != 'just_researching';

  OnboardingAnswers withSingle(String id, String value) {
    final next = Map<String, Object>.from(values)..[id] = value;
    return OnboardingAnswers(next);
  }

  OnboardingAnswers withToggle(String id, String value) {
    final set = Set<String>.from(multi(id));
    set.contains(value) ? set.remove(value) : set.add(value);
    final next = Map<String, Object>.from(values)..[id] = set;
    return OnboardingAnswers(next);
  }

  bool isAnswered(OnboardingStep step) {
    switch (step.kind) {
      case StepKind.info:
        return true;
      case StepKind.single:
        return single(step.id) != null;
      case StepKind.multi:
        return multi(step.id).isNotEmpty;
    }
  }
}

/// The Standard (~7 question) flow. Copy grounded in Articles/ + forum.
const List<OnboardingStep> kOnboardingSteps = [
  OnboardingStep(
    id: 'welcome',
    kind: StepKind.info,
    title: 'Know what’s really in the vial',
    subtitle:
        'A few quick questions about your research compound and its paperwork. '
        'We’ll point out what to check and what to avoid, then finish by '
        'verifying the COA itself. Skip anytime to go straight to verification.',
    whyBody:
        'The research-peptide market is largely unregulated. A Certificate of '
        'Analysis (COA) is the main objective evidence that what’s in the vial '
        'matches the label — but only if you know how to read and verify it.',
  ),
  OnboardingStep(
    id: 'coa_origin',
    kind: StepKind.single,
    title: 'Whose COA are you checking?',
    options: [
      StepOption('vendor', 'A COA from a vendor / seller'),
      StepOption('self', 'A COA from my own independent testing'),
    ],
    whyBody:
        'If you commissioned the test yourself from an independent lab, the source '
        'is already trustworthy — we’ll skip the vendor-trust questions and tailor '
        'the result (for example, "ask the lab" instead of "ask the vendor").',
  ),
  OnboardingStep(
    id: 'vendor',
    kind: StepKind.single,
    title: 'Where did the compound come from?',
    options: [
      StepOption('domestic_reseller', 'Domestic reseller / brand'),
      StepOption('overseas_direct', 'Overseas / direct (grey market)'),
      StepOption('group_buy', 'Group buy'),
      StepOption('telehealth_pharmacy', 'Telehealth / compounding pharmacy'),
      StepOption('just_researching', 'Just researching — not sourced yet'),
    ],
    whyBody:
        'A COA is only as trustworthy as the source behind it. Favour vendors '
        'with a real storefront, a physical address, responsive support, and '
        'transparent third-party testing partners. Group buys that fund shared '
        'independent testing are among the strongest signals.',
    redFlags: [
      'No storefront — sales only via WhatsApp / Instagram / Telegram DMs',
      'Crypto-only payment (irreversible if you’re scammed)',
      'No verifiable address or testing partner named',
    ],
  ),
  OnboardingStep(
    id: 'coa_source',
    kind: StepKind.single,
    title: 'Who produced the COA?',
    options: [
      StepOption('third_party', 'An independent third-party lab (named)'),
      StepOption('in_house', 'The vendor / manufacturer themselves'),
      StepOption('unsure', 'There’s a COA but I’m not sure who made it'),
      StepOption('none', 'No COA provided'),
    ],
    whyBody:
        'Third-party = an independent, accredited lab with no financial tie to '
        'the seller tested it — the gold standard. In-house = the seller graded '
        'their own work; better than nothing, but self-reported and easy to '
        'fabricate. Your first question should always be: which lab produced it?',
    redFlags: [
      'In-house only, with no independent lab named',
      'Generic “example” COAs reused across products',
    ],
  ),
  OnboardingStep(
    id: 'verifiability',
    kind: StepKind.single,
    title: 'Can the COA be verified on the lab’s own site?',
    options: [
      StepOption('yes', 'Yes — a QR code, key, or lookup portal'),
      StepOption('no', 'No way to verify it independently'),
      StepOption('unsure', 'Not sure'),
    ],
    whyBody:
        'The single strongest check: a genuine third-party COA carries a '
        'verification key or QR that you enter on the lab’s website to confirm '
        'the report is real and unaltered. If you can’t cross-reference it at '
        'the source, treat it as unverified. (The verification step does this '
        'for you automatically.)',
    redFlags: [
      'No QR / key / portal of any kind',
      'A verification field that’s blanked out or unreadable',
    ],
  ),
  OnboardingStep(
    id: 'batch',
    kind: StepKind.single,
    title: 'Does the batch / lot on the COA match the vial?',
    options: [
      StepOption('matches', 'Yes — they match'),
      StepOption('different', 'No — they differ'),
      StepOption('no_batch', 'The vial has no batch / lot at all'),
      StepOption('unchecked', 'Haven’t checked'),
    ],
    whyBody:
        'A COA is batch-specific: the lot number on the report should match the '
        'lot on the vial, and ideally a vial photo / cap colour too. Even then, '
        'remember the lab tested one sample — there’s little real batch '
        'traceability, so a tested sample is not a guarantee for your exact vial.',
    redFlags: [
      'Lot on the vial doesn’t match the COA',
      'A reused COA dated long before your order',
    ],
  ),
  OnboardingStep(
    id: 'cap_match',
    kind: StepKind.single,
    title: 'Does the cap / crimp colour match the COA’s vial photo?',
    options: [
      StepOption('matches', 'Yes — cap colour and vial match the photo'),
      StepOption('different', 'No — they look different'),
      StepOption('no_photo', 'The COA has no vial photo / cap reference'),
      StepOption('unchecked', 'Haven’t checked'),
    ],
    whyBody:
        'Many labs photograph the tested vial on the report. The cap / crimp '
        'colour and label on that photo should match the vial in your hand — '
        'it’s a quick visual tie between the document and the physical product. '
        'A mismatch often means the COA belongs to a different batch or product '
        'entirely.',
    redFlags: [
      'Cap or crimp colour differs from the COA’s vial photo',
      'Photo cropped or blurred so the vial can’t be compared',
    ],
  ),
  OnboardingStep(
    id: 'recency',
    kind: StepKind.single,
    title: 'How recent is the COA?',
    options: [
      StepOption('under6', 'Less than 6 months old'),
      StepOption('six_to_twelve', '6–12 months old'),
      StepOption('over12', 'Over 12 months / unknown'),
    ],
    whyBody:
        'Testing reflects the batch at the time it was analysed. Peptides '
        'degrade, and stock turns over — an old COA may not represent current '
        'material. Recent testing (within a few months) is ideal; many guides '
        'treat anything past 6–12 months as stale.',
    redFlags: ['COA older than a year offered for fresh stock'],
  ),
  OnboardingStep(
    id: 'test_scope',
    kind: StepKind.multi,
    title: 'What did the COA actually test for?',
    subtitle: 'Select everything listed on the report.',
    options: [
      StepOption('purity', 'Purity (HPLC %)'),
      StepOption('assay', 'Assay / measured mass'),
      StepOption('ms_identity', 'Identity by mass spec (MS)'),
      StepOption('heavy_metals', 'Heavy metals'),
      StepOption('endotoxin', 'Bacterial endotoxin'),
      StepOption('sterility', 'Sterility / microbial'),
      StepOption('not_sure', 'Not sure'),
    ],
    whyBody:
        'Purity is not safety, and purity is not identity. HPLC purity tells you '
        'how clean the main peak is — not that it’s the right compound (that '
        'needs MS) nor that it’s free of heavy metals, endotoxins, or microbes. '
        'Most grey-market COAs show only purity and mass; comprehensive '
        'contaminant testing is rare but is what real safety depends on.',
    redFlags: [
      'Only a purity % with no identity (MS) confirmation',
      'No contaminant testing at all',
    ],
  ),
  OnboardingStep(
    id: 'options',
    kind: StepKind.info,
    title: 'If the COA is weak — your options',
    subtitle:
        'Independent COA verification is the main tool, but it’s not the only one.',
    whyBody:
        'If a COA can’t be verified, doesn’t match the vial, or omits key tests:\n'
        '• Have a vial independently tested (e.g. Janoshik) or join a community '
        'group test that funds shared testing.\n'
        '• Ask the vendor for a recent, batch-matched, third-party report; a '
        'refund or replacement if it doesn’t add up.\n'
        '• When in doubt, walk away — no document proves what’s in your specific '
        'vial.\n'
        'Handle/store lyophilised material dry and cold per its retest date.',
  ),
];
