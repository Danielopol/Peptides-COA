"""Synthesis — the plain-language verdict that ties the three result categories
together for the user:

  1. Authenticity  — is the DOCUMENT genuine or falsified?
  2. Completeness  — which tests were performed (present/absent)?
  3. Values        — what did the measured results say, and is any value off?

These are orthogonal: a test can be PRESENT (completeness) yet its VALUE
unusable (e.g. purity reported "n/a") — that's a value concern, not a missing
test. This module reads the already-computed checks and emits one structured
object: a short "X because A, B, C" for each category plus a single, evidence-
framed recommendation.

Safety stance: the recommendation NEVER asserts the vial is safe or unsafe — a
document can prove neither. It states what the COA does/doesn't establish and
always anchors on "only independent testing of YOUR vial proves your vial."
"""
from __future__ import annotations

# Completeness sections that matter for the summary (safety-relevant first).
_KEY_SECTIONS = {
    "identity": "identity (MS)",
    "purity": "purity",
    "assay_mass": "measured mass",
    "heavy_metals": "heavy metals",
    "endotoxin": "endotoxin",
    "sterility": "sterility",
}
_CONTAMINANT_SECTIONS = ("heavy_metals", "endotoxin", "sterility")

_AUTH_VERDICT = {
    "likely_authentic": "Authentic",
    "verify_recommended": "Verify recommended",
    "suspicious": "Suspicious",
    "likely_forged": "Likely forged",
}
_COMPLETENESS_VERDICT = {
    "full_report": "Comprehensive",
    "partial_report": "Partial",
    "minimal_report": "Minimal",
    "skeletal": "Skeletal",
}


def _r(text: str, polarity: str) -> dict:
    return {"text": text, "polarity": polarity}  # polarity: pos | neg | neutral


def _authenticity(auth: dict, hc: dict, origin: str) -> dict:
    label = auth.get("label", "")
    reasons: list[dict] = []

    def st(name: str) -> str:
        return (hc.get(name) or {}).get("status", "")

    # --- negatives (forgery / weakness) ---
    if st("mw_table") == "fired":
        reasons.append(_r("Claimed molecular weight/formula doesn't match the named peptide", "neg"))
    if st("visual_lab") == "fired":
        reasons.append(_r("Layout matches one lab's template but the text names a different lab", "neg"))
    if st("verifiability") == "no_verification_path":
        reasons.append(_r("No independent way to verify this COA at the source", "neg"))
    elif st("verifiability") == "redacted":
        reasons.append(_r("A verification field appears blanked out or altered", "neg"))
    if st("blur_tamper") in ("fired", "suspicious"):
        reasons.append(_r("Image shows possible tampering artifacts", "neg"))
    if st("known_lab") == "no_issuer":
        reasons.append(_r("No testing-laboratory name found on the COA", "neg"))
    elif st("known_lab") in ("unrecognized_named", "untrusted"):
        reasons.append(_r("Issuing lab is unrecognized or flagged in our registry", "neg"))
    if st("doc_type") == "manufacturer_qc":
        reasons.append(_r("In-house / manufacturer report — self-reported, weaker evidence", "neg"))
    if st("recency") == "stale":
        reasons.append(_r("COA is stale (older than ~6 months)", "neg"))

    # --- positives ---
    kl = hc.get("known_lab") or {}
    if st("known_lab") == "pass":
        nm = kl.get("lab_name") or kl.get("matched_lab_name") or "a recognized lab"
        reasons.append(_r(f"Issued by a recognized lab ({nm})", "pos"))
    if st("doc_type") == "third_party_lab":
        reasons.append(_r("Independent third-party report", "pos"))
    if st("verifiability") == "verifiable" or st("janoshik") == "pending_user_verification":
        reasons.append(_r("Carries a verification path you can check at the lab", "pos"))
    if st("visual_lab") == "pass":
        reasons.append(_r("Layout matches the lab's known template", "pos"))
    if st("mw_table") == "pass":
        reasons.append(_r("Molecular weight matches the named peptide", "pos"))
    if st("recency") == "pass":
        reasons.append(_r("Recently dated", "pos"))

    return {"verdict": _AUTH_VERDICT.get(label, "Inconclusive"), "label": label,
            "score": auth.get("score"), "reasons": reasons}


