"""Tests for assay/mass vs labeled-strength (FORG-018).

Runs standalone (`python -m tests.test_assay_mass` from backend/) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import assay_mass as am  # noqa: E402


def test_underdose_particle_peptides_case():
    # The real forum example: 10 mg label, 8.45 mg assay (~-15.5%).
    r = am.check("Retatrutide 10 mg\nPurity: 99.8%\nAssay: 8.45 mg", "Retatrutide")
    assert r["status"] == "underdosed"
    assert r["labeled_mg"] == 10 and r["measured_mg"] == 8.45
    assert r["deviation_pct"] < -10
    assert r["severity"] == "minor"  # within 25%


def test_severe_underdose_flags_possible_mismatch():
    # 20 mg label, 10 mg assay (-50%) -> severe, hints at reused/mismatched COA.
    r = am.check("Label claim: 20 mg\nAssay: 10 mg", "Tirzepatide")
    assert r["status"] == "underdosed"
    assert r["severity"] == "major"
    assert "mismatch" in r["message"].lower() or "reused" in r["message"].lower()


def test_overfill_is_benign():
    # 30 mg label, net content 33.02 mg (~+10.1%) -> overfilled, informational.
    r = am.check("Retatrutide 30mg\nNet content: 33.02 mg", "Retatrutide")
    assert r["status"] == "overfilled"
    assert r["deviation_pct"] > 10


def test_within_tolerance_passes():
    r = am.check("Retatrutide 20mg\nAssay: 19.88 mg", "Retatrutide")
    assert r["status"] == "pass"


def test_total_mass_with_excipients_is_ignored():
    # "total mass including excipients" must NOT be read as the assay.
    r = am.check("Retatrutide 10mg\nTotal mass (including excipients): 43.6 mg", "Retatrutide")
    assert r["status"] == "not_applicable"
    assert r["measured_mg"] is None


def test_not_applicable_when_no_label():
    r = am.check("Assay: 9.9 mg, purity 99%", None)
    assert r["status"] == "not_applicable"
    assert r["labeled_mg"] is None


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
