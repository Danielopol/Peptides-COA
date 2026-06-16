"""Match the COA's issuing lab/vendor against the registry (rule LAB-009).

Three outcomes when unmatched, so scoring can grade the penalty:
  - recognized        : issuer is in the registry (trust bonus applies)
  - unrecognized_named : a lab-like name is present but not catalogued
                         (mild "verify the lab" signal)
  - no_issuer          : no testing-lab name detectable at all
                         (stronger red flag per the source articles)
"""
from __future__ import annotations
import re

from .. import registry

# Tokens that indicate a testing-lab / issuer name is present on the document.
_LAB_INDICATORS = re.compile(
    r"\b(?:laborator(?:y|ies)|labs?|analytical?s?|analytics|diagnostics?|"
    r"bioscience(?:s)?|biolabs?|bio\s?labs?|proteomics|bioanalytical|"
    r"testing\s+(?:lab|services|laborator))\b",
    re.IGNORECASE,
)


def check(ocr_text: str) -> dict:
    entity = registry.match_in_text(ocr_text)
    if entity is not None:
        result = {
            "status": "pass",
            "rule_id": "LAB-009",
            "entity_id": entity["id"],
            "entity_kind": entity["entity_kind"],
            "lab_name": entity["name"],
            "trust": entity.get("trust", "unknown"),
        }
        if entity.get("caveat"):
            result["caveat"] = entity["caveat"]
        if entity.get("verification"):
            result["verification"] = entity["verification"]
        return result

    if _LAB_INDICATORS.search(ocr_text or ""):
        return {
            "status": "unrecognized_named",
            "rule_id": "LAB-009",
            "severity": "minor",
            "message": "A testing-lab name is present but not in our verified registry — verify the lab independently.",
        }
    return {
        "status": "no_issuer",
        "rule_id": "LAB-009",
        "severity": "major",
        "message": "No testing-laboratory name found on the COA — a classic red flag.",
    }
