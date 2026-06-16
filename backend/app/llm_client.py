"""Gemini vision second-opinion pass.

Runs ONLY on ambiguous COAs (gated in scan.py) to catch visual tampering the
deterministic rules can't see — blurred/pasted fields, altered lab names,
distorted QR codes. Uses a lean prompt (the full ruleset already ran
deterministically) and returns a parsed structured verdict.
"""
from __future__ import annotations
import json
import os
import re

MODEL = os.environ.get("LLM_MODEL", "gemini-2.5-flash-lite")

LEAN_PROMPT = """You are a forensic reviewer of peptide Certificates of Analysis (COAs).
You are given a COA image and its OCR text. Automated rule checks have ALREADY run;
your job is to catch VISUAL tampering and inconsistencies that automated rules miss.

Look specifically for:
- Fields that appear blurred, smudged, erased, whited-out, or pasted over — especially
  the lab/issuer name, task/report number, client name, QR code, verification key, dates, results
- Text with mismatched fonts, sizes, weights, or alignment that suggests edits
- A QR code or verification stamp that is missing, distorted, or unreadable
- Inconsistencies between what the image shows and the OCR text
- Signs the document reuses another lab's template with details swapped

Respond with ONLY a JSON object, no prose:
{
  "verdict": "authentic" | "suspicious" | "likely_forged",
  "confidence": 0.0-1.0,
  "visual_tampering": true | false,
  "lab_name_altered": true | false,
  "findings": ["short, specific observations"],
  "summary": "one sentence"
}

Be conservative: only "likely_forged" when there is CLEAR visual evidence of tampering
(e.g. a field deliberately blurred or pasted over). A low-quality or sparse but
untampered scan is "authentic" or "suspicious", never "likely_forged"."""


def llm_enabled() -> bool:
    return os.environ.get("ENABLE_LLM", "false").lower() == "true" and bool(
        os.environ.get("GEMINI_API_KEY")
    )


def _parse_json(text: str) -> dict | None:
    if not text:
        return None
    # tolerate ```json fences or surrounding prose
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except json.JSONDecodeError:
        return None


AUDIT_PROMPT = """You are reviewing a peptide Certificate of Analysis (COA) image.
Automated text extraction (OCR) FAILED to find the fields listed below — but OCR
routinely misses fields that ARE clearly on the page: stamps, signatures,
handwriting, small or low-contrast text, text inside logos, or values printed
beside an unlabeled heading.

Look at the IMAGE (and OCR text) and decide, for EACH field, whether it is
actually present on the document. Mark present=true ONLY if you can actually see
it AND can quote its concrete value/text verbatim from the document. If you
cannot see it, present=false. Do NOT guess or infer; only report what is visibly
printed.

Fields to check (key: what to look for):
{fields}

Respond with ONLY this JSON, no prose:
{{ "fields": {{ "<key>": {{"present": true|false, "value": "<verbatim text you see, else empty>"}} }} }}"""


RESULTS_PROMPT = """You are reading the analytical RESULTS table of a peptide
Certificate of Analysis (COA).

For EACH row in the results / analysis table, report the analysis name, the
method, and the RESULT exactly as printed. Read the RESULT verbatim — it may be a
numeric value (e.g. "99.1%", "5.2 mg", "36 IU") OR a NULL result such as
"Not Detected", "ND", "n/a", "N/A", "< LOQ", "below LOD", "0", "undetectable".
Look at the IMAGE; OCR often drops these small result cells. Do NOT infer or fill
in values — report only what is printed. If there is no results table at all,
return an empty list.

Respond with ONLY this JSON, no prose:
{ "results": [ {"analysis": "<name>", "method": "<method or empty>", "result": "<verbatim result>"} ] }"""


def read_results(ocr_text: str, image_pngs) -> dict:
    """Vision read of the analytical RESULTS table — used to recover result
    VALUES (esp. null results like 'Not Detected' / 'n/a') that OCR routinely
    drops from small tabular cells. Read-only: callers turn null results into a
    content alert; it never touches the authenticity score."""
    if not llm_enabled():
        return {"enabled": False, "results": []}
    try:
        import google.generativeai as genai
    except ImportError:
        return {"enabled": False, "error": "google-generativeai not installed", "results": []}

    genai.configure(api_key=os.environ["GEMINI_API_KEY"])
    model = genai.GenerativeModel(MODEL)
    parts: list = [RESULTS_PROMPT, f"\n\nOCR text from the COA:\n{(ocr_text or '')[:6000]}"]
    if isinstance(image_pngs, (bytes, bytearray)):
        image_pngs = [image_pngs]
    for _png in (image_pngs or []):
        if _png:
            parts.append({"mime_type": "image/png", "data": _png})
    try:
        resp = model.generate_content(
            parts,
            generation_config={"response_mime_type": "application/json", "temperature": 0.0},
        )
    except Exception as e:  # noqa: BLE001
        return {"enabled": True, "error": str(e), "results": []}
    parsed = _parse_json(getattr(resp, "text", "") or "")
    if parsed is None:
        return {"enabled": True, "error": "could not parse JSON", "results": []}
    res = parsed.get("results")
    return {"enabled": True, "model": MODEL, "results": res if isinstance(res, list) else []}


