/// Hand-written, immutable models for the backend's `/api/scan` response.
///
/// No codegen (no freezed/json_serializable) — a deliberate MVP decision so the
/// app compiles after `flutter pub get` with no build_runner step. See
/// DECISIONS.md. Parsing is defensive: the backend payload is rich and a little
/// irregular (per-check fields vary), so we keep raw maps around for anything
/// not explicitly typed, and surface the full payload for the debug panel.
library;

// ---------------------------------------------------------------------------
// Parse helpers (tolerant of int/double/string/null variations from JSON)
// ---------------------------------------------------------------------------

int _toInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? fallback;
  return fallback;
}

double _toDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String? _toStr(Object? v) => v?.toString();

List<String> _toStrList(Object? v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

Map<String, dynamic> _toMap(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return const {};
}

// ---------------------------------------------------------------------------
// Scan outcome (sealed): success | not-a-COA
// ---------------------------------------------------------------------------

sealed class ScanOutcome {
  const ScanOutcome();
}

class ScanSuccess extends ScanOutcome {
  final ScanResult result;
  const ScanSuccess(this.result);
}

class ScanNotACoaOutcome extends ScanOutcome {
  final NotACoa info;
  const ScanNotACoaOutcome(this.info);
}

// ---------------------------------------------------------------------------
// Full scan result
// ---------------------------------------------------------------------------

class ScanResult {
  final String filename;
  final String inputType; // "pdf" | "image"
  final AxisScore authenticity;
  final AxisScore completeness;
  final ScanSummary summary;
  final List<String> notes;
  final List<String> limitations;
  final List<ResultAlert> resultAlerts;
  final Synthesis? synthesis;
  final HardChecks hardChecks;
  final List<RuleResult> ruleResults;
  final Map<String, dynamic> features; // raw — debug panel only
  final LlmResult llm;
  final Map<String, dynamic> raw; // full payload — debug panel
  final DateTime scannedAt;

  ScanResult({
    required this.filename,
    required this.inputType,
    required this.authenticity,
    required this.completeness,
    required this.summary,
    required this.notes,
    required this.limitations,
    this.resultAlerts = const [],
    this.synthesis,
    required this.hardChecks,
    required this.ruleResults,
    required this.features,
    required this.llm,
    required this.raw,
    required this.scannedAt,
  });

  /// True when the lab reported no measurable product (Quantity "Not Detected",
  /// Purity "n/a", below LOQ…) — a content red flag, separate from authenticity.
  bool get hasCriticalResultAlert => resultAlerts.any((a) => a.severity == 'critical');

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      filename: _toStr(json['filename']) ?? 'COA',
      inputType: _toStr(json['input_type']) ?? 'pdf',
      authenticity: AxisScore.fromJson(_toMap(json['authenticity'])),
      completeness: AxisScore.fromJson(_toMap(json['completeness'])),
      summary: ScanSummary.fromJson(_toMap(json['summary'])),
      notes: _toStrList(json['notes']),
      limitations: _toStrList(json['limitations']),
      resultAlerts: (json['result_alerts'] is List)
          ? (json['result_alerts'] as List).map((e) => ResultAlert.fromJson(_toMap(e))).toList()
          : const [],
      synthesis: json['synthesis'] is Map ? Synthesis.fromJson(_toMap(json['synthesis'])) : null,
      hardChecks: HardChecks.fromJson(_toMap(json['hard_checks'])),
      ruleResults: (json['rule_results'] is List)
          ? (json['rule_results'] as List).map((e) => RuleResult.fromJson(_toMap(e))).toList()
          : const [],
      features: _toMap(json['features']),
      llm: LlmResult.fromJson(_toMap(json['llm'])),
      raw: json,
      scannedAt: DateTime.now(),
    );
  }
}

/// A "null result" content alert: the document is genuine, but the lab reported
/// no measurable product (Quantity "Not Detected", Purity "n/a", below LOQ…).
/// Distinct from authenticity — surfaced as its own prominent banner.
class ResultAlert {
  final String analysis; // e.g. "Quantity", "Chromatographic Purity"
  final String result; // verbatim cell, e.g. "Not Detected", "n/a"
  final String category; // "quantity" | "purity" | "other"
  final String kind; // "not_detected" | "not_applicable"
  final String severity; // "critical" | "warning"
  final String message;

  const ResultAlert({
    required this.analysis,
    required this.result,
    required this.category,
    required this.kind,
    required this.severity,
    required this.message,
  });

