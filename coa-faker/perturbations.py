"""
Perturbation functions for generating fake/tampered COA documents.

Contract: each `perturb_*(doc, rng, meta)` mutates `doc` in place and returns
either None (no-op on this doc) or a `dict` describing exactly what changed.
The dict always has a `type` key plus perturbation-specific fields:

  test_values:    {type, changes: [{page, bbox, old, new, pct}]}
  batch_number:   {type, page, bbox, old, new}
  dates:          {type, page, bbox, old, new, shift_days}
  names:          {type, page, bbox, old, new, mode: "vector"|"ocr"}
  font_mismatch:  {type, page, bbox, value, wrong_font}
  logo_shift:     {type, page, old_bbox, new_bbox, dx, dy}
  alignment:      {type, page, old_bbox, new_bbox, dx, dy, text}
  dpi_quality:    {type, pages, jpeg_quality, blur_radius}
  paper_cast:     {type, page, cast_rgb, alpha}
  contrast_noise: {type, page, contrast_factor, noise_sigma}
  jpeg_regions:   {type, page, regions: [{bbox_px, quality}]}
  stamp_repaste:  {type, page, source_bbox_px, dest_bbox_px, rotation, alpha}
  signature_shift:{type, page, old_bbox, new_bbox, dx, dy, rotation}
  metadata:       {type, fields, creation_date, mod_date, timestamp_inconsistent}
  page_structure_*: variant-specific (duplicated_page, old_order/new_order, ...)

All bboxes are PDF-point [x0,y0,x1,y1] unless suffixed `_px`.
"""

from __future__ import annotations

import io
import re
from datetime import datetime, timedelta
from typing import Optional

import fitz  # PyMuPDF
import numpy as np
from faker import Faker
from PIL import Image, ImageEnhance, ImageFilter

try:
    import pytesseract
    from pytesseract import Output as _TessOutput
    _HAS_TESS = True
except Exception:
    _HAS_TESS = False

_TESS_BINARY_OK = None


def _tesseract_available() -> bool:
    global _TESS_BINARY_OK
    if _TESS_BINARY_OK is not None:
        return _TESS_BINARY_OK
    if not _HAS_TESS:
        _TESS_BINARY_OK = False
        return False
    try:
        pytesseract.get_tesseract_version()
        _TESS_BINARY_OK = True
    except Exception:
        _TESS_BINARY_OK = False
    return _TESS_BINARY_OK


NUMBER_RE = re.compile(r"(?<![A-Za-z])(\d{1,4}(?:[.,]\d{1,4})?)(?![A-Za-z])")
DATE_RE = re.compile(
    r"\b(\d{1,2}[-/.\s](?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|\d{1,2})[-/.\s]\d{2,4}"
    r"|\d{4}[-/.]\d{1,2}[-/.]\d{1,2})\b",
    re.IGNORECASE,
)
BATCH_RE = re.compile(r"\b([A-Z]{0,3}\d{3,8}[A-Z0-9]{0,6})\b")


# ---------- helpers ----------

def _rect_to_list(rect: fitz.Rect):
    return [round(rect.x0, 2), round(rect.y0, 2),
            round(rect.x1, 2), round(rect.y1, 2)]


