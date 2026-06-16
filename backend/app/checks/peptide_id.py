"""Identify which peptide a COA is about, using the MW table as the single
source of truth (replaces the stale hardcoded KNOWN_PEPTIDES list).

Detection strategies, in order of confidence:
  1. name / alias   - word-boundary match of a table name or alias
  2. cas            - exact CAS registry number match
  3. sequence       - amino-acid sequence match (robust to OCR name garbling)
  4. fuzzy name     - difflib ratio on peptide-code-like tokens (e.g. OCR
                      'AOD604' vs 'AOD9604'); high threshold to avoid mismatches
"""
from __future__ import annotations
import difflib
import re

_AA3 = ("Ala|Arg|Asn|Asp|Cys|Gln|Glu|Gly|His|Ile|Leu|Lys|"
        "Met|Phe|Pro|Ser|Thr|Trp|Tyr|Val")
_AA_RE = re.compile(rf"\b({_AA3})\b", re.I)
_CAS_RE = re.compile(r"\b\d{2,7}-\d{2}-\d\b")
_CODE_TOKEN_RE = re.compile(r"[A-Za-z]{2,}[-\s]?\d{2,5}")
_FUZZY_MIN = 0.85


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _seq_norm(text: str) -> str:
    aas = _AA_RE.findall(text or "")
    return "".join(a[:3].lower() for a in aas) if len(aas) >= 4 else ""


def detect(ocr_text: str, table: dict) -> dict | None:
    """Return {'peptide': entry, 'method': str, 'matched': str} or None."""
    text = ocr_text or ""
    low = text.lower()
    peptides = table.get("peptides", [])

    # 1. exact name / alias (word boundary, longest wins)
    best_name = None
    for p in peptides:
        for nm in [p["name"]] + p.get("aliases", []):
            if len(nm) < 3:
                continue
            if re.search(rf"(?<!\w){re.escape(nm.lower())}(?!\w)", low):
                if best_name is None or len(nm) > len(best_name[1]):
                    best_name = (p, nm)
    if best_name:
        return {"peptide": best_name[0], "method": "name", "matched": best_name[1]}

    # 2. CAS number
    cas_found = set(_CAS_RE.findall(text))
    if cas_found:
        for p in peptides:
            if p.get("cas") and p["cas"] in cas_found:
                return {"peptide": p, "method": "cas", "matched": p["cas"]}

    # 3. amino-acid sequence
    seq = _seq_norm(text)
    if seq:
        for p in peptides:
            if p.get("sequence"):
                ps = _seq_norm(p["sequence"])
                if ps and (ps in seq or seq in ps):
                    return {"peptide": p, "method": "sequence", "matched": p["name"]}

    # 4. fuzzy name on peptide-code-like tokens (handles OCR drops/typos)
    tokens = {_norm(t) for t in _CODE_TOKEN_RE.findall(text)}
    best_fuzzy = None
    for tok in tokens:
        if len(tok) < 4:
            continue
        for p in peptides:
            for nm in [p["name"]] + p.get("aliases", []):
                cn = _norm(nm)
                if len(cn) < 4:
                    continue
                ratio = difflib.SequenceMatcher(None, tok, cn).ratio()
                if ratio >= _FUZZY_MIN and (best_fuzzy is None or ratio > best_fuzzy[0]):
                    best_fuzzy = (ratio, p, tok)
    if best_fuzzy:
        return {"peptide": best_fuzzy[1], "method": f"fuzzy:{best_fuzzy[0]:.2f}",
                "matched": best_fuzzy[2]}
    return None
