#!/usr/bin/env python3
"""Calibrate coa_rules.json weights against the coa-faker dataset.

For each rule the evaluator emits one of:
  - True  -> rule "fires" (flags the document as suspicious)
  - False -> rule passes (document looks legit per this rule)
  - None  -> rule is not programmatically evaluable on this corpus

The corpus is image-only PDFs from coa-faker, so any rule that needs OCR of
the COA body text is marked non-evaluable. Calibration focuses on signals
that are actually present: PDF metadata, page structure, image stats,
and local image quality.

Note: the keyword field on fakes contains "X-Synthetic-Training-Data" — that
is a label leak from the generator, NOT a real-world signal, so the
evaluator explicitly ignores it.
"""
from __future__ import annotations
import io
import json
import os
import random
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import fitz  # PyMuPDF
import numpy as np
from PIL import Image
import pytesseract

ROOT = Path("/mnt/d/DIRECTORY/Peptides")
DATA = ROOT / "coa-faker" / "output"
RULES_PATH = ROOT / "Rules" / "coa_rules.json"
OUT_DIR = ROOT / "Rules" / "calibration"
OCR_CACHE = OUT_DIR / "ocr_cache"
def _today() -> datetime:
    """Current date for date-plausibility rules (META-003 / XREF-004 / NUM-006).

    Defaults to the real current date so genuine COAs dated after any fixed
    build date are not flagged 'future-dated'. Set COA_TODAY=YYYY-MM-DD to pin it
    (e.g. for reproducible calibration runs against the frozen corpus)."""
    override = os.environ.get("COA_TODAY")
    if override:
        try:
            return datetime.strptime(override.strip(), "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


# Snapshot at import — used only for calibration-report timestamps. The live
# date-plausibility rules call _today() so a long-running server never goes stale.
TODAY = _today()
OCR_DPI = 200

RANDOM_SEED = 7
SAMPLE_N = 100

# Known orig file basenames (so we can look up baseline page count etc.)
ORIG_INDEX: dict[str, Path] = {}
ORIG_FEATURES: dict[str, dict] = {}


# ---------- feature extraction ----------------------------------------------
def parse_pdf_date(s: str) -> datetime | None:
    if not s:
        return None
    m = re.match(r"D:(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?", s)
    if not m:
        return None
    parts = [int(x) if x else 0 for x in m.groups()]
    try:
        return datetime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], tzinfo=timezone.utc)
    except ValueError:
        return None


def page_image_quality(arr: np.ndarray) -> dict:
    """Block-wise sharpness/variance to detect localized blur/JPEG damage."""
    if arr.ndim == 3:
        gray = arr.mean(axis=2)
    else:
        gray = arr.astype(np.float32)
    h, w = gray.shape
    bs = 128  # block size
    sharps = []
    means = []
    for y in range(0, h - bs, bs):
        for x in range(0, w - bs, bs):
            blk = gray[y : y + bs, x : x + bs]
            # use laplacian-like: variance of pixel-wise diff
            dx = np.diff(blk, axis=1)
            dy = np.diff(blk, axis=0)
            sharps.append(float(dx.var() + dy.var()))
            means.append(float(blk.mean()))
    if not sharps:
        return {}
    sharps_a = np.asarray(sharps)
    means_a = np.asarray(means)
    # only consider "content" blocks (not pure white margin)
    content_mask = means_a < 240
    content_sharps = sharps_a[content_mask] if content_mask.any() else sharps_a
    if len(content_sharps) < 4:
        content_sharps = sharps_a
    return {
        "blocks": int(len(sharps_a)),
        "content_blocks": int(content_mask.sum()),
        "sharp_mean": float(content_sharps.mean()),
        "sharp_std": float(content_sharps.std()),
        "sharp_cv": float(content_sharps.std() / (content_sharps.mean() + 1e-6)),
        "sharp_p10": float(np.percentile(content_sharps, 10)),
        "sharp_p90": float(np.percentile(content_sharps, 90)),
        "low_quality_block_frac": float((content_sharps < (content_sharps.mean() * 0.25)).mean()),
    }


