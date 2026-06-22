"""Analytical-method coverage (informational).

The community/BatchGuild guidance: multiple analytical methods cross-verify each
other (e.g. HPLC for purity + LC-MS for identity), so a single method is weaker
("easier to fake / no cross-check") and no named method is a red flag. This is
ADVISORY — single-method testing is extremely common on legitimate COAs
(plenty are HPLC-UV only), so it never changes the authenticity score; it just
surfaces a caution finding.

Statuses: multi | single | none.
"""
from __future__ import annotations
import re

RULE_ID = "METH-013"

_FAMILIES = {
    "HPLC": re.compile(
        r"hplc|uplc|u-?hplc|rp-?hplc|\bpda\d*\b|\bmau\b|\bdad\d*\b|diode\s*array|chromatogram|"
        r"retention\s*time|c-?18|reversed[\s-]?phase",
        re.I,
    ),
    "MS": re.compile(
        # Short tokens are boundary-anchored so "esi" can't match inside "design".
        r"\bms\b|mass\s*spec|\blc-?ms\b|\bgc-?ms\b|\besi\b|\bmaldi\b|\bq-?tof\b|"
        r"\borbitrap\b|triple\s*quad|\bm/?z\b",
        re.I,
    ),
    "NMR": re.compile(r"\bnmr\b|nuclear\s+magnetic", re.I),
    "FTIR": re.compile(r"\bftir\b|infrared\s+spectro", re.I),
}


def check(ocr_text: str, ms_technique: str | None = None) -> dict:
    text = ocr_text or ""
    families = [name for name, rx in _FAMILIES.items() if rx.search(text)]
    if ms_technique and "MS" not in families:
        families.append("MS")

    if len(families) >= 2:
        return {
            "status": "multi", "rule_id": RULE_ID, "families": families,
            "message": (
                f"Multiple analytical methods used ({', '.join(families)}) — the results "
                "cross-verify each other, which is stronger than a single method."
            ),
        }
    if len(families) == 1:
        return {
            "status": "single", "rule_id": RULE_ID, "severity": "minor", "families": families,
            "message": (
                f"Only one analytical method detected ({families[0]}). Cross-verified "
                "testing (e.g. HPLC purity + LC-MS identity) is stronger; a single method "
                "can't confirm identity independently and is easier to fake. Common on "
                "real COAs, but ask for MS identity confirmation if it matters."
            ),
        }
    # No method detected. Don't surface this as a finding: on table-heavy COAs the
    # OCR often drops the method column even though a method IS named, so a "no
    # method" flag would false-positive. (not_applicable -> hidden from findings.)
    return {
        "status": "not_applicable", "rule_id": RULE_ID, "families": [],
        "reason": "no analytical method detected in the extracted text (may be an OCR miss)",
    }