  factory ResultAlert.fromJson(Map<String, dynamic> json) => ResultAlert(
        analysis: _toStr(json['analysis']) ?? '',
        result: _toStr(json['result']) ?? '',
        category: _toStr(json['category']) ?? 'other',
        kind: _toStr(json['kind']) ?? 'not_detected',
        severity: _toStr(json['severity']) ?? 'warning',
        message: _toStr(json['message']) ?? '',
      );
}

/// Plain-language synthesis tying the three result categories together:
/// authenticity (genuine?), completeness (which tests?), values (what they say?),
/// plus one evidence-framed recommendation.
class Synthesis {
  final SynthCategory authenticity;
  final SynthCategory completeness;
  final SynthValues values;
  final Recommendation recommendation;
  final String origin; // "vendor" | "self"

  const Synthesis({
    required this.authenticity,
    required this.completeness,
    required this.values,
    required this.recommendation,
    required this.origin,
  });

  factory Synthesis.fromJson(Map<String, dynamic> json) => Synthesis(
        authenticity: SynthCategory.fromJson(_toMap(json['authenticity'])),
        completeness: SynthCategory.fromJson(_toMap(json['completeness'])),
        values: SynthValues.fromJson(_toMap(json['values'])),
        recommendation: Recommendation.fromJson(_toMap(json['recommendation'])),
        origin: _toStr(json['origin']) ?? 'vendor',
      );
}

class SynthReason {
  final String text;
  final String polarity; // pos | neg | neutral
  const SynthReason(this.text, this.polarity);
  factory SynthReason.fromJson(Map<String, dynamic> j) =>
      SynthReason(_toStr(j['text']) ?? '', _toStr(j['polarity']) ?? 'neutral');
}

List<SynthReason> _reasons(dynamic v) => (v is List)
    ? v.map((e) => SynthReason.fromJson(_toMap(e))).toList()
    : const [];

class SynthCategory {
  final String verdict;
  final List<SynthReason> reasons;
  final List<String> present; // completeness only
  final List<String> missing; // completeness only

  const SynthCategory({required this.verdict, required this.reasons, this.present = const [], this.missing = const []});

  factory SynthCategory.fromJson(Map<String, dynamic> j) => SynthCategory(
        verdict: _toStr(j['verdict']) ?? '',
        reasons: _reasons(j['reasons']),
        present: _toStrList(j['present']),
        missing: _toStrList(j['missing']),
      );
}

class SynthValueEntry {
  final String label;
  final String value;
  final String assessment; // ok | caution | suspicious | invalid
  final String note;
  const SynthValueEntry({required this.label, required this.value, required this.assessment, required this.note});
  factory SynthValueEntry.fromJson(Map<String, dynamic> j) => SynthValueEntry(
        label: _toStr(j['label']) ?? '',
        value: _toStr(j['value']) ?? '',
        assessment: _toStr(j['assessment']) ?? 'ok',
        note: _toStr(j['note']) ?? '',
      );
}

class SynthValues {
  final String verdict;
  final List<SynthValueEntry> entries;
  final List<SynthReason> reasons;
  const SynthValues({required this.verdict, required this.entries, required this.reasons});
  factory SynthValues.fromJson(Map<String, dynamic> j) => SynthValues(
        verdict: _toStr(j['verdict']) ?? '',
        entries: (j['entries'] is List)
            ? (j['entries'] as List).map((e) => SynthValueEntry.fromJson(_toMap(e))).toList()
            : const [],
        reasons: _reasons(j['reasons']),
      );
}

class Recommendation {
  final String level; // critical | caution | ok
  final String headline;
  final String detail;
  final List<String> actions;
  const Recommendation({required this.level, required this.headline, required this.detail, required this.actions});
  factory Recommendation.fromJson(Map<String, dynamic> j) => Recommendation(
        level: _toStr(j['level']) ?? 'ok',
        headline: _toStr(j['headline']) ?? '',
        detail: _toStr(j['detail']) ?? '',
        actions: _toStrList(j['actions']),
      );
}

class AxisScore {
  final int score; // 0–100
  final String label;
  final String copy;
  final double weightInAxis;
  final double weightFired;
  final List<String> firedRuleIds;
  final List<String> passedRuleIds;
  final List<ChecklistItem> checklist; // completeness only; empty for authenticity

  const AxisScore({
    required this.score,
    required this.label,
    required this.copy,
    required this.weightInAxis,
    required this.weightFired,
    required this.firedRuleIds,
    required this.passedRuleIds,
    this.checklist = const [],
  });

