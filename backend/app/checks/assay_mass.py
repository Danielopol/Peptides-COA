"""Assay / measured-mass vs labeled-strength check (rule FORG-018, new).

The community's recurring complaint is that buyers read only the big "99.8%
purity" line and miss the measured content. A real example: a COA advertising
"Retatrutide 10 mg" whose own assay row reads 8.45 mg — a ~15% underdose hidden
in plain sight.

This check parses the labeled strength and the measured assay/content from the
COA's own text and compares them against the community's ±10% tolerance. It
ALWAYS returns both numbers (when found) so the UI can surface the assay next to
the purity, even when nothing is wrong.

Framing (grounded in the forums):
  - Underdose beyond -10% is the real red flag — possible skimming, and a very
    large gap can also mean the COA simply doesn't match this product (a reused
    or mismatched report).
  - Overfill beyond +10% is generally benign ("they slightly overfilled instead
    of cutting it short") and fill variance is rarely intentional, so it is
    reported as information, not penalized.

Statuses: pass | underdosed | overfilled | not_applicable.
"""
from __future__ import annotations
import re

RULE_ID = "FORG-018"
TOL = 0.10          # ±10% community tolerance
SEVERE_UNDER = 0.25  # below this fraction of label -> likely mismatched/reused COA

_MG = r"(\d{1,4}(?:\.\d{1,3})?)\s*mg\b"

# Measured content / assay value. "net content" and "result" are how the forums
# describe the measured fill; "total mass (incl. excipients)" is NOT peptide
# content and is filtered out below.
_ASSAY_RE = re.compile(
    r"(?:assay|measured(?:\s+(?:content|amount|mass))?|actual(?:\s+(?:content|amount))?|"
    r"net\s*content|content\s+(?:found|measured|result)|result|quantif\w*|determined|found)"
    r"\s*[:=]?\s*(?:was\s*)?" + _MG,
    re.I,
)
# Explicit label claim.
_LABEL_RE = re.compile(
    r"(?:label(?:l?ed)?(?:\s*(?:claim|amount|strength|dose))?|nominal|declared|"
    r"stated(?:\s+(?:amount|strength))?)\s*[:=]?\s*" + _MG,
    re.I,
)
_EXCIPIENT_CTX = re.compile(r"excipient|total\s+mass|including", re.I)


def _plausible(mg: float) -> bool:
    return 0.05 <= mg <= 2000


def _first_assay(text: str) -> float | None:
    for m in _ASSAY_RE.finditer(text):
        ctx = text[max(0, m.start() - 30): m.end() + 30]
        if _EXCIPIENT_CTX.search(ctx):
            continue  # total powder mass, not peptide content
        val = float(m.group(1))
        if _plausible(val):
            return val
    return None


def _explicit_label(text: str) -> float | None:
    m = _LABEL_RE.search(text)
    if m:
        val = float(m.group(1))
        if _plausible(val):
            return val
    return None


def _label_from_name(text: str, peptide_name: str | None) -> float | None:
    """Strength stated next to the product/peptide name, e.g. 'Retatrutide 10mg'
    or 'Product: 10 mg Retatrutide'."""
    if not peptide_name:
        return None
    nm = re.escape(peptide_name.strip())
    for pat in (nm + r"[^\n]{0,25}?" + _MG, _MG + r"[^\n]{0,25}?" + nm):
        m = re.search(pat, text, re.I)
        if m:
            val = float(m.group(1))
            if _plausible(val):
                return val
    return None


def check(ocr_text: str, peptide_name: str | None = None) -> dict:
    text = ocr_text or ""
    labeled = _explicit_label(text)
    label_source = "explicit" if labeled is not None else None
    if labeled is None:
        labeled = _label_from_name(text, peptide_name)
        label_source = "product_name" if labeled is not None else None
    measured = _first_assay(text)

    if labeled is None or measured is None:
        missing = []
        if labeled is None:
            missing.append("labeled strength")
        if measured is None:
            missing.append("measured assay/content")
        return {
            "status": "not_applicable",
            "rule_id": RULE_ID,
            "labeled_mg": labeled,
            "measured_mg": measured,
            "reason": "could not find " + " and ".join(missing),
        }

    deviation = (measured - labeled) / labeled
    pct = round(deviation * 100, 1)
    base = {
        "rule_id": RULE_ID,
        "labeled_mg": labeled,
        "measured_mg": measured,
        "deviation_pct": pct,
        "label_source": label_source,
    }

    if abs(deviation) <= TOL:
        return {
            **base,
            "status": "pass",
            "message": (
                f"Measured content ({measured} mg) matches the labeled {labeled} mg "
                f"within ±10% ({pct:+}%)."
            ),
        }

    if deviation < 0:  # underdose
        severe = measured < labeled * (1 - SEVERE_UNDER)
        msg = (
            f"Measured content ({measured} mg) is {abs(pct)}% below the labeled "
            f"{labeled} mg — outside the ±10% norm. Don't judge by the purity % "
            "alone; this is a possible underdose."
        )
        if severe:
            msg += (
                " A gap this large can also mean the COA doesn't match this "
                "product (a reused or mismatched report)."
            )
        return {
            **base,
            "status": "underdosed",
            "severity": "major" if severe else "minor",
            "message": msg,
        }

    # overfill — benign, informational only
    return {
        **base,
        "status": "overfilled",
        "severity": "minor",
        "message": (
            f"Measured content ({measured} mg) is {pct:+}% vs the labeled "
            f"{labeled} mg. Overfill is generally benign (vendors often overfill "
            "slightly rather than short-fill), but it's outside the ±10% norm."
        ),
    }