def _completeness(comp: dict, checklist: list[dict]) -> dict:
    present_ids = {c["section"] for c in checklist if c.get("present")}
    present = [v for k, v in _KEY_SECTIONS.items() if k in present_ids]
    missing = [v for k, v in _KEY_SECTIONS.items() if k not in present_ids]
    reasons: list[dict] = []
    if present:
        reasons.append(_r("Tested: " + ", ".join(present), "pos"))
    if missing:
        reasons.append(_r("Not tested: " + ", ".join(missing), "neg"))
    no_contaminants = all(s not in present_ids for s in _CONTAMINANT_SECTIONS)
    if no_contaminants:
        reasons.append(_r("No contaminant testing (sterility, endotoxin, heavy metals) — purity is not safety", "neg"))
    return {"verdict": _COMPLETENESS_VERDICT.get(comp.get("label", ""), "Partial"),
            "label": comp.get("label"), "score": comp.get("score"),
            "present": present, "missing": missing, "reasons": reasons}


_GRADE_ASSESS = {
    "pharma grade": "ok", "excellent": "ok", "good": "ok",
    "acceptable": "caution", "marginal": "caution", "below grade": "suspicious",
}


def _values(hc: dict, summary_bits: dict, result_alerts: list[dict]) -> dict:
    entries: list[dict] = []
    # null-result alerts, keyed by category, take precedence (invalid/suspicious)
    alerts_by_cat = {a.get("category"): a for a in (result_alerts or [])}

    def add(label, value, assessment, note):
        entries.append({"label": label, "value": value, "assessment": assessment, "note": note})

    # --- Purity ---
    if "purity" in alerts_by_cat:
        a = alerts_by_cat["purity"]
        add("Purity", a.get("result", "—"),
            "invalid" if a.get("kind") == "not_detected" else "suspicious", a.get("message", ""))
    else:
        ps = hc.get("purity_sanity") or {}
        pv = summary_bits.get("purity_pct")
        if pv is not None:
            grade = summary_bits.get("purity_grade") or ""
            status = ps.get("status")
            if status == "too_perfect":
                assess = "suspicious"
            elif status == "vague":
                assess = "caution"
            else:
                assess = _GRADE_ASSESS.get(grade, "ok")
            val = f"{pv:g}%" + (f" · {grade}" if grade else "")
            add("Purity", val, assess, ps.get("message", "") if assess != "ok" else "")

    # --- Measured mass / assay ---
    if "quantity" in alerts_by_cat:
        a = alerts_by_cat["quantity"]
        add("Measured mass", a.get("result", "—"),
            "invalid" if a.get("kind") == "not_detected" else "suspicious", a.get("message", ""))
    else:
        am = hc.get("assay_mass") or {}
        measured, labeled = am.get("measured_mg"), am.get("labeled_mg")
        if measured is not None and labeled is not None:
            status = am.get("status")
            assess = {"underdosed": "suspicious", "overfilled": "caution"}.get(status, "ok")
            add("Measured mass", f"{measured:g} / {labeled:g} mg", assess,
                am.get("message", "") if assess != "ok" else "")

    # --- Molecular weight identity ---
    mw = hc.get("mw_table") or {}
    if mw.get("status") == "fired":
        add("Molecular weight", "mismatch", "suspicious", mw.get("message", ""))
    elif mw.get("status") == "pass":
        add("Molecular weight", "matches expected", "ok", "")

    # any remaining alert category not mapped above
    for cat, a in alerts_by_cat.items():
        if cat not in ("purity", "quantity") and not any(e["label"].lower().startswith(cat) for e in entries):
            add(a.get("analysis") or cat, a.get("result", "—"),
                "invalid" if a.get("kind") == "not_detected" else "suspicious", a.get("message", ""))

    order = {"invalid": 0, "suspicious": 1, "caution": 2, "ok": 3}
    entries.sort(key=lambda e: order.get(e["assessment"], 4))

    if not entries:
        verdict = "No quantitative values reported"
    elif any(e["assessment"] in ("invalid", "suspicious") for e in entries):
        verdict = "Concerns"
    elif any(e["assessment"] == "caution" for e in entries):
        verdict = "Some caution"
    else:
        verdict = "Consistent"
    reasons = [_r(f"{e['label']}: {e['value']}", "neg") for e in entries
               if e["assessment"] in ("invalid", "suspicious")]
    return {"verdict": verdict, "entries": entries, "reasons": reasons}


