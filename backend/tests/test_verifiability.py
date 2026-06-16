"""Tests for the generalized verifiability check (XREF-012).

Runs standalone (`python -m tests.test_verifiability` from backend/) or under
pytest if installed. No external fixtures — pure text inputs.
"""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import verifiability as v  # noqa: E402


def test_no_verification_path():
    r = v.check("Retatrutide 10mg purity 99.8% HPLC results, lyophilized powder")
    assert r["status"] == "no_verification_path"
    assert r["severity"] == "major"


def test_verify_url_in_document():
    r = v.check("Verify this report at https://acme-labs.com/verify report id AB12CD34")
    assert r["status"] == "verifiable"
    assert r["verification_url"].startswith("http")
    assert r["via"] == "document"


def test_known_lab_portal():
    known = {
        "lab_name": "TrustPointe Analytics",
        "verification": {"url": "https://coa.trustpointeanalytics.com"},
    }
    r = v.check("Certificate of Analysis — purity 99.2%", known)
    assert r["status"] == "verifiable"
    assert r["via"] == "registry_lab"
    assert "trustpointe" in r["verification_url"].lower()


def test_redacted_when_code_missing():
    r = v.check("Verify this report — unique key: ______   (scan the qr code)")
    assert r["status"] == "redacted"


def test_generic_id_labels_are_not_redacted():
    # A plain COA with a report/sample number but NO verification mechanism must
    # be 'no_verification_path', not 'redacted' (generic IDs aren't verify codes).
    r = v.check("Certificate of Analysis\nReport Number: 12345\nSample ID: 9\nPurity 99%")
    assert r["status"] == "no_verification_path"


def test_janoshik_is_deferred():
    r = v.check("Janoshik Analytical  Task Number #12345  unique key ABCD1234WXYZ")
    assert r["status"] == "deferred_to_janoshik"


def test_qr_with_code_is_verifiable():
    r = v.check("Scan the QR code to verify.  Report Number: RT10426X")
    assert r["status"] == "verifiable"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
