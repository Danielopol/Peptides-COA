"""Purity plausibility check (rule FORG-019, advisory).

Two soft tells the community calls out about the purity figure itself:
  - "too perfect": a purity of 100% / ≥99.99% is implausible for real HPLC of a
    peptide — genuine results show some impurity.
  - "vague": purity stated only as a bare threshold like ">99%" or "≥99.9%" with
    no exact measured value ("the fact there is no specific percent is weird").

This is a WEAK discriminator, so it is ADVISORY: it surfaces a caution finding
but does NOT change the authenticity score (see scan.py — no override is applied
until this is calibrated against the corpus, mirroring blur_tamper's treatment).

It is complementary to FORG-002 (zero impurity *peaks* in a sub-100% claim):
that inspects the chromatogram; this inspects the stated purity *value*.

Statuses: pass | vague | too_perfect | not_applicable.
"""
from __future__ import annotations
import re

RULE_ID = "FORG-019"

_PURITY_RE = re.compile(
    r"(?:chromatographic\s+|hplc\s+)?purit(?:y|ies)\s*[:=]?\s*"
    r"(?P<op>>=|<=|>|<|≥|≤)?\s*"
    r"(?P<val>\d{1,3}(?:\.\d{1,4})?)\s*%",
    re.I,
)
_GTE_OPS = {">", ">=", "≥"}


def grade(purity: float | None) -> str | None:
    """Community/industry purity-grade band for a purity %, e.g. 99.05 -> 'good'.
    (BatchGuild bands: 90-95 marginal, 95-98 acceptable, 98-99 good, 99-99.9
    excellent, 99.9+ pharma; <90 below grade.)"""
    if purity is None:
        return None
    if purity < 90:
        return "below grade"
    if purity < 95:
        return "marginal"
    if purity < 98:
        return "acceptable"
    if purity < 99:
        return "good"
    if purity < 99.9:
        return "excellent"
    return "pharma grade"


def check(ocr_text: str) -> dict:
    m = _PURITY_RE.search(ocr_text or "")
    if not m:
        return {"status": "not_applicable", "rule_id": RULE_ID, "reason": "no purity value found"}

    val_str = m.group("val")
    op = (m.group("op") or "").strip()
    try:
        val = float(val_str)
    except ValueError:
        return {"status": "not_applicable", "rule_id": RULE_ID, "reason": "unparseable purity"}

    if val > 100.5:  # parse noise, not a real purity
        return {"status": "not_applicable", "rule_id": RULE_ID, "reason": "implausible purity value"}

    decimals = len(val_str.split(".")[1]) if "." in val_str else 0
    base = {"rule_id": RULE_ID, "purity": val, "operator": op or None, "grade": grade(val)}

    if val >= 99.99:
        return {
            **base, "status": "too_perfect", "severity": "minor",
            "message": (
                f"Reported purity ({val_str}%) is implausibly perfect — real HPLC of a "
                "peptide essentially never reads ≥99.99%/100%, since some impurity is "
                "always present. Treat as a soft red flag and verify the actual report."
            ),
        }

    if op in _GTE_OPS and decimals <= 1 and val >= 90:
        return {
            **base, "status": "vague", "severity": "minor",
            "message": (
                f"Purity is given only as '{op}{val_str}%' with no exact measured value. "
                "The strongest reports state a precise figure (e.g. 98.62%); a bare "
                "threshold is a soft red flag — ask for the exact measured purity."
            ),
        }

    return {
        **base, "status": "pass",
        "message": f"Reported purity {val_str}% looks like a normal, specific measurement.",
    }