def ocr_pdf(path: Path) -> str:
    """OCR all pages of a PDF, cached to disk."""
    OCR_CACHE.mkdir(parents=True, exist_ok=True)
    cache_file = OCR_CACHE / (path.name + ".txt")
    if cache_file.exists():
        return cache_file.read_text()
    d = fitz.open(path)
    parts = []
    for i in range(d.page_count):
        pix = d[i].get_pixmap(dpi=OCR_DPI)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        try:
            parts.append(pytesseract.image_to_string(img))
        except Exception as e:
            parts.append(f"[OCR_ERROR: {e}]")
    d.close()
    out = "\n\n--- PAGE BREAK ---\n\n".join(parts)
    cache_file.write_text(out)
    return out


def extract_features(path: Path) -> dict:
    d = fitz.open(path)
    meta = dict(d.metadata or {})
    feat: dict = {
        "path": str(path),
        "name": path.name,
        "pages": d.page_count,
        "meta": meta,
        "has_text_layer": False,
        "image_dpis": [],
        "image_dims": [],
        "image_jpeg": [],
        "page_quality": [],
        "blank_page_pages": 0,
        "duplicate_image_pages": 0,
    }
    seen_image_hashes: dict[bytes, int] = {}
    for i in range(d.page_count):
        page = d[i]
        if page.get_text().strip():
            feat["has_text_layer"] = True
        imgs = page.get_images(full=True)
        page_w, page_h = page.rect.width, page.rect.height  # in points (1/72")
        if not imgs:
            feat["blank_page_pages"] += 1
        seen_xref_this_page = set()
        for img in imgs:
            xref = img[0]
            if xref in seen_xref_this_page:
                continue  # same image referenced multiple times on page
            seen_xref_this_page.add(xref)
            try:
                base = d.extract_image(xref)
            except Exception:
                continue
            imbytes = base.get("image", b"")
            ext = base.get("ext", "")
            try:
                pil = Image.open(io.BytesIO(imbytes))
                w, h = pil.size
            except Exception:
                continue
            # rough dpi estimate from page size in points (72 pts/inch)
            dpi_w = w / (page_w / 72.0) if page_w else 0
            dpi_h = h / (page_h / 72.0) if page_h else 0
            feat["image_dims"].append([w, h])
            feat["image_dpis"].append(round((dpi_w + dpi_h) / 2.0))
            feat["image_jpeg"].append(ext == "jpeg")
            # duplicate detection by raw byte hash
            import hashlib
            h_ = hashlib.sha1(imbytes).digest()
            if h_ in seen_image_hashes:
                feat["duplicate_image_pages"] += 1
            seen_image_hashes[h_] = i
            # quality stats on first/main image of each page (largest)
            if len(feat["page_quality"]) <= i:
                try:
                    arr = np.asarray(pil.convert("L"))
                    feat["page_quality"].append(page_image_quality(arr))
                except Exception:
                    feat["page_quality"].append({})
    d.close()
    # OCR text + parsed semantic fields
    try:
        feat["ocr_text"] = ocr_pdf(path)
    except Exception as e:
        feat["ocr_text"] = ""
        feat["ocr_error"] = str(e)
    feat["semantic"] = parse_ocr(feat["ocr_text"])
    return feat


# ---------- OCR semantic parsing --------------------------------------------
KNOWN_PEPTIDES = [
    "bpc-157", "bpc157", "tb-500", "tb500", "thymosin",
    "semaglutide", "tirzepatide", "retatrutide", "cagrilintide",
    "ipamorelin", "cjc-1295", "ghrp", "hexarelin", "sermorelin",
    "tesamorelin", "ghk-cu", "ghkcu", "ghk", "kpv", "kisspeptin",
    "oxytocin", "glutathione", "snap-8", "snap8",
    "5-amino-1mq", "5amino1mq", "ahk", "vip", "dsip",
    "igf-1", "igf1lr3", "igf-1lr3", "mots-c", "motsc", "lipoc",
    "pt-141", "pt141", "epithalon", "epitalon", "ll-37",
    "melanotan", "selank", "semax", "noopept",
    "proviron", "anastrozole", "letrozole",
    "nad+", "nad", "humanin", "fragment 176-191",
]