def audit_completeness(ocr_text: str, image_pngs, fields: dict[str, str]) -> dict:
    """Vision presence-audit: confirm which OCR-missed COA fields are actually on
    the page(s), quoting each value. Presence-only (callers must use it to raise
    completeness, never to lower a score). `fields` maps a key (rule_id or
    checklist section id) -> description. `image_pngs` is a single PNG or a list
    of page PNGs (later pages often hold the chromatogram / vial photo)."""
    if not llm_enabled():
        return {"enabled": False, "note": "Set ENABLE_LLM=true and GEMINI_API_KEY to activate"}
    if not fields:
        return {"enabled": False, "note": "no fields to audit"}
    try:
        import google.generativeai as genai
    except ImportError:
        return {"enabled": False, "error": "google-generativeai not installed"}

    genai.configure(api_key=os.environ["GEMINI_API_KEY"])
    model = genai.GenerativeModel(MODEL)
    field_lines = "\n".join(f"- {k}: {v}" for k, v in fields.items())
    parts: list = [
        AUDIT_PROMPT.format(fields=field_lines),
        f"\n\nOCR text from the COA:\n{(ocr_text or '')[:6000]}",
    ]
    if isinstance(image_pngs, (bytes, bytearray)):
        image_pngs = [image_pngs]
    for _png in (image_pngs or []):
        if _png:
            parts.append({"mime_type": "image/png", "data": _png})

    try:
        resp = model.generate_content(
            parts,
            generation_config={"response_mime_type": "application/json", "temperature": 0.0},
        )
    except Exception as e:  # noqa: BLE001
        return {"enabled": True, "error": str(e)}

    usage = {}
    um = getattr(resp, "usage_metadata", None)
    if um is not None:
        usage = {
            "input_tokens": getattr(um, "prompt_token_count", None),
            "output_tokens": getattr(um, "candidates_token_count", None),
            "total_tokens": getattr(um, "total_token_count", None),
        }
    parsed = _parse_json(getattr(resp, "text", "") or "")
    if parsed is None:
        return {"enabled": True, "error": "could not parse JSON",
                "raw": getattr(resp, "text", "")[:500], "usage": usage}
    return {"enabled": True, "model": MODEL, "usage": usage, "fields": parsed.get("fields", {})}


def assess(ocr_text: str, image_png: bytes | None = None) -> dict:
    if not llm_enabled():
        return {"enabled": False, "note": "Set ENABLE_LLM=true and GEMINI_API_KEY to activate"}
    try:
        import google.generativeai as genai
    except ImportError:
        return {"enabled": False, "error": "google-generativeai not installed"}

    genai.configure(api_key=os.environ["GEMINI_API_KEY"])
    model = genai.GenerativeModel(MODEL)

    parts: list = [LEAN_PROMPT, f"\n\nOCR text from the COA:\n{(ocr_text or '')[:6000]}"]
    if image_png:
        parts.append({"mime_type": "image/png", "data": image_png})

    try:
        resp = model.generate_content(
            parts,
            generation_config={"response_mime_type": "application/json", "temperature": 0.0},
        )
    except Exception as e:  # noqa: BLE001
        return {"enabled": True, "error": str(e)}

    usage = {}
    um = getattr(resp, "usage_metadata", None)
    if um is not None:
        usage = {
            "input_tokens": getattr(um, "prompt_token_count", None),
            "output_tokens": getattr(um, "candidates_token_count", None),
            "total_tokens": getattr(um, "total_token_count", None),
        }

    parsed = _parse_json(getattr(resp, "text", "") or "")
    if parsed is None:
        return {"enabled": True, "error": "could not parse JSON",
                "raw": getattr(resp, "text", "")[:500], "usage": usage}
    return {"enabled": True, "model": MODEL, "usage": usage, **parsed}
