"""Completeness checklist (informational).

Turns the completeness axis into a plain present/absent list of the sections a
thorough COA is expected to contain, so a user who "doesn't know what to look
for" can see at a glance what's there and what to ask the vendor for.

This is INFORMATIONAL: it does not change the completeness score (the rule
engine drives that). It is a transparent breakdown built by scanning the OCR
text and reusing signals already computed by the other checks.

Grounded in the community's "what a good COA contains": identity, purity, assay/
mass, heavy metals, endotoxin, sterility, residual solvents, batch/lot, vial
photo, accreditation, verification path, and a test date.
"""
from __future__ import annotations
import re

from . import semantic_enrich

# section_id -> (label, regex over lowercased OCR text). Some sections are also
# (or instead) satisfied by signals from other checks — see build().
_PATTERNS: list[tuple[str, str, str | None]] = [
    ("identity", "Identity confirmation (mass spec)",
     r"identit|confirmed\s+to\s+be|sequence\s|mass\s*spec|maldi|esi|lc-?ms|q-?tof"),
    ("purity", "Purity (HPLC %)", r"purit"),
    ("assay_mass", "Assay / measured mass",
     r"assay|net\s*content|content\s*[:=]|fill\s*(?:test|amount|weight)|quantific"),
    ("heavy_metals", "Heavy metals",
     r"heavy\s*metal|arsenic|cadmium|\blead\b|mercury|icp-?ms"),
    ("endotoxin", "Bacterial endotoxin", r"endotoxin|\blal\b|eu/?\s*mg|pyrogen"),
    ("sterility", "Sterility / microbial",
     r"steril|bioburden|microbial|\btamc\b|\btymc\b|\bcfu\b|microbio"),
    ("residual_solvents", "Residual solvents",
     r"residual\s*solvent|\btfa\b|trifluoroacetic|acetonitrile|solvent\s*content"),
    ("impurity_profile", "Impurity breakdown",
     r"impurit|related\s+substance|main\s+peak|unknown\s+peak|degrad"),
    ("water_content", "Water content (Karl Fischer)",
     r"water\s*content|moisture|karl\s*fischer|\bkf\b|loss\s+on\s+drying|\blod\b"),
    ("batch_lot", "Batch / lot number",
     r"batch\s*(?:no|number|#|:)|lot\s*(?:no|number|#|:)|lot#"),
    ("vial_photo", "Vial photo",
     r"vial\s*(?:photo|image|picture)|photo\s*of\s*(?:the\s*)?vial|see\s*image"),
    ("accreditation", "Lab accreditation",
     r"iso[\s/]*(?:iec)?\s*17025|a2la|accredit|\bclia\b|cap\s*accredit|dea\s*regist"),
]


def _present(pattern: str, low: str) -> bool:
    return bool(re.search(pattern, low, re.I))


def build(ocr_text: str, hard_checks: dict, ms_technique: str | None = None) -> list[dict]:
    low = (ocr_text or "").lower()
    hc = hard_checks or {}
    items: list[dict] = []

    for sid, label, pattern in _PATTERNS:
        present = _present(pattern, low) if pattern else False
        # Reuse already-computed signals / robust detectors where they're more
        # reliable than a plain keyword regex.
        if sid == "identity" and (ms_technique or semantic_enrich._MS_CUES.search(low)):
            present = True
        elif sid == "purity" and hc.get("purity_sanity", {}).get("status") not in (None, "not_applicable"):
            present = True
        elif sid == "assay_mass":
            am = hc.get("assay_mass", {})
            if am.get("labeled_mg") is not None or am.get("measured_mg") is not None:
                present = True
        elif sid == "batch_lot" and not present:
            present = semantic_enrich.detect_batch(ocr_text) is not None
        items.append({"section": sid, "label": label, "present": present})

    # Verification path: reuse verifiability / janoshik rather than a raw regex.
    verif = hc.get("verifiability", {}).get("status")
    janoshik_applicable = hc.get("janoshik", {}).get("status") not in (None, "not_applicable")
    items.append({
        "section": "verification",
        "label": "Verification code / QR",
        "present": verif in ("verifiable", "redacted") or janoshik_applicable,
    })

    # Test date: reuse recency (pass or stale both mean a date was found).
    items.append({
        "section": "test_date",
        "label": "Test / analysis date",
        "present": hc.get("recency", {}).get("status") in ("pass", "stale"),
    })

    return items
