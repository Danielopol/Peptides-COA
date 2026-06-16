"""Integration test for the vision completeness presence-audit.

The LLM call is stubbed (no network/key). Verifies that a confirmed field with a
real value flips fired->pass and raises completeness, while a confirmation with
an empty value is rejected (the monotonic value-grounding guardrail).

Runs standalone (`python -m tests.test_llm_completeness_audit`) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import llm_client, scan  # noqa: E402

COA = Path("/mnt/d/DIRECTORY/Peptides/COAs/Freedom Diagnostic/"
           "Melanotan-II_10mg_COA_Batch-A2601MT1.pdf")


def _run_with_stubbed_audit(audit_fields: dict) -> dict:
    orig_enabled, orig_audit, orig_assess, orig_results = (
        llm_client.llm_enabled, llm_client.audit_completeness,
        llm_client.assess, llm_client.read_results,
    )
    llm_client.llm_enabled = lambda: True
    llm_client.audit_completeness = lambda ocr_text, png, fields: {
        "enabled": True, "model": "stub",
        "fields": {k: v for k, v in audit_fields.items() if k in fields},
    }
    # strong_authentic (recognized Freedom + verifiable) means assess() is skipped,
    # but stub it too so the test never reaches the network on any path.
    llm_client.assess = lambda **kw: {"enabled": True, "verdict": "authentic", "confidence": 1.0}
    # The null-result vision reader is also gated behind llm_enabled — stub it so
    # this audit-focused test never hits the network (no result alerts expected).
    llm_client.read_results = lambda ocr_text, png: {"enabled": True, "results": []}
    try:
        return scan.run_scan(COA.read_bytes(), COA.name)
    finally:
        llm_client.llm_enabled = orig_enabled
        llm_client.audit_completeness = orig_audit
        llm_client.assess = orig_assess
        llm_client.read_results = orig_results


def _status(out: dict, rid: str) -> str:
    return next(r["status"] for r in out["rule_results"] if r["rule_id"] == rid)


def test_confirmed_field_flips_and_raises_completeness():
    if not COA.exists():
        print("SKIP (fixture COA missing)"); return
    baseline = scan.run_scan(COA.read_bytes(), COA.name)  # LLM disabled in this env
    base_compl = baseline["completeness"]["score"]
    assert _status(baseline, "STRUCT-007") == "fired"

    out = _run_with_stubbed_audit({
        "STRUCT-007": {"present": True, "value": "Alex Johnson"},   # valid -> flip
        "STRUCT-005": {"present": True, "value": ""},               # empty -> rejected
    })
    assert "STRUCT-007" in out["llm_completeness"]["confirmed_rule_ids"]
    assert _status(out, "STRUCT-007") == "pass"
    r7 = next(r for r in out["rule_results"] if r["rule_id"] == "STRUCT-007")
    assert r7.get("confirmed_by") == "visual" and "Alex Johnson" in r7.get("visual_value", "")
    # empty-value confirmation must NOT flip
    assert "STRUCT-005" not in out["llm_completeness"]["confirmed_rule_ids"]
    assert out["completeness"]["score"] >= base_compl


JANO = Path("/mnt/d/DIRECTORY/Peptides/COAs/Janoshik_Tests/#69929_Retatrutide_10mg.pdf")


def test_confirmed_rule_syncs_checklist_section():
    """A confirmed purity (STRUCT-008, OCR missed it) must light up the
    user-facing 'purity' checklist item, not just raise the score."""
    if not JANO.exists():
        print("SKIP (fixture COA missing)"); return
    orig = (llm_client.llm_enabled, llm_client.audit_completeness, llm_client.assess)
    llm_client.llm_enabled = lambda: True
    llm_client.audit_completeness = lambda ocr_text, png, fields: {
        "enabled": True, "model": "stub",
        "fields": {"STRUCT-008": {"present": True, "value": "99.856%"}} if "STRUCT-008" in fields else {},
    }
    llm_client.assess = lambda **kw: {"enabled": True, "verdict": "authentic", "confidence": 1.0}
    try:
        out = scan.run_scan(JANO.read_bytes(), JANO.name)
    finally:
        llm_client.llm_enabled, llm_client.audit_completeness, llm_client.assess = orig
    purity = next(i for i in out["completeness"]["checklist"] if i["section"] == "purity")
    assert purity["present"] is True and purity.get("confirmed_by") == "visual"
    assert _status(out, "STRUCT-008") == "pass"


def test_norule_section_confirmed_updates_checklist_only():
    """A no-rule section (vial photo, on Janoshik page 2) confirmed by the audit
    lights up the checklist via confirmed_sections, without needing a rule."""
    if not JANO.exists():
        print("SKIP (fixture COA missing)"); return
    orig = (llm_client.llm_enabled, llm_client.audit_completeness, llm_client.assess,
            llm_client.read_results)
    llm_client.llm_enabled = lambda: True
    llm_client.audit_completeness = lambda ocr_text, pngs, fields: {
        "enabled": True, "model": "stub",
        "fields": {"vial_photo": {"present": True, "value": "photo of the vial"}} if "vial_photo" in fields else {},
    }
    llm_client.assess = lambda **kw: {"enabled": True, "verdict": "authentic", "confidence": 1.0}
    llm_client.read_results = lambda ocr_text, pngs: {"enabled": True, "results": []}
    try:
        out = scan.run_scan(JANO.read_bytes(), JANO.name)
    finally:
        (llm_client.llm_enabled, llm_client.audit_completeness, llm_client.assess,
         llm_client.read_results) = orig
    vp = next(i for i in out["completeness"]["checklist"] if i["section"] == "vial_photo")
    assert vp["present"] is True and vp.get("confirmed_by") == "visual"
    assert "vial_photo" in out["llm_completeness"]["confirmed_sections"]


def test_hallucinated_present_without_value_is_ignored():
    if not COA.exists():
        print("SKIP (fixture COA missing)"); return
    out = _run_with_stubbed_audit({"STRUCT-007": {"present": True, "value": "N/A"}})
    assert out["llm_completeness"]["confirmed_rule_ids"] == []
    assert _status(out, "STRUCT-007") == "fired"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
