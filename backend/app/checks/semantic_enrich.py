"""Robust semantic enrichment for the completeness presence-rules.

`calibrate.parse_ocr` detects expected COA sections via narrow keyword matches
(e.g. it only finds a batch when the literal word "Batch:" precedes it, and only
finds MS when "ESI/MALDI" appears). Compact real COAs (e.g. Freedom Diagnostics)
print these elements WITHOUT those exact labels — a bare lot code "A2601B10", a
"Mass Identification" section with an "m/z" axis, a PDA/mAU chromatogram — so the
presence rules (STRUCT-002, STRUCT-009, METH-001/002/003) false-fire as "missing"
and deflate the completeness score.

`enrich()` augments the `semantic` dict using broader, evidence-based detection.
It is MONOTONIC: it only ever flips a presence signal from absent→present when it
finds real evidence in the text. It never marks something absent and never
creates a new fire, so it can only REDUCE false "missing" completeness fires —
it cannot introduce a false forgery flag.
"""
from __future__ import annotations
import difflib
import re

from . import mw_table

# Batch/lot with an explicit label.
_BATCH_LABELED = re.compile(
    r"(?:batch|lot)\s*(?:no\.?|number|id|#)?\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9\-/]{2,20})",
    re.I,
)
# A lot-style code as a standalone token (works inline, e.g. "...10mg A2601MT1"):
# "A2601B10", "A2601BT2", "A2601CI5", "RT10426" — uppercase letters + digits with
# an internal letter block, no hyphen. The lookarounds require it to be its own
# token; the no-hyphen + letter-block shape keeps it from matching peptide codes
# ("BPC-157", "CJC-1295", "BPC157"), purities, or dates.
_BATCH_TOKEN = re.compile(
    r"(?<![A-Za-z0-9])(?:[A-Z]{1,3}\d{2,6}[A-Z]{1,3}\d{0,4}|[A-Z]{2,4}\d{4,8})(?![A-Za-z0-9])"
)

# Word boundaries on the short tokens (esi/tof/mz/lc-ms): without them a bare
# "esi" matches inside "design" etc., falsely confirming MS identity on non-COAs.
_MS_CUES = re.compile(
    r"mass\s*(?:spec\w*|identif\w*)|\bm\s*/?\s*z\b|\bmz\b|\besi\b|\bmaldi\b|\bq-?tof\b|"
    r"\borbitrap\b|\blc-?ms\b|\btof\b|triple\s*quad",
    re.I,
)
_HPLC_CUES = re.compile(
    r"hplc|uplc|u-?hplc|rp-?hplc|\bpda\b|\bmau\b|chromatogram|retention\s*time",
    re.I,
)
_C18_CUES = re.compile(r"\bc-?18\b|revers[e]?d?[\s-]?phase", re.I)


_NAME_FUZZY_MIN = 0.86  # strict, to avoid matching noise to a peptide name
_WORD_RE = re.compile(r"[a-z][a-z\-]{5,}")  # alpha tokens long enough to fuzzy-match


def _peptide_names() -> list[str]:
    names: list[str] = []
    for p in mw_table._load_table().get("peptides", []):
        names.append(p.get("name", ""))
        names.extend(p.get("aliases", []))
    return [n.lower() for n in names if n]


def detect_peptide_name(ocr_text: str) -> str | None:
    """Fuzzy-match a product/peptide name even when OCR garbles it slightly
    (e.g. 'Turzepatide' -> 'Tirzepatide'). Completeness-only; never feeds the
    authenticity MW/formula checks."""
    low = (ocr_text or "").lower()
    names = _peptide_names()
    for tok in set(_WORD_RE.findall(low)):
        m = difflib.get_close_matches(tok, names, n=1, cutoff=_NAME_FUZZY_MIN)
        if m:
            return m[0]
    return None


def detect_batch(ocr_text: str) -> str | None:
    """Batch/lot identifier from an explicit label OR an inline lot-style token."""
    text = ocr_text or ""
    m = _BATCH_LABELED.search(text)
    if m and any(c.isdigit() for c in m.group(1)):
        return m.group(1)
    t = _BATCH_TOKEN.search(text)
    return t.group(0) if t else None


# Client / sponsor name: a company-style line that is NOT the issuing lab.
_CLIENT_SUFFIX = re.compile(
    r"\b(?:peptides?|research|biotech\w*|bioscience\w*|therapeutics?|sciences?|"
    r"labs?|inc\.?|llc|ltd\.?|gmbh|co\.)\b",
    re.I,
)
_LAB_SUFFIX = re.compile(r"diagnostic|analytical|laborator|testing|\bjanoshik\b", re.I)
_CLIENT_BOILERPLATE = re.compile(
    r"searchable|contact|owned|operated|certificate|analysis|lyophilized|powder|"
    r"identification|purity|result|mass\b",
    re.I,
)


def detect_client(ocr_text: str) -> str | None:
    """A client/sponsor company named on the COA (e.g. 'Titan Peptides
    Research'), distinct from the issuing testing lab. Freedom-style COAs print
    the client without a 'Client:' label, so the keyword rule misses it."""
    for line in (ocr_text or "").splitlines():
        s = line.strip()
        if len(s) < 4 or _LAB_SUFFIX.search(s) or _CLIENT_BOILERPLATE.search(s):
            continue
        if _CLIENT_SUFFIX.search(s) and re.search(r"[A-Z][a-z]", s):
            return s
    return None


def enrich(sem: dict, ocr_text: str) -> dict:
    """Monotonically upgrade absent→present presence signals in `sem`."""
    sem = sem or {}
    low = (ocr_text or "").lower()

    if not sem.get("peptide_name_found"):
        nm = detect_peptide_name(ocr_text)
        if nm:
            sem["peptide_name_found"] = nm
    if not sem.get("batch"):
        b = detect_batch(ocr_text)
        if b:
            sem["batch"] = b
    if not sem.get("has_ms") and _MS_CUES.search(low):
        sem["has_ms"] = True
    if not sem.get("has_hplc") and _HPLC_CUES.search(low):
        sem["has_hplc"] = True
    if not sem.get("has_c18") and _C18_CUES.search(low):
        sem["has_c18"] = True
    return sem
