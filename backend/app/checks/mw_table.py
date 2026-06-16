"""Cross-reference claimed peptide MW + molecular formula against a curated table
(XREF-009).

MW: picks monoisotopic vs average mass based on the detected MS technique;
high-res MS (ESI/Q-TOF) reports monoisotopic, most COAs labelled 'MW' quote
average mass. Only fires when a verified reference mass exists for the peptide.

Formula: catches the dominant template-reuse forgery the community has flagged —
a COA whose stated molecular formula belongs to a *different* compound (e.g. a
Retatrutide COA carrying GHK-Cu's copper-containing formula). To stay robust
against OCR noise on long peptide formulas, it fires only on high-confidence
signals: (a) a distinctive metal in the claimed formula that none of the
peptide's accepted forms contain, or (b) a formula that exactly matches a
different known compound in the table. Gross carbon-count drift is deliberately
NOT used (OCR mangles long formulas, risking false positives).
"""
from __future__ import annotations
import json
import re
from pathlib import Path

from . import peptide_id

ROOT = Path(__file__).resolve().parents[3]
TABLE_PATH = ROOT / "Rules" / "peptide_mw_table.json"

_MW_PATTERN = re.compile(
    r"(?:molecular\s*weight|mol\.?\s*wt|mw|m\.?w\.?)\s*[:=]?\s*"
    r"([0-9]{2,5}(?:\.[0-9]{1,4})?)\s*(?:da|g/?mol)?",
    re.IGNORECASE,
)
_MONO_TECHNIQUES = {"ESI-MS", "ESI-TOF", "Q-TOF"}  # high-res -> monoisotopic

# --- Molecular-formula cross-check -----------------------------------------
_FORMULA_LABEL = re.compile(
    r"(?:molecular|chemical|empirical|mol\.?)\s*formula\s*[:=]?\s*([^\n]{2,60})",
    re.IGNORECASE,
)
# Unicode subscripts ₀-₉ -> ASCII digits (COAs often render C₂₈H₄₈...).
_SUBSCRIPTS = {0x2080 + i: str(i) for i in range(10)}
# Bio-plausible elements. A parsed formula containing anything else is treated
# as OCR garbage and ignored (fail-safe — we don't fire on it).
_KNOWN_ELEMENTS = {
    "H", "B", "C", "N", "O", "F", "P", "S", "Cl", "Br", "I", "Se", "Si",
    "Na", "K", "Ca", "Mg", "Zn", "Cu", "Fe", "Mn", "Co", "Ni", "Cr", "Pt", "Au", "Ag",
}
# Distinctive (non-counterion) metals whose presence/absence is a strong identity
# signal — a stray one from OCR is very unlikely, and these define metal-complex
# peptides like GHK-Cu.
_DISTINCTIVE_METALS = {"Cu", "Fe", "Zn", "Mn", "Co", "Ni", "Cr", "Pt", "Au", "Ag", "Se"}


def _extract_formula_token(raw: str) -> str | None:
    """Pull a clean element-count token from the text after a 'formula' label."""
    s = raw.translate(_SUBSCRIPTS).replace(" ", "").replace("·", "").replace("•", "")
    m = re.match(r"((?:[A-Z][a-z]?\d*){2,})", s)
    return m.group(1) if m else None


def _parse_formula(token: str | None) -> dict[str, int] | None:
    """Element -> count, or None if the token contains unknown elements (OCR noise)."""
    if not token:
        return None
    counts: dict[str, int] = {}
    for el, n in re.findall(r"([A-Z][a-z]?)(\d*)", token):
        if not el:
            continue
        if el not in _KNOWN_ELEMENTS:
            return None
        counts[el] = counts.get(el, 0) + (int(n) if n else 1)
    return counts or None


def _metals(counts: dict[str, int]) -> set[str]:
    return {el for el in counts if el in _DISTINCTIVE_METALS}


def _accepted_formulas(peptide: dict) -> list[str]:
    out = []
    if peptide.get("formula"):
        out.append(peptide["formula"])
    for v in peptide.get("variants") or []:
        if v.get("formula"):
            out.append(v["formula"])
    return out


