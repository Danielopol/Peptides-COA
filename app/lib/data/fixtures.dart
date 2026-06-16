/// Canned fixtures for [MockApiClient], mirroring the real backend shape so the
/// UI can be developed/demoed without a live backend. Embedded as JSON strings
/// (no asset wiring needed; works identically on web and Android).
library;

/// likely_authentic + full_report Janoshik COA: lab badge + verify deeplink.
const String kFixtureAuthentic = r'''
{
  "filename": "janoshik_bpc157.pdf",
  "input_type": "pdf",
  "authenticity": {
    "score": 91,
    "label": "likely_authentic",
    "copy": "This COA appears authentic. No tampering or forgery indicators detected.",
    "weight_in_axis": 92.0, "weight_fired": 6.0,
    "fired_rule_ids": ["FMT-002"],
    "passed_rule_ids": ["LAB-003", "FMT-003", "META-003", "META-005", "FORG-003", "FORG-006"]
  },
  "completeness": {
    "score": 82,
    "label": "full_report",
    "copy": "Comprehensive COA. Most expected fields and tests are present.",
    "weight_in_axis": 160.0, "weight_fired": 22.0,
    "fired_rule_ids": ["METH-007"],
    "passed_rule_ids": ["STRUCT-001", "STRUCT-002", "STRUCT-008", "LAB-001", "METH-001", "METH-002"],
    "checklist": [
      {"section": "identity", "label": "Identity confirmation", "present": true},
      {"section": "purity", "label": "Purity (HPLC %)", "present": true},
      {"section": "assay_mass", "label": "Assay / measured mass", "present": true},
      {"section": "heavy_metals", "label": "Heavy metals", "present": true},
      {"section": "endotoxin", "label": "Bacterial endotoxin", "present": true},
      {"section": "sterility", "label": "Sterility / microbial", "present": false},
      {"section": "residual_solvents", "label": "Residual solvents", "present": true},
      {"section": "impurity_profile", "label": "Impurity breakdown", "present": true},
      {"section": "water_content", "label": "Water content (Karl Fischer)", "present": false},
      {"section": "batch_lot", "label": "Batch / lot number", "present": true},
      {"section": "vial_photo", "label": "Vial photo", "present": false},
      {"section": "accreditation", "label": "Lab accreditation", "present": true},
      {"section": "verification", "label": "Verification code / QR", "present": true},
      {"section": "test_date", "label": "Test / analysis date", "present": true}
    ]
  },
  "summary": {
    "fired_critical_authenticity_rules": [],
    "rule_counts": {"pass": 52, "fired": 4, "not_applicable": 26, "error": 0},
    "peptide_detected": "BPC-157",
    "peptide_detect_method": "name",
    "ms_technique_detected": "ESI-MS",
    "purity_pct": 99.18,
    "purity_grade": "excellent"
  },
  "notes": [],
  "limitations": [
    "Even a genuine, verifiable COA only proves the specific sample that was tested — not the vial you received. There is no real batch traceability in this market, and vendors can reuse one COA across many vials.",
    "Purity is not safety. Sterility, bacterial endotoxins, heavy metals and residual solvents are usually NOT tested on these COAs, yet they are what cause the worst reactions.",
    "The only way to know what is in your vial is independent testing of that vial (or a community/group test of the same batch)."
  ],
  "hard_checks": {
    "mw_table": {"status": "pass", "rule_id": "XREF-009", "message": "Claimed mass matches the expected molecular weight for BPC-157."},
    "known_lab": {"status": "pass", "rule_id": "LAB-009", "entity_id": "janoshik", "entity_kind": "lab", "lab_name": "Janoshik Analytical", "trust": "high"},
    "janoshik": {"status": "pending_user_verification", "rule_id": "XREF-010", "task_number": "100491", "unique_key": "DAWP5HCLAV5W", "verification_url": "https://janoshik.com/verify/?key=DAWP5HCLAV5W", "message": "Janoshik task #100491 with key DAWP5HCLAV5W — tap to verify on janoshik.com/verify"},
    "verifiability": {"status": "deferred_to_janoshik", "rule_id": "XREF-012", "message": "Janoshik COA — verifiability handled by the Janoshik check."},
    "doc_type": {"status": "third_party_lab", "rule_id": "DOC-001", "confidence": "high", "signals": ["issuer is a recognized lab (Janoshik Analytical)"], "message": "Issued by Janoshik Analytical, a recognized independent testing lab — this is third-party analysis."},
    "purity_sanity": {"status": "pass", "rule_id": "FORG-019", "purity": 99.18, "operator": null, "grade": "excellent", "message": "Reported purity 99.18% looks like a normal, specific measurement."},
    "methods": {"status": "multi", "rule_id": "METH-013", "families": ["HPLC", "MS"], "message": "Multiple analytical methods used (HPLC, MS) — the results cross-verify each other, which is stronger than a single method."},
    "visual_lab": {"status": "pass", "rule_id": "XREF-011", "matched_lab_name": "Janoshik Analytical", "confidence": "strong", "distance": 0, "message": "Visual layout matches Janoshik Analytical template and OCR text confirms."},
    "multi_mass": {"status": "pass", "rule_id": "FORG-017"},
    "metadata": {"status": "pass", "rule_id": "META-004", "creation_date": "2026-05-13T13:54:13+00:00", "mod_date": "2026-05-13T20:26:10+00:00"},
    "blur_tamper": {"status": "metrics_only", "rule_id": "FORG-016", "word_count": 74, "median_conf": 96.0, "low_conf_frac": 0.027}
  },
  "rule_results": [
    {"rule_id": "STRUCT-001", "name": "Product Name Present", "category": "structure", "weight": 8, "severity": "critical", "status": "pass"},
    {"rule_id": "STRUCT-008", "name": "Purity Result Present as Numerical Value", "category": "structure", "weight": 10, "severity": "critical", "status": "pass"},
    {"rule_id": "METH-001", "name": "HPLC Method Explicitly Named", "category": "analytical_methods", "weight": 10, "severity": "critical", "status": "pass"},
    {"rule_id": "METH-007", "name": "HPLC Chromatogram Baseline Stability", "category": "analytical_methods", "weight": 4, "severity": "minor", "status": "fired"},
    {"rule_id": "FMT-002", "name": "Uniform Resolution Across All Document Sections", "category": "formatting", "weight": 7.73, "severity": "critical", "status": "fired"}
  ],
  "features": {"pages": 3, "has_text_layer": false, "semantic": {"peptide_name_found": "bpc-157", "has_hplc": true, "has_ms": true}, "ocr_text": "TEST REPORT — Janoshik ... Task Number #100491 ... unique key DAWP5HCLAV5W"},
  "llm": {"enabled": true, "model": "gemini-2.5-flash-lite", "usage": {"input_tokens": 790, "output_tokens": 71, "total_tokens": 861}, "verdict": "authentic", "confidence": 1.0, "visual_tampering": false, "lab_name_altered": false, "findings": [], "summary": "The document appears to be an authentic Certificate of Analysis with no visual tampering detected."}
}
''';

