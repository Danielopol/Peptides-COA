"""Two-axis scoring.

- authenticity: is the COA genuine or tampered/forged?
- completeness: how thorough is the report — does it contain the expected
  analytical detail (purity, chromatogram, methods, lab credentials)?

A real-but-minimal COA scores HIGH authenticity, LOW completeness.
A polished forgery scores LOW authenticity, HIGH completeness.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AXIS_PATH = ROOT / "Rules" / "rule_axis_mapping.json"


def _load_axis_map() -> tuple[dict, dict]:
    data = json.loads(AXIS_PATH.read_text(encoding="utf-8"))
    rule_to_axis: dict[str, str] = {}
    for axis, rule_ids in data["axes"].items():
        for rid in rule_ids:
            rule_to_axis[rid] = axis
    return rule_to_axis, data["bands"]


def _band(score: int, bands: list[dict]) -> dict:
    for b in bands:
        if score >= b["min"]:
            return {"label": b["label"], "copy": b["copy"]}
    return {"label": "unknown", "copy": ""}


def band_label(axis: str, score: int) -> str:
    """Public helper: band label for a (possibly override-adjusted) score."""
    _, bands_cfg = _load_axis_map()
    return _band(score, bands_cfg[axis])["label"]


def band_copy(axis: str, score: int) -> str:
    """Public helper: the generic band copy for a score."""
    _, bands_cfg = _load_axis_map()
    return _band(score, bands_cfg[axis])["copy"]


def band_copies(axis: str) -> set[str]:
    """All generic band-copy strings for an axis — used to tell a generic band
    copy apart from a specific override message before refreshing it."""
    _, bands_cfg = _load_axis_map()
    return {b["copy"] for b in bands_cfg[axis]}


def aggregate(rule_results: list[dict]) -> dict:
    rule_to_axis, bands_cfg = _load_axis_map()

    axes = {
        "authenticity": {"fired_w": 0.0, "total_w": 0.0, "fired_rules": [], "passed_rules": []},
        "completeness": {"fired_w": 0.0, "total_w": 0.0, "fired_rules": [], "passed_rules": []},
    }
    counts = {"pass": 0, "fired": 0, "not_applicable": 0, "error": 0}
    fired_critical: list[str] = []

    for r in rule_results:
        status = r["status"]
        counts[status] = counts.get(status, 0) + 1
        axis = rule_to_axis.get(r["rule_id"], "completeness")
        if status not in ("pass", "fired"):
            continue
        w = float(r.get("weight", 1))
        axes[axis]["total_w"] += w
        if status == "fired":
            axes[axis]["fired_w"] += w
            axes[axis]["fired_rules"].append(r["rule_id"])
            if r.get("severity") == "critical" and axis == "authenticity":
                fired_critical.append(r["rule_id"])
        else:
            axes[axis]["passed_rules"].append(r["rule_id"])

    out: dict = {"counts": counts, "fired_critical_rule_ids": fired_critical}
    for axis, data in axes.items():
        score = (
            round(100 * (1 - data["fired_w"] / data["total_w"]))
            if data["total_w"] > 0 else 50
        )
        band = _band(score, bands_cfg[axis])
        out[axis] = {
            "score": score,
            "label": band["label"],
            "copy": band["copy"],
            "weight_in_axis": round(data["total_w"], 2),
            "weight_fired": round(data["fired_w"], 2),
            "fired_rule_ids": data["fired_rules"],
            "passed_rule_ids": data["passed_rules"],
        }
    return out
