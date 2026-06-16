#!/usr/bin/env python3
"""Calibrate the forum-insight checks added in 2026-06 against the existing
labeled corpus, using the already-cached OCR text (zero re-OCR).

Corpus (Rules/calibration/ocr_cache/*.txt):
  - orig_*  -> labeled REAL COA renders          (primary false-positive set)
  - fake_*  -> coa-faker perturbed FAKES
  - tmp*/named -> real SOURCE COAs (extra real-world false-positive set)

What matters here: the new advisory/scoring checks must NOT fire on genuine
COAs. Detection on `fake_*` is only meaningful where the faker actually
perturbs the relevant field, so the headline metric is the FALSE-POSITIVE rate
on the real sets.

Run from backend/:  .venv/bin/python calibrate_new_checks.py
"""
from __future__ import annotations
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from app.checks import (  # noqa: E402
    assay_mass, doc_type, known_labs, mw_table, purity_sanity, recency, verifiability,
)

CACHE = Path(__file__).resolve().parents[1] / "Rules" / "calibration" / "ocr_cache"
NOW = datetime(2026, 6, 1, tzinfo=timezone.utc)

# Statuses that represent the check "firing" / flagging (vs pass/not_applicable).
FLAG_STATUSES = {
    "verifiability": {"no_verification_path", "redacted"},
    "doc_type": {"manufacturer_qc"},
    "assay_mass": {"underdosed", "overfilled"},
    "recency": {"stale"},
    "purity_sanity": {"vague", "too_perfect"},
    "mw_formula": {"fired"},
}


def classify(name: str) -> str:
    if name.startswith("fake_"):
        return "fake"
    if name.startswith("orig_"):
        return "real_labeled"
    return "real_source"


def run_checks(text: str) -> dict[str, str]:
    det = mw_table.detect(text)
    pep = det["peptide"]["name"] if det else None
    mwr = mw_table.check(pep, text)
    # mw_formula status = "fired" only when the formula sub-check caused the fire
    mwf = "fired" if (mwr.get("status") == "fired" and mwr.get("mismatch_kind") == "formula") else "ok"
    # Resolve the issuing lab from text, as the real pipeline does, so the
    # registry verification portal + recognized-lab classification are available.
    known_lab = known_labs.check(text)
    return {
        "verifiability": verifiability.check(text, known_lab)["status"],
        "doc_type": doc_type.classify(text, known_lab)["status"],
        "assay_mass": assay_mass.check(text, pep)["status"],
        "recency": recency.check(text, now=NOW)["status"],
        "purity_sanity": purity_sanity.check(text)["status"],
        "mw_formula": mwf,
    }


def main() -> int:
    files = sorted(CACHE.glob("*.txt"))
    # status tallies: check -> class -> Counter(status)
    tally: dict[str, dict[str, Counter]] = defaultdict(lambda: defaultdict(Counter))
    class_counts: Counter = Counter()
    formula_fp_examples: list[str] = []

    for fp in files:
        cls = classify(fp.name)
        text = fp.read_text(encoding="utf-8", errors="ignore")
        if len(text.strip()) < 80:
            continue
        class_counts[cls] += 1
        res = run_checks(text)
        for check, status in res.items():
            tally[check][cls][status] += 1
            if check == "mw_formula" and status == "fired" and cls != "fake" and len(formula_fp_examples) < 8:
                formula_fp_examples.append(fp.name)

    real_total = class_counts["real_labeled"] + class_counts["real_source"]
    fake_total = class_counts["fake"]

    print("# Calibration: new forum-insight checks\n")
    print(f"Corpus: real_labeled={class_counts['real_labeled']}  "
          f"real_source={class_counts['real_source']}  fake={fake_total}  "
          f"(now={NOW.date()})\n")

    for check in FLAG_STATUSES:
        print(f"\n## {check}")
        # status distribution per class
        for cls in ("real_labeled", "real_source", "fake"):
            c = tally[check][cls]
            n = sum(c.values())
            if not n:
                continue
            dist = ", ".join(f"{s}={c[s]} ({100*c[s]//n}%)" for s in sorted(c))
            print(f"  {cls:12} n={n:4}  {dist}")
        # headline: false-positive rate on combined real
        real_flags = sum(tally[check][cls][s]
                         for cls in ("real_labeled", "real_source")
                         for s in FLAG_STATUSES[check])
        fake_flags = sum(tally[check]["fake"][s] for s in FLAG_STATUSES[check])
        fp = (100 * real_flags / real_total) if real_total else 0
        det = (100 * fake_flags / fake_total) if fake_total else 0
        print(f"  -> FLAG on REAL (false positive): {real_flags}/{real_total} = {fp:.1f}%"
              f"   |   FLAG on FAKE: {fake_flags}/{fake_total} = {det:.1f}%")

    if formula_fp_examples:
        print("\n## mw_formula false-positive examples (REAL flagged):")
        for n in formula_fp_examples:
            print(f"  - {n}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