def _find_first_text(page: fitz.Page, pattern: re.Pattern):
    for block in page.get_text("dict")["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block["lines"]:
            for span in line["spans"]:
                m = pattern.search(span["text"])
                if m:
                    return (
                        fitz.Rect(span["bbox"]),
                        m.group(0),
                        span["text"],
                        span.get("font", "Helvetica"),
                        span.get("size", 10),
                    )
    return None


def _page_is_image_based(page: fitz.Page) -> bool:
    return len(page.get_text("text").strip()) == 0


def _ocr_page_words(page: fitz.Page, dpi: int = 200):
    if not _tesseract_available():
        return []
    pix = page.get_pixmap(dpi=dpi)
    img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    data = pytesseract.image_to_data(img, output_type=_TessOutput.DICT)
    scale = 72.0 / dpi
    results = []
    for i, txt in enumerate(data["text"]):
        if not txt or not txt.strip():
            continue
        try:
            conf = float(data["conf"][i])
        except (ValueError, TypeError):
            conf = -1
        if conf < 40:
            continue
        x = data["left"][i] * scale
        y = data["top"][i] * scale
        w = data["width"][i] * scale
        h = data["height"][i] * scale
        rect = fitz.Rect(x, y, x + w, y + h)
        est_pt = max(6, min(24, h * 0.85))
        results.append((txt, rect, est_pt))
    return results


def _find_first_ocr_match(page: fitz.Page, pattern: re.Pattern, dpi: int = 200):
    for txt, rect, sz in _ocr_page_words(page, dpi=dpi):
        m = pattern.search(txt)
        if m:
            return rect, m.group(0), txt, "Helvetica", sz
    return None


def _find_first_any(page: fitz.Page, pattern: re.Pattern, dpi: int = 200):
    hit = _find_first_text(page, pattern)
    if hit:
        return hit
    if _page_is_image_based(page):
        return _find_first_ocr_match(page, pattern, dpi=dpi)
    return None


def _replace_text_in_place(page: fitz.Page, rect: fitz.Rect, new: str,
                           size: float = 10, wrong_font: bool = False) -> None:
    page.draw_rect(rect, color=(1, 1, 1), fill=(1, 1, 1), width=0)
    use_font = "courier" if wrong_font else "helv"
    page.insert_text(
        (rect.x0, rect.y1 - 1.5),
        new,
        fontname=use_font,
        fontsize=size,
        color=(0, 0, 0),
    )


# ---------- data tampering ----------

def perturb_test_values(doc, rng, meta):
    changes = []
    for page_idx, page in enumerate(doc):
        hit = _find_first_any(page, NUMBER_RE, dpi=meta.get("render_dpi", 200))
        if not hit:
            continue
        rect, val_str, _, _, size = hit
        try:
            val = float(val_str.replace(",", "."))
        except ValueError:
            continue
        if val == 0:
            continue
        direction = rng.choice([-1, 1])
        pct = rng.uniform(0.05, 0.20)
        new_val = val * (1 + direction * pct)
        if "." in val_str or "," in val_str:
            decimals = len(val_str.split("." if "." in val_str else ",")[1])
            new_str = f"{new_val:.{decimals}f}"
        else:
            new_str = str(int(round(new_val)))
        _replace_text_in_place(page, rect, new_str, size=size)
        changes.append({
            "page": page_idx, "bbox": _rect_to_list(rect),
            "old": val_str, "new": new_str,
            "pct": round(direction * pct, 4),
        })
        if len(changes) >= 2:
            break
    if not changes:
        return None
    return {"type": "test_values", "changes": changes}


def perturb_batch_number(doc, rng, meta):
    for page_idx, page in enumerate(doc):
        hit = _find_first_any(page, BATCH_RE, dpi=meta.get("render_dpi", 200))
        if not hit:
            continue
        rect, batch, _, _, size = hit
        chars = list(batch)
        digit_idxs = [i for i, c in enumerate(chars) if c.isdigit()]
        if len(digit_idxs) >= 2:
            i, j = rng.sample(digit_idxs, 2)
            chars[i], chars[j] = chars[j], chars[i]
        new_batch = "".join(chars)
        _replace_text_in_place(page, rect, new_batch, size=size)
        return {
            "type": "batch_number", "page": page_idx,
            "bbox": _rect_to_list(rect), "old": batch, "new": new_batch,
        }
    return None


def perturb_dates(doc, rng, meta):
    for page_idx, page in enumerate(doc):
        hit = _find_first_any(page, DATE_RE, dpi=meta.get("render_dpi", 200))
        if not hit:
            continue
        rect, date_str, _, _, size = hit
        shift = rng.randint(7, 180) * rng.choice([-1, 1])
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y"):
            try:
                dt = datetime.strptime(date_str, fmt)
            except ValueError:
                continue
            new_dt = dt + timedelta(days=shift)
            new_fmt = rng.choice(["%d-%b-%Y", "%m/%d/%y", "%Y.%m.%d"])
            new_str = new_dt.strftime(new_fmt)
            _replace_text_in_place(page, rect, new_str, size=size)
            return {
                "type": "dates", "page": page_idx,
                "bbox": _rect_to_list(rect),
                "old": date_str, "new": new_str, "shift_days": shift,
            }
    return None


def perturb_names(doc, rng, meta):
    fake = meta["faker"]
    target_keywords = ("Analyst", "Reviewed", "Approved", "Tested by", "QA", "Signed")
    for page_idx, page in enumerate(doc):
        if not _page_is_image_based(page):
            for block in page.get_text("dict")["blocks"]:
                if block.get("type") != 0:
                    continue
                for line in block["lines"]:
                    line_text = "".join(s["text"] for s in line["spans"])
                    if not any(k.lower() in line_text.lower() for k in target_keywords):
                        continue
                    span = line["spans"][-1]
                    if len(span["text"].strip()) < 3:
                        continue
                    rect = fitz.Rect(span["bbox"])
                    new_name = fake.name()
                    _replace_text_in_place(page, rect, new_name,
                                           size=span.get("size", 10))
                    return {
                        "type": "names", "page": page_idx,
                        "bbox": _rect_to_list(rect),
                        "old": span["text"], "new": new_name,
                        "mode": "vector",
                    }
            continue
        words = _ocr_page_words(page, dpi=meta.get("render_dpi", 200))
        for idx, (txt, rect, sz) in enumerate(words):
            if not any(k.lower() in txt.lower() for k in target_keywords):
                continue
            row_y = rect.y0
            tail = [w for w in words[idx + 1: idx + 6]
                    if abs(w[1].y0 - row_y) < (rect.height * 0.8)]
            if not tail:
                continue
            target_rect = fitz.Rect(
                tail[0][1].x0, tail[0][1].y0,
                tail[-1][1].x1, tail[-1][1].y1,
            )
            new_name = fake.name()
            _replace_text_in_place(page, target_rect, new_name, size=sz)
            return {
                "type": "names", "page": page_idx,
                "bbox": _rect_to_list(target_rect),
                "old": " ".join(w[0] for w in tail),
                "new": new_name, "mode": "ocr",
            }
    return None


# ---------- visual tampering ----------

def perturb_font_mismatch(doc, rng, meta):
    for page_idx, page in enumerate(doc):
        hit = _find_first_any(page, NUMBER_RE, dpi=meta.get("render_dpi", 200))
        if not hit:
            continue
        rect, val_str, _, _, size = hit
        _replace_text_in_place(page, rect, val_str, size=size, wrong_font=True)
        return {
            "type": "font_mismatch", "page": page_idx,
            "bbox": _rect_to_list(rect),
            "value": val_str, "wrong_font": "courier",
        }
    return None


def perturb_logo_shift(doc, rng, _meta):
    page = doc[0]
    images = page.get_images(full=True)
    if not images:
        return None
    xref = images[0][0]
    img_rects = list(page.get_image_rects(xref))
    if not img_rects:
        return None
    rect = img_rects[0]
    pix = fitz.Pixmap(doc, xref)
    dx = rng.choice([-8, -5, 5, 8])
    dy = rng.choice([-8, -5, 5, 8])
    page.draw_rect(rect, color=(1, 1, 1), fill=(1, 1, 1), width=0)
    new_rect = fitz.Rect(rect.x0 + dx, rect.y0 + dy,
                         rect.x1 + dx, rect.y1 + dy)
    try:
        page.insert_image(new_rect, pixmap=pix)
    except Exception:
        return None
    return {
        "type": "logo_shift", "page": 0,
        "old_bbox": _rect_to_list(rect),
        "new_bbox": _rect_to_list(new_rect),
        "dx": dx, "dy": dy,
    }


def perturb_alignment(doc, rng, _meta):
    page_idx = rng.randrange(len(doc))
    page = doc[page_idx]
    blocks = [b for b in page.get_text("dict")["blocks"] if b.get("type") == 0]
    if not blocks:
        return None
    block = rng.choice(blocks)
    if not block["lines"] or not block["lines"][0]["spans"]:
        return None
    span = rng.choice(block["lines"][0]["spans"])
    if not span["text"].strip():
        return None
    rect = fitz.Rect(span["bbox"])
    dx = rng.choice([-3, -2, 2, 3])
    dy = rng.choice([-2, -1, 1, 2])
    new_rect = fitz.Rect(rect.x0 + dx, rect.y0 + dy,
                         rect.x1 + dx, rect.y1 + dy)
    _replace_text_in_place(page, rect, "", size=span.get("size", 10))
    page.insert_text((new_rect.x0, new_rect.y1 - 1.5), span["text"],
                     fontname="helv", fontsize=span.get("size", 10),
                     color=(0, 0, 0))
    return {
        "type": "alignment", "page": page_idx,
        "old_bbox": _rect_to_list(rect),
        "new_bbox": _rect_to_list(new_rect),
        "dx": dx, "dy": dy, "text": span["text"],
    }


def perturb_dpi_quality(doc, rng, meta):
    dpi = meta.get("render_dpi", 300)
    quality = rng.randint(35, 55)
    blur = round(rng.uniform(0.3, 0.8), 2)
    new_doc = fitz.open()
    for page in doc:
        pix = page.get_pixmap(dpi=dpi)
        img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
        img = img.filter(ImageFilter.GaussianBlur(radius=blur))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality)
        new_page = new_doc.new_page(width=page.rect.width,
                                    height=page.rect.height)
        new_page.insert_image(new_page.rect, stream=buf.getvalue())
    n = len(doc)
    doc.delete_pages(0, n - 1)
    doc.insert_pdf(new_doc)
    new_doc.close()
    return {
        "type": "dpi_quality", "pages": list(range(n)),
        "jpeg_quality": quality, "blur_radius": blur,
    }


