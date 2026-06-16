"""Wraps the existing calibrate.py evaluators as a callable for the backend.

Imports the evaluator stack directly from Rules/calibration/calibrate.py so
there is one source of truth for rule logic.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CALIBRATION_DIR = ROOT / "Rules" / "calibration"
sys.path.insert(0, str(CALIBRATION_DIR))

import calibrate  # noqa: E402  (Rules/calibration/calibrate.py)

from .checks import semantic_enrich  # noqa: E402

# Presence rules whose eval_rule logic is a narrow keyword/text regex that misses
# real fields printed without the expected label. After a rule fires (=missing),
# a robust detector rechecks the text and clears the false "missing" (fired→pass
# only — never the reverse). STRUCT-002 (batch) is already handled via the
# enriched `semantic` dict, so only the text-regex rules need this.
_PRESENCE_RECHECK = {
    "STRUCT-012": lambda text: semantic_enrich.detect_client(text) is not None,  # client/sponsor
}


def load_rules(rules_path: Path) -> list[dict]:
    """Supports both schemas: original {rule_categories: [...]} and
    calibrated {categories: {cat_id: [rules]}}."""
    data = json.loads(rules_path.read_text(encoding="utf-8"))
    flat: list[dict] = []
    if "rule_categories" in data:
        for cat in data["rule_categories"]:
            for rule in cat.get("rules", []):
                rule["_category"] = cat.get("category_id")
                flat.append(rule)
    elif "categories" in data:
        for cat_id, rules in data["categories"].items():
            for rule in rules:
                rule["_category"] = cat_id
                flat.append(rule)
    return flat


def evaluate(pdf_path: Path, rules: list[dict], ocr_text: str | None = None) -> dict:
    feat = calibrate.extract_features(pdf_path)
    # Prefer the pipeline's OCR text if supplied (keeps the rule engine consistent
    # with the rest of the scan), then robustly enrich the presence signals so
    # compact real COAs don't false-fire completeness rules as "missing".
    if ocr_text is not None and ocr_text.strip():
        feat["ocr_text"] = ocr_text
        feat["semantic"] = calibrate.parse_ocr(ocr_text)
    feat["semantic"] = semantic_enrich.enrich(feat.get("semantic") or {}, feat.get("ocr_text", ""))
    results = []
    for rule in rules:
        try:
            fired = calibrate.eval_rule(rule["rule_id"], feat, None)
        except Exception as e:  # noqa: BLE001
            fired = None
            results.append({
                "rule_id": rule["rule_id"],
                "name": rule.get("name"),
                "category": rule["_category"],
                "weight": rule.get("weight", 1),
                "severity": rule.get("severity"),
                "status": "error",
                "error": str(e),
            })
            continue
        if fired is None:
            status = "not_applicable"
        elif fired:
            status = "fired"
        else:
            status = "pass"
        if status == "fired":
            recheck = _PRESENCE_RECHECK.get(rule["rule_id"])
            if recheck and recheck(feat.get("ocr_text", "")):
                status = "pass"
        results.append({
            "rule_id": rule["rule_id"],
            "name": rule.get("name"),
            "category": rule["_category"],
            "weight": rule.get("weight", 1),
            "severity": rule.get("severity"),
            "status": status,
        })
    return {"features": _safe_features(feat), "rule_results": results}


def _safe_features(feat: dict) -> dict:
    """Strip numpy / large blobs so the dict is JSON-serializable."""
    out = {}
    for k, v in feat.items():
        if isinstance(v, (str, int, float, bool)) or v is None:
            out[k] = v
        elif isinstance(v, (list, tuple)) and all(
            isinstance(x, (str, int, float, bool)) for x in v
        ):
            out[k] = list(v)
        elif isinstance(v, dict):
            out[k] = {
                kk: vv for kk, vv in v.items()
                if isinstance(vv, (str, int, float, bool)) or vv is None
            }
    return out