  factory AxisScore.fromJson(Map<String, dynamic> json) {
    return AxisScore(
      score: _toInt(json['score']),
      label: _toStr(json['label']) ?? 'unknown',
      copy: _toStr(json['copy']) ?? '',
      weightInAxis: _toDouble(json['weight_in_axis']),
      weightFired: _toDouble(json['weight_fired']),
      firedRuleIds: _toStrList(json['fired_rule_ids']),
      passedRuleIds: _toStrList(json['passed_rule_ids']),
      checklist: (json['checklist'] is List)
          ? (json['checklist'] as List).map((e) => ChecklistItem.fromJson(_toMap(e))).toList()
          : const [],
    );
  }
}

/// One expected-section row in the completeness checklist.
class ChecklistItem {
  final String section;
  final String label;
  final bool present;

  const ChecklistItem({required this.section, required this.label, required this.present});

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      section: _toStr(json['section']) ?? '',
      label: _toStr(json['label']) ?? '',
      present: json['present'] == true,
    );
  }
}

class ScanSummary {
  final List<String> firedCriticalAuthenticityRules;
  final Map<String, int> ruleCounts;
  final String? peptideDetected;
  final String? peptideDetectMethod;
  final String? msTechniqueDetected;
  final double? labeledMassMg;
  final double? measuredAssayMg;
  final String? batchLot;
  final double? purityPct;
  final String? purityGrade;

  const ScanSummary({
    required this.firedCriticalAuthenticityRules,
    required this.ruleCounts,
    required this.peptideDetected,
    required this.peptideDetectMethod,
    required this.msTechniqueDetected,
    this.labeledMassMg,
    this.measuredAssayMg,
    this.batchLot,
    this.purityPct,
    this.purityGrade,
  });

  /// True when both the labeled and measured masses were parsed (so the UI can
  /// surface the assay next to the purity).
  bool get hasDose => labeledMassMg != null && measuredAssayMg != null;

  factory ScanSummary.fromJson(Map<String, dynamic> json) {
    final counts = _toMap(json['rule_counts']).map((k, v) => MapEntry(k, _toInt(v)));
    return ScanSummary(
      firedCriticalAuthenticityRules: _toStrList(json['fired_critical_authenticity_rules']),
      ruleCounts: counts,
      peptideDetected: _toStr(json['peptide_detected']),
      peptideDetectMethod: _toStr(json['peptide_detect_method']),
      msTechniqueDetected: _toStr(json['ms_technique_detected']),
      labeledMassMg: json['labeled_mass_mg'] == null ? null : _toDouble(json['labeled_mass_mg']),
      measuredAssayMg: json['measured_assay_mg'] == null ? null : _toDouble(json['measured_assay_mg']),
      batchLot: _toStr(json['batch_lot']),
      purityPct: json['purity_pct'] == null ? null : _toDouble(json['purity_pct']),
      purityGrade: _toStr(json['purity_grade']),
    );
  }
}

/// A single hard check. Field set varies per check, so extra fields are read
/// from [data] via getters rather than typed individually.
class HardCheck {
  final String name; // e.g. "janoshik"
  final Map<String, dynamic> data;

  const HardCheck(this.name, this.data);

  String get status => _toStr(data['status']) ?? 'unknown';
  String? get message => _toStr(data['message']);
  String? get reason => _toStr(data['reason']);

  // janoshik
  String? get verificationUrl => _toStr(data['verification_url']);
  String? get taskNumber => _toStr(data['task_number']);
  String? get uniqueKey => _toStr(data['unique_key']);

  // known_lab / visual_lab
  String? get labName => _toStr(data['lab_name']) ?? _toStr(data['matched_lab_name']);
  String? get trust => _toStr(data['trust']);

  /// known_lab: lab-specific warning (e.g. documented accuracy issues) carried
  /// over from the registry, even for an otherwise-recognized lab.
  String? get caveat => _toStr(data['caveat']);

  // verifiability (XREF-012) / doc_type (DOC-001)
  String? get confidence => _toStr(data['confidence']);

  /// Whether this check produced something worth showing as a finding.
  bool get isApplicable =>
      status != 'not_applicable' &&
      status != 'metrics_only' &&
      status != 'deferred_to_janoshik';

  /// True for clearly-failing states the UI should treat as red.
  bool get isFailing => status == 'fired';

  /// True for ambiguous / verify-further states (amber).
  bool get isWarning =>
      status == 'suspicious' ||
      status == 'no_match' ||
      status == 'unrecognized_named' ||
      status == 'no_issuer' ||
      status == 'redacted' ||
      status == 'no_verification_path' ||
      status == 'manufacturer_qc' ||
      status == 'underdosed' ||
      status == 'stale' ||
      status == 'vague' ||
      status == 'too_perfect' ||
      status == 'single' ||
      status == 'none';