# ---------- image-level ----------

def _rasterize_page_to_pil(page: fitz.Page, dpi: int):
    pix = page.get_pixmap(dpi=dpi)
    return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def _replace_page_with_image(doc, page_index, img, quality: int = 92):
    page = doc[page_index]
    w, h = page.rect.width, page.rect.height
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    new_doc = fitz.open()
    new_page = new_doc.new_page(width=w, height=h)
    new_page.insert_image(new_page.rect, stream=buf.getvalue())
    doc.delete_page(page_index)
    doc.insert_pdf(new_doc, start_at=page_index)
    new_doc.close()


def perturb_paper_cast(doc, rng, meta):
    dpi = meta.get("render_dpi", 200)
    cast = rng.choice([(252, 248, 230), (245, 240, 232), (240, 240, 245)])
    alpha = round(rng.uniform(0.08, 0.18), 3)
    page_idx = rng.randrange(len(doc))
    img = _rasterize_page_to_pil(doc[page_idx], dpi).convert("RGB")
    overlay = Image.new("RGB", img.size, cast)
    blended = Image.blend(img, overlay, alpha)
    _replace_page_with_image(doc, page_idx, blended, quality=90)
    return {"type": "paper_cast", "page": page_idx,
            "cast_rgb": list(cast), "alpha": alpha}