/// suspicious: wrong molecular weight (mw_table fired, XREF-009 critical).
const String kFixtureCaution = r'''
{
  "filename": "vendor_retatrutide.pdf",
  "input_type": "pdf",
  "authenticity": {
    "score": 48,
    "label": "suspicious",
    "copy": "Claimed molecular weight does not match the named peptide — strong forgery indicator.",
    "weight_in_axis": 88.0, "weight_fired": 46.0,
    "fired_rule_ids": ["XREF-009", "NUM-006", "FMT-005"],
    "passed_rule_ids": ["LAB-003", "FMT-003", "META-002"]
  },
  "completeness": {
    "score": 58,
    "label": "partial_report",
    "copy": "Some expected sections are missing. Ask vendor for the full report.",
    "weight_in_axis": 150.0, "weight_fired": 63.0,
    "fired_rule_ids": ["METH-006", "LAB-002"],
    "passed_rule_ids": ["STRUCT-001", "STRUCT-002", "STRUCT-008"]
  },
  "summary": {
    "fired_critical_authenticity_rules": ["XREF-009", "FMT-005"],
    "rule_counts": {"pass": 31, "fired": 14, "not_applicable": 37, "error": 0},
    "peptide_detected": "Retatrutide",
    "peptide_detect_method": "name",
    "ms_technique_detected": "MALDI-TOF",
    "labeled_mass_mg": 10.0,
    "measured_assay_mg": 8.45,
    "batch_lot": "RT10426"
  },
  "notes": [],
  "limitations": [
    "Even a genuine, verifiable COA only proves the specific sample that was tested — not the vial you received. There is no real batch traceability in this market, and vendors can reuse one COA across many vials.",
    "Purity is not safety. Sterility, bacterial endotoxins, heavy metals and residual solvents are usually NOT tested on these COAs, yet they are what cause the worst reactions.",
    "The only way to know what is in your vial is independent testing of that vial (or a community/group test of the same batch)."
  ],
  "hard_checks": {
    "mw_table": {"status": "fired", "rule_id": "XREF-009", "severity": "critical", "message": "Claimed molecular weight (4731.3) does not match the expected mass for Retatrutide. This is a strong forgery indicator."},
    "known_lab": {"status": "unrecognized_named", "rule_id": "LAB-009", "severity": "minor", "message": "A testing-lab name is present but not in our verified registry — verify the lab independently."},
    "janoshik": {"status": "not_applicable", "reason": "not a Janoshik COA"},
    "verifiability": {"status": "no_verification_path", "rule_id": "XREF-012", "severity": "major", "message": "No way to independently verify this COA was found (no verification portal, QR code, or lookup key). An unverifiable COA should not be trusted without independent testing."},
    "doc_type": {"status": "manufacturer_qc", "rule_id": "DOC-001", "confidence": "medium", "signals": ["storage/stability instructions present"], "message": "This looks like a manufacturer / in-house QC report (it carries storage/stability instructions), not an independent third-party lab test. The community considers in-house COAs weak evidence — seek independent testing."},
    "assay_mass": {"status": "underdosed", "rule_id": "FORG-018", "labeled_mg": 10.0, "measured_mg": 8.45, "deviation_pct": -15.5, "severity": "minor", "message": "Measured content (8.45 mg) is 15.5% below the labeled 10 mg — outside the ±10% norm. Don't judge by the purity % alone; this is a possible underdose."},
    "recency": {"status": "stale", "rule_id": "META-006", "coa_date": "2025-03-12", "age_days": 446, "severity": "minor", "message": "The most recent date on this COA is 2025-03-12 (~15 months old). COAs older than ~6 months are considered stale — peptides degrade and the current batch may differ. Ask for a recent report or independent testing."},
    "visual_lab": {"status": "no_match", "rule_id": "XREF-011", "best_distance": 171, "message": "Layout does not match any known lab template."},
    "multi_mass": {"status": "pass", "rule_id": "FORG-017"},
    "metadata": {"status": "pass", "rule_id": "META-004", "creation_date": "2026-04-02T10:00:00+00:00"},
    "blur_tamper": {"status": "metrics_only", "rule_id": "FORG-016", "word_count": 120, "median_conf": 91.0}
  },
  "rule_results": [
    {"rule_id": "XREF-009", "name": "Wrong molecular weight for claimed peptide", "category": "cross_reference", "weight": 10, "severity": "critical", "status": "fired"},
    {"rule_id": "FMT-005", "name": "No Clone-Stamp or Copy-Paste Artifacts Visible", "category": "formatting", "weight": 7.38, "severity": "critical", "status": "fired"},
    {"rule_id": "NUM-006", "name": "COA Age Within Acceptable Window", "category": "numerical", "weight": 7, "severity": "major", "status": "fired"},
    {"rule_id": "STRUCT-001", "name": "Product Name Present", "category": "structure", "weight": 8, "severity": "critical", "status": "pass"}
  ],
  "features": {"pages": 1, "has_text_layer": true, "semantic": {"peptide_name_found": "retatrutide", "max_purity": 99.0}, "ocr_text": "Certificate of Analysis ... Retatrutide ... MW 4731.3 ..."},
  "llm": {"enabled": false, "note": "not run (gated)"}
}
''';

