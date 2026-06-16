"""Unit tests for the synthesis verdict (authenticity / completeness / values
+ evidence-framed recommendation)."""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import synthesis  # noqa: E402

_FULL_CHECKLIST = [
    {"section": s, "present": True}
    for s in ("identity", "purity", "assay_mass", "heavy_metals", "endotoxin", "sterility")
]


def _build(*, label="likely_authentic", score=90, comp_label="full_report",
           checklist=None, hard_checks=None, summary_bits=None, alerts=None, origin="vendor"):
    return synthesis.build(
        authenticity={"score": score, "label": label},
        completeness={"score": 80, "label": comp_label},
        checklist=checklist if checklist is not None else _FULL_CHECKLIST,
        hard_checks=hard_checks or {},
        summary_bits=summary_bits or {},
        result_alerts=alerts or [],
        origin=origin,
    )


def test_forged_doc_is_unreliable_critical():
    s = _build(label="likely_forged", score=22,
               hard_checks={"mw_table": {"status": "fired", "message": "MW mismatch"}})
    assert s["recommendation"]["level"] == "critical"
    assert "unreliable" in s["recommendation"]["headline"].lower()
    assert any(r["polarity"] == "neg" for r in s["authenticity"]["reasons"])


def test_authentic_but_not_detected_is_critical_empty_product():
    alerts = [
        {"category": "quantity", "kind": "not_detected", "result": "Not Detected",
         "severity": "critical", "message": "no measurable amount"},
        {"category": "purity", "kind": "not_applicable", "result": "n/a",
         "severity": "warning", "message": "no purity determined"},
    ]
    s = _build(label="likely_authentic", score=95, alerts=alerts)
    assert s["recommendation"]["level"] == "critical"
    assert "no measurable product" in s["recommendation"]["headline"].lower()
    vals = {e["label"]: e["assessment"] for e in s["values"]["entries"]}
    assert vals["Measured mass"] == "invalid"
    assert vals["Purity"] == "suspicious"
    assert s["values"]["verdict"] == "Concerns"


def test_too_perfect_purity_is_suspicious_value():
    s = _build(summary_bits={"purity_pct": 100.0, "purity_grade": "implausible"},
               hard_checks={"purity_sanity": {"status": "too_perfect", "message": "implausibly perfect"}})
    assert any(e["assessment"] == "suspicious" and e["label"] == "Purity"
               for e in s["values"]["entries"])
    assert s["recommendation"]["level"] == "caution"
    assert "concerning" in s["recommendation"]["headline"].lower()


def test_authentic_complete_consistent_is_ok_but_anchored():
    s = _build(summary_bits={"purity_pct": 98.6, "purity_grade": "excellent"},
               hard_checks={"assay_mass": {"status": "pass", "measured_mg": 5.0, "labeled_mg": 5.0},
                            "mw_table": {"status": "pass"}})
    assert s["recommendation"]["level"] == "ok"
    assert s["values"]["verdict"] == "Consistent"
    # the safety anchor is always present
    assert "only" in s["recommendation"]["detail"].lower()


def test_incomplete_no_contaminants_is_caution():
    checklist = [{"section": s, "present": s in ("identity", "purity", "assay_mass")}
                 for s in ("identity", "purity", "assay_mass", "heavy_metals", "endotoxin", "sterility")]
    s = _build(comp_label="partial_report", checklist=checklist,
               summary_bits={"purity_pct": 99.0, "purity_grade": "excellent"},
               hard_checks={"assay_mass": {"status": "pass", "measured_mg": 5.0, "labeled_mg": 5.0}})
    assert s["recommendation"]["level"] == "caution"
    assert "limited" in s["recommendation"]["headline"].lower()


def test_self_tested_not_detected_changes_advice_not_just_wording():
    # A self-commissioned test reporting "Not Detected" is a VALID result about
    # an empty product — not a reason to re-test or ask for a 'valid' report.
    alerts = [{"category": "quantity", "kind": "not_detected", "result": "Not Detected",
               "severity": "critical", "message": "x"}]
    vendor = _build(alerts=alerts, origin="vendor")
    self_ = _build(alerts=alerts, origin="self")
    v_actions = " ".join(vendor["recommendation"]["actions"]).lower()
    s_actions = " ".join(self_["recommendation"]["actions"]).lower()
    # vendor: ask the vendor + independently test
    assert "vendor" in v_actions and "independently test" in v_actions
    # self: NOT 'ask for a valid report' and NOT 're-test' (already done); it's
    # about the product (don't use / refund)
    assert "valid" not in s_actions and "independently test" not in s_actions
    assert "don't use this vial" in s_actions or "refund" in s_actions
    assert "your own test" in self_["recommendation"]["headline"].lower()


def test_self_tested_strong_is_self_framed():
    s = _build(origin="self",
               summary_bits={"purity_pct": 98.6, "purity_grade": "excellent"},
               hard_checks={"assay_mass": {"status": "pass", "measured_mg": 5.0, "labeled_mg": 5.0},
                            "mw_table": {"status": "pass"}})
    assert "your own independent test" in s["recommendation"]["headline"].lower()
    assert not any("vendor" in a.lower() for a in s["recommendation"]["actions"])


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn(); print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
