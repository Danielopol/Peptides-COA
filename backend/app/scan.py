"""Pipeline orchestrator: OCR + features -> rule engine -> hard checks -> LLM -> aggregate."""
from __future__ import annotations
import io
import os
import re
import sys
import tempfile
from pathlib import Path

import fitz  # PyMuPDF
import pytesseract
from PIL import Image

from . import llm_client, registry, rules_engine, scoring, synthesis
from .checks import (
    assay_mass, blur_tamper, completeness_checklist, doc_type, janoshik, known_labs,
    metadata, methods, multi_mass, mw_table, purity_sanity, recency, result_alerts,
    semantic_enrich, verifiability, visual_lab,
)

ROOT = Path(__file__).resolve().parents[2]
CALIBRATION_DIR = ROOT / "Rules" / "calibration"
if str(CALIBRATION_DIR) not in sys.path:
    sys.path.insert(0, str(CALIBRATION_DIR))
import calibrate  # noqa: E402

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff", ".bmp"}

# Fixed, always-returned framing so the UI can make the document-vs-product
# distinction loud. The dominant misconception in the community is that an
# authentic/verifiable COA means a safe product — it does not.
LIMITATIONS = [
    "Even a genuine, verifiable COA only proves the specific sample that was "
    "tested — not the vial you received. There is no real batch traceability in "
    "this market, and vendors can reuse one COA across many vials.",
    "Purity is not safety. Sterility, bacterial endotoxins, heavy metals and "
    "residual solvents are usually NOT tested on these COAs, yet they are what "
    "cause the worst reactions.",
    "The only way to know what is in your vial is independent testing of that "
    "vial (or a community/group test of the same batch).",
    "Purity is not potency. A peptide can be highly pure yet denatured, "
    "misfolded, or degraded and therefore inactive — bioactivity is almost never "
    "tested on these COAs.",
]


def _infer_ms_technique(text: str) -> str | None:
    # Word boundaries are required: a bare-substring "esi" matches inside ordinary
    # words (e.g. "design" / "designer"), which manufactured a phantom "ESI-MS"
    # technique on non-COA screenshots and lit the identity checklist row green.
    low = (text or "").lower()
    if re.search(r"\bmaldi", low):
        return "MALDI-TOF"
    if re.search(r"\besi\b", low) and re.search(r"\btof\b", low):
        return "ESI-TOF"
    if re.search(r"\besi\b", low):
        return "ESI-MS"
    if re.search(r"\bq-?tof\b", low):
        return "Q-TOF"
    return None


# A document explicitly framing itself as a certificate/analytical report. Any
# one of these is a STRONG signal that the input is a COA.
_COA_PHRASE = re.compile(
    r"certificate\s+of\s+analysis|certificate\s+of\s+conformance|"
    r"\bc\.?\s*o\.?\s*a\.?\b|analytical\s+report|test\s+report",
    re.I,
)


def coa_signals(ocr_text: str, peptide_name: str | None, ms_technique: str | None,
                hard_checks: dict) -> dict:
    """Decide whether the input even looks like a COA, BEFORE scoring it.

    Every downstream check is a COA-conditional discriminator ("given a COA, is it
    forged / complete?") — none establishes that the input is a COA at all. On
    out-of-distribution input (a random screenshot) the forgery checks fail open
    to "pass" and a few loose matchers manufacture phantom "present" fields, so
    the result reads like a half-valid COA. This gate stops that: it requires
    real COA markers and otherwise short-circuits to the not-a-COA verdict.

    Conservative by design — it must never reject a genuine (even sparse) COA:
    a COA is accepted on ANY single strong marker, or any TWO weak markers.
    """
    hc = hard_checks or {}
    strong: list[str] = []
    weak: list[str] = []

    if peptide_name:
        strong.append("peptide_identified")
    if _COA_PHRASE.search(ocr_text or ""):
        strong.append("coa_header")

    if hc.get("purity_sanity", {}).get("status") not in (None, "not_applicable"):
        weak.append("purity")
    _am = hc.get("assay_mass", {})
    if _am.get("labeled_mg") is not None or _am.get("measured_mg") is not None:
        weak.append("assay_mass")
    if hc.get("known_lab", {}).get("status") in ("pass", "unrecognized_named"):
        weak.append("lab_named")
    if hc.get("methods", {}).get("status") in ("multi", "single"):
        weak.append("analytical_method")
    if ms_technique:
        weak.append("ms_technique")
    if semantic_enrich.detect_batch(ocr_text):
        weak.append("batch_lot")
    if hc.get("mw_table", {}).get("claimed_mw") is not None:
        weak.append("molecular_weight")

    is_coa = len(strong) >= 1 or len(weak) >= 2
    return {"is_coa": is_coa, "strong": strong, "weak": weak}


