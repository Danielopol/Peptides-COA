"""Evaluate the pipeline against the coa-faker synthetic set, broken down by
perturbation type. Answers: which perturbations does the pipeline catch?

A fake is "caught" if its authenticity score < CATCH_THRESHOLD.
We classify perturbations into must-catch (content tampering) vs tolerate
(scan artifacts) per the project decision, and report catch rate for each.

Run:
    .venv/bin/python eval_perturbations.py [N]
"""
from __future__ import annotations
import json
import random
import sys
from collections import defaultdict
from pathlib import Path

from app.scan import run_scan

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "coa-faker" / "output"
DETAILS = OUTPUT / "details.jsonl"

CATCH_THRESHOLD = 60     # authenticity below this = flagged as fake

MUST_CATCH = {"test_values", "batch_number", "dates", "names"}
TOLERATE = {"paper_cast", "contrast_noise", "dpi_quality", "jpeg_regions"}
# everything else (font_mismatch, metadata, logo_shift, alignment,
# page_structure, stamp_repaste, signature_shift) = secondary, reported but
# not held to a strict bar.


def applied_types(rec: dict) -> set[str]:
    types = {p.get("type") for p in rec.get("applied_perturbations", []) if p.get("type")}
    if not types:
        types = set(rec.get("requested_perturbations", []))
    return types


def main() -> None:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 150
    records = [json.loads(l) for l in DETAILS.read_text().splitlines() if l.strip()]
    random.seed(11)
    random.shuffle(records)
    records = records[:n]

    # per-type tallies, attributed only to SINGLE-perturbation fakes for clean signal
    single = defaultdict(lambda: {"total": 0, "caught": 0})
    anytype = defaultdict(lambda: {"total": 0, "caught": 0})
    overall = {"total": 0, "caught": 0}

    for i, rec in enumerate(records):
        path = OUTPUT / rec["filename"]
        if not path.exists():
            continue
        try:
            res = run_scan(path.read_bytes(), rec["filename"])
        except Exception as e:  # noqa: BLE001
            print(f"  ! {rec['filename']}: {e}")
            continue
        if "authenticity" not in res:
            continue
        score = res["authenticity"]["score"]
        caught = score < CATCH_THRESHOLD
        overall["total"] += 1
        overall["caught"] += caught

        types = applied_types(rec)
        for t in types:
            anytype[t]["total"] += 1
            anytype[t]["caught"] += caught
        if len(types) == 1:
            t = next(iter(types))
            single[t]["total"] += 1
            single[t]["caught"] += caught
        if (i + 1) % 25 == 0:
            print(f"  ...{i+1}/{len(records)} scanned")

    def fmt(d):
        return f"{d['caught']:>3}/{d['total']:<3} ({100*d['caught']/d['total']:.0f}%)" if d["total"] else "  n/a"

    def block(title, keys):
        print(f"\n{'='*64}\n{title}\n{'='*64}")
        print(f"  {'perturbation':<18} {'single-only':<18} {'appears-in-any'}")
        for t in sorted(keys):
            print(f"  {t:<18} {fmt(single[t]):<18} {fmt(anytype[t])}")

    print(f"\nOverall caught: {fmt(overall)} (threshold authenticity<{CATCH_THRESHOLD})")
    block("MUST-CATCH (content tampering)", MUST_CATCH)
    block("TOLERATE (scan artifacts — high catch = false-positive risk)", TOLERATE)
    secondary = (set(single) | set(anytype)) - MUST_CATCH - TOLERATE
    if secondary:
        block("SECONDARY (reported, no strict bar)", secondary)


if __name__ == "__main__":
    main()
