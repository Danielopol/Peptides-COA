import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/models.dart';

/// Collapsible technical view for validating the backend: fired rules grouped
/// by severity, rule counts, LLM result, and the raw JSON payload.
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key, required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fired = result.ruleResults.where((r) => r.status == 'fired').toList()
      ..sort((a, b) => _sevRank(a.severity).compareTo(_sevRank(b.severity)));
    final counts = result.summary.ruleCounts;

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.terminal),
        title: const Text('Advanced / technical detail'),
        // A "pass" means a rule did not fire — NOT that a field was verified.
        // Most rules are forgery detectors, so a clean non-COA trips none of them
        // and racks up a high "pass" count. Label it so it can't be read as trust.
        subtitle: Text(
          '${counts['pass'] ?? 0} forgery checks didn’t trip · '
          '${counts['fired'] ?? 0} flagged · n/a ${counts['not_applicable'] ?? 0} · '
          'err ${counts['error'] ?? 0}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (result.llm.didRun) ...[
            _section(context, 'LLM vision second opinion'),
            Text(
              'verdict: ${result.llm.verdict} · confidence: ${result.llm.confidence} · '
              'model: ${result.llm.model ?? "?"}',
              style: const TextStyle(fontSize: 13),
            ),
            if (result.llm.summary != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(result.llm.summary!, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
          ],
          ..._visualAudit(context, result),
          _section(context, 'What we couldn’t confirm (${fired.length})'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'These are the things we couldn’t find on the document, or that looked '
              'off. A missing item isn’t proof of a problem — a simple COA may just '
              'leave it out, or the scan may have missed it. Red marks are the most '
              'important, amber next, grey are minor.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: scheme.onSurfaceVariant),
            ),
          ),
          if (fired.isEmpty)
            Text('All evaluated checks passed.', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
          else
            ...fired.map((r) => _ruleRow(context, r)),
        ],
      ),
    );
  }

  /// Fields the vision LLM confirmed are present (OCR had missed them), so their
  /// completeness checks were flipped from "did not pass" to pass.
  List<Widget> _visualAudit(BuildContext context, ScanResult result) {
    final lc = result.raw['llm_completeness'];
    if (lc is! Map) return const [];
    final sections = lc['confirmed_sections'];
    if (sections is! List || sections.isEmpty) return const [];
    final scheme = Theme.of(context).colorScheme;
    return [
      _section(context, 'Fields confirmed by visual review (${sections.length})'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'OCR missed these, but the vision model saw them on the page, so these '
          'completeness sections were marked present: ${sections.join(", ")}.',
          style: TextStyle(fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      );

  Widget _ruleRow(BuildContext context, RuleResult r) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (r.severity) {
      'critical' => HelixColors.of(context).vRed,
      'major' => HelixColors.of(context).vAmber,
      _ => scheme.onSurfaceVariant,
    };
    // Presentation-only plain-language line; falls back to the raw rule name if a
    // rule isn't mapped. Does NOT change the rule or its result.
    final text = _friendly[r.ruleId] ?? r.name ?? r.ruleId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.close, size: 14, color: color),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, height: 1.3, color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }

  static int _sevRank(String? s) => switch (s) {
        'critical' => 0,
        'major' => 1,
        'minor' => 2,
        _ => 3,
      };

  /// Plain-language phrasing for each rule WHEN IT IS FLAGGED (presence rules read
  /// as "… is missing"; forgery/quality rules describe the red flag). Presentation
  /// only — keyed by rule_id, used solely to render this card.
  static const Map<String, String> _friendly = {
    // Structure — required fields (flagged = not found on the document)
    'STRUCT-001': 'Product / peptide name is missing',
    'STRUCT-002': 'Batch or lot number is missing',
    'STRUCT-003': 'Analysis date is missing',
    'STRUCT-004': 'Testing laboratory name is missing',
    'STRUCT-005': 'Laboratory address is missing',
    'STRUCT-006': 'Laboratory contact information is missing',
    'STRUCT-007': 'Analyst signature or certification is missing',
    'STRUCT-008': 'Purity result (a % value) is missing',
    'STRUCT-009': 'Mass-spec identity confirmation is missing',
    'STRUCT-010': 'Pass / fail determination is missing',
    'STRUCT-011': 'Sample-receipt and test dates are missing',
    'STRUCT-012': 'Client or supplier name is missing',
    // Methods (flagged = method/data not stated on the document)
    'METH-001': 'HPLC method is not named',
    'METH-002': 'Mass-spec method is not named',
    'METH-003': 'Reversed-phase C18 column is not specified',
    'METH-004': 'Mobile phase / solvent is not specified',
    'METH-005': 'MS technique type (ESI, MALDI, …) is not specified',
    'METH-006': 'No HPLC chromatogram is attached',
    'METH-007': 'Chromatogram baseline stability is not shown',
    'METH-008': 'Integration lines are not visible on the chromatogram',
    'METH-009': 'ESI-MS charge states are not shown for a large peptide',
    'METH-010': 'Net peptide content method is not specified',
    'METH-011': 'Heavy-metals testing (ICP-MS) is not reported',
    'METH-012': 'Endotoxin testing (LAL) is not reported',
    // Lab credentials
    'LAB-001': 'Not tested by an independent third-party lab',
    'LAB-002': 'No ISO/IEC 17025 accreditation is stated',
    'LAB-003': 'Accreditation wording looks incorrect',
    'LAB-004': 'Accreditation scope may not cover peptide analysis',
    'LAB-005': 'Accreditation body is not recognized / verifiable',
    'LAB-006': 'The lab could not be found in a web search',
    'LAB-007': 'The lab did not confirm this COA when contacted',
    'LAB-008': 'Verification key or QR code is not valid',
    'LAB-009': 'The lab has no established peptide-testing track record',
    'LAB-010': 'The lab’s accreditation may be expired',
    // Metadata
    'META-001': 'PDF creation date doesn’t match the analysis date',
    'META-002': 'Authoring software isn’t a typical lab / document tool',
    'META-003': 'The analysis is dated in the future',
    'META-004': 'The file has an unusual modification history',
    'META-005': 'Looks like a generic template, not batch-specific',
    // Numerical
    'NUM-001': 'HPLC purity is below the minimum threshold',
    'NUM-002': 'Purity is a suspiciously round number',
    'NUM-003': 'Purity is above 100% (not possible)',
    'NUM-004': 'Mass-spec error is outside instrument tolerance',
    'NUM-005': 'Net peptide content is outside the expected range',
    'NUM-006': 'The COA is older than the acceptable window',
    'NUM-007': 'HPLC detection wavelength is unusual for peptides',
    'NUM-008': 'No trace impurity peaks in the chromatogram (too clean)',
    'NUM-009': 'Endotoxin level is above the standard threshold',
    'NUM-010': 'Molecular weight is outside the reference range for this peptide',
    'NUM-011': 'HPLC flow rate is outside the normal range',
    // Formatting / appearance
    'FMT-001': 'The document looks low-quality or unprofessional',
    'FMT-002': 'Resolution is uneven across the document (possible editing)',
    'FMT-003': 'Fonts are inconsistent (possible editing)',
    'FMT-004': 'Text / number alignment doesn’t match the template',
    'FMT-005': 'Clone-stamp or copy-paste artifacts are visible',
    'FMT-006': 'The signature looks copied or unnatural',
    'FMT-007': 'Security features look pasted on, not integrated',
    'FMT-008': 'The document isn’t fully downloadable / accessible',
    // Forgery indicators
    'FORG-001': 'Purity values look suspiciously round',
    'FORG-002': 'Claims under 100% purity but shows zero impurity peaks',
    'FORG-003': 'Mass-spec matches theory exactly with zero error (suspicious)',
    'FORG-004': 'The same COA layout is reused across different products',
    'FORG-005': 'Identical HPLC retention times across different peptides',
    'FORG-006': 'Stamps / seals are blurry while the surrounding text is sharp',
    'FORG-007': 'Localized pixelation in specific fields (possible edits)',
    'FORG-008': 'Batch numbers look generic or sequential',
    'FORG-009': 'The vendor’s whole catalog shows perfect purity',
    'FORG-010': 'The COA is only available after purchase',
    'FORG-011': 'The vendor discourages contacting the lab',
    'FORG-012': 'Community testing contradicts the COA’s claims',
    'FORG-013': 'The lab has no record of this vendor or batch',
    'FORG-014': 'Vendor marketing shows compliance red flags',
    'FORG-015': 'The price is far below the market rate',
    // Cross-reference
    'XREF-001': 'Batch number doesn’t match the product vial',
    'XREF-002': 'Measured mass doesn’t match the named peptide',
    'XREF-003': 'Vendor name doesn’t match a known vendor',
    'XREF-004': 'The dates aren’t in a plausible order',
    'XREF-005': 'ESI-MS charge states aren’t internally consistent',
    'XREF-006': 'MS adduct peaks aren’t at the expected masses',
    'XREF-007': 'QR / verification data doesn’t match the paper COA',
    'XREF-008': 'HPLC and MS data reference different batches',
    'XREF-009': 'The molecular weight doesn’t match the named peptide',
  };
}