# Tesseract reads small text poorly below ~300 DPI. A low-resolution image
# (phone screenshot, downscaled COA) loses all the small body text, leaving only
# the big header logo — which then trips the "<100 chars => not a COA" guard on a
# perfectly real certificate. So upscale small images toward a ~300-DPI page and
# grayscale them before OCR.
_OCR_TARGET_LONG_EDGE = 2400
_OCR_MAX_SCALE = 4.0
# The rules engine OCRs the image-as-PDF, which calibrate already renders at a
# fixed DPI. Upscaling an already-decent image before that adds a second
# resample that *softens* text and can cost OCR chars (observed on a 1593px
# input). So only pre-upscale for the rules path when the image is genuinely too
# small to be legible at all (the OCR path below has no such round-trip and
# always targets the full size).
_RULES_UPSCALE_BELOW = 1400


def _upscale_small_image(img: Image.Image, trigger: int = _OCR_TARGET_LONG_EDGE) -> Image.Image:
    """Upscale a low-resolution image toward a ~300-DPI page so small text
    survives OCR. No-op once the long edge reaches `trigger`."""
    long_edge = max(img.size)
    if long_edge >= trigger:
        return img
    scale = min(_OCR_MAX_SCALE, _OCR_TARGET_LONG_EDGE / long_edge)
    new_size = (round(img.size[0] * scale), round(img.size[1] * scale))
    return img.resize(new_size, Image.LANCZOS)


# Scanned COA PDFs are often low-resolution images; calibrate.ocr_pdf renders at
# 200 DPI which loses small body text. Render higher (300 DPI) + grayscale +
# upscale so fields like batch/purity/MS survive OCR. (calibrate's shared 200-DPI
# OCR is left untouched so the rules-corpus cache/calibration stays stable; the
# rule engine consumes this text via rules_engine.evaluate(ocr_text=...).)
_PDF_OCR_DPI = 300
# Below this much extracted text, field detection is unreliable (poor scan).
_SPARSE_OCR_CHARS = 400

# Completeness "presence" rules a vision model can confirm when OCR missed the
# field (e.g. a signature graphic). The LLM audit (presence-only) may flip these
# fired->pass; it can NEVER touch authenticity. rule_id -> what to look for.
_PRESENCE_RULE_LABELS = {
    "STRUCT-001": "Product / peptide name",
    "STRUCT-002": "Batch or lot number",
    "STRUCT-003": "Analysis / test date",
    "STRUCT-004": "Testing laboratory name",
    "STRUCT-005": "Lab address (city/country)",
    "STRUCT-006": "Lab contact info (email, phone, or website)",
    "STRUCT-007": "Analyst signature or certification (incl. a signed name)",
    "STRUCT-008": "Purity result as a numeric percentage",
    "STRUCT-009": "Mass-spectrometry identity confirmation",
    "STRUCT-010": "Pass/fail or conformance determination",
    "STRUCT-011": "Both a sample-receipt date and a test date",
    "STRUCT-012": "Client / supplier / customer name",
    "METH-001": "HPLC method",
    "METH-002": "Mass-spectrometry method",
    "METH-003": "Reversed-phase C18 column",
    "METH-004": "Mobile phase / solvent",
    "METH-005": "MS technique type (ESI, MALDI, Q-TOF, etc.)",
    "METH-006": "Chromatogram / retention-time trace",
    "METH-010": "Net peptide content method",
    "METH-011": "Heavy-metals testing",
    "METH-012": "Endotoxin testing",
    "LAB-002": "ISO/IEC 17025 accreditation mark",
}
_AUDIT_REJECT_VALUES = {"", "n/a", "na", "none", "absent", "not present", "not visible", "-", "—"}

# The vision audit covers the UNION of (a) fired presence-RULES (above) — which
# move the rules-driven score — and (b) checklist SECTIONS that have NO backing
# rule, so every user-facing section still gets an LLM fallback.
# A confirmed rule also lights up the checklist section it maps to.
# NOTE: the "Identity confirmation (mass spec)" row is gated on STRUCT-009 (the
# actual MS identity confirmation) ONLY. METH-002/METH-005 (MS method / technique
# *named*) deliberately do NOT light it — naming a method is not confirming
# identity. They still flip fired->pass and move the completeness score when
# genuinely confirmed; they just don't stand in for an identity confirmation.
_RULE_TO_CHECKLIST_SECTION = {
    "STRUCT-008": "purity",
    "STRUCT-009": "identity",
    "STRUCT-002": "batch_lot",
    "STRUCT-003": "test_date",
    "STRUCT-011": "test_date",
    "METH-011": "heavy_metals",
    "METH-012": "endotoxin",
    "LAB-002": "accreditation",
}