def _recommendation(authenticity: dict, completeness: dict, values: dict, origin: str) -> dict:
    """Evidence-framed. `origin` ∈ {'vendor','self'} changes the actual ADVICE,
    not just who to ask: a vendor COA is third-party paperwork to be verified and
    cross-checked against your vial; a self-commissioned test is your OWN result —
    its findings are the truth about the sample you submitted, so the advice is
    about what to do with the product, not re-testing or asking for a 'valid' one.
    Never asserts the vial is safe/unsafe."""
    self_ = origin == "self"
    label = authenticity.get("label")
    has_invalid = any(e["assessment"] == "invalid" for e in values["entries"])
    has_suspicious = any(e["assessment"] == "suspicious" for e in values["entries"])
    no_contaminants = all(s not in completeness["present"] for s in
                          ("heavy metals", "endotoxin", "sterility"))
    # The vendor anchor closes the document↔your-vial gap; for a self test you
    # already closed it — the result covers the sample you submitted.
    anchor = ("This result reflects the specific sample you submitted to the lab; "
              "store the rest of the vial accordingly."
              if self_ else
              "No document proves what's in your specific vial — only independent "
              "testing of that vial (or a community test of the same batch) can.")

    forged = label in ("suspicious", "likely_forged") or authenticity["verdict"] == "Likely forged"
    if forged:
        if self_:
            return {"level": "critical",
                    "headline": "This document shows forgery indicators — unexpected for a test you commissioned.",
                    "detail": "If you ordered this yourself, the file you scanned may be altered or "
                              "not the lab's original copy. " + anchor,
                    "actions": ["Re-download the report directly from the lab's portal and rescan",
                                "Confirm the result with the lab directly"]}
        return {"level": "critical",
                "headline": "Treat this COA as unreliable evidence.",
                "detail": "The document itself shows forgery or strong red-flag indicators, so "
                          "nothing it reports can be trusted at face value. " + anchor,
                "actions": ["Don't rely on this COA",
                            "Ask the vendor for a verifiable third-party report",
                            "Have your vial independently tested"]}
    if has_invalid:
        if self_:
            return {"level": "critical",
                    "headline": "Your own test found no measurable product in this vial.",
                    "detail": "The result is valid — the problem is the product, not the document. "
                              "Treat this vial as failed. " + anchor,
                    "actions": ["Don't use this vial",
                                "Seek a refund or replacement from the seller"]}
        return {"level": "critical",
                "headline": "The document looks genuine, but it reports no measurable product.",
                "detail": "An authentic report can still describe an empty or failed sample. "
                          "This is a result, not a forgery — and it's a serious one. " + anchor,
                "actions": ["Ask the vendor for a valid, in-spec report for this batch",
                            "Have your vial independently tested before any use"]}
    if has_suspicious:
        if self_:
            return {"level": "caution",
                    "headline": "Your test flags a measured value.",
                    "detail": "This is your own lab's report, so the measurement stands — a "
                              "reported value is off (see Values). " + anchor,
                    "actions": ["Confirm the flagged value with the lab if it looks like an error",
                                "Factor it into how you treat this vial"]}
        return {"level": "caution",
                "headline": "Genuine-looking, but a measured value is concerning.",
                "detail": "The document checks out, yet a reported value is off (see Values). " + anchor,
                "actions": ["Ask the vendor to clarify the flagged value",
                            "Consider independent testing of your vial"]}
    if no_contaminants:
        if self_:
            return {"level": "caution",
                    "headline": "Your test is genuine but limited in scope.",
                    "detail": "Purity is not safety: sterility, endotoxin and heavy-metals testing "
                              "weren't part of this report, and those are what cause the worst reactions. " + anchor,
                    "actions": ["Consider commissioning contaminant testing (sterility, endotoxin, metals)"]}
        return {"level": "caution",
                "headline": "Genuine and consistent, but the testing is limited.",
                "detail": "Purity is not safety: sterility, endotoxin and heavy-metals testing "
                          "weren't done, and those are what cause the worst reactions. " + anchor,
                "actions": ["Ask the vendor for a fuller report (contaminant testing)",
                            "Consider independent testing of your vial"]}
    if self_:
        return {"level": "ok",
                "headline": "Your own independent test is strong across the board.",
                "detail": "About as good as documentary evidence gets. " + anchor,
                "actions": ["Keep this report with the batch for reference"]}
    return {"level": "ok",
            "headline": "Strong across authenticity, completeness and values.",
            "detail": "Still verify the COA at the lab's site if it offers one. " + anchor,
            "actions": ["Verify the COA at the lab's site",
                        "Remember: only testing your vial proves your vial"]}


def build(*, authenticity: dict, completeness: dict, checklist: list[dict],
          hard_checks: dict, summary_bits: dict, result_alerts: list[dict],
          origin: str = "vendor") -> dict:
    a = _authenticity(authenticity, hard_checks, origin)
    c = _completeness(completeness, checklist)
    v = _values(hard_checks, summary_bits, result_alerts)
    rec = _recommendation(a, c, v, origin)
    return {"authenticity": a, "completeness": c, "values": v,
            "recommendation": rec, "origin": origin}
