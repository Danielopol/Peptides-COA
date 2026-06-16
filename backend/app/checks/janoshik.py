"""Janoshik task-number + verification-key check (rule XREF-010).

Real Janoshik COAs always carry TWO distinct fields:
  1. Task Number  — "Task Number #NNNNNN"  (# prefix, 4-7 digits)
  2. Unique key   — a ~12-char alphanumeric code at the bottom, after
     "Verify this test at www.janoshik.com/verify/ with the following unique key"

A genuine Janoshik form has both. A repurposed/forged one typically has the
task number and/or unique key blurred, distorted, or missing. Missing the
unique key on a Janoshik-format COA is a critical authenticity flag.

Automated online verification is gated behind JANOSHIK_AUTOMATED=1 pending
ToS review; by default we return a deeplink for the user to verify.
"""
from __future__ import annotations
import os
import re

import httpx

VERIFY_URL = "https://janoshik.com/verification"

# OCR frequently mangles "Janoshik" -> "Janosuik", "jancenik", etc.
# Must be Janoshik-specific: a bare "/verify" collides with other labs'
# scan-to-verify language (e.g. AccuMark), so it is NOT a marker.
_JANOSHIK_MARKERS = re.compile(r"janos[hu]?ik|jancenik|janoshik\.com", re.I)

_TASK_RE = re.compile(r"task\s*number\s*#\s*(\d{4,7})", re.I)
# Unique key: appears after the "unique key" phrase. OCR often splits the
# ~12-char alnum key with spaces/newlines, so capture a run that may contain
# internal whitespace, then strip it and validate the length.
_KEY_CONTEXT_RE = re.compile(
    r"unique\s*key\s*[\s:.\-]*\n*\s*([A-Z0-9\\|IlO][A-Z0-9\\|IlO \t]{6,20})", re.I
)


def is_janoshik_coa(ocr_text: str) -> bool:
    return bool(_JANOSHIK_MARKERS.search(ocr_text or ""))


def extract_task_number(ocr_text: str) -> str | None:
    m = _TASK_RE.search(ocr_text or "")
    return m.group(1) if m else None


def extract_unique_key(ocr_text: str) -> str | None:
    m = _KEY_CONTEXT_RE.search(ocr_text or "")
    if not m:
        return None
    raw = m.group(1)
    # Strip OCR artifacts and internal whitespace.
    cleaned = re.sub(r"[\\|\s]", "", raw)
    # Genuine Janoshik keys are ~12-char UPPERCASE alphanumeric that include
    # digits (e.g. DAWP5HCLAV5W, 6X4TJKBT8VPK). Reject lowercase word-like
    # strings that forgers paste in place of the key (e.g. "Yewvyrvzve").
    if not (10 <= len(cleaned) <= 16):
        return None
    if sum(c.islower() for c in cleaned) > 2:
        return None
    if not any(c.isdigit() for c in cleaned):
        return None
    return cleaned.upper()


def check(ocr_text: str) -> dict:
    if not is_janoshik_coa(ocr_text):
        return {"status": "not_applicable", "reason": "not a Janoshik COA"}

    task = extract_task_number(ocr_text)
    key = extract_unique_key(ocr_text)

    missing = []
    if not task:
        missing.append("task number (#)")
    if not key:
        missing.append("unique verification key")

    if missing:
        return {
            "status": "fired",
            "rule_id": "XREF-010",
            "severity": "critical",
            "task_number": task,
            "unique_key": key,
            "missing_fields": missing,
            "message": (
                "Janoshik-format COA is missing required field(s): "
                + ", ".join(missing)
                + ". Genuine Janoshik reports always show both a #task number "
                "and a unique verification key — absence usually means the field "
                "was blurred or removed to repurpose someone else's report."
            ),
        }

    deeplink = f"{VERIFY_URL}/?key={key}"
    result = {
        "status": "pending_user_verification",
        "rule_id": "XREF-010",
        "task_number": task,
        "unique_key": key,
        "verification_url": deeplink,
        "message": f"Janoshik task #{task} with key {key} — tap to verify on janoshik.com/verify",
    }

    if os.environ.get("JANOSHIK_AUTOMATED") == "1":
        try:
            with httpx.Client(timeout=8.0) as client:
                resp = client.get(deeplink, headers={"User-Agent": "PeptideCOAScanner/0.1"})
            result["automated_lookup"] = {
                "http_status": resp.status_code,
                "response_excerpt": resp.text[:500] if resp.status_code == 200 else None,
            }
        except Exception as e:  # noqa: BLE001
            result["automated_lookup"] = {"error": str(e)}
    return result
