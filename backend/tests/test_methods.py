"""Tests for analytical-method coverage (METH-013) and purity grading."""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import methods, purity_sanity  # noqa: E402


def test_multi_method():
    r = methods.check("Purity by HPLC-UV. Identity confirmed by LC-MS (ESI).")
    assert r["status"] == "multi"
    assert set(r["families"]) >= {"HPLC", "MS"}


def test_single_method():
    r = methods.check("Chromatographic Purity: HPLC-UV/VIS 99.0%. Quantity HPLC-UV/VIS.")
    assert r["status"] == "single"
    assert r["families"] == ["HPLC"]


def test_no_method_is_not_applicable():
    # No method detected -> not_applicable (hidden), to avoid false "no method"
    # flags when OCR drops a method table.
    r = methods.check("Retatrutide 10mg. Purity 99%. White powder.")
    assert r["status"] == "not_applicable"


def test_dad_detector_counts_as_hplc():
    r = methods.check("DAD1 A, Sig=214 Ref=off")  # diode-array detector = HPLC
    assert r["status"] == "single" and r["families"] == ["HPLC"]


def test_ms_technique_counts_as_ms():
    r = methods.check("HPLC purity 99%", ms_technique="ESI-MS")
    assert r["status"] == "multi"


def test_purity_grade_bands():
    assert purity_sanity.grade(99.95) == "pharma grade"
    assert purity_sanity.grade(99.5) == "excellent"
    assert purity_sanity.grade(98.5) == "good"
    assert purity_sanity.grade(96.0) == "acceptable"
    assert purity_sanity.grade(92.0) == "marginal"
    assert purity_sanity.grade(85.0) == "below grade"
    assert purity_sanity.grade(None) is None


def test_check_includes_grade():
    r = purity_sanity.check("Purity: 99.05%")
    assert r["grade"] == "excellent" and r["purity"] == 99.05


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
