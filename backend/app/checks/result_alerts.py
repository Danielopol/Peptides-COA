"""Null-result content alerts — "authentic document, empty product".

A genuine, verifiable COA can still report that the lab found NO measurable
product: Quantity / Assay = "Not Detected", Chromatographic Purity = "n/a",
results "below LOQ" / "< LOD". That is a CONTENT signal, not a document-
authenticity signal — so it is surfaced as its own prominent alert and never
moves the authenticity score.

Two sources feed the same alert list:
  - from_text():   regex over OCR text (free; works when OCR captured the cell)
  - from_vision(): the vision result-reader (recovers cells OCR dropped — the
                   common case, since small result cells OCR poorly)
"""
from __future__ import annotations
import re

# A result cell meaning "no measurable amount / no usable result".
_NULL_RESULT = re.compile(
    r"(not\s*detected|\bn\.?\s*d\.?\b|below\s*(?:loq|lod|the\s*(?:limit|loq|lod))|"
    r"<\s*lo[qd]\b|undetectable|none\s*detected)",
    re.I,
)
# Standalone "n/a" / "not applicable" result.
_NA_RESULT = re.compile(r"(n\s*/\s*a|n\.a\.|not\s*applicable)", re.I)

# Analysis-name cues → category.
_QUANTITY_CUE = re.compile(r"quantit|assay|net\s*(?:peptide\s*)?content|concentrat|potenc", re.I)
_PURITY_CUE = re.compile(r"purit", re.I)


def _category(analysis: str) -> str:
    if _QUANTITY_CUE.search(analysis):
        return "quantity"
    if _PURITY_CUE.search(analysis):
        return "purity"
    return "other"


def _classify(result: str) -> str | None:
    """null kind for a result string: 'not_detected' | 'not_applicable' | None."""
    s = (result or "").strip()
    if not s:
        return None
    if _NULL_RESULT.search(s):
        return "not_detected"
    # only treat n/a as null when the WHOLE cell is n/a (not part of a value)
    if _NA_RESULT.search(s) and len(s) <= 18:
        return "not_applicable"
    return None


def _message(category: str, analysis: str, result: str, kind: str) -> str:
    name = analysis.strip() or category
    if kind == "not_detected":
        if category == "quantity":
            return (f"The lab tested this vial and reported {name} as “{result.strip()}” — "
                    "no measurable amount of the compound was found in the sample tested. "
                    "A genuine report can still describe an empty or failed product.")
        if category == "purity":
            return (f"{name} came back “{result.strip()}” — the lab could not measure a "
                    "purity for what was in the vial.")
        return f"{name} was reported as “{result.strip()}” — a null result for a measured test."
    # not_applicable
    return (f"{name} was reported as “{result.strip()}” — no result was determined for a "
            "test the COA lists.")


def _alert(category: str, analysis: str, result: str, kind: str) -> dict:
    # "Not Detected" on the headline quantity/assay is the strongest content flag.
    severity = "critical" if (kind == "not_detected" and category in ("quantity", "purity")) else "warning"
    return {
        "analysis": analysis.strip(),
        "result": result.strip(),
        "category": category,
        "kind": kind,
        "severity": severity,
        "message": _message(category, analysis, result, kind),
    }


def _dedupe(alerts: list[dict]) -> list[dict]:
    seen: set = set()
    out: list[dict] = []
    # critical first, then by category for a stable, sensible order
    for a in sorted(alerts, key=lambda x: (x["severity"] != "critical", x["category"])):
        key = (a["category"], a["kind"])
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


def from_vision(results) -> list[dict]:
    """Build alerts from the vision result-reader's row list."""
    alerts: list[dict] = []
    for row in results or []:
        if not isinstance(row, dict):
            continue
        analysis = str(row.get("analysis") or "")
        result = str(row.get("result") or "")
        kind = _classify(result)
        if kind is None:
            continue
        cat = _category(analysis)
        # Ignore null cells on tests that aren't the headline measurements unless
        # clearly a measured analysis — keeps noise (e.g. an empty "notes" cell) out.
        if cat == "other":
            continue
        alerts.append(_alert(cat, analysis, result, kind))
    return _dedupe(alerts)


def from_text(ocr_text: str) -> list[dict]:
    """Best-effort detection from OCR text: a null-result token on the same line
    as a quantity/purity analysis name. Low recall (tables OCR poorly) but free
    and high-precision; the vision reader covers what this misses."""
    alerts: list[dict] = []
    for line in (ocr_text or "").splitlines():
        cat = _category(line)
        if cat == "other":
            continue
        kind = _classify(line)
        if kind is None:
            continue
        # quote the matched token as the result
        m = _NULL_RESULT.search(line) or _NA_RESULT.search(line)
        alerts.append(_alert(cat, line.strip()[:40], m.group(0) if m else line.strip(), kind))
    return _dedupe(alerts)