# Audit keys whose evidence must actually be mass-spec. The vision model
# sometimes drops an HPLC/UV value into one of these MS slots; requiring a real
# MS cue in the quoted value rejects that mislabel.
_MS_AUDIT_KEYS = {"STRUCT-009", "METH-002", "METH-005"}
# Checklist sections with no rule — audited directly (key = section id). Confirming
# these updates the checklist only (the calibrated score stays rules-driven).
_NORULE_SECTION_DESC = {
    "sterility": "Sterility or microbial testing",
    "residual_solvents": "Residual solvents test (e.g. TFA, acetonitrile)",
    "impurity_profile": "An impurity breakdown / related-substances listing (named impurities or "
                        "main-peak-vs-impurity table), not just a single purity number",
    "water_content": "A water content / moisture result (Karl Fischer, % water, or loss on drying)",
    "vial_photo": "A photograph of the actual product vial",
    "assay_mass": "Measured mass / net peptide content in mg",
    "verification": "A verification code, QR code, or lookup key to verify the COA online",
}


def _valid_audit_value(v) -> bool:
    """A confirmed field must come with a concrete, non-boilerplate value — this
    grounding is what keeps the model from hallucinating a field as present."""
    if not isinstance(v, str):
        return False
    s = v.strip()
    return len(s) >= 2 and s.lower() not in _AUDIT_REJECT_VALUES


def _audit_value_consistent(key: str, v) -> bool:
    """Reject a confirmation whose quoted value contradicts the field it fills.

    For the mass-spec slots (STRUCT-009 / METH-002 / METH-005) the value must
    carry a real MS cue (m/z, ESI, MALDI, TOF, LC-MS…). This blocks the classic
    vision-model mislabel of confirming an MS field with an HPLC/UV value such
    as "HPLC-UV/VIS"."""
    if key not in _MS_AUDIT_KEYS:
        return True
    return bool(semantic_enrich._MS_CUES.search(str(v or "")))


def _ocr_pdf(path: Path) -> str:
    try:
        doc = fitz.open(path)
    except Exception as e:  # noqa: BLE001
        return f"[OCR_ERROR: {e}]"
    parts: list[str] = []
    try:
        for i in range(doc.page_count):
            pix = doc[i].get_pixmap(dpi=_PDF_OCR_DPI)
            img = Image.open(io.BytesIO(pix.tobytes("png"))).convert("L")
            # A 300-DPI page render is already ~1.5k+ px; only upscale a genuinely
            # tiny render. Over-upscaling an already-decent render softens text and
            # *hurts* OCR (observed: 2400px upscale dropped a readable scan to noise).
            img = _upscale_small_image(img, trigger=_RULES_UPSCALE_BELOW)
            try:
                parts.append(pytesseract.image_to_string(img))
            except Exception as e:  # noqa: BLE001
                parts.append(f"[OCR_ERROR: {e}]")
    finally:
        doc.close()
    return "\n\n--- PAGE BREAK ---\n\n".join(parts)


def _ocr_image(path: Path) -> str:
    try:
        img = _upscale_small_image(Image.open(path).convert("L"))  # grayscale aids OCR
        return pytesseract.image_to_string(img)
    except Exception as e:  # noqa: BLE001
        return f"[OCR_ERROR: {e}]"


def _image_to_pdf_bytes(path: Path) -> bytes:
    """Wrap a raster image as a single-page PDF so extract_features can run.
    Upscales only genuinely-tiny inputs (see _RULES_UPSCALE_BELOW) so the rules
    engine can read the body text on low-resolution COAs without softening
    already-legible ones."""
    img = Image.open(path)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    img = _upscale_small_image(img, trigger=_RULES_UPSCALE_BELOW)
    buf = io.BytesIO()
    img.save(buf, format="PDF", resolution=200.0)
    return buf.getvalue()


def _render_png(file_bytes: bytes, filename: str) -> bytes | None:
    """First page as PNG bytes for the LLM vision pass."""
    suffix = Path(filename).suffix.lower()
    try:
        if suffix == ".pdf":
            doc = fitz.open(stream=file_bytes, filetype="pdf")
            try:
                if doc.page_count == 0:
                    return None
                return doc[0].get_pixmap(dpi=150).tobytes("png")
            finally:
                doc.close()
        img = Image.open(io.BytesIO(file_bytes))
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()
    except Exception:
        return None


