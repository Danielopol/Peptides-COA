/// Trust Profile — a qualitative green/amber/red signal checklist built from the
/// onboarding answers (and, in Phase C, reconciled against the COA scan).
///
/// Deliberately NOT a single number — it mirrors the app's evidence-based,
/// anti-overclaim stance: signals + a one-line "what to do" verdict.
library;

import '../../models/models.dart';
import 'onboarding_models.dart';

enum TrustLevel { green, amber, red }

class TrustSignal {
  final String label;
  final TrustLevel level;
  final String note;
  const TrustSignal(this.label, this.level, this.note);
}

class TrustProfile {
  final List<TrustSignal> signals;
  final TrustLevel verdictLevel;
  final String verdict;
  const TrustProfile(this.signals, this.verdictLevel, this.verdict);
}

/// Build the profile from answers. `scan` is reserved for Phase C reconciliation
/// (ignored here when null).
TrustProfile buildTrustProfile(OnboardingAnswers a, {ScanResult? scan}) {
  final s = <TrustSignal>[];
  final selfTested = a.single('coa_origin') == 'self';

  if (selfTested) {
    // Own independent-lab COA: the source is self-commissioned, so it's a
    // strength rather than a vendor-trust question (those were skipped).
    s.add(const TrustSignal('Source', TrustLevel.green,
        'Self-commissioned independent test — you chose the lab, not the seller.'));
  } else {
    switch (a.single('vendor')) {
      case 'telehealth_pharmacy':
        s.add(const TrustSignal('Source', TrustLevel.green, 'Pharmacy / telehealth — a regulated supply chain.'));
      case 'domestic_reseller':
        s.add(const TrustSignal('Source', TrustLevel.amber, 'Domestic reseller — confirm track record and third-party testing.'));
      case 'group_buy':
        s.add(const TrustSignal('Source', TrustLevel.amber, 'Group buy — strongest when it funds shared independent testing.'));
      case 'overseas_direct':
        s.add(const TrustSignal('Source', TrustLevel.amber, 'Overseas / grey-market — verify storefront and testing partner; avoid crypto-only / DM-only sellers.'));
      // just_researching: no source signal
    }
  }

  // When a scan is present, its findings are AUTHORITATIVE for everything that
  // can be read off the COA (source, verifiability, recency, test scope) — the
  // scan actually read the document, so it overrides/corrects the user's answer
  // and only the answer is used where the scan can't help. Answers remain the
  // source for what the scan CAN'T see: the purchase channel, and whether the
  // lot matches the user's physical vial.
  final hasScan = scan != null;
  String hc(String name) => scan?.hardChecks.byName(name)?.status ?? '';
  bool sectionPresent(String sec) {
    if (scan == null) return false;
    final m = scan.completeness.checklist.where((c) => c.section == sec);
    return m.isNotEmpty && m.first.present;
  }

  // --- COA source (scan doc_type authoritative) ---
  final claimCoa = a.single('coa_source');
  final doc = hc('doc_type');
  if (hasScan && doc == 'third_party_lab') {
    final corrected = claimCoa == 'in_house' || claimCoa == 'none' || claimCoa == 'unsure';
    s.add(TrustSignal('COA source', TrustLevel.green,
        'Independent third-party lab — the gold standard.${corrected ? ' (The scan confirms it’s third-party.)' : ''}'));
  } else if (hasScan && doc == 'manufacturer_qc') {
    if (claimCoa == 'third_party') {
      s.add(const TrustSignal('COA source', TrustLevel.red,
          'You said third-party, but the scan reads this as an in-house / manufacturer report.'));
    } else {
      s.add(const TrustSignal('COA source', TrustLevel.amber,
          'In-house / manufacturer report — self-reported; ask for an independent report.'));
    }
  } else {
    switch (claimCoa) {
      case 'third_party':
        s.add(const TrustSignal('COA source', TrustLevel.green, 'Independent third-party lab — the gold standard.'));
      case 'in_house':
        s.add(const TrustSignal('COA source', TrustLevel.amber, 'In-house COA — self-reported; ask for an independent report.'));
      case 'unsure':
        s.add(const TrustSignal('COA source', TrustLevel.amber, 'COA source unknown — find out which lab produced it.'));
      case 'none':
        s.add(const TrustSignal('COA source', TrustLevel.red, 'No COA — the main evidence of quality is missing.'));
    }
  }

  // --- Verifiable (scan verifiability / Janoshik key authoritative) ---
  final claimVerif = a.single('verifiability');
  final v = hc('verifiability');
  final janoshikPending = hc('janoshik') == 'pending_user_verification';
  if (hasScan && (v == 'verifiable' || janoshikPending)) {
    final corrected = claimVerif == 'no' || claimVerif == 'unsure';
    s.add(TrustSignal('Verifiable', TrustLevel.green,
        'The COA carries a verification path you can check at the lab.${corrected ? ' (The scan found one.)' : ''}'));
  } else if (hasScan && v == 'redacted') {
    s.add(const TrustSignal('Verifiable', TrustLevel.red,
        'A verification field appears blanked or altered on the COA.'));
  } else if (hasScan && v == 'no_verification_path') {
    s.add(TrustSignal('Verifiable', TrustLevel.red,
        claimVerif == 'yes'
            ? 'You said it’s verifiable, but the scan found no verification path on the document.'
            : 'No verification path found on the COA — the strongest check is missing.'));
  } else {
    switch (claimVerif) {
      case 'yes':
        s.add(const TrustSignal('Verifiable', TrustLevel.green, 'Has a verification key / QR you can check at the lab.'));
      case 'unsure':
        s.add(const TrustSignal('Verifiable', TrustLevel.amber, 'Verifiability unknown — look for a QR / key / portal.'));
      case 'no':
        s.add(const TrustSignal('Verifiable', TrustLevel.red, 'No independent way to verify — the strongest check is missing.'));
    }
  }

  // --- Batch match (answer-only: only you can compare to your physical vial) ---
  switch (a.single('batch')) {
    case 'matches':
      s.add(const TrustSignal('Batch match', TrustLevel.green, 'Vial lot matches the COA.'));
    case 'no_batch':
      s.add(const TrustSignal('Batch match', TrustLevel.amber, 'Vial has no lot — limits traceability.'));
    case 'unchecked':
      s.add(const TrustSignal('Batch match', TrustLevel.amber, 'Not checked — compare the vial lot to the COA.'));
    case 'different':
      s.add(const TrustSignal('Batch match', TrustLevel.red, 'Vial lot ≠ COA lot — the report may not apply to your vial.'));
  }

  // --- Cap / crimp match (answer-only: the scan can't see the physical vial) ---
  switch (a.single('cap_match')) {
    case 'matches':
      s.add(const TrustSignal('Cap / vial match', TrustLevel.green, 'Cap colour and vial match the COA’s photo.'));
    case 'no_photo':
      s.add(const TrustSignal('Cap / vial match', TrustLevel.amber, 'COA has no vial photo — one less link to your product.'));
    case 'unchecked':
      s.add(const TrustSignal('Cap / vial match', TrustLevel.amber, 'Not checked — compare the cap / crimp to the COA’s vial photo.'));
    case 'different':
      s.add(const TrustSignal('Cap / vial match', TrustLevel.red, 'Cap / vial doesn’t match the COA photo — the report may be for a different product.'));
  }

  // --- Recency (scan date authoritative) ---
  final claimRec = a.single('recency');
  final r = hc('recency');
  if (hasScan && r == 'pass') {
    final corrected = claimRec == 'over12' || claimRec == 'six_to_twelve';
    s.add(TrustSignal('Recency', TrustLevel.green,
        'COA date is within the last ~6 months.${corrected ? ' (Per the scan.)' : ''}'));
  } else if (hasScan && r == 'stale') {
    s.add(TrustSignal('Recency', claimRec == 'under6' ? TrustLevel.red : TrustLevel.amber,
        claimRec == 'under6'
            ? 'You said under 6 months, but the COA date reads as stale (over ~6 months).'
            : 'COA date reads as stale (over ~6 months).'));
  } else {
    switch (claimRec) {
      case 'under6':
        s.add(const TrustSignal('Recency', TrustLevel.green, 'Tested within the last 6 months.'));
      case 'six_to_twelve':
        s.add(const TrustSignal('Recency', TrustLevel.amber, '6–12 months old — getting stale.'));
      case 'over12':
        s.add(const TrustSignal('Recency', TrustLevel.red, 'Over a year / unknown — may not reflect current material.'));
    }
  }

  // --- Test scope (scan checklist authoritative) ---
  if (hasScan) {
    final hasMs = sectionPresent('identity');
    final hasContaminant =
        sectionPresent('heavy_metals') || sectionPresent('endotoxin') || sectionPresent('sterility');
    if (hasMs && hasContaminant) {
      s.add(const TrustSignal('Test scope', TrustLevel.green, 'Identity (MS) + contaminant testing — comprehensive (per scan).'));
    } else if (hasMs) {
      s.add(const TrustSignal('Test scope', TrustLevel.amber, 'Identity confirmed, but no contaminant testing (per scan).'));
    } else {
      s.add(const TrustSignal('Test scope', TrustLevel.amber, 'Purity / mass only — no identity (MS) or contaminant testing (per scan).'));
    }
    // Over-claim flag: the user said it tests X, but the scan didn't find X.
    const scopeToSection = {'ms_identity': 'identity', 'heavy_metals': 'heavy_metals', 'endotoxin': 'endotoxin', 'sterility': 'sterility'};
    final overclaimed = scopeToSection.entries
        .where((e) => a.multi('test_scope').contains(e.key) && !sectionPresent(e.value))
        .map((e) => e.key == 'ms_identity' ? 'MS identity' : e.key.replaceAll('_', ' '))
        .toList();
    if (overclaimed.isNotEmpty) {
      s.add(TrustSignal('Tests not found', TrustLevel.amber,
          'You said the COA covers ${overclaimed.join(', ')}, but ${overclaimed.length == 1 ? "that wasn’t" : "those weren’t"} found on it.'));
    }
  } else {
    final scope = a.multi('test_scope');
    const contaminants = {'heavy_metals', 'endotoxin', 'sterility'};
    final hasContaminant = scope.any(contaminants.contains);
    final hasMs = scope.contains('ms_identity');
    if (scope.isEmpty || scope.contains('not_sure')) {
      s.add(const TrustSignal('Test scope', TrustLevel.amber, 'Test scope unclear — confirm what was actually tested.'));
    } else if (hasMs && hasContaminant) {
      s.add(const TrustSignal('Test scope', TrustLevel.green, 'Identity (MS) + contaminant testing — comprehensive.'));
    } else if (hasMs) {
      s.add(const TrustSignal('Test scope', TrustLevel.amber, 'Identity confirmed, but no contaminant testing.'));
    } else {
      s.add(const TrustSignal('Test scope', TrustLevel.amber, 'Purity / mass only — no identity (MS) or contaminant testing; purity ≠ safety or identity.'));
    }
  }

  final reds = s.where((x) => x.level == TrustLevel.red).length;
  final ambers = s.where((x) => x.level == TrustLevel.amber).length;
  final TrustLevel level;
  final String verdict;
  // Verdict copy is origin-aware: a self-commissioned test IS the independent
  // test, so it never tells you to "get one" — only how to weigh its findings.
  if (reds >= 2) {
    level = TrustLevel.red;
    verdict = selfTested
        ? 'Weak or contradicted signals — even your own test shows problems here. Don’t rely on this vial.'
        : 'Weak or contradicted signals — treat as unreliable; have a vial independently tested, or walk away.';
  } else if (reds == 1 || ambers >= 2) {
    level = TrustLevel.amber;
    verdict = selfTested
        ? 'Mixed signals — your own test stands; weigh the flagged points before relying on this vial.'
        : 'Mixed signals — verify the COA at the lab and consider an independent test before relying on it.';
  } else {
    level = TrustLevel.green;
    verdict = selfTested
        ? 'Strong signals — your own independent test backs them up; it covers the sample you submitted.'
        : 'Strong signals — still verify the COA on the lab’s site and consider an independent test.';
  }
  return TrustProfile(s, level, verdict);
}