def _matches_other_compound(claimed: dict, peptide: dict, table: dict) -> str | None:
    for p in table["peptides"]:
        if p is peptide or p.get("name") == peptide.get("name"):
            continue
        if _parse_formula(p.get("formula")) == claimed:
            return p["name"]
    return None


def _formula_check(ocr_text: str, peptide: dict, table: dict) -> dict:
    """Compare a COA-stated molecular formula against the peptide's accepted
    forms. Returns {'formula_status': match|mismatch|not_found|unparsed|inconclusive, ...}."""
    label = _FORMULA_LABEL.search(ocr_text or "")
    if not label:
        return {"formula_status": "not_found"}
    token = _extract_formula_token(label.group(1))
    claimed = _parse_formula(token)
    if not claimed:
        return {"formula_status": "unparsed", "claimed_formula": token}

    accepted = [c for c in (_parse_formula(f) for f in _accepted_formulas(peptide)) if c]
    if any(claimed == a for a in accepted):
        return {"formula_status": "match", "claimed_formula": token}

    accepted_metals: set[str] = set().union(*[_metals(a) for a in accepted]) if accepted else set()
    extra_metals = sorted(_metals(claimed) - accepted_metals)
    if extra_metals:
        return {
            "formula_status": "mismatch", "reason": "metal",
            "claimed_formula": token, "unexpected_elements": extra_metals,
        }
    other = _matches_other_compound(claimed, peptide, table)
    if other:
        return {
            "formula_status": "mismatch", "reason": "other_compound",
            "claimed_formula": token, "matches_compound": other,
        }
    return {"formula_status": "inconclusive", "claimed_formula": token}


def _load_table() -> dict:
    if not TABLE_PATH.exists():
        return {"peptides": [], "tolerance_da": {}}
    return json.loads(TABLE_PATH.read_text(encoding="utf-8"))


def _match_peptide(name: str, table: dict) -> dict | None:
    if not name:
        return None
    n = name.strip().lower()
    for p in table["peptides"]:
        candidates = [p["name"].lower()] + [a.lower() for a in p.get("aliases", [])]
        if any(n == c or c in n or n in c for c in candidates):
            return p
    return None


def _pick_mass(obj: dict, ms_technique: str | None) -> tuple[float | None, str]:
    """Choose monoisotopic vs average mass for a peptide or one of its variants."""
    mono = obj.get("monoisotopic_mass")
    avg = obj.get("average_mass")
    use_mono = ms_technique in _MONO_TECHNIQUES or ms_technique == "MALDI-TOF"
    if use_mono and mono is not None:
        return mono, "monoisotopic"
    if avg is not None:
        return avg, "average"
    if mono is not None:
        return mono, "monoisotopic"
    return None, "none"


def _reference_candidates(peptide: dict, ms_technique: str | None) -> list[dict]:
    """All accepted reference masses for a peptide: its primary plus any
    species variants[] (e.g. peptide vs copper-complex, fragment vs full-length).
    A COA matching any of these is treated as a match.
    """
    cands: list[dict] = []
    mass, mass_type = _pick_mass(peptide, ms_technique)
    if mass is not None:
        cands.append({"mass": mass, "mass_type": mass_type, "form": peptide["name"], "primary": True})
    for v in peptide.get("variants", []):
        vm, vt = _pick_mass(v, ms_technique)
        if vm is not None:
            cands.append({"mass": vm, "mass_type": vt, "form": v.get("form", "variant"), "primary": False})
    return cands


def _tolerance(table: dict, mass_type: str, ms_technique: str | None) -> float:
    tol = table.get("tolerance_da", {})
    if mass_type == "monoisotopic":
        m = tol.get("monoisotopic", {})
        return m.get(ms_technique or "", m.get("default", 0.5))
    return tol.get("average", {}).get("default", 1.5)


def detect(ocr_text: str) -> dict | None:
    """Identify the peptide from OCR text using the MW table (name/CAS/sequence/fuzzy)."""
    return peptide_id.detect(ocr_text, _load_table())


