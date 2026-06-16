"""Generalized independent-verifiability signal (rule XREF-012, new).

The single most-repeated litmus test in the research-peptide community is:
"if you can't independently verify the COA on the lab's own site (QR code /
unique key / lookup portal), assume it's worthless." This generalizes the
Janoshik-specific task#+key check (XREF-010) to ANY issuer.

Outcomes:
  - verifiable          : a verification affordance is present (a known lab's
                          portal/URL, a generic /verify URL, a QR reference, or
                          a lookup code/key) -> surface a deeplink + how-to.
  - redacted            : a verification phrase is present but the code/key that
                          should follow it is missing -> classic "blanked to
                          repurpose someone else's report" tell.
  - no_verification_path : nothing to verify against -> strong red flag.
  - deferred_to_janoshik : a Janoshik COA; the janoshik check (XREF-010) owns it
                          so we don't double-count.

This check is text-based and deterministic. It never *confirms* a COA is real
(only the lab's portal can); it reports whether self-verification is even
possible, which is what the score should reward/penalize.
"""
from __future__ import annotations
import re

from . import janoshik

RULE_ID = "XREF-012"

# A phrase inviting verification ("verify this report at ...", "scan to verify",
# "searchable via <lab>.com", "search for your COA", "accession number").
_VERIFY_PHRASE = re.compile(
    r"verif(?:y|ication)|scan\s+to\s+verify|authenticate\s+this|"
    r"validate\s+this\s+(?:report|certificate|coa)|"
    r"searchable\s+(?:via|at|on)|search\s+for\s+your\s+coa|look\s*up\s+(?:this|your)\s+coa|"
    r"accession\s*(?:no\.?|number|#|code)?",
    re.I,
)
# A verification URL (…/verify) or a dedicated COA-lookup host (coa.<domain>).
_VERIFY_URL = re.compile(
    r"(https?://)?[\w.-]+\.[a-z]{2,}/verify\S*|(https?://)?coa\.[\w.-]+\.[a-z]{2,}",
    re.I,
)
# A QR-code reference (OCR rarely reads the QR itself, but the caption is text).
_QR = re.compile(r"\bqr\b|qr[\s-]?code|scan\s+(?:the\s+|this\s+)?(?:qr|code)", re.I)
# A VERIFICATION-SPECIFIC label (an identifier the user types into a portal).
# Deliberately excludes generic COA fields like "report number" / "sample id" /
# "certificate no" — those appear on almost every COA and are NOT a verification
# mechanism, so treating their absence-of-code as "redacted" false-positives on
# ordinary recognized-lab COAs (e.g. Vanguard).
_CODE_LABEL = re.compile(
    r"unique\s*key|verification\s*code|lookup\s*code|accession\s*(?:no\.?|number|#|code)?",
    re.I,
)
# An actual code/key token: a 6-20 char run containing BOTH a letter and a digit
# (e.g. AB12CD34, Tita2603230148). Case-insensitive so OCR's mixed case registers.
_CODE_TOKEN = re.compile(
    r"\b(?=[A-Za-z0-9-]{6,20}\b)(?=[A-Za-z0-9-]*[0-9])(?=[A-Za-z0-9-]*[A-Za-z])[A-Za-z0-9-]+\b"
)


def _has_code_after_label(text: str) -> bool:
    """Whether a code-token appears on or just after a code-label line — i.e. the
    lookup identifier the portal needs is actually present, not blanked out."""
    for m in _CODE_LABEL.finditer(text or ""):
        window = text[m.start(): m.end() + 60]
        if _CODE_TOKEN.search(window):
            return True
    return False


def _has_code_near_phrase(text: str) -> bool:
    """A code-token within ~120 chars after a verification phrase (e.g. an
    accession code printed under 'Searchable via ...')."""
    for m in _VERIFY_PHRASE.finditer(text or ""):
        if _CODE_TOKEN.search(text[m.end(): m.end() + 120]):
            return True
    return False


def _lab_verification_url(known_lab: dict | None) -> str | None:
    if not known_lab:
        return None
    v = known_lab.get("verification") or {}
    return v.get("url")


def check(ocr_text: str, known_lab: dict | None = None) -> dict:
    text = ocr_text or ""

    # Janoshik COAs are owned by the dedicated check (task# + unique key).
    if janoshik.is_janoshik_coa(text):
        return {
            "status": "deferred_to_janoshik",
            "rule_id": RULE_ID,
            "message": "Janoshik COA — verifiability handled by the Janoshik check.",
        }

    has_phrase = bool(_VERIFY_PHRASE.search(text))
    url_match = _VERIFY_URL.search(text)
    has_qr = bool(_QR.search(text))
    has_code_label = bool(_CODE_LABEL.search(text))
    has_code = _has_code_after_label(text) or _has_code_near_phrase(text)
    lab_url = _lab_verification_url(known_lab)

    # A verification path exists if we can point the user somewhere to check.
    if (url_match or lab_url or (has_phrase and has_code)
            or (has_qr and (has_code or lab_url)) or (has_code_label and has_code)):
        verification_url = lab_url or (url_match.group(0) if url_match else None)
        if verification_url and not verification_url.lower().startswith("http"):
            verification_url = "https://" + verification_url
        lab_name = (known_lab or {}).get("lab_name")
        where = f"on {lab_name}'s site" if lab_name else "on the issuing lab's site"
        return {
            "status": "verifiable",
            "rule_id": RULE_ID,
            "verification_url": verification_url,
            "via": "registry_lab" if lab_url else "document",
            "message": (
                f"This COA appears self-verifiable {where}. Independently verify "
                "it yourself — a verification path is the single strongest trust "
                "signal, but only confirms the tested sample, not your vial."
            ),
        }

    # A verification phrase/label is present but the code that should follow it
    # is missing -> the field was likely blanked to repurpose another's report.
    if (has_phrase or has_code_label or has_qr) and not has_code:
        return {
            "status": "redacted",
            "rule_id": RULE_ID,
            "severity": "major",
            "message": (
                "The COA references verification (a portal, QR, or lookup code) "
                "but the code/key that should accompany it is missing or blanked "
                "— a common sign a real report was repurposed."
            ),
        }

    return {
        "status": "no_verification_path",
        "rule_id": RULE_ID,
        "severity": "major",
        "message": (
            "No way to independently verify this COA was found (no verification "
            "portal, QR code, or lookup key). An unverifiable COA should not be "
            "trusted without independent testing."
        ),
    }