  /// True for confirmed-good states (green).
  bool get isPassing =>
      status == 'pass' || status == 'verifiable' || status == 'third_party_lab' ||
      status == 'multi';

  /// Janoshik "tap to verify" state.
  bool get isPendingVerification => status == 'pending_user_verification';

  /// True when the issuer is flagged as a known bad actor.
  bool get isUntrusted => trust == 'untrusted';
}

/// Hard checks in a stable display order.
class HardChecks {
  final List<HardCheck> all;

  const HardChecks(this.all);

  static const _order = [
    'mw_table',
    'known_lab',
    'janoshik',
    'verifiability',
    'doc_type',
    'assay_mass',
    'recency',
    'purity_sanity',
    'methods',
    'visual_lab',
    'multi_mass',
    'metadata',
    'blur_tamper',
  ];

  factory HardChecks.fromJson(Map<String, dynamic> json) {
    final checks = <HardCheck>[];
    // Known checks first (stable order), then any unexpected extras.
    for (final key in _order) {
      if (json.containsKey(key)) checks.add(HardCheck(key, _toMap(json[key])));
    }
    for (final key in json.keys) {
      if (!_order.contains(key)) checks.add(HardCheck(key, _toMap(json[key])));
    }
    return HardChecks(checks);
  }

  HardCheck? byName(String name) {
    for (final c in all) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Checks worth showing as findings, failing/warning first. `doc_type` is
  /// always shown via its own chip; `verifiability` gets a dedicated verify
  /// button when positive, so only its negative states appear here.
  List<HardCheck> get findings {
    final list = all.where((c) {
      if (!c.isApplicable) return false;
      if (c.name == 'doc_type') return false;
      if (c.name == 'verifiability' && c.isPassing) return false;
      return c.message != null || c.isPassing;
    }).toList();
    int rank(HardCheck c) => c.isFailing ? 0 : (c.isWarning ? 1 : (c.isPendingVerification ? 2 : 3));
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }
}

class RuleResult {
  final String ruleId;
  final String? name;
  final String? category;
  final double weight;
  final String? severity; // critical | major | minor
  final String status; // pass | fired | not_applicable | error

  const RuleResult({
    required this.ruleId,
    required this.name,
    required this.category,
    required this.weight,
    required this.severity,
    required this.status,
  });

  factory RuleResult.fromJson(Map<String, dynamic> json) {
    return RuleResult(
      ruleId: _toStr(json['rule_id']) ?? '?',
      name: _toStr(json['name']),
      category: _toStr(json['category']),
      weight: _toDouble(json['weight']),
      severity: _toStr(json['severity']),
      status: _toStr(json['status']) ?? 'unknown',
    );
  }
}

class LlmResult {
  final bool enabled;
  final String? note;
  final String? verdict;
  final double? confidence;
  final bool? visualTampering;
  final bool? labNameAltered;
  final String? summary;
  final String? model;
  final List<String> findings;

  const LlmResult({
    required this.enabled,
    this.note,
    this.verdict,
    this.confidence,
    this.visualTampering,
    this.labNameAltered,
    this.summary,
    this.model,
    this.findings = const [],
  });

  bool get didRun => enabled && verdict != null;

  factory LlmResult.fromJson(Map<String, dynamic> json) {
    return LlmResult(
      enabled: json['enabled'] == true,
      note: _toStr(json['note']),
      verdict: _toStr(json['verdict']),
      confidence: json['confidence'] == null ? null : _toDouble(json['confidence']),
      visualTampering: json['visual_tampering'] is bool ? json['visual_tampering'] as bool : null,
      labNameAltered: json['lab_name_altered'] is bool ? json['lab_name_altered'] as bool : null,
      summary: _toStr(json['summary']),
      model: _toStr(json['model']),
      findings: _toStrList(json['findings']),
    );
  }
}

// ---------------------------------------------------------------------------
// Not-a-COA (HTTP 200 with error:"input_not_coa")
// ---------------------------------------------------------------------------

class NotACoa {
  final String filename;
  final String message;
  final int ocrChars;

  const NotACoa({required this.filename, required this.message, required this.ocrChars});

  factory NotACoa.fromJson(Map<String, dynamic> json) {
    return NotACoa(
      filename: _toStr(json['filename']) ?? 'file',
      message: _toStr(json['message']) ?? "This doesn't look like a COA.",
      ocrChars: _toInt(json['ocr_chars']),
    );
  }
}

// ---------------------------------------------------------------------------
// Errors / cancellation
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException({required this.message, this.statusCode});
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ScanCancelled implements Exception {
  const ScanCancelled();
}
