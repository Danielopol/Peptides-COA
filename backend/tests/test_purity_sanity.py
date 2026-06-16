"""Tests for the purity plausibility check (FORG-019, advisory).

Runs standalone (`python -m tests.test_purity_sanity`) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import purity_sanity as ps  # noqa: E402


def test_hundred_percent_is_too_perfect():
    r = ps.check("Purity: 100%")
    assert r["status"] == "too_perfect"


def test_four_nines_is_too_perfect():
    r = ps.check("Chromatographic Purity: 99.99%")
    assert r["status"] == "too_perfect"


def test_vague_threshold_flagged():
    r = ps.check("Purity: >99%")
    assert r["status"] == "vague"
    assert r["operator"] == ">"


def test_vague_unicode_gte():
    r = ps.check("HPLC Purity ≥ 99.9%")
    assert r["status"] == "vague"


def test_specific_purity_passes():
    r = ps.check("Purity: 98.62%")
    assert r["status"] == "pass"


def test_specific_high_decimal_passes():
    # The forum's 99.966% example is considered clean/specific, not a flag.
    r = ps.check("Purity: 99.966%")
    assert r["status"] == "pass"


def test_specific_with_gt_but_precise_passes():
    # ">99.87%" has an operator but is precise -> not vague.
    r = ps.check("Purity: >99.87%")
    assert r["status"] == "pass"


def test_no_purity_is_not_applicable():
    r = ps.check("Retatrutide 10mg, mass 12.15 mg")
    assert r["status"] == "not_applicable"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