LAB_KEYWORDS = [
    "laborator", "laboratoire", "labs", "analytic", "diagnostics",
    "janoshik", "colmaric", "vanguard", "freedom diagnostics",
    "qc", "quality control", "tested by",
]


def parse_ocr(text: str) -> dict:
    """Extract semantic fields from OCR'd COA text."""
    t = text or ""
    low = t.lower()
    s: dict = {}

    # peptide name
    s["peptide_name_found"] = next((p for p in KNOWN_PEPTIDES if p in low), None)

    # batch / lot number — look near 'batch' or 'lot' label, or ERL-style codes
    batch = None
    m = re.search(r"\b(?:batch|lot)\s*(?:no\.?|number|#|:)?\s*([A-Z0-9][A-Z0-9_\-/]{2,30})", t, re.I)
    if m:
        batch = m.group(1).strip(".,:")
    if not batch:
        m = re.search(r"\b([A-Z]{2,4}-?\d{3,5}[-_/]?[A-Z0-9]{1,10}[-_/]?[A-Z0-9]{0,10})\b", t)
        if m:
            batch = m.group(1)
    s["batch"] = batch

    # dates. Bound the year to a plausible COA window so instrument timestamps
    # (e.g. an "HH-MM-SS" trace caption like "14-06-57") can't be parsed as a
    # far-future date (year 2057) and trip the chronology rules.
    dates = []
    _yr_lo, _yr_hi = 2015, _today().year + 1
    for m in re.finditer(r"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b", t):
        a, b, yy = m.groups()
        try:
            a_i, b_i, yy_i = int(a), int(b), int(yy)
            if yy_i < 100:
                yy_i += 2000
            if not (_yr_lo <= yy_i <= _yr_hi):
                continue
            # Prefer US M/D/Y (first=month, second=day); fall back to D/M/Y only
            # when month-first is invalid (e.g. "25/12/2025"). Ambiguous dates
            # like 6/11 resolve to the US reading (June 11), not 6 November.
            cand = None
            if 1 <= a_i <= 12 and 1 <= b_i <= 31:
                cand = datetime(yy_i, a_i, b_i, tzinfo=timezone.utc)
            elif 1 <= b_i <= 12 and 1 <= a_i <= 31:
                cand = datetime(yy_i, b_i, a_i, tzinfo=timezone.utc)
            if cand:
                dates.append(cand)
        except ValueError:
            pass
    for m in re.finditer(r"\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b", t):
        yy, mm, dd = m.groups()
        try:
            dt = datetime(int(yy), int(mm), int(dd), tzinfo=timezone.utc)
            if _yr_lo <= dt.year <= _yr_hi:
                dates.append(dt)
        except ValueError:
            pass
    s["dates"] = dates
    s["latest_date"] = max(dates) if dates else None
    s["earliest_date"] = min(dates) if dates else None

    # purity percentages
    purities = []
    for m in re.finditer(r"(\d{1,3}(?:\.\d{1,4})?)\s*%", t):
        try:
            v = float(m.group(1))
            if 50.0 <= v <= 105.0:
                purities.append(v)
        except ValueError:
            pass
    s["purities"] = purities
    s["max_purity"] = max(purities) if purities else None

    # lab name presence
    s["has_lab_keyword"] = any(k in low for k in LAB_KEYWORDS)

    # MS / HPLC method mentions
    s["has_hplc"] = bool(re.search(r"\bhplc\b|high[- ]performance liquid", low))
    s["has_ms"] = bool(re.search(r"\bms\b|mass spec|m/z|esi[- ]ms|maldi", low))
    s["has_c18"] = "c18" in low or "c-18" in low
    s["has_iso17025"] = bool(re.search(r"iso[\s/\-]*(?:iec)?[\s/\-]*17025", low))

    return s


# ---------- per-rule evaluators ---------------------------------------------
# Each evaluator returns True (flagged), False (passes), or None (n/a).

