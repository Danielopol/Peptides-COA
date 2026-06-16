"""Build Rules/lab_visual_fingerprints.json from known-lab COA samples.

For each lab folder, render first page to image (200 dpi grayscale), strip
text contrast by blurring, then compute perceptual hashes (pHash + dHash) to
capture pure layout structure rather than specific content.

The output JSON stores 1+ reference hashes per lab. At scan time we compare
the input's hash against all reference hashes and report the closest match.

Run:
    .venv/bin/python -m app.checks.build_lab_fingerprints
"""
from __future__ import annotations
import io
import json
import random
from pathlib import Path

import fitz
import imagehash
from PIL import Image, ImageFilter

from .. import registry

ROOT = Path(__file__).resolve().parents[3]
COAS = ROOT / "COAs"
OUT = ROOT / "Rules" / "lab_visual_fingerprints.json"


def _lab_folders() -> dict[str, str]:
    """folder name -> entity id, from registry coa_template_owner entries."""
    return {
        e["coa_folder"]: e["id"]
        for e in registry.template_owners()
        if e.get("coa_folder")
    }

SAMPLES_PER_LAB = 250        # use all available up to this cap
RANDOM_SEED = 17
RENDER_DPI = 150
HASH_SIZE = 16  # 256-bit hash for finer template granularity


def render_first_page(path: Path) -> Image.Image | None:
    try:
        if path.suffix.lower() == ".pdf":
            doc = fitz.open(path)
            try:
                if doc.page_count == 0:
                    return None
                pix = doc[0].get_pixmap(dpi=RENDER_DPI)
                img = Image.open(io.BytesIO(pix.tobytes("png")))
            finally:
                doc.close()
        else:
            img = Image.open(path)
        if img.mode != "L":
            img = img.convert("L")
        return img
    except Exception as e:
        print(f"  ! could not render {path.name}: {e}")
        return None


def layout_signature(img: Image.Image) -> dict:
    """pHash + dHash on a layout-emphasized version of the page."""
    # Resize to standard, then blur to wash out fine text but keep layout shapes
    small = img.resize((512, 660))
    blurred = small.filter(ImageFilter.GaussianBlur(radius=2))
    p = imagehash.phash(blurred, hash_size=HASH_SIZE)
    d = imagehash.dhash(blurred, hash_size=HASH_SIZE)
    return {"phash": str(p), "dhash": str(d)}


def fingerprint_folder(folder: Path) -> list[dict]:
    pdfs = list(folder.glob("*.pdf"))
    random.shuffle(pdfs)
    pdfs = pdfs[:SAMPLES_PER_LAB]
    fps: list[dict] = []
    for p in pdfs:
        img = render_first_page(p)
        if img is None:
            continue
        sig = layout_signature(img)
        sig["source"] = p.name
        fps.append(sig)
        print(f"  + {p.name}  phash={sig['phash'][:16]}…")
    return fps


def main() -> None:
    random.seed(RANDOM_SEED)
    out: dict = {
        "version": "0.1",
        "last_updated": "2026-05-19",
        "hash_size": HASH_SIZE,
        "render_dpi": RENDER_DPI,
        "samples_per_lab": SAMPLES_PER_LAB,
        "method": "pHash + dHash on Gaussian-blurred grayscale first page (256-bit each)",
        "labs": {},
    }
    for folder_name, lab_id in _lab_folders().items():
        folder = COAS / folder_name
        if not folder.exists():
            print(f"[skip] {folder_name}: not found")
            continue
        print(f"[{lab_id}] sampling {folder_name}/")
        out["labs"][lab_id] = {
            "folder": folder_name,
            "fingerprints": fingerprint_folder(folder),
        }
    OUT.write_text(json.dumps(out, indent=2), encoding="utf-8")
    total = sum(len(v["fingerprints"]) for v in out["labs"].values())
    print(f"\nWrote {OUT} ({total} fingerprints across {len(out['labs'])} labs)")


if __name__ == "__main__":
    main()
