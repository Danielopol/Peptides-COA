"""Tests for the completeness checklist (informational).

Runs standalone (`python -m tests.test_completeness_checklist`) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import completeness_checklist as cc  # noqa: E402


def _by_section(items):
    return {i["section"]: i["present"] for i in items}


def test_detects_sections_from_text():
    text = (
        "Certificate of Analysis. Purity 99.2% by HPLC. Heavy metals: arsenic, lead ND. "
        "Endotoxin 1.86 EU/mg. Sterility: pass. Residual solvents: TFA <0.5%. "
        "Batch number: RT10426. ISO/IEC 17025 accredited."
    )
    got = _by_section(cc.build(text, {}))
    for sec in ("purity", "heavy_metals", "endotoxin", "sterility",
                "residual_solvents", "batch_lot", "accreditation"):
        assert got[sec] is True, sec


def test_detects_impurity_and_water_sections():
    text = ("Related substances: Impurity A 0.05%, Unknown 0.02%. "
            "Water content (Karl Fischer): 3.1%.")
    got = _by_section(cc.build(text, {}))
    assert got["impurity_profile"] is True
    assert got["water_content"] is True


def test_impurity_and_water_absent_on_minimal():
    got = _by_section(cc.build("Retatrutide 10mg. Purity 99%.", {}))
    assert got["impurity_profile"] is False
    assert got["water_content"] is False


def test_minimal_coa_mostly_absent():
    got = _by_section(cc.build("Retatrutide 10mg. Looks fine.", {}))
    assert got["heavy_metals"] is False
    assert got["endotoxin"] is False
    assert got["sterility"] is False


def test_reuses_hard_check_signals():
    hc = {
        "assay_mass": {"status": "underdosed", "labeled_mg": 10.0, "measured_mg": 8.45},
        "verifiability": {"status": "verifiable"},
        "recency": {"status": "stale"},
        "purity_sanity": {"status": "too_perfect"},
    }
    got = _by_section(cc.build("no obvious keywords here", hc, ms_technique="ESI-MS"))
    assert got["assay_mass"] is True       # from assay_mass labeled/measured
    assert got["verification"] is True     # from verifiability
    assert got["test_date"] is True        # from recency
    assert got["purity"] is True           # from purity_sanity
    assert got["identity"] is True         # from ms_technique


def test_every_item_has_shape():
    items = cc.build("Purity 99%", {})
    assert len(items) == 14
    for it in items:
        assert set(it.keys()) == {"section", "label", "present"}
        assert isinstance(it["present"], bool)


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