def _generic_creator(meta: dict) -> bool:
    """Creator/producer looks consumer-grade or like a generic forger fingerprint."""
    creator = (meta.get("creator") or "").lower()
    producer = (meta.get("producer") or "").lower()
    blob = f"{creator} {producer}"
    suspicious = ["microsoft word", "word", "openoffice", "libreoffice writer",
                  "google docs", "canva", "photoshop", "gimp", "preview"]
    return any(s in blob for s in suspicious)


def _author_is_personal_name(meta: dict) -> bool:
    a = (meta.get("author") or "").strip()
    if not a:
        return False
    # personal-name pattern: "First Last"
    return bool(re.match(r"^[A-Z][a-z]+ [A-Z][a-z]+$", a))


def eval_rule(rule_id: str, feat: dict, source_feat: dict | None) -> bool | None:
    meta = feat["meta"]
    creation = parse_pdf_date(meta.get("creationDate", ""))
    mod = parse_pdf_date(meta.get("modDate", ""))
    sem = feat.get("semantic", {}) or {}
    text = feat.get("ocr_text", "") or ""
    low = text.lower()

    # ------------------- METADATA --------------------
    if rule_id == "META-001":  # PDF creation date consistent with analysis date
        # can't read analysis date without OCR; mark n/a
        return None
    if rule_id == "META-002":  # authoring software is professional lab/document tool
        # flag if creator/producer is consumer or personal-name author
        if _generic_creator(meta) or _author_is_personal_name(meta):
            return True
        return False
    if rule_id == "META-003":  # no future-dated analysis
        if creation and creation > _today():
            return True
        return False
    if rule_id == "META-004":  # mod history clean (modDate ~ creationDate)
        if not creation or not mod:
            return None
        delta = abs((mod - creation).total_seconds())
        # Allow up to 1 day of slack (timezones, batch processing) — originals
        # in this corpus routinely differ by ~7h due to mixed-TZ stamps.
        return delta > 86400
    if rule_id == "META-005":  # batch-specific, not generic template
        b = sem.get("batch") or ""
        if not b:
            return None
        return bool(re.fullmatch(r"(?:BATCH|LOT)?[\-_]?0*1?(?:23)?", b, re.I)) or b.lower() in ("batch-001", "lot-001", "001", "123")

    # ------------------- CONTENT (OCR-backed) ---------
    # STRUCT-* presence rules: fire (=flag suspicious) when expected field is absent
    if rule_id == "STRUCT-001":  # product name present
        return sem.get("peptide_name_found") is None
    if rule_id == "STRUCT-002":  # batch/lot present
        return sem.get("batch") is None
    if rule_id == "STRUCT-003":  # analysis date present
        return not sem.get("dates")
    if rule_id == "STRUCT-004":  # lab name present
        return not sem.get("has_lab_keyword")
    if rule_id == "STRUCT-005":  # lab address — fire if no comma-separated city/country pattern
        return not bool(re.search(r"\b(USA|UK|Germany|China|Canada|EU|Switzerland|Spain|Italy)\b", text, re.I))
    if rule_id == "STRUCT-006":  # contact info: email/phone/url
        return not bool(re.search(r"[\w.+\-]+@[\w\-]+\.[\w.\-]+|https?://|www\.[\w\-]+|\+?\d[\d\s\-()]{7,}", text))
    if rule_id == "STRUCT-007":  # signature/certification
        return not bool(re.search(r"signature|approved|certified|analyst|sign", low))
    if rule_id == "STRUCT-008":  # purity as numerical value
        return not sem.get("purities")
    if rule_id == "STRUCT-009":  # MS identity confirmation
        return not sem.get("has_ms")
    if rule_id == "STRUCT-010":  # pass/fail determination
        return not bool(re.search(r"\bpass\b|\bfail\b|conform|meets specification", low))
    if rule_id == "STRUCT-011":  # sample receipt + test date — flag if <2 distinct dates
        return len({d.date() for d in sem.get("dates", [])}) < 2
    if rule_id == "STRUCT-012":  # client/supplier name on COA
        return not bool(re.search(r"\bclient\b|\bsupplier\b|\bcustomer\b|prepared for|requested by", low))

    # NUM-* numerical thresholds
    if rule_id == "NUM-001":  # HPLC purity >= 95%
        mp = sem.get("max_purity")
        if mp is None:
            return None
        return mp < 95.0
    if rule_id == "NUM-002":  # non-round purity (has decimal)
        purs = sem.get("purities") or []
        if not purs:
            return None
        # flag (suspicious) if every purity value is an integer
        return all(abs(p - round(p)) < 0.01 for p in purs)
    if rule_id == "NUM-003":  # purity <= 100%
        mp = sem.get("max_purity")
        if mp is None:
            return None
        return mp > 100.0
    if rule_id == "NUM-004":  # MS error within tolerance — need theoretical mass; skip
        return None
    if rule_id == "NUM-005":  # net peptide content range — skip
        return None
    if rule_id == "NUM-006":  # COA age within window (<= 2 years)
        ld = sem.get("latest_date")
        if not ld:
            return None
        return (_today() - ld).days > 730
    if rule_id == "NUM-007":  # HPLC wavelength standard (210/214/220/280 nm)
        m = re.search(r"(\d{3})\s*nm", low)
        if not m:
            return None
        nm = int(m.group(1))
        return nm not in (210, 214, 220, 230, 254, 280)
    if rule_id == "NUM-008":  # trace impurity peaks — flag if claim ≥99% but no impurity mention
        mp = sem.get("max_purity")
        if mp is None or mp < 99.0:
            return None
        return "impurit" not in low
    if rule_id == "NUM-009":  # endotoxin threshold
        if "endotoxin" not in low:
            return None
        return False  # mentioned at all = pass for this rough check
    if rule_id == "NUM-010":  # MW in reference range — skip (needs theoretical lookup)
        return None
    if rule_id == "NUM-011":
        return None

    # METH-* method declarations
    if rule_id == "METH-001":  # HPLC method named
        return not sem.get("has_hplc")
    if rule_id == "METH-002":  # MS method named
        return not sem.get("has_ms")
    if rule_id == "METH-003":  # reversed-phase C18
        return not sem.get("has_c18")
    if rule_id == "METH-004":  # mobile phase
        return not bool(re.search(r"mobile phase|acetonitril|tfa\b|formic acid|0\.1\s*%", low))
    if rule_id == "METH-005":  # MS technique type
        return not bool(re.search(r"esi|maldi|q-?tof|orbitrap|triple quad", low))
    if rule_id == "METH-006":  # chromatogram data attached
        return not bool(re.search(r"chromatogram|retention time|\bmin\b", low))
    if rule_id in ("METH-007", "METH-008"):
        return None
    if rule_id == "METH-009":  # ESI-MS charge states
        return None
    if rule_id == "METH-010":  # net peptide content method
        return "net peptide" not in low
    if rule_id == "METH-011":  # heavy metals by ICP-MS
        return not bool(re.search(r"heavy metal|icp[\-\s]?ms", low))
    if rule_id == "METH-012":  # endotoxin by LAL
        return not bool(re.search(r"\blal\b|endotoxin", low))

    # LAB-* credentials
    if rule_id == "LAB-001":  # third-party independent lab — flag if 'in-house' or 'internal'
        return bool(re.search(r"in[- ]?house|internal lab", low))
    if rule_id == "LAB-002":  # ISO/IEC 17025
        return not sem.get("has_iso17025")
    if rule_id == "LAB-003":  # correct accreditation terminology — flag bad phrasing
        return bool(re.search(r"iso certified|iso-certified", low)) and not sem.get("has_iso17025")
    if rule_id in ("LAB-004", "LAB-005", "LAB-006", "LAB-007", "LAB-008", "LAB-009", "LAB-010"):
        return None  # need external verification

    # ------------------- FORMATTING / FORENSIC --------
    if rule_id == "FMT-001":  # overall clarity
        q = feat.get("page_quality", [])
        if not q or not q[0]:
            return None
        return q[0].get("sharp_mean", 0) < 30  # heuristic low sharpness
    if rule_id == "FMT-002":  # uniform resolution across pages/images
        dpis = feat.get("image_dpis", [])
        if len(dpis) < 2:
            return None  # not applicable
        rng = max(dpis) - min(dpis)
        return rng > 50
    if rule_id == "FMT-003":  # font consistency — image-only PDFs: flag if text layer appears (font_mismatch perturbation)
        if feat.get("has_text_layer"):
            return True
        return False
    if rule_id == "FMT-004":  # alignment consistent — needs reference
        return None
    if rule_id == "FMT-005":  # no clone-stamp/copy-paste artifacts
        # symmetric: flag if duplicate image bytes appear within doc
        return feat.get("duplicate_image_pages", 0) > 0
    if rule_id == "FMT-006":  # signature appears natural — n/a without reference signature library
        return None
    if rule_id == "FMT-007":
        return None
    if rule_id == "FMT-008":  # document fully accessible
        return False  # we successfully opened it

    # XREF rules
    if rule_id == "XREF-001":  # batch matches vial — no vial reference; skip
        return None
    if rule_id == "XREF-002":  # MS mass matches theoretical — need MW lookup; skip
        return None
    if rule_id == "XREF-003":  # vendor name on COA matches known vendor — skip
        return None
    if rule_id == "XREF-004":  # all dates chronologically plausible
        ds = sem.get("dates") or []
        if len(ds) < 2:
            return None
        # plausibility: no date in the future, span <= 1 year
        if any(d > _today() for d in ds):
            return True
        span = (max(ds) - min(ds)).days
        return span > 365
    if rule_id in ("XREF-005", "XREF-006", "XREF-007", "XREF-008"):
        return None

    # FORGERY indicators
    if rule_id == "FORG-001":  # suspiciously round purity
        purs = sem.get("purities") or []
        if not purs:
            return None
        mp = max(purs)
        return abs(mp - round(mp)) < 0.01 and round(mp) in (98, 99, 100)
    if rule_id == "FORG-002":  # zero impurity claim with sub-100% purity
        mp = sem.get("max_purity")
        if mp is None:
            return None
        if not (95.0 <= mp < 100.0):
            return None
        return "impurit" not in low and "related substance" not in low
    if rule_id == "FORG-003":  # exact theoretical MS match w/ zero error
        return bool(re.search(r"\b0\.000\s*(?:da|ppm)\b|\berror[: ]*0\b", low)) or False
    if rule_id == "FORG-004":  # identical structure across peptides — corpus-level, skip
        return None
    if rule_id == "FORG-005":  # identical retention times across peptides — corpus-level, skip
        return None
    if rule_id == "FORG-006":  # blurry stamps with sharp surroundings
        q = feat.get("page_quality", [])
        if not q or not q[0]:
            return None
        cv = q[0].get("sharp_cv", 0)
        # high coefficient of variation in sharpness across content blocks
        return cv > 1.8
    if rule_id == "FORG-007":  # localized pixelation in specific fields
        q = feat.get("page_quality", [])
        if not q or not q[0]:
            return None
        # fraction of content blocks much less sharp than the mean (compression patches)
        return q[0].get("low_quality_block_frac", 0) > 0.08
    if rule_id == "FORG-008":  # generic/sequential batch numbers
        b = sem.get("batch")
        if not b:
            return None
        return bool(re.fullmatch(r"\d{1,3}|0*\d{1,3}|BATCH-?0*\d{1,3}|LOT-?0*\d{1,3}", b, re.I))
    if rule_id in ("FORG-009", "FORG-010", "FORG-011", "FORG-012", "FORG-013", "FORG-014", "FORG-015"):
        return None  # require corpus-/market-level signals outside this PDF

    return None


