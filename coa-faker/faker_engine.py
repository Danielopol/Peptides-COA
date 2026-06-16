"""
COA Faker — synthetic-data generator for training a COA authenticity classifier.

Reads authentic Certificate-of-Analysis PDFs from --input, applies 1-3 random
perturbations per fake, writes results + a manifest.csv to --output. Originals
are also copied to output and listed in the manifest with is_fake=False so the
output dir is a self-contained labelled dataset.

Every generated fake is tagged with a hidden synthetic-data marker (set in
config.yaml > synthetic_marker) embedded in the PDF /Keywords field, so leaked
files can be programmatically identified as training artifacts.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import shutil
import sys
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

import fitz  # PyMuPDF
import yaml
from faker import Faker

import perturbations as P


# ---------- config ----------

@dataclass
class Config:
    fakes_per_original: int
    difficulty_distribution: dict
    perturbation_weights: dict
    image_render_dpi: int
    output_format: str
    seed: int
    synthetic_marker: str

    @classmethod
    def load(cls, path: Path) -> "Config":
        data = yaml.safe_load(path.read_text())
        return cls(
            fakes_per_original=int(data["fakes_per_original"]),
            difficulty_distribution=data["difficulty_distribution"],
            perturbation_weights=data["perturbation_weights"],
            image_render_dpi=int(data.get("image_render_dpi", 300)),
            output_format=data.get("output_format", "pdf"),
            seed=int(data.get("seed", 42)),
            synthetic_marker=data.get(
                "synthetic_marker", "X-Synthetic-Training-Data: coa-faker"
            ),
        )


# ---------- difficulty selection ----------

def pick_difficulty(rng: random.Random, dist: dict) -> str:
    levels = list(dist.keys())
    weights = [float(dist[k]) for k in levels]
    return rng.choices(levels, weights=weights, k=1)[0]


def pick_perturbations(rng: random.Random, difficulty: str,
                       weights: dict) -> List[str]:
    pool = P.DIFFICULTY_POOLS[difficulty]
    available = [p for p in pool if weights.get(p, 0) > 0]
    if not available:
        return []
    n = rng.randint(1, min(3, len(available)))
    w = [weights[p] for p in available]
    chosen = []
    candidates = available.copy()
    cand_w = w.copy()
    for _ in range(n):
        if not candidates:
            break
        pick = rng.choices(candidates, weights=cand_w, k=1)[0]
        idx = candidates.index(pick)
        candidates.pop(idx)
        cand_w.pop(idx)
        chosen.append(pick)
    return chosen


# ---------- marker ----------

def stamp_synthetic_marker(doc: fitz.Document, marker: str,
                           source_sha: str) -> None:
    """Embed a hidden tag identifying this PDF as synthetic training data."""
    md = doc.metadata or {}
    existing_kw = md.get("keywords") or ""
    tag = f"{marker}; src_sha256={source_sha}"
    md["keywords"] = (existing_kw + "; " + tag).strip("; ")
    doc.set_metadata(md)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------- generation ----------

def generate_one_fake(src_path: Path, out_path: Path, difficulty: str,
                      perts: List[str], rng: random.Random, cfg: Config,
                      faker_inst: Faker, src_sha: str) -> List[dict]:
    """Returns the list of structured change-dicts actually applied."""
    doc = fitz.open(src_path)
    meta_for_perts = {"faker": faker_inst, "render_dpi": cfg.image_render_dpi}
    applied: List[dict] = []
    for name in perts:
        fn = P.PERTURBATIONS[name]
        try:
            result = fn(doc, rng, meta_for_perts)
            if result:
                applied.append(result)
        except Exception as e:
            print(f"    warn: perturbation '{name}' failed: {e}", file=sys.stderr)
    stamp_synthetic_marker(doc, cfg.synthetic_marker, src_sha)
    doc.save(out_path, garbage=4, deflate=True)
    doc.close()
    return applied


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--config", required=True, type=Path)
    args = ap.parse_args()

    cfg = Config.load(args.config)
    args.output.mkdir(parents=True, exist_ok=True)

    rng = random.Random(cfg.seed)
    faker_inst = Faker()
    Faker.seed(cfg.seed)

    pdfs = sorted([p for p in args.input.rglob("*.pdf") if p.is_file()])
    if not pdfs:
        print(f"No PDFs found under {args.input}", file=sys.stderr)
        sys.exit(1)

    manifest_path = args.output / "manifest.csv"
    details_path = args.output / "details.jsonl"
    sidecar_dir = args.output / "labels"
    sidecar_dir.mkdir(exist_ok=True)
    with manifest_path.open("w", newline="") as mf, \
            details_path.open("w") as df:
        writer = csv.writer(mf)
        writer.writerow([
            "filename", "source_file", "perturbation_types",
            "difficulty", "is_fake", "label_json",
        ])

        total_fakes = 0
        for i, src in enumerate(pdfs, start=1):
            # copy original
            orig_out_name = f"orig_{i:04d}_{src.stem}.pdf"
            orig_out = args.output / orig_out_name
            try:
                shutil.copy2(src, orig_out)
            except Exception as e:
                print(f"warn: could not copy {src}: {e}", file=sys.stderr)
                continue
            writer.writerow([orig_out_name, src.name, "", "", "False", ""])

            # validate parseability
            try:
                d = fitz.open(src)
                if d.page_count == 0:
                    raise RuntimeError("0 pages")
                d.close()
            except Exception as e:
                print(f"warn: skipping unparseable {src.name}: {e}",
                      file=sys.stderr)
                continue

            src_sha = sha256_of(src)

            for k in range(1, cfg.fakes_per_original + 1):
                difficulty = pick_difficulty(rng, cfg.difficulty_distribution)
                perts = pick_perturbations(rng, difficulty,
                                           cfg.perturbation_weights)
                fake_name = f"fake_{i:04d}_{k:03d}_{difficulty}.pdf"
                fake_out = args.output / fake_name
                print(f"[{i}/{len(pdfs)}] Generating {difficulty} fake from "
                      f"{src.name} → {fake_name}")
                try:
                    applied = generate_one_fake(
                        src, fake_out, difficulty, perts, rng, cfg,
                        faker_inst, src_sha,
                    )
                except Exception as e:
                    print(f"  error generating {fake_name}: {e}",
                          file=sys.stderr)
                    traceback.print_exc(file=sys.stderr)
                    continue
                types = [a.get("type", "?") for a in applied]
                label_payload = {
                    "filename": fake_name,
                    "source_file": src.name,
                    "source_sha256": src_sha,
                    "difficulty": difficulty,
                    "requested_perturbations": perts,
                    "applied_perturbations": applied,
                }
                sidecar_name = f"{Path(fake_name).stem}.json"
                (sidecar_dir / sidecar_name).write_text(
                    json.dumps(label_payload, indent=2)
                )
                df.write(json.dumps(label_payload) + "\n")
                writer.writerow([
                    fake_name, src.name, ",".join(types),
                    difficulty, "True", f"labels/{sidecar_name}",
                ])
                total_fakes += 1

    print(f"\nDone. {len(pdfs)} originals copied, {total_fakes} fakes generated.")
    print(f"Manifest: {manifest_path}")
    print(f"Details:  {details_path}")
    print(f"Labels:   {sidecar_dir}/")


if __name__ == "__main__":
    main()