def check(peptide_name: str | None, ocr_text: str, ms_technique: str | None = None) -> dict:
    table = _load_table()
    peptide = _match_peptide(peptide_name or "", table)
    detect_method = "name" if peptide else None
    if not peptide:
        # Fall back to detecting the peptide directly from the COA text using
        # the MW table as the source of truth (name/CAS/sequence/fuzzy).
        det = peptide_id.detect(ocr_text, table)
        if det:
            peptide = det["peptide"]
            detect_method = det["method"]
    if not peptide:
        return {"status": "not_applicable", "reason": "peptide not identified"}
    if peptide.get("is_blend"):
        return {
            "status": "not_applicable",
            "reason": f"{peptide['name']} is a multi-component blend with no single MW",
            "peptide": peptide["name"],
        }
    if not peptide.get("verified"):
        return {
            "status": "not_applicable",
            "reason": f"reference mass for {peptide['name']} not yet verified",
            "peptide": peptide["name"],
        }

    # Molecular-formula cross-check first: it fires even when no MW is printed,
    # and a formula belonging to a different compound is a strong identity flag.
    fcheck = _formula_check(ocr_text, peptide, table)
    if fcheck.get("formula_status") == "mismatch":
        if fcheck["reason"] == "metal":
            msg = (
                f"The molecular formula on this COA ({fcheck['claimed_formula']}) contains "
                f"{', '.join(fcheck['unexpected_elements'])}, which {peptide['name']} does not — "
                "the formula belongs to a different compound (a classic copy-paste/template error)."
            )
        else:
            msg = (
                f"The molecular formula on this COA ({fcheck['claimed_formula']}) is that of "
                f"{fcheck['matches_compound']}, not {peptide['name']} — the COA appears to reuse "
                "another compound's template."
            )
        return {
            "status": "fired", "rule_id": "XREF-009", "severity": "critical",
            "peptide": peptide["name"], "detect_method": detect_method,
            "claimed_formula": fcheck["claimed_formula"], "formula_status": "mismatch",
            "mismatch_kind": "formula", "message": msg,
        }

    candidates = _reference_candidates(peptide, ms_technique)
    if not candidates:
        return {"status": "not_applicable", "reason": "no reference mass available",
                "peptide": peptide["name"], "formula_status": fcheck.get("formula_status")}

    match = _MW_PATTERN.search(ocr_text or "")
    if not match:
        return {"status": "not_applicable", "reason": "no MW value found in COA text",
                "peptide": peptide["name"], "formula_status": fcheck.get("formula_status")}
    claimed = float(match.group(1))

    # Accept a match against the primary OR any species variant; report which form matched.
    scored = []
    for c in candidates:
        tol = _tolerance(table, c["mass_type"], ms_technique)
        scored.append((abs(claimed - c["mass"]), tol, c))
    scored.sort(key=lambda s: s[0])
    best_diff, best_tol, best = scored[0]

    if best_diff <= best_tol:
        result = {
            "status": "pass", "peptide": peptide["name"],
            "detect_method": detect_method,
            "mass_type": best["mass_type"], "claimed_mw": claimed,
            "expected_mw": best["mass"], "tolerance_da": best_tol,
            "formula_status": fcheck.get("formula_status"),
        }
        if fcheck.get("claimed_formula"):
            result["claimed_formula"] = fcheck["claimed_formula"]
        if not best["primary"]:
            result["matched_variant"] = best["form"]
            result["note"] = f"matched species variant '{best['form']}', not the primary form"
        return result

    expected_masses = [{"form": c["form"], "mass": c["mass"], "mass_type": c["mass_type"]} for c in candidates]
    return {
        "status": "fired", "rule_id": "XREF-009", "severity": "critical",
        "peptide": peptide["name"], "detect_method": detect_method,
        "mass_type": best["mass_type"], "mismatch_kind": "mw",
        "claimed_mw": claimed, "expected_mw": best["mass"],
        "diff_da": round(best_diff, 4), "tolerance_da": best_tol,
        "expected_masses": expected_masses,
        "formula_status": fcheck.get("formula_status"),
        "message": (
            f"Claimed MW {claimed} Da does not match any accepted mass for "
            f"{peptide['name']} (closest: {best['mass']} Da '{best['form']}', ±{best_tol})."
            + (f" Accepted forms: {', '.join(str(e['mass']) for e in expected_masses)} Da."
               if len(expected_masses) > 1 else "")
        ),
    }
