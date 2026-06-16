"""Tests for robust semantic enrichment of completeness presence-signals.

Runs standalone (`python -m tests.test_semantic_enrich`) or under pytest.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import semantic_enrich as se  # noqa: E402

# Trimmed OCR of the real Freedom BPC-157 COA (no "Batch:"/"HPLC"/"MS" labels).
FREEDOM = """FREEDOM DIAGNOSTICS
Searchable via: FreedomDiagnosticsTesting.com
BPC-157 10mg   11.52 mg
Certificate of Analysis
Titan Peptides Research
A2601B10
99.693%
White Lyophilized Powder
Mass Identification
mAU  1 PDA Multi 1   750 1000 1250 mz
"""


def test_detect_batch_standalone_code():
    assert se.detect_batch(FREEDOM) == "A2601B10"


def test_detect_batch_labeled():
    assert se.detect_batch("Batch Number: RT10426") == "RT10426"


def test_detect_batch_none_when_absent():
    assert se.detect_batch("Purity 99% white powder") is None


def test_detect_batch_inline_token():
    # Lot code sitting inline on a product line (Freedom style).
    assert se.detect_batch("Melanotan I 10mg A2601MT1\n11.29 mg 99.711%") == "A2601MT1"


def test_detect_client_company_name():
    txt = "2603230149\nTitan Peptides Research\nFREEDOM\nDIAGNOSTICS 03/23/2026"
    assert se.detect_client(txt) == "Titan Peptides Research"


def test_detect_client_excludes_issuing_lab():
    assert se.detect_client("Freedom Diagnostics Testing\nCertificate of Analysis") is None


def test_detect_client_none_on_boilerplate():
    assert se.detect_client("White Lyophilized Powder\nMass Identification") is None


def test_enrich_sets_ms_from_mass_identification_and_mz():
    sem = se.enrich({"has_ms": False}, FREEDOM)
    assert sem["has_ms"] is True


def test_enrich_sets_hplc_from_pda_chromatogram():
    sem = se.enrich({"has_hplc": False}, FREEDOM)
    assert sem["has_hplc"] is True


def test_enrich_is_monotonic_and_fills_batch():
    sem = se.enrich({"batch": None, "has_ms": False}, FREEDOM)
    assert sem["batch"] == "A2601B10"


def test_enrich_never_clears_existing():
    sem = se.enrich({"batch": "X1", "has_ms": True, "has_hplc": True,
                     "peptide_name_found": "bpc-157"}, "no cues here")
    assert sem["batch"] == "X1" and sem["has_ms"] is True and sem["has_hplc"] is True
    assert sem["peptide_name_found"] == "bpc-157"


def test_fuzzy_peptide_name_handles_ocr_slip():
    # 'Turzepatide' (1-char OCR error) should still resolve to tirzepatide.
    assert se.detect_peptide_name("Turzepatide 10mg") == "tirzepatide"


def test_fuzzy_peptide_name_rejects_non_peptide_words():
    assert se.detect_peptide_name("White Lyophilized Powder certificate") is None


def test_enrich_fills_product_name_when_missing():
    sem = se.enrich({}, "Turzepatide 10mg  GLP TZ 99.878%")
    assert sem.get("peptide_name_found") == "tirzepatide"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
