"""Tests for the molecular-formula cross-check inside mw_table (XREF-009).

Runs standalone (`python -m tests.test_mw_formula` from backend/) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import mw_table as mw  # noqa: E402


def test_copper_formula_on_retatrutide_fires():
    # The forum case: a Retatrutide COA carrying a copper-containing formula.
    text = "Retatrutide 10mg\nMolecular Formula: C28H48CuN12O8\nPurity 99.6%"
    r = mw.check("Retatrutide", text)
    assert r["status"] == "fired"
    assert r["mismatch_kind"] == "formula"
    assert "Cu" in "".join(r["message"]) or "copper" in r["message"].lower()


def test_unicode_subscripts_are_handled():
    text = "Retatrutide 10mg\nMolecular Formula: C₂₈H₄₈CuN₁₂O₈"
    r = mw.check("Retatrutide", text)
    assert r["status"] == "fired"
    assert r["mismatch_kind"] == "formula"


def test_exact_other_compound_formula_fires():
    # BPC-157 COA stating Semaglutide's exact formula.
    text = "BPC-157\nMolecular Formula: C187H291N45O59"
    r = mw.check("BPC-157", text)
    assert r["status"] == "fired"
    assert r.get("matches_compound", "").lower() == "semaglutide" or r["mismatch_kind"] == "formula"


def test_correct_formula_passes_formula_check():
    # Correct Retatrutide formula + a matching MW -> overall pass, formula match.
    text = "Retatrutide 10mg\nMolecular Formula: C221H342N46O68\nMolecular Weight: 4731.33 g/mol"
    r = mw.check("Retatrutide", text)
    assert r["status"] == "pass"
    assert r["formula_status"] == "match"


def test_ghk_cu_with_copper_is_fine():
    # GHK-Cu legitimately contains copper -> no metal mismatch.
    text = "GHK-Cu\nMolecular Formula: C14H21CuN6O4\nMolecular Weight: 400.9"
    r = mw.check("GHK-Cu", text)
    assert r["status"] != "fired"


def test_ocr_garbage_formula_does_not_fire():
    # Unknown elements -> treated as noise, not a forgery flag.
    text = "Retatrutide 10mg\nMolecular Formula: Xz99Qq12\nMolecular Weight: 4731.33"
    r = mw.check("Retatrutide", text)
    assert r["status"] != "fired"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
