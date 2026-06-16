"""Visual layout fingerprinting (rule XREF-011, new).

Catches the dominant real-world fake pattern: a fraudster reuses a known lab's
visual COA template (typically Janoshik) but swaps in a different vendor's
text/branding. OCR catches the text content; this check catches whether the
underlying *visual layout* matches a known lab's template.

If visual template strongly matches lab X, but the OCR'd text doesn't mention
lab X → critical authenticity finding.
"""
from __future__ import annotations
import io
import json
from pathlib import Path

import fitz
import imagehash
from PIL import Image, ImageFilter

from .. import registry

ROOT = Path(__file__).resolve().parents[3]
FINGERPRINTS_PATH = ROOT / "Rules" / "lab_visual_fingerprints.json"

# Hash size set by builder; loaded from JSON. Hamming-distance thresholds tuned
# for 256-bit (16x16) blurred-layout hashes.
# Calibrated against intra-lab vs cross-lab Hamming distance distribution
# in the user's corpus (see /tmp/calibrate_threshold.py output 2026-05-19):
#  - Janoshik (single template family): p90 intra-lab=56, cross-to-others≥137
#  - Elite/Prime/Titan use multiple template variants per lab (mixed-bag p90>200)
#  - Janoshik↔Prime min=137 reflects legit Janoshik-tested Prime COAs
DIST_THRESHOLD_MATCH = 80   # nearest sample within this = same template family
DIST_THRESHOLD_STRONG = 30  # below this = essentially same template
MAX_BITS = 256              # for hash_size=16, two hashes summed


def _load_registry() -> dict:
    if not FINGERPRINTS_PATH.exists():
        return {"labs": {}, "hash_size": 16}
    return json.loads(FINGERPRINTS_PATH.read_text(encoding="utf-8"))


def _load_known_labs() -> dict[str, dict]:
    return registry.by_id()


def _render_first_page(file_bytes: bytes, filename: str) -> Image.Image | None:
    suffix = Path(filename).suffix.lower()
    try:
        if suffix == ".pdf":
            doc = fitz.open(stream=file_bytes, filetype="pdf")
            try:
                if doc.page_count == 0:
                    return None
                pix = doc[0].get_pixmap(dpi=150)
                img = Image.open(io.BytesIO(pix.tobytes("png")))
            finally:
                doc.close()
        else:
            img = Image.open(io.BytesIO(file_bytes))
        if img.mode != "L":
            img = img.convert("L")
        return img
    except Exception:
        return None


def _layout_hashes(img: Image.Image, hash_size: int) -> tuple[imagehash.ImageHash, imagehash.ImageHash]:
    small = img.resize((512, 660))
    blurred = small.filter(ImageFilter.GaussianBlur(radius=2))
    return (
        imagehash.phash(blurred, hash_size=hash_size),
        imagehash.dhash(blurred, hash_size=hash_size),
    )


def _ocr_mentions_lab(ocr_text: str, lab_id: str, known: dict[str, dict]) -> bool:
    if lab_id not in known:
        return False
    # Same matching as the text registry (word-boundary + compacted/domain
    # fallback) so a name glued into a URL/email still counts as confirmation.
    return registry.text_mentions(known[lab_id], ocr_text)


def check(file_bytes: bytes, filename: str, ocr_text: str) -> dict:
    fp_registry = _load_registry()
    if not fp_registry.get("labs"):
        return {"status": "not_applicable", "reason": "fingerprint registry empty"}

    hash_size = fp_registry.get("hash_size", 16)
    img = _render_first_page(file_bytes, filename)
    if img is None:
        return {"status": "not_applicable", "reason": "could not render input page"}

    in_p, in_d = _layout_hashes(img, hash_size)

    best: dict | None = None
    for lab_id, lab_data in fp_registry["labs"].items():
        for fp in lab_data["fingerprints"]:
            ref_p = imagehash.hex_to_hash(fp["phash"])
            ref_d = imagehash.hex_to_hash(fp["dhash"])
            d = (in_p - ref_p) + (in_d - ref_d)
            if best is None or d < best["distance"]:
                best = {
                    "lab_id": lab_id,
                    "distance": d,
                    "matched_sample": fp["source"],
                }

    if best is None:
        return {"status": "not_applicable", "reason": "no fingerprints"}

    known = _load_known_labs()
    matched_lab_id = best["lab_id"]
    matched_lab_name = known.get(matched_lab_id, {}).get("name", matched_lab_id)
    dist = best["distance"]

    if dist > DIST_THRESHOLD_MATCH:
        # No stored template is close enough to compare against. This is NOT a
        # negative signal about the document: phone photos sit far from the
        # PDF/scan-built fingerprints, and per-lab template coverage is thin and
        # varies by product. The check is score-neutral here by design — it only
        # ever penalises a layout that matches lab X while the text claims a
        # *different* lab Y. Reported as not_applicable (with the nearest-match
        # detail kept for the debug view) so a genuine COA isn't shown a
        # confusing "does not match any known template" warning finding.
        pct = round(100 * dist / (2 * MAX_BITS), 1)
        return {
            "status": "not_applicable",
            "rule_id": "XREF-011",
            "nearest_lab_id": matched_lab_id,
            "nearest_lab_name": matched_lab_name,
            "best_distance": int(dist),
            "best_distance_pct": pct,
            "reason": (
                f"No known COA template within range to compare against "
                f"(nearest: {matched_lab_name}, {pct}% layout difference). Expected for "
                "photos and labs with few reference samples — not a forgery signal."
            ),
        }

    confidence = "strong" if dist <= DIST_THRESHOLD_STRONG else "moderate"
    base = {
        "rule_id": "XREF-011",
        "matched_lab_id": matched_lab_id,
        "matched_lab_name": matched_lab_name,
        "matched_sample": best["matched_sample"],
        "distance": int(dist),
        "confidence": confidence,
    }

    if _ocr_mentions_lab(ocr_text, matched_lab_id, known):
        return {**base, "status": "pass",
                "message": f"Visual layout matches {matched_lab_name} template and OCR text confirms."}

    # Template matches lab X but OCR doesn't confirm X. Only hard-fire when the
    # text explicitly names a DIFFERENT registered lab/vendor (template X,
    # claims Y = forgery). If no recognized issuer is named, the name was likely
    # OCR-garbled on a real COA, or it's an unknown issuer — flag as suspicious,
    # don't force a forgery verdict (avoids false positives on real COAs).
    named = registry.match_in_text(ocr_text)
    if named and named["id"] != matched_lab_id:
        return {**base, "status": "fired", "severity": "critical",
                "claimed_entity": named["name"],
                "message": (
                    f"VISUAL/TEXT MISMATCH: layout matches {matched_lab_name} template "
                    f"({confidence}, distance={dist}) but the COA text names a different "
                    f"issuer ({named['name']}). Canonical lab-template forgery pattern."
                )}
    # No conflicting issuer named. A STRONG (near-zero distance) match to a known
    # template means the document is essentially identical to a genuine COA from
    # that lab — OCR simply missed the name. Treat as pass. Only moderate matches
    # with no name confirmation stay suspicious.
    if confidence == "strong":
        return {**base, "status": "pass",
                "message": (
                    f"Visual layout strongly matches {matched_lab_name} template "
                    f"(distance={dist}); issuer name not cleanly OCR'd but template is genuine."
                )}
    return {**base, "status": "suspicious", "severity": "major",
            "message": (
                f"Visual layout matches {matched_lab_name} template ({confidence}, "
                f"distance={dist}) but its name was not clearly found in the text "
                "(possible OCR noise or unrecognized issuer) — verify the issuing lab."
            )}
