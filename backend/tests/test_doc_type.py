"""Tests for document-type classification (DOC-001).

Runs standalone (`python -m tests.test_doc_type` from backend/) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import doc_type as dt  # noqa: E402

# The Retatrutide example from the forum: a storage/stability block is the tell.
_STORAGE_COA = """Certificate of Analysis
Product: Retatrutide 10mg
Purity: 99.68%
Storage / Stability (Powder & In Solvent)
Powder: 20°C: 36 months, 4°C: 24 months
In Solvent: -80°C: 6 months, -2°C: 30 days
"""


def test_storage_block_is_manufacturer_qc():
    r = dt.classify(_STORAGE_COA)
    assert r["status"] == "manufacturer_qc"
    assert any("storage" in s for s in r["signals"])


def test_recognized_lab_is_third_party():
    known = {"status": "pass", "entity_kind": "lab", "lab_name": "Janoshik Analytical"}
    r = dt.classify("Certificate of Analysis, HPLC purity 99.2%", known)
    assert r["status"] == "third_party_lab"
    assert r["confidence"] == "high"


def test_recognized_lab_with_storage_still_third_party_but_notes_it():
    known = {"status": "pass", "entity_kind": "lab", "lab_name": "Janoshik Analytical"}
    r = dt.classify(_STORAGE_COA, known)
    assert r["status"] == "third_party_lab"
    assert "unusual" in r["message"].lower()


def test_vendor_issuer_is_manufacturer_qc():
    known = {"status": "pass", "entity_kind": "vendor", "lab_name": "SomeVendor"}
    r = dt.classify("Certificate of Analysis", known)
    assert r["status"] == "manufacturer_qc"


def test_manufacturer_language():
    r = dt.classify("Manufactured by ACME Bio. Production date 2026-01-01. Batch release approved.")
    assert r["status"] == "manufacturer_qc"


def test_third_party_claim_without_recognized_lab():
    r = dt.classify("This product was tested by an independent third-party laboratory.")
    assert r["status"] == "third_party_lab"
    assert r["confidence"] == "low"


def test_unknown_when_no_signal():
    r = dt.classify("Retatrutide 10mg. Purity 99.8%. HPLC chromatogram attached.")
    assert r["status"] == "unknown"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