def perturb_contrast_noise(doc, rng, meta):
    dpi = meta.get("render_dpi", 200)
    page_idx = rng.randrange(len(doc))
    contrast_factor = round(rng.uniform(1.08, 1.25), 3)
    noise_sigma = round(rng.uniform(4, 10), 2)
    img = _rasterize_page_to_pil(doc[page_idx], dpi).convert("RGB")
    img = ImageEnhance.Contrast(img).enhance(contrast_factor)
    arr = np.asarray(img).astype(np.int16)
    noise = np.random.default_rng(rng.randint(0, 2**31)).normal(
        0, noise_sigma, arr.shape
    ).astype(np.int16)
    arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
    _replace_page_with_image(doc, page_idx, Image.fromarray(arr), quality=88)
    return {"type": "contrast_noise", "page": page_idx,
            "contrast_factor": contrast_factor, "noise_sigma": noise_sigma}


def perturb_jpeg_regions(doc, rng, meta):
    dpi = meta.get("render_dpi", 200)
    page_idx = rng.randrange(len(doc))
    img = _rasterize_page_to_pil(doc[page_idx], dpi).convert("RGB")
    W, H = img.size
    regions = []
    for _ in range(rng.randint(1, 2)):
        rw = rng.randint(W // 6, W // 3)
        rh = rng.randint(H // 10, H // 4)
        rx = rng.randint(0, W - rw)
        ry = rng.randint(0, H - rh)
        q = rng.randint(18, 32)
        crop = img.crop((rx, ry, rx + rw, ry + rh))
        buf = io.BytesIO()
        crop.save(buf, format="JPEG", quality=q)
        buf.seek(0)
        degraded = Image.open(buf).convert("RGB")
        img.paste(degraded, (rx, ry))
        regions.append({"bbox_px": [rx, ry, rx + rw, ry + rh], "quality": q})
    _replace_page_with_image(doc, page_idx, img, quality=90)
    return {"type": "jpeg_regions", "page": page_idx,
            "render_dpi": dpi, "regions": regions}


def perturb_stamp_repaste(doc, rng, meta):
    dpi = meta.get("render_dpi", 200)
    page_idx = rng.randrange(len(doc))
    img = _rasterize_page_to_pil(doc[page_idx], dpi).convert("RGBA")
    W, H = img.size
    rx = rng.randint(W // 2, int(W * 0.75))
    ry = rng.randint(int(H * 0.65), int(H * 0.85))
    rw = rng.randint(W // 6, W // 4)
    rh = rng.randint(H // 14, H // 8)
    rw = min(rw, W - rx - 5)
    rh = min(rh, H - ry - 5)
    if rw < 30 or rh < 15:
        return None
    rotation = round(rng.uniform(-4, 4), 2)
    crop = img.crop((rx, ry, rx + rw, ry + rh))
    crop = crop.rotate(rotation, resample=Image.BICUBIC, expand=True)
    alpha = crop.split()[-1].point(lambda a: int(a * 0.55))
    crop.putalpha(alpha)
    dx = rng.choice([-1, 1]) * rng.randint(8, 22)
    dy = rng.choice([-1, 1]) * rng.randint(6, 18)
    img.paste(crop, (rx + dx, ry + dy), crop)
    _replace_page_with_image(doc, page_idx, img.convert("RGB"), quality=90)
    return {
        "type": "stamp_repaste", "page": page_idx, "render_dpi": dpi,
        "source_bbox_px": [rx, ry, rx + rw, ry + rh],
        "dest_bbox_px": [rx + dx, ry + dy, rx + dx + rw, ry + dy + rh],
        "rotation": rotation, "alpha": 0.55,
    }


def perturb_signature_shift(doc, rng, _meta):
    for page_idx, page in enumerate(doc):
        images = page.get_images(full=True)
        if not images:
            continue
        candidates = []
        for img_info in images:
            xref = img_info[0]
            for rect in page.get_image_rects(xref):
                ph = page.rect.height
                if (rect.height < ph * 0.18 and
                        rect.width / max(rect.height, 1) > 2.0 and
                        rect.y0 > ph * 0.5):
                    candidates.append((xref, rect))
        if not candidates:
            continue
        xref, rect = rng.choice(candidates)
        pix = fitz.Pixmap(doc, xref)
        page.draw_rect(rect, color=(1, 1, 1), fill=(1, 1, 1), width=0)
        dx = rng.choice([-1, 1]) * rng.randint(6, 15)
        dy = rng.choice([-1, 1]) * rng.randint(4, 10)
        rotation = rng.choice([0, 0, 0, 90, 270])
        new_rect = fitz.Rect(rect.x0 + dx, rect.y0 + dy,
                             rect.x1 + dx, rect.y1 + dy)
        try:
            page.insert_image(new_rect, pixmap=pix, rotate=rotation)
        except Exception:
            return None
        return {
            "type": "signature_shift", "page": page_idx,
            "old_bbox": _rect_to_list(rect),
            "new_bbox": _rect_to_list(new_rect),
            "dx": dx, "dy": dy, "rotation": rotation,
        }
    return None


# ---------- metadata tampering ----------

def perturb_metadata(doc, rng, meta):
    fake = meta["faker"]
    md = doc.metadata or {}
    new_author = fake.name()
    new_producer = rng.choice([
        "Microsoft Word 2019", "LibreOffice 6.4", "Foxit PhantomPDF",
        "Adobe Acrobat 11.0", "iText 5.5.13",
    ])
    new_creator = rng.choice(["Word", "PDFCreator", "Acrobat Pro"])
    base = datetime.now() - timedelta(days=rng.randint(30, 400))
    creation = base.strftime("D:%Y%m%d%H%M%S+00'00'")
    mod = (base - timedelta(days=rng.randint(5, 60))).strftime(
        "D:%Y%m%d%H%M%S+00'00'"
    )
    prev = {k: md.get(k) for k in
            ("author", "producer", "creator", "creationDate", "modDate")}
    md["author"] = new_author
    md["producer"] = new_producer
    md["creator"] = new_creator
    md["creationDate"] = creation
    md["modDate"] = mod
    doc.set_metadata(md)
    return {
        "type": "metadata",
        "fields": {
            "author": {"old": prev["author"], "new": new_author},
            "producer": {"old": prev["producer"], "new": new_producer},
            "creator": {"old": prev["creator"], "new": new_creator},
        },
        "creation_date": {"old": prev["creationDate"], "new": creation},
        "mod_date": {"old": prev["modDate"], "new": mod},
        "timestamp_inconsistent": True,
    }


# ---------- structural tampering ----------

def perturb_page_structure(doc, rng, _meta):
    if len(doc) < 2:
        new_page = doc.new_page(-1)
        new_page.insert_text((72, 72), " ", fontsize=8)
        return {"type": "page_structure_insert_blank",
                "inserted_at": len(doc) - 1}
    op = rng.choice(["duplicate", "reorder", "insert_blank"])
    if op == "duplicate":
        idx = rng.randrange(len(doc))
        doc.fullcopy_page(idx)
        return {"type": "page_structure_duplicate",
                "duplicated_page": idx, "inserted_at": len(doc) - 1}
    if op == "reorder" and len(doc) >= 3:
        old_order = list(range(len(doc)))
        new_order = old_order.copy()
        rng.shuffle(new_order)
        doc.select(new_order)
        return {"type": "page_structure_reorder",
                "old_order": old_order, "new_order": new_order}
    new_page = doc.new_page(-1)
    new_page.insert_text((72, 72), " ", fontsize=8)
    return {"type": "page_structure_insert_blank",
            "inserted_at": len(doc) - 1}


# ---------- registry ----------

PERTURBATIONS = {
    "test_values": perturb_test_values,
    "batch_number": perturb_batch_number,
    "dates": perturb_dates,
    "names": perturb_names,
    "font_mismatch": perturb_font_mismatch,
    "logo_shift": perturb_logo_shift,
    "alignment": perturb_alignment,
    "dpi_quality": perturb_dpi_quality,
    "metadata": perturb_metadata,
    "page_structure": perturb_page_structure,
    "paper_cast": perturb_paper_cast,
    "contrast_noise": perturb_contrast_noise,
    "jpeg_regions": perturb_jpeg_regions,
    "stamp_repaste": perturb_stamp_repaste,
    "signature_shift": perturb_signature_shift,
}

DIFFICULTY_POOLS = {
    "easy": [
        "font_mismatch", "logo_shift", "page_structure",
        "dpi_quality", "jpeg_regions", "stamp_repaste",
    ],
    "medium": [
        "test_values", "batch_number", "dates", "names",
        "alignment", "signature_shift", "contrast_noise",
    ],
    "hard": [
        "test_values", "dates", "metadata", "alignment",
        "paper_cast", "signature_shift",
    ],
}
