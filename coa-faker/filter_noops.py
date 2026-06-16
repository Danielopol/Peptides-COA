"""
Produce a cleaned dataset that excludes no-op fakes (is_fake=True but no
perturbations actually landed). Reads output/manifest.csv + the JSON sidecars;
writes manifest_clean.csv and details_clean.jsonl alongside them.

Doesn't delete the original files or manifest — the clean versions are
additive so you can pick the dataset you want at training time.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path


def main(out_dir: Path) -> None:
    manifest = out_dir / "manifest.csv"
    details = out_dir / "details.jsonl"
    if not manifest.exists():
        sys.exit(f"missing {manifest}")

    rows = list(csv.DictReader(manifest.open()))
    fieldnames = list(rows[0].keys()) if rows else [
        "filename", "source_file", "perturbation_types",
        "difficulty", "is_fake", "label_json",
    ]

    kept, dropped = [], []
    for r in rows:
        if r["is_fake"] != "True":
            kept.append(r)
            continue
        label_path = r.get("label_json", "")
        if not label_path:
            dropped.append(r)
            continue
        sidecar = out_dir / label_path
        try:
            data = json.loads(sidecar.read_text())
        except Exception:
            dropped.append(r)
            continue
        if data.get("applied_perturbations"):
            kept.append(r)
        else:
            dropped.append(r)

    clean_manifest = out_dir / "manifest_clean.csv"
    with clean_manifest.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(kept)

    if details.exists():
        clean_details = out_dir / "details_clean.jsonl"
        kept_names = {r["filename"] for r in kept if r["is_fake"] == "True"}
        with details.open() as src, clean_details.open("w") as dst:
            for line in src:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("filename") in kept_names:
                    dst.write(line)

    n_total = sum(1 for r in rows if r["is_fake"] == "True")
    n_kept_fakes = sum(1 for r in kept if r["is_fake"] == "True")
    n_orig = sum(1 for r in rows if r["is_fake"] == "False")
    print(f"originals:        {n_orig}")
    print(f"fakes total:      {n_total}")
    print(f"fakes kept:       {n_kept_fakes}")
    print(f"fakes dropped:    {len(dropped)} (no perturbations applied)")
    print(f"wrote: {clean_manifest}")
    if details.exists():
        print(f"wrote: {out_dir/'details_clean.jsonl'}")


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("output")
    main(out)