/// likely_forged: Janoshik-format COA missing required fields (repurposed form).
const String kFixtureHighRisk = r'''
{
  "filename": "Fake1.png",
  "input_type": "image",
  "authenticity": {
    "score": 25,
    "label": "likely_forged",
    "copy": "Janoshik-format COA is missing required field(s): task number (#), unique verification key. Genuine Janoshik reports always show both a #task number and a unique verification key — absence usually means the field was blurred or removed to repurpose someone else's report.",
    "weight_in_axis": 103.0, "weight_fired": 29.0,
    "fired_rule_ids": ["META-003", "FORG-002", "FORG-007"],
    "passed_rule_ids": ["NUM-002", "NUM-003", "LAB-003"]
  },
  "completeness": {
    "score": 35,
    "label": "minimal_report",
    "copy": "Bare-bones report. Most analytical detail is absent — ask vendor for a complete COA before purchase.",
    "weight_in_axis": 185.0, "weight_fired": 120.0,
    "fired_rule_ids": ["STRUCT-009", "METH-001", "METH-002"],
    "passed_rule_ids": ["STRUCT-001", "STRUCT-004"]
  },
  "summary": {
    "fired_critical_authenticity_rules": ["META-003", "FORG-002", "FORG-007"],
    "rule_counts": {"pass": 18, "fired": 22, "not_applicable": 41, "error": 0},
    "peptide_detected": "Semaglutide",
    "peptide_detect_method": "name",
    "ms_technique_detected": null
  },
  "notes": ["Image input: PDF-metadata rules (META-*) are not evaluable; authenticity score may be lower-confidence."],
  "limitations": [
    "Even a genuine, verifiable COA only proves the specific sample that was tested — not the vial you received. There is no real batch traceability in this market, and vendors can reuse one COA across many vials.",
    "Purity is not safety. Sterility, bacterial endotoxins, heavy metals and residual solvents are usually NOT tested on these COAs, yet they are what cause the worst reactions.",
    "The only way to know what is in your vial is independent testing of that vial (or a community/group test of the same batch)."
  ],
  "hard_checks": {
    "mw_table": {"status": "not_applicable", "reason": "no MW value found in COA text"},
    "known_lab": {"status": "pass", "rule_id": "LAB-009", "entity_id": "janoshik", "entity_kind": "lab", "lab_name": "Janoshik Analytical", "trust": "high"},
    "janoshik": {"status": "fired", "rule_id": "XREF-010", "severity": "critical", "task_number": null, "unique_key": null, "missing_fields": ["task number (#)", "unique verification key"], "message": "Janoshik-format COA is missing required field(s): task number (#), unique verification key. Genuine Janoshik reports always show both a #task number and a unique verification key — absence usually means the field was blurred or removed to repurpose someone else's report."},
    "verifiability": {"status": "deferred_to_janoshik", "rule_id": "XREF-012", "message": "Janoshik COA — verifiability handled by the Janoshik check."},
    "doc_type": {"status": "third_party_lab", "rule_id": "DOC-001", "confidence": "high", "signals": ["issuer is a recognized lab (Janoshik Analytical)"], "message": "Issued by Janoshik Analytical, a recognized independent testing lab — this is third-party analysis."},
    "purity_sanity": {"status": "too_perfect", "rule_id": "FORG-019", "purity": 100.0, "operator": null, "message": "Reported purity (100%) is implausibly perfect — real HPLC of a peptide essentially never reads ≥99.99%/100%, since some impurity is always present. Treat as a soft red flag and verify the actual report."},
    "visual_lab": {"status": "no_match", "rule_id": "XREF-011", "best_distance": 171, "best_distance_pct": 33.4, "message": "Layout does not match any known lab template."},
    "multi_mass": {"status": "pass", "rule_id": "FORG-017"},
    "metadata": {"status": "not_applicable", "reason": "no PDF metadata on image input"},
    "blur_tamper": {"status": "metrics_only", "rule_id": "FORG-016", "word_count": 35, "median_conf": 93.0}
  },
  "rule_results": [
    {"rule_id": "FORG-007", "name": "Localized Pixelation in Specific Data Fields", "category": "forgery_indicators", "weight": 10, "severity": "critical", "status": "fired"},
    {"rule_id": "FORG-002", "name": "Zero Impurity Peaks in Sub-100% Purity Claim", "category": "forgery_indicators", "weight": 9, "severity": "critical", "status": "fired"},
    {"rule_id": "STRUCT-009", "name": "Mass Spectrometry Identity Confirmation Present", "category": "structure", "weight": 9, "severity": "critical", "status": "fired"}
  ],
  "features": {"pages": 1, "has_text_layer": false, "semantic": {"peptide_name_found": "semaglutide", "max_purity": 99.667}, "ocr_text": "Janoshik ... results ... Semaglutide ..."},
  "llm": {"enabled": false, "note": "not run (gated)"}
}
''';

/// HTTP 200 not-a-COA body.
const String kFixtureNotACoa = r'''
{
  "filename": "blank.png",
  "error": "input_not_coa",
  "message": "OCR yielded <100 chars; input is likely not a COA",
  "ocr_chars": 0
}
''';
