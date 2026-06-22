"""Multiple-masses-per-peptide check (rule FORG-017, new).

A genuine COA reports one measured mass per peptide entry, e.g.:
    BPC-157            12.02 mg
    TB-500 (TBA)       10.71 mg
Combo products list distinct peptides joined with '+', each with one mass.

A forgery seen in the wild pads a single peptide line with several near-equal
replicate masses to look more thorough, e.g.:
    GHK-Cu | 61.57 mg; 59.03 mg; 61.51 mg.
    BPC-157 | 14.54 mg; 14.16 mg; 14.60 mg.

Signal: a single result line carrying 2+ mass values separated by ';' (or ',')
where the values are numerically close (replicates of the same quantity).
Deterministic, zero expected false positives on real COAs.
"""
from __future__ import annotations
import re

_MASS_RE = re.compile(r"(\d{1,4}(?:\.\d{1,3})?)\s*mg\b", re.I)
# A line is a "replicate list" if masses are joined by ; or , (not '+', which
# separates distinct peptides in combo products).
_SEPARATOR_RE = re.compile(r"\d\s*mg\s*[;,]\s*\d", re.I)


def check(ocr_text: str) -> dict:
    if not ocr_text:
        return {"status": "not_applicable", "reason": "no text"}

    offenders = []
    saw_mass = False  # did the document contain ANY measured mass to check?
    for raw in ocr_text.splitlines():
        line = raw.strip()
        if not line:
            continue
        masses = [float(m) for m in _MASS_RE.findall(line)]
        if masses:
            saw_mass = True
        if len(masses) < 2:
            continue
        # combo products use '+' to join distinct peptides — not an offense
        if "+" in line and not _SEPARATOR_RE.search(line):
            continue
        # require ; or , separating the masses (replicate-list punctuation)
        if not _SEPARATOR_RE.search(line):
            continue
        lo, hi = min(masses), max(masses)
        close = hi <= lo * 1.5  # replicates of the same quantity cluster tightly
        offenders.append({
            "line": line[:120],
            "masses": masses,
            "values_close": close,
        })

    # Fire only when at least one line has clustered replicate masses — that is
    # the unambiguous forgery signature. Far-apart values on a ';' line are
    # left as suspicious rather than forged.
    clustered = [o for o in offenders if o["values_close"]]
    if clustered:
        return {
            "status": "fired",
            "rule_id": "FORG-017",
            "severity": "critical",
            "offending_lines": clustered[:6],
            "message": (
                f"{len(clustered)} peptide entr{'y' if len(clustered)==1 else 'ies'} "
                "report multiple near-equal masses on one line "
                "(e.g. '14.54 mg; 14.16 mg; 14.60 mg'). Genuine COAs report a "
                "single measured mass per peptide — this pattern indicates a "
                "fabricated or padded report."
            ),
        }
    if offenders:
        return {
            "status": "suspicious",
            "rule_id": "FORG-017",
            "severity": "major",
            "offending_lines": offenders[:6],
            "message": "A result line lists multiple masses for one entry — review manually.",
        }
    # No measured mass anywhere -> nothing to cross-check. Report this as
    # not_applicable (hidden / greyed) rather than a confident green PASS: the
    # absence of the replicate-padding signature is not positive evidence of
    # mass consistency, and rendering it as "Pass" misled on non-COA inputs.
    if not saw_mass:
        return {"status": "not_applicable", "rule_id": "FORG-017",
                "reason": "no measured masses on the document to cross-check"}
    return {"status": "pass", "rule_id": "FORG-017"}