def _render_pngs(file_bytes: bytes, filename: str, max_pages: int = 4) -> list[bytes]:
    """All pages (capped) as PNGs for the completeness audit — later pages often
    hold the chromatogram/vial photo the field audit needs to see."""
    suffix = Path(filename).suffix.lower()
    try:
        if suffix == ".pdf":
            doc = fitz.open(stream=file_bytes, filetype="pdf")
            try:
                return [doc[i].get_pixmap(dpi=150).tobytes("png")
                        for i in range(min(doc.page_count, max_pages))]
            finally:
                doc.close()
        one = _render_png(file_bytes, filename)
        return [one] if one else []
    except Exception:
        return []


def _default_rules_path() -> Path:
    env = os.environ.get("RULES_PATH")
    if env:
        p = Path(env)
        # Relative paths in .env are written relative to backend/ — resolve them
        # against it so they work regardless of the process's working directory.
        return p if p.is_absolute() else (ROOT / "backend" / p).resolve()
    return ROOT / "Rules" / "calibration" / "coa_rules_calibrated.json"


def run_scan(file_bytes: bytes, filename: str, origin: str = "vendor") -> dict:
    rules = rules_engine.load_rules(_default_rules_path())

    suffix = Path(filename).suffix.lower() or ".pdf"
    is_image = suffix in IMAGE_SUFFIXES
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(file_bytes)
        tmp_path = Path(tmp.name)

    pdf_for_features: Path = tmp_path
    pdf_tempfile: Path | None = None
    try:
        if is_image:
            ocr_text = _ocr_image(tmp_path)
            pdf_bytes = _image_to_pdf_bytes(tmp_path)
            with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as ptmp:
                ptmp.write(pdf_bytes)
                pdf_tempfile = Path(ptmp.name)
            pdf_for_features = pdf_tempfile
        else:
            ocr_text = _ocr_pdf(tmp_path)

        if len(ocr_text.strip()) < 100:
            return {
                "filename": filename,
                "error": "input_not_coa",
                "message": "OCR yielded <100 chars; input is likely not a COA",
                "ocr_chars": len(ocr_text.strip()),
            }
        engine_out = rules_engine.evaluate(pdf_for_features, rules, ocr_text=ocr_text)
        ms_technique = _infer_ms_technique(ocr_text)
        # Identify the peptide from the MW table (single source of truth):
        # name/CAS/sequence/fuzzy. Falls back to the legacy parser only if unmatched.
        det = mw_table.detect(ocr_text)
        if det:
            peptide_name = det["peptide"]["name"]
            peptide_detect_method = det["method"]
        else:
            parsed = calibrate.parse_ocr(ocr_text)
            peptide_name = parsed.get("peptide_name_found") if isinstance(parsed, dict) else None
            peptide_detect_method = "legacy" if peptide_name else None

        hard_checks = {
            "mw_table": mw_table.check(peptide_name, ocr_text, ms_technique),
            "known_lab": known_labs.check(ocr_text),
            "janoshik": janoshik.check(ocr_text),
            "visual_lab": visual_lab.check(file_bytes, filename, ocr_text),
            "multi_mass": multi_mass.check(ocr_text),
            "metadata": metadata.check(file_bytes, filename),
            "blur_tamper": blur_tamper.check(file_bytes, filename),
            "assay_mass": assay_mass.check(ocr_text, peptide_name),
            "recency": recency.check(ocr_text),
            "purity_sanity": purity_sanity.check(ocr_text),
            "methods": methods.check(ocr_text, ms_technique),
        }
    finally:
        for p in (tmp_path, pdf_tempfile):
            if p is None:
                continue
            try:
                p.unlink()
            except OSError:
                pass

    # ---- COA-ness gate -----------------------------------------------------
    # Short-circuit BEFORE scoring if the input doesn't look like a COA at all.
    # OCR read plenty of text (we're past the <100-char guard) but none of the
    # markers a certificate carries are present, so the scoring path would just
    # report fail-open "passes" as if it were a half-valid COA. Reuse the
    # existing input_not_coa contract the frontend already renders.
    _sig = coa_signals(ocr_text, peptide_name, ms_technique, hard_checks)
    if not _sig["is_coa"]:
        return {
            "filename": filename,
            "error": "input_not_coa",
            "message": (
                "We read the text on this file, but it's missing the fields a "
                "Certificate of Analysis contains (no peptide identity, purity, "
                "testing lab, mass, or analytical results were found). It doesn't "
                "look like a COA."
            ),
            "ocr_chars": len(ocr_text.strip()),
            "coa_signals": _sig,
        }

    # Lab-identity reconciliation: if the visual template confidently matches a
    # known lab but the text matcher didn't independently find that issuer
    # (e.g. the name is readable only in a stylized logo OCR can't parse, with
    # no URL/email to fall back on), attribute the lab from the template.
    # Guarded against forgery: visual_lab returns "pass" only when the OCR text
    # does NOT name a *different* recognized issuer — a template reused under
    # another lab's name fires a critical mismatch there instead — so this
    # cannot launder a template-reuse forgery into a recognized lab.
    _vl = hard_checks["visual_lab"]
    if (
        hard_checks["known_lab"].get("status") != "pass"
        and _vl.get("status") == "pass"
        and _vl.get("matched_lab_id")
    ):
        _entity = registry.by_id().get(_vl["matched_lab_id"])
        if _entity:
            hard_checks["known_lab"] = {
                "status": "pass",
                "rule_id": "LAB-009",
                "entity_id": _entity["id"],
                "entity_kind": _entity.get("entity_kind", "lab"),
                "lab_name": _entity["name"],
                "trust": _entity.get("trust", "unknown"),
                "matched_via": "visual_template",
                "message": (
                    "Issuer name didn't OCR cleanly, but the document's visual "
                    "template matches this lab."
                ),
            }
            if _entity.get("caveat"):
                hard_checks["known_lab"]["caveat"] = _entity["caveat"]
            if _entity.get("verification"):
                hard_checks["known_lab"]["verification"] = _entity["verification"]

    # Generalized verifiability — computed after lab reconciliation so it can use
    # the (possibly template-recovered) issuer's verification portal.
    hard_checks["verifiability"] = verifiability.check(ocr_text, hard_checks["known_lab"])

    # Document-type classification (third-party lab vs in-house/manufacturer QC).
    # Informational only — never moves the authenticity score (a genuine
    # manufacturer report is authentic, just weak evidence).
    hard_checks["doc_type"] = doc_type.classify(ocr_text, hard_checks["known_lab"])

    agg = scoring.aggregate(engine_out["rule_results"])

    # Informational completeness checklist (present/absent expected sections).
    # Does not change the completeness score — the rule engine drives that.
    agg["completeness"]["checklist"] = completeness_checklist.build(
        ocr_text, hard_checks, ms_technique
    )

    # Hard-check overrides — applied to AUTHENTICITY only, never completeness.
    if hard_checks["mw_table"].get("status") == "fired":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 25)
        agg["authenticity"]["label"] = "likely_forged"
        # Use the check's specific message — it distinguishes a mass mismatch from
        # a molecular-formula mismatch (e.g. a copper formula on a peptide).
        agg["authenticity"]["copy"] = hard_checks["mw_table"].get("message") or (
            "Claimed molecular weight does not match the named peptide — "
            "strong forgery indicator."
        )
    _lab_trust = hard_checks["known_lab"].get("trust")
    if _lab_trust == "untrusted":
        # Issuer is flagged as a known bad actor — cap hard, never bonus.
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 30)
        agg["authenticity"]["label"] = "likely_forged"
        agg["authenticity"]["copy"] = (
            "The issuing lab is flagged as a known bad actor in our registry — "
            "do not rely on this COA."
        )
    elif _lab_trust in ("high", "established_pharma_cro", "established_cro"):
        agg["authenticity"]["score"] = min(100, agg["authenticity"]["score"] + 5)
    elif _lab_trust in ("moderate", "emerging"):
        agg["authenticity"]["score"] = min(100, agg["authenticity"]["score"] + 2)
    else:
        # Issuer not recognized by name. Skip the penalty entirely if the visual
        # template matches a known lab (real COA whose name just didn't OCR).
        # Otherwise grade by whether ANY lab name is present:
        #   - a lab name exists but isn't catalogued -> mild "verify further" cap
        #   - no testing-lab name at all -> stronger red flag (per source articles)
        _visual = hard_checks["visual_lab"].get("status")
        _lab_status = hard_checks["known_lab"].get("status")
        if _visual != "pass":
            if _lab_status == "no_issuer":
                agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 50)
                agg["authenticity"]["copy"] = (
                    "No testing-laboratory name found on the COA, and the layout "
                    "matches no known lab. An untraceable COA should not be trusted "
                    "without independent confirmation."
                )
            elif _lab_status == "unrecognized_named":
                agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 70)
                agg["authenticity"]["copy"] = (
                    "The issuing lab is named but not in our verified registry. "
                    "Verify the lab independently before relying on this COA."
                )
    # Generalized verifiability (XREF-012). Janoshik COAs are deferred to the
    # janoshik check below, so this never double-counts with it.
    # Calibrated 2026-06-01 against the corpus: ~20% of GENUINE non-Janoshik COAs
    # simply have no online verification portal, so this is a trust/verify signal,
    # not a forgery signal — the caps are gentle to avoid branding real COAs fake.
    _verif = hard_checks["verifiability"].get("status")
    if _verif == "redacted" and agg["authenticity"]["score"] > 55:
        # A blanked verification field is suspicious but the OCR heuristic is
        # noisy (~2% false positive on real COAs), so cap to "suspicious", not
        # "likely_forged".
        agg["authenticity"]["score"] = 55
        agg["authenticity"]["copy"] = hard_checks["verifiability"]["message"]
    elif _verif == "no_verification_path" and agg["authenticity"]["score"] > 70:
        # No portal found -> "verify_recommended", not "suspicious": many real
        # labs don't offer one (calibration FP would otherwise be ~20%).
        agg["authenticity"]["score"] = 70
        agg["authenticity"]["copy"] = hard_checks["verifiability"]["message"]
    elif _verif == "verifiable" and _lab_trust in (
        "high", "established_pharma_cro", "established_cro", "moderate", "emerging"
    ):
        # Small bonus only when the issuer is also a recognized lab, so a bare
        # "/verify" string can't launder an otherwise-untraceable COA.
        agg["authenticity"]["score"] = min(100, agg["authenticity"]["score"] + 3)

    # Assay vs labeled strength (FORG-018). Underdose is the real concern;
    # overfill is benign (community: vendors overfill rather than short-fill) and
    # is reported without a score penalty. A severe underdose can also signal a
    # reused/mismatched COA, so it caps harder.
    if hard_checks["assay_mass"].get("status") == "underdosed":
        _severe = hard_checks["assay_mass"].get("severity") == "major"
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 45 if _severe else 65)
        agg["authenticity"]["copy"] = hard_checks["assay_mass"]["message"]

    if hard_checks["janoshik"].get("status") == "fired":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 25)
        agg["authenticity"]["label"] = "likely_forged"
        agg["authenticity"]["copy"] = hard_checks["janoshik"]["message"]
    if hard_checks["visual_lab"].get("status") == "fired":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 20)
        agg["authenticity"]["label"] = "likely_forged"
        agg["authenticity"]["copy"] = hard_checks["visual_lab"]["message"]
    elif hard_checks["visual_lab"].get("status") == "suspicious":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 55)
    elif hard_checks["visual_lab"].get("status") == "pass":
        agg["authenticity"]["score"] = min(100, agg["authenticity"]["score"] + 5)
    if hard_checks["multi_mass"].get("status") == "fired":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 25)
        agg["authenticity"]["label"] = "likely_forged"
        agg["authenticity"]["copy"] = hard_checks["multi_mass"]["message"]
    elif hard_checks["multi_mass"].get("status") == "suspicious":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 55)
    if hard_checks["metadata"].get("status") == "fired":
        agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 25)
        agg["authenticity"]["label"] = "likely_forged"
        agg["authenticity"]["copy"] = hard_checks["metadata"]["message"]

    # Stale COA (META-006) — advisory: a stale date isn't forgery, so cap only a
    # still-high score to "verify_recommended" and don't override a stronger flag.
    if hard_checks["recency"].get("status") == "stale" and agg["authenticity"]["score"] > 70:
        agg["authenticity"]["score"] = 70
        agg["authenticity"]["copy"] = hard_checks["recency"]["message"]

    # blur_tamper is advisory only until recalibrated (current detector
    # over-fires on legitimate layout variation — see OCR-confidence rewrite).
    # purity_sanity (FORG-019) is likewise advisory: it surfaces a caution
    # finding (too-perfect / vague purity) but applies NO score override until
    # calibrated against the corpus — it is a weak discriminator on its own.

    # ---- LLM vision second opinion (GATED) ---------------------------------
    # Only call the LLM on AMBIGUOUS COAs: skip when already confidently forged
    # (a hard check fired -> score<=30) or confidently authentic (>=85). This
    # is where it earns its keep — blurred/altered fields the rules can't see.
    # Influence is downward-only: it can flag a fake the rules missed, never
    # inflate a fake into "authentic".
    # Strong deterministic authenticity corroboration: a recognized issuer whose
    # visual template matches (visual_lab pass) OR whose COA is independently
    # verifiable. The LLM's failure mode here is hallucinating "template from
    # another lab" / "lab name altered" on a genuine niche-lab COA (observed on
    # real Freedom Diagnostics COAs), so we skip the vision pass — this is not the
    # ambiguous case it exists for, and visual_lab already checks template reuse.
    _kl = hard_checks["known_lab"]
    _recognized = _kl.get("status") == "pass" and _kl.get("trust") != "untrusted"
    _strong_authentic = _recognized and (
        hard_checks["visual_lab"].get("status") == "pass"
        or hard_checks["verifiability"].get("status") == "verifiable"
    )

    llm_out: dict = {"enabled": False, "note": "not run (gated)"}
    llm_completeness: dict = {"enabled": False, "note": "not run"}
    png: bytes | None = None
    rendered_pngs: list[bytes] | None = None  # shared across vision passes
    score = agg["authenticity"]["score"]
    if _strong_authentic:
        llm_out = {"enabled": False,
                   "note": "not run (recognized lab + template/verification match)"}
    elif llm_client.llm_enabled() and 30 < score < 85:
        png = _render_png(file_bytes, filename)
        llm_out = llm_client.assess(ocr_text=ocr_text, image_png=png)
        verdict = llm_out.get("verdict")
        conf = float(llm_out.get("confidence") or 0)
        if verdict == "not_a_coa" and conf >= 0.6:
            # Vision agrees this isn't a COA (the deterministic gate let it through
            # on a borderline marker). Downward-only, like the other LLM verdicts.
            agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 30)
            agg["authenticity"]["copy"] = (
                "Visual review: this does not appear to be a certificate of analysis."
            )
        elif verdict == "likely_forged" and conf >= 0.6:
            agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 28)
            agg["authenticity"]["copy"] = (
                "Visual review found tampering: " + (llm_out.get("summary") or "altered fields detected") + "."
            )
        elif verdict == "suspicious" and conf >= 0.5:
            agg["authenticity"]["score"] = min(agg["authenticity"]["score"], 55)
            if llm_out.get("summary"):
                agg["authenticity"]["copy"] = "Visual review: " + llm_out["summary"]

    # ---- Completeness presence audit (vision, presence-only) ---------------
    # OCR routinely misses fields that ARE on the page (signatures, stamps,
    # low-contrast/unlabeled text). When LLM is enabled, have the vision model
    # confirm the presence-rules that fired as "missing", quoting each value.
    # Influence is PRESENCE-ONLY: a confirmed field flips fired->pass and raises
    # completeness; it can never lower a score or touch authenticity.
    if llm_client.llm_enabled():
        checklist = agg["completeness"].get("checklist") or []
        # (a) fired presence-rules; (b) absent checklist sections with no rule.
        audit_fields = {
            r["rule_id"]: _PRESENCE_RULE_LABELS[r["rule_id"]]
            for r in engine_out["rule_results"]
            if r["status"] == "fired" and r["rule_id"] in _PRESENCE_RULE_LABELS
        }
        for it in checklist:
            if not it["present"] and it["section"] in _NORULE_SECTION_DESC:
                audit_fields[it["section"]] = _NORULE_SECTION_DESC[it["section"]]

        if audit_fields:
            # Send ALL pages — later pages often hold the chromatogram/vial photo
            # the field audit needs (page-1-only would miss them).
            rendered_pngs = rendered_pngs or _render_pngs(file_bytes, filename)
            audit = llm_client.audit_completeness(ocr_text, rendered_pngs, audit_fields)
            confirmed_rules: list[str] = []
            confirmed_sections: list[str] = []
            sections_present: set[str] = set()
            for key, info in (audit.get("fields") or {}).items():
                if not (key in audit_fields and isinstance(info, dict)
                        and info.get("present") and _valid_audit_value(info.get("value"))
                        and _audit_value_consistent(key, info.get("value"))):
                    continue
                val = str(info.get("value"))[:80]
                if key in _PRESENCE_RULE_LABELS:  # a fired rule -> flip it (moves score)
                    for r in engine_out["rule_results"]:
                        if r["rule_id"] == key and r["status"] == "fired":
                            r["status"] = "pass"
                            r["confirmed_by"] = "visual"
                            r["visual_value"] = val
                            confirmed_rules.append(key)
                    if key in _RULE_TO_CHECKLIST_SECTION:
                        sections_present.add(_RULE_TO_CHECKLIST_SECTION[key])
                else:  # a no-rule checklist section -> checklist only
                    confirmed_sections.append(key)
                    sections_present.add(key)

            # Light up every confirmed checklist section (from rules or sections).
            for it in checklist:
                if it["section"] in sections_present and not it["present"]:
                    it["present"] = True
                    it["confirmed_by"] = "visual"

            if confirmed_rules:  # rebuild the rules-driven score, keep patched checklist
                _re = scoring.aggregate(engine_out["rule_results"])
                _re["completeness"]["checklist"] = checklist
                agg["completeness"] = _re["completeness"]
                agg["counts"] = _re["counts"]

            audit["confirmed_rule_ids"] = confirmed_rules
            audit["confirmed_sections"] = sorted(sections_present)
            llm_completeness = audit

    # Purity % + grade for the chip: prefer the OCR-parsed value, else recover it
    # from the vision audit's confirmed purity (when OCR dropped the number).
    purity_pct = hard_checks["purity_sanity"].get("purity")
    purity_grade = hard_checks["purity_sanity"].get("grade")
    if purity_pct is None:
        _pf = (llm_completeness.get("fields") or {}).get("STRUCT-008") or {}
        _pm = re.search(r"(\d{1,3}(?:\.\d+)?)\s*%", str(_pf.get("value") or ""))
        if _pm:
            purity_pct = float(_pm.group(1))
            purity_grade = purity_sanity.grade(purity_pct)

    # ---- Null-result content alert ('Not Detected' / 'n/a') ----------------
    # An authentic, verifiable COA can still report no measurable product. This
    # is a CONTENT signal, surfaced on its own and NEVER allowed to touch the
    # authenticity score. Text path is free; the vision read recovers the result
    # cells OCR drops (the common case) — gated to when the headline quantitative
    # results are missing from the deterministic parse, so it adds no cost to a
    # COA whose purity/assay already parsed cleanly.
    measured_mg = hard_checks["assay_mass"].get("measured_mg")
    alerts = result_alerts.from_text(ocr_text)
    if not alerts and llm_client.llm_enabled() and purity_pct is None and measured_mg is None:
        rendered_pngs = rendered_pngs or _render_pngs(file_bytes, filename)
        _read = llm_client.read_results(ocr_text, rendered_pngs)
        alerts = result_alerts.from_vision(_read.get("results"))

    # Orthogonality: a null-result row ("Purity: n/a") still means the test was
    # PERFORMED. Mark it present in the completeness checklist (was it tested?)
    # while the value concern is carried separately by the synthesis 'values'
    # section (what did it say?). Informational only — does not move the score.
    if alerts:
        _cat_to_section = {"purity": "purity", "quantity": "assay_mass"}
        _tested = {_cat_to_section[a["category"]] for a in alerts if a["category"] in _cat_to_section}
        for _it in (agg["completeness"].get("checklist") or []):
            if _it["section"] in _tested and not _it["present"]:
                _it["present"] = True
                _it["confirmed_by"] = "result_row"

    # Keep the band label consistent with the final (override-adjusted) score.
    _final = agg["authenticity"]["score"]
    agg["authenticity"]["label"] = scoring.band_label("authenticity", _final)
    # If the copy is still a generic band copy (no override set a specific
    # message), refresh it to the final band so copy and label can't disagree —
    # e.g. score bonuses lifting a "verify_recommended" into "likely_authentic".
    if agg["authenticity"]["copy"] in scoring.band_copies("authenticity"):
        agg["authenticity"]["copy"] = scoring.band_copy("authenticity", _final)

    notes = []
    if is_image:
        notes.append(
            "Image input: PDF-metadata rules (META-*) are not evaluable; "
            "authenticity score may be lower-confidence."
        )
    # Sparse OCR -> field-detection (and thus completeness) is unreliable. Warn
    # so a poor scan isn't read as a genuinely incomplete COA.
    if len(ocr_text.strip()) < _SPARSE_OCR_CHARS:
        notes.append(
            "Low-quality / low-text scan: little text could be read, so several "
            "fields may be present on the COA but not detected — completeness is "
            "likely understated. Try a clearer scan or the original PDF."
        )

    # Synthesis — the plain-language "authentic/complete/values because…" + an
    # evidence-framed recommendation, tying the three categories together.
    synthesis_obj = synthesis.build(
        authenticity=agg["authenticity"],
        completeness=agg["completeness"],
        checklist=agg["completeness"].get("checklist") or [],
        hard_checks=hard_checks,
        summary_bits={"purity_pct": purity_pct, "purity_grade": purity_grade},
        result_alerts=alerts,
        origin=origin,
    )

    return {
        "filename": filename,
        "input_type": "image" if is_image else "pdf",
        "authenticity": agg["authenticity"],
        "completeness": agg["completeness"],
        "synthesis": synthesis_obj,
        "summary": {
            "fired_critical_authenticity_rules": agg["fired_critical_rule_ids"],
            "rule_counts": agg["counts"],
            "peptide_detected": peptide_name,
            "peptide_detect_method": peptide_detect_method,
            "ms_technique_detected": ms_technique,
            "labeled_mass_mg": hard_checks["assay_mass"].get("labeled_mg"),
            "measured_assay_mg": hard_checks["assay_mass"].get("measured_mg"),
            "batch_lot": semantic_enrich.detect_batch(ocr_text),
            "purity_pct": purity_pct,
            "purity_grade": purity_grade,
        },
        "notes": notes,
        "limitations": LIMITATIONS,
        "result_alerts": alerts,
        "hard_checks": hard_checks,
        "rule_results": engine_out["rule_results"],
        "features": engine_out["features"],
        "llm": llm_out,
        "llm_completeness": llm_completeness,
    }
