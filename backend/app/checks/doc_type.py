"""Document-type classification (rule DOC-001, new).

The research-peptide community draws a sharp line between an *independent
third-party lab report* and an *in-house / manufacturer QC report* — the latter
is widely treated as near-worthless for trust ("it's an internal COA and means
nothing"). The most reliable tell, repeated in the forums, is the presence of
storage / stability instructions on the document:

    "You can see at the bottom where they are giving storage instructions.
     A testing lab wouldn't do that. This is either from the manufacturer or
     it is fake."

This check classifies the document so the UI can caveat it. It is INFORMATIONAL
— it never moves the authenticity score, because a genuine manufacturer QC
report is authentic (just weak evidence). The trust nuance belongs in
presentation, not in the forgery score.

Outcomes (returned in `status`):
  - third_party_lab : issued by a recognized independent lab, or carries
                      independent-lab / third-party language and no manufacturer
                      markers.
  - manufacturer_qc : storage/stability block, manufacturer/in-house language,
                      or a vendor (not a lab) named as the issuer.
  - unknown         : not enough signal to tell.
"""
from __future__ import annotations
import re

RULE_ID = "DOC-001"

# Storage / stability handling instructions — a manufacturer/QC hallmark.
_STORAGE_KW = re.compile(
    r"storage|stability|shelf[-\s]?life|store\s+at|keep\s+(?:refrigerated|frozen)|"
    r"reconstitut\w+\s+(?:storage|stability)",
    re.I,
)
# A temperature token (e.g. "-80°C", "4 C", "20°C") — pairs with storage to
# confirm a real storage block rather than an incidental mention.
_TEMP = re.compile(r"-?\s*\d{1,3}\s*°?\s*c\b", re.I)
# Duration token typical of a stability table.
_DURATION = re.compile(r"\b\d+\s*(?:months?|days?|weeks?|years?)\b", re.I)

# Manufacturer / in-house / production language.
_MFR = re.compile(
    r"manufactur(?:er|ed\s+by)|in[-\s]?house|production\s*date|batch\s*release|"
    r"finished[-\s]?product\s+specification|qc\s*(?:report|certificate)|"
    r"manufacturing\s+(?:date|lot)",
    re.I,
)
# Independent / third-party language.
_THIRD_PARTY = re.compile(
    r"third[-\s]?party|independent\s+(?:lab\w*|analy\w+|testing)|contract\s+lab\w*",
    re.I,
)


def _has_storage_block(text: str) -> bool:
    if not _STORAGE_KW.search(text):
        return False
    # Require corroboration so a one-word "storage" footnote doesn't fire.
    return bool(_TEMP.search(text)) or bool(_DURATION.search(text))


def classify(ocr_text: str, known_lab: dict | None = None) -> dict:
    text = ocr_text or ""
    known_lab = known_lab or {}
    signals: list[str] = []

    storage = _has_storage_block(text)
    has_mfr = bool(_MFR.search(text))
    has_third_party = bool(_THIRD_PARTY.search(text))
    if storage:
        signals.append("storage/stability instructions present")
    if has_mfr:
        signals.append("manufacturer/in-house/QC language")
    if has_third_party:
        signals.append("independent / third-party language")

    lab_pass = known_lab.get("status") == "pass"
    entity_kind = known_lab.get("entity_kind")
    lab_name = known_lab.get("lab_name")

    # 1. Recognized independent LAB issuer -> third-party (highest confidence).
    if lab_pass and entity_kind == "lab":
        signals.append(f"issuer is a recognized lab ({lab_name})")
        msg = (
            f"Issued by {lab_name}, a recognized independent testing lab — this "
            "is third-party analysis."
        )
        if storage or has_mfr:
            # Genuine lab reports rarely carry storage/stability handling; note it
            # but don't override the recognized-lab classification.
            msg += (
                " Note: it also carries manufacturer-style content (storage/QC), "
                "which is unusual for a pure lab report."
            )
        return {
            "status": "third_party_lab",
            "rule_id": RULE_ID,
            "confidence": "high",
            "signals": signals,
            "message": msg,
        }

    # 2. A vendor (not a lab) named as issuer -> in-house/vendor document.
    if lab_pass and entity_kind == "vendor":
        signals.append(f"issuer is a vendor ({lab_name})")
        return {
            "status": "manufacturer_qc",
            "rule_id": RULE_ID,
            "confidence": "high",
            "signals": signals,
            "message": (
                f"Issued by the vendor/seller ({lab_name}) rather than an "
                "independent lab — treat as an in-house document, not third-party "
                "verification."
            ),
        }

    # 3. No recognized lab: lean on content markers.
    if storage or has_mfr:
        return {
            "status": "manufacturer_qc",
            "rule_id": RULE_ID,
            "confidence": "high" if (storage and has_mfr) else "medium",
            "signals": signals,
            "message": (
                "This looks like a manufacturer / in-house QC report (it carries "
                + ("storage/stability instructions" if storage else "manufacturer language")
                + "), not an independent third-party lab test. The community "
                "considers in-house COAs weak evidence — seek independent testing."
            ),
        }

    if has_third_party:
        return {
            "status": "third_party_lab",
            "rule_id": RULE_ID,
            "confidence": "low",
            "signals": signals,
            "message": (
                "The document claims independent / third-party testing, but the "
                "issuing lab isn't recognized — verify the lab itself before "
                "relying on it."
            ),
        }

    return {
        "status": "unknown",
        "rule_id": RULE_ID,
        "confidence": "low",
        "signals": signals,
        "message": "Could not determine whether this is a third-party or in-house report.",
    }
