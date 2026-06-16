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
        subtitle: Text(
          'passed ${counts['pass'] ?? 0} · did not pass ${counts['fired'] ?? 0} · '
          'n/a ${counts['not_applicable'] ?? 0} · err ${counts['error'] ?? 0}',
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
          _section(context, 'Checks that did not pass (${fired.length})'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Each rule is named after the thing it checks for. A rule here did '
              'NOT pass: for a “… present / named / attached” check that means the '
              'element wasn’t found in the extracted text (a compact COA may '
              'genuinely omit it, or the scan’s OCR may have missed it); for a '
              'forgery check it means a red flag was raised.',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: Icon(Icons.close, size: 14, color: color),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(r.ruleId, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${r.name ?? r.ruleId}  ·  ${r.severity ?? "?"} · ${r.category ?? ""}',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
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
}
