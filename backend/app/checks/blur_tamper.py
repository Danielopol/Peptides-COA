"""Localized illegibility / tamper detection via OCR word confidence (FORG-016).

A forger smudges specific fields (client, task#, QR, key, lab name) to repurpose
a real COA. Those fields become illegible, so Tesseract's per-word confidence
collapses *locally* while the rest of the document still reads cleanly.

We measure, over real word tokens:
  - low_conf_frac : fraction of words with confidence below LOW_CONF
  - worst_band    : max fraction of low-conf words within any horizontal band
                    (catches a smudge concentrated in one region, e.g. a footer
                     verification key or a header client field)

Metrics are returned always; the fire decision uses thresholds calibrated
against the real-vs-fake corpus (see calibrate output, do not hand-tune blind).
"""
from __future__ import annotations
import io
from pathlib import Path

import fitz
import numpy as np
import pytesseract
from PIL import Image

RENDER_DPI = 200
LOW_CONF = 40           # Tesseract word confidence below this = poorly read
MIN_WORDS = 15          # need enough text to judge
N_BANDS = 6             # horizontal bands for localized concentration


def _to_image(file_bytes: bytes, filename: str) -> Image.Image | None:
    suffix = Path(filename).suffix.lower()
    try:
        if suffix == ".pdf":
            doc = fitz.open(stream=file_bytes, filetype="pdf")
            try:
                if doc.page_count == 0:
                    return None
                pix = doc[0].get_pixmap(dpi=RENDER_DPI)
                img = Image.open(io.BytesIO(pix.tobytes("png")))
            finally:
                doc.close()
        else:
            img = Image.open(io.BytesIO(file_bytes))
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        return img
    except Exception:
        return None


def _real_words(img: Image.Image) -> list[dict]:
    data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)
    words = []
    n = len(data["text"])
    for i in range(n):
        txt = (data["text"][i] or "").strip()
        conf = float(data["conf"][i])
        if conf < 0:                      # -1 = non-word block
            continue
        if len(txt) < 2:
            continue
        if not any(ch.isalnum() for ch in txt):
            continue
        words.append({
            "text": txt, "conf": conf,
            "top": data["top"][i], "height": data["height"][i],
        })
    return words


def check(file_bytes: bytes, filename: str) -> dict:
    img = _to_image(file_bytes, filename)
    if img is None:
        return {"status": "not_applicable", "reason": "could not render page"}

    try:
        words = _real_words(img)
    except Exception as e:  # noqa: BLE001
        return {"status": "not_applicable", "reason": f"ocr error: {e}"}

    if len(words) < MIN_WORDS:
        return {"status": "not_applicable", "reason": "too few words to assess", "word_count": len(words)}

    confs = np.array([w["conf"] for w in words])
    low = confs < LOW_CONF
    low_conf_frac = float(low.mean())
    median_conf = float(np.median(confs))

    # localized concentration: bin words by vertical position, find the band
    # with the highest low-confidence fraction (min 3 words in band).
    page_h = max(w["top"] + w["height"] for w in words) or 1
    band_low = np.zeros(N_BANDS)
    band_tot = np.zeros(N_BANDS)
    for w in words:
        b = min(N_BANDS - 1, int(N_BANDS * w["top"] / page_h))
        band_tot[b] += 1
        if w["conf"] < LOW_CONF:
            band_low[b] += 1
    worst_band = 0.0
    for b in range(N_BANDS):
        if band_tot[b] >= 3:
            worst_band = max(worst_band, band_low[b] / band_tot[b])

    metrics = {
        "rule_id": "FORG-016",
        "word_count": len(words),
        "median_conf": round(median_conf, 1),
        "low_conf_frac": round(low_conf_frac, 3),
        "worst_band_low_frac": round(float(worst_band), 3),
    }
    return {"status": "metrics_only", **metrics}
