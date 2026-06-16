"""Generate Rules/registry.json from peptide_testing_labs.xlsx.

Pulls name/website/accreditation/description/trust from the spreadsheet and
overlays curated fields: stable ids, aliases, COA folders (for visual
fingerprinting), and verification portals (sheet 3). Re-run whenever the xlsx
changes:  .venv/bin/python build_registry.py
"""
from __future__ import annotations
import json
import re
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
XLSX = ROOT / "peptide_testing_labs.xlsx"
OUT = ROOT / "Rules" / "registry.json"

TRUST_MAP = {
    "High": "high",
    "Established (pharma/CRO)": "established_pharma_cro",
    "Established (CRO)": "established_cro",
    "Moderate": "moderate",
    "Emerging": "emerging",
}

# lab name -> stable id (only for ones we reference elsewhere; rest are slugified)
ID_OVERRIDES = {
    "Janoshik Analytical": "janoshik",
    "Vanguard Laboratory": "vanguard",
    "AccuMark Labs": "accumark_labs",
    "Bioviridian Inc.": "bioviridian",
    "Freedom Diagnostics Testing": "freedom_diagnostics",
    "MZ Biolabs": "mz_biolabs",
    "Colmaric Analyticals": "colmaric",
}

# extra aliases (incl. common OCR manglings) merged with auto-extracted ones
ALIAS_OVERRIDES = {
    "janoshik": ["Janoshik", "Janoshík", "Janosuik", "Janoshik Analytical"],
    "freedom_diagnostics": ["Freedom Diagnostics", "Freedom Diagnostic", "Freedom Diagnostics Testing"],
    "vanguard": ["Vanguard", "Vanguard Lab", "Vanguard Laboratory"],
    "accumark_labs": ["AccuMark", "Accumark", "AccuMark Labs"],
    "bioviridian": ["Bioviridian", "Bioviridians", "BIOVIRIDIAN"],
    "mz_biolabs": ["MZ Biolabs", "MZBiolabs", "MZ Bio"],
}

# id -> COAs/ subfolder (entities we have reference COAs for -> fingerprinted)
COA_FOLDERS = {
    "janoshik": "Janoshik_Tests",
    "vanguard": "VANGUARD LABORATORY",
    "accumark_labs": "ACCUMARK LABS",
    "bioviridian": "BIOVIRIDIAN",
    "freedom_diagnostics": "Freedom Diagnostic",
}

# id -> verification config (from sheet 3 "Community Verification Portals")
VERIFICATION = {
    "janoshik": {"url": "https://janoshik.com/verify", "method": "sample ID + QR", "requires_task_number": True, "requires_unique_key": True},
    "mz_biolabs": {"url": "https://mzbiolabs.com", "method": "COA lookup on platform"},
    "vanguard": {"url": "https://vanguardlaboratory.com", "method": "'Verified by Vanguard' lookup"},
    "accumark_labs": {"url": "https://accumarklabs.com", "method": "scan-to-verify cryptographically signed digital COA"},
    "testides": {"url": "https://testides.com", "method": "public COA portal"},
    "finnrick_analytics": {"url": "https://finnrick.com", "method": "public test database / rankings"},
    "arq_biolabs": {"url": "https://arqbiolabs.com", "method": "digitally verifiable COAs"},
    "novacert": {"url": "https://novacert.org", "method": "public batch verification"},
    "certiklabs": {"url": "https://certiklabs.com", "method": "public batch verification"},
    "jrax_bio_solutions": {"url": "https://jraxbio.com", "method": "public COA publishing"},
    "sp_bio_testing": {"url": "https://spbiotesting.com", "method": "QR-verifiable reporting"},
}


def clean(s: str | None) -> str:
    if not s:
        return ""
    # fix common UTF-8 mojibake from the xlsx
    s = s.replace("â€”", "—").replace("â€“", "–").replace("â€™", "’")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def slugify(name: str) -> str:
    base = re.sub(r"\(.*?\)", "", name)             # drop parentheticals
    base = re.sub(r"[^A-Za-z0-9]+", "_", base).strip("_").lower()
    return base


def aliases_for(name: str) -> list[str]:
    al = set()
    m = re.search(r"\((.*?)\)", name)
    if m:
        al.add(m.group(1).strip())
    bare = re.sub(r"\(.*?\)", "", name).strip()
    if bare != name:
        al.add(bare)
    return sorted(a for a in al if a and a.lower() != name.lower())


def main() -> None:
    wb = openpyxl.load_workbook(XLSX, data_only=True)
    ws = wb["Peptide Testing Labs"]
    rows = list(ws.iter_rows(values_only=True))
    header = rows[0]
    labs = []
    for row in rows[1:]:
        if not row or not row[0]:
            continue
        name = clean(str(row[0]))
        website = clean(str(row[1])) if row[1] else ""
        accreditation = clean(str(row[2])) if row[2] else ""
        description = clean(str(row[3])) if row[3] else ""
        trust_raw = clean(str(row[4])) if row[4] else ""
        lab_id = ID_OVERRIDES.get(name) or slugify(name)
        merged_aliases = sorted(set(aliases_for(name)) | set(ALIAS_OVERRIDES.get(lab_id, [])))
        entry = {
            "id": lab_id,
            "name": name,
            "aliases": merged_aliases,
            "type": "independent",
            "website": website,
            "accreditation": accreditation,
            "trust": TRUST_MAP.get(trust_raw, "moderate"),
            "coa_template_owner": lab_id in COA_FOLDERS,
            "coa_folder": COA_FOLDERS.get(lab_id),
        }
        if lab_id in VERIFICATION:
            entry["verification"] = VERIFICATION[lab_id]
        if description:
            entry["description"] = description
        labs.append(entry)

    out = {
        "version": "2.0",
        "last_updated": "2026-05-22",
        "source": "peptide_testing_labs.xlsx",
        "description": "Lab-centric registry generated from peptide_testing_labs.xlsx. 'coa_template_owner' labs have reference COAs under COAs/<coa_folder> for visual fingerprinting. Vendors are tracked separately if needed; current corpus is organized by issuing lab.",
        "trust_levels": {
            "high": "Widely used and trusted across the research-peptide community; public/QR-verifiable COAs, strong track record.",
            "established_pharma_cro": "Reputable accredited contract labs oriented to manufacturers/regulatory work (cGMP/ICH).",
            "established_cro": "Credible accredited analytical labs (e.g. ISO 17025), less community-facing.",
            "moderate": "Recognized labs with a smaller or less-documented independent track record.",
            "emerging": "Newer platforms / accreditation pending; promising but unproven.",
            "untrusted": "Known bad actor."
        },
        "labs": labs,
        "vendors": []
    }
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {OUT}: {len(labs)} labs")
    print("Template owners (fingerprinted):",
          [l["id"] for l in labs if l["coa_template_owner"]])
    print("With verification portals:",
          [l["id"] for l in labs if "verification" in l])


if __name__ == "__main__":
    main()