# ---------- main calibration -------------------------------------------------
def build_orig_index() -> None:
    # Map source basename -> orig PDF path (so fakes can be paired)
    for p in DATA.iterdir():
        if p.name.startswith("orig_") and p.suffix == ".pdf":
            # source filename is encoded in name as orig_NNNN_<basename>
            base = re.sub(r"^orig_\d+_", "", p.name)
            ORIG_INDEX[base] = p


def main() -> int:
    rules = json.loads(RULES_PATH.read_text())
    all_rules = []
    for cat, rs in rules["categories"].items():
        for r in rs:
            r["_category"] = cat
            all_rules.append(r)

    # Index originals
    build_orig_index()
    print(f"orig index size: {len(ORIG_INDEX)}", file=sys.stderr)

    # Load fake details to pair with sources
    fake_details: dict[str, dict] = {}
    with open(DATA / "details.jsonl") as f:
        for line in f:
            d = json.loads(line)
            fake_details[d["filename"]] = d

    rng = random.Random(RANDOM_SEED)

    origs_all = sorted(p.name for p in DATA.iterdir() if p.name.startswith("orig_"))
    fakes_all = sorted(p.name for p in DATA.iterdir() if p.name.startswith("fake_"))

    orig_sample = rng.sample(origs_all, min(SAMPLE_N, len(origs_all)))

    # Stratified fake sample by difficulty
    by_diff = defaultdict(list)
    for f in fakes_all:
        d = fake_details.get(f)
        if d:
            by_diff[d["difficulty"]].append(f)
    fake_sample = []
    # roughly proportional, totaling 100
    diff_props = {"easy": 33, "medium": 47, "hard": 20}
    for diff, n in diff_props.items():
        avail = by_diff.get(diff, [])
        fake_sample.extend(rng.sample(avail, min(n, len(avail))))
    # pad to 100 if needed
    while len(fake_sample) < SAMPLE_N:
        cand = rng.choice(fakes_all)
        if cand not in fake_sample:
            fake_sample.append(cand)

    print(f"orig sample: {len(orig_sample)}, fake sample: {len(fake_sample)}", file=sys.stderr)

    # Extract features
    feats: dict[str, dict] = {}
    for name in orig_sample + fake_sample:
        try:
            feats[name] = extract_features(DATA / name)
        except Exception as e:
            print(f"  ! {name}: {e}", file=sys.stderr)

    # Pre-extract source features for fakes (cache)
    src_cache: dict[str, dict] = {}
    for fk in fake_sample:
        d = fake_details.get(fk, {})
        src_base = d.get("source_file")
        if src_base and src_base in ORIG_INDEX:
            sp = ORIG_INDEX[src_base]
            if sp.name not in src_cache:
                try:
                    src_cache[sp.name] = extract_features(sp)
                except Exception:
                    src_cache[sp.name] = None
        else:
            pass

    # Apply rules
    results = {r["rule_id"]: {"fake_fired": 0, "fake_total": 0, "fake_na": 0,
                              "orig_fired": 0, "orig_total": 0, "orig_na": 0}
               for r in all_rules}

    for name in orig_sample:
        f = feats.get(name)
        if not f:
            continue
        for r in all_rules:
            v = eval_rule(r["rule_id"], f, None)
            rec = results[r["rule_id"]]
            if v is None:
                rec["orig_na"] += 1
            else:
                rec["orig_total"] += 1
                if v:
                    rec["orig_fired"] += 1

    for name in fake_sample:
        f = feats.get(name)
        if not f:
            continue
        d = fake_details.get(name, {})
        src_base = d.get("source_file")
        src_feat = None
        if src_base and src_base in ORIG_INDEX:
            src_feat = src_cache.get(ORIG_INDEX[src_base].name)
        for r in all_rules:
            v = eval_rule(r["rule_id"], f, src_feat)
            rec = results[r["rule_id"]]
            if v is None:
                rec["fake_na"] += 1
            else:
                rec["fake_total"] += 1
                if v:
                    rec["fake_fired"] += 1

    # Compute discrimination & recalibrated weights
    calib_rows = []
    for r in all_rules:
        rid = r["rule_id"]
        rec = results[rid]
        orig_rate = rec["orig_fired"] / rec["orig_total"] if rec["orig_total"] else None
        fake_rate = rec["fake_fired"] / rec["fake_total"] if rec["fake_total"] else None
        evaluable = rec["orig_total"] + rec["fake_total"] > 0
        if evaluable and orig_rate is not None and fake_rate is not None:
            discrim = fake_rate - orig_rate  # Youden's J for binary classifier
        else:
            discrim = None
        original_w = r.get("weight", 5)
        # Calibration policy:
        # - non-evaluable rules: keep original weight, mark status
        # - evaluable & discrim > 0: scale weight up to +50% capped at 10
        # - evaluable & discrim ~ 0 (|d|<0.05): leave weight (rule fires equally on both -> noise)
        # - evaluable & discrim < -0.05: rule is anti-discriminative -> downweight by 50%
        # The scaling factor: 1 + clip(discrim, -1, 1) * 0.6
        if discrim is None:
            new_w = original_w
            note = "non-evaluable (needs OCR or external verification)"
        else:
            if abs(discrim) < 0.05:
                new_w = original_w
                note = "no discrimination signal (noise)"
            elif discrim < 0:
                factor = 1.0 + discrim * 0.5  # downweight
                new_w = max(1.0, round(original_w * factor, 2))
                note = "anti-discriminative; downweighted"
            else:
                factor = 1.0 + discrim * 0.6
                new_w = min(10.0, round(original_w * factor, 2))
                note = "discriminative; upweighted"
        calib_rows.append({
            "rule_id": rid,
            "category": r["_category"],
            "name": r["name"],
            "check_type": r.get("check_type"),
            "severity": r.get("severity"),
            "weight_original": original_w,
            "orig_total": rec["orig_total"],
            "orig_fired": rec["orig_fired"],
            "orig_fire_rate": round(orig_rate, 3) if orig_rate is not None else None,
            "fake_total": rec["fake_total"],
            "fake_fired": rec["fake_fired"],
            "fake_fire_rate": round(fake_rate, 3) if fake_rate is not None else None,
            "discrimination": round(discrim, 3) if discrim is not None else None,
            "weight_new": new_w,
            "note": note,
        })

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "calibration_results.json").write_text(
        json.dumps({
            "generated": TODAY.isoformat(),
            "sample_orig": len(orig_sample),
            "sample_fake": len(fake_sample),
            "fake_difficulty_breakdown": {k: sum(1 for x in fake_sample if fake_details.get(x, {}).get("difficulty") == k) for k in ("easy", "medium", "hard")},
            "rules": calib_rows,
        }, indent=2)
    )

    # Write updated rules
    updated = json.loads(RULES_PATH.read_text())
    rid_to_new = {r["rule_id"]: r for r in calib_rows}
    for cat, rs in updated["categories"].items():
        for r in rs:
            cr = rid_to_new.get(r["rule_id"])
            if cr:
                r["weight"] = cr["weight_new"]
                r["calibration"] = {
                    "fake_fire_rate": cr["fake_fire_rate"],
                    "orig_fire_rate": cr["orig_fire_rate"],
                    "discrimination": cr["discrimination"],
                    "note": cr["note"],
                    "weight_before": cr["weight_original"],
                }
    updated["version"] = "1.1-calibrated"
    updated["calibrated"] = TODAY.isoformat()
    updated["calibration_method"] = "Empirical fake-vs-orig flag-rate discrimination on 100+100 sample from coa-faker output. Non-evaluable rules retain original weight."
    (OUT_DIR / "coa_rules_calibrated.json").write_text(json.dumps(updated, indent=2))

    # Print summary table
    calib_rows.sort(key=lambda x: (x["discrimination"] is None, -(x["discrimination"] or -2)))
    print()
    print(f"{'RULE':12} {'CAT':18} {'W0':>4} {'W1':>5} {'ORIG':>6} {'FAKE':>6} {'D':>6}  NOTE")
    for r in calib_rows:
        d = f"{r['discrimination']:+.2f}" if r["discrimination"] is not None else "  n/a"
        of = f"{r['orig_fire_rate']:.2f}" if r["orig_fire_rate"] is not None else "  - "
        ff = f"{r['fake_fire_rate']:.2f}" if r["fake_fire_rate"] is not None else "  - "
        print(f"{r['rule_id']:12} {r['category']:18} {r['weight_original']:>4} {r['weight_new']:>5} {of:>6} {ff:>6} {d:>6}  {r['note']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
