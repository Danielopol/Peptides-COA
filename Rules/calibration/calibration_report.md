# COA Rules Calibration Report (OCR-backed)

**Generated:** 2026-05-18
**Ruleset:** `Rules/coa_rules.json` (v1.0, 81 rules across 8 categories)
**Corpus:** `coa-faker/output/` — 292 originals + 1245 fakes
**Sample:** 100 originals + 100 fakes (stratified by difficulty: 33 easy / 47 medium / 20 hard)
**OCR:** tesseract 5.3.4 @ 200 dpi, cached in `ocr_cache/` (255 files, ~7 min cold; near-instant on re-run)
**Method:** Empirical fake-vs-orig flag-rate discrimination. Each rule's evaluator returns *fire* (suspicious), *pass*, or *n/a*. Discrimination *D* = fake_fire_rate − orig_fire_rate (Youden's J). New weight = original_weight × (1 + clip(D, −1, 1) × 0.6 if D > 0 else 0.5), clipped to [1, 10]. |D| < 0.05 = noise (weight unchanged).

## What OCR unlocked

With OCR, **57 of 81 rules are now evaluable** (up from 13 pre-OCR). Semantic parser extracts: peptide name, batch/lot ID, dates, purity %, lab/method/MS/HPLC/ISO-17025/C18 keywords, contact info, signatures, pass/fail wording.

24 rules remain non-evaluable from a single PDF in isolation: anything that needs a theoretical MS mass table (`NUM-004`, `NUM-010`, `XREF-002`), the vendor's vial/registry (`XREF-001`, `XREF-003`), corpus-level comparison (`FORG-004`, `FORG-005`), or real-world verification (`LAB-006..010`, `XREF-007`, `FORG-010..015`).

## Discriminative rules — weight increased

| Rule | What it catches | Orig | Fake | D | Weight |
|------|-----------------|------|------|----|--------|
| **FMT-003** Font consistency | `font_mismatch` perturbation injects a text layer that originals (pure-scan) don't have. | 8% | **54%** | +0.46 | 7 → **8.93** |
| **XREF-004** All dates chronologically plausible | `dates` perturbation produces date spans > 1 year or future dates. | 53% | **75%** | +0.22 | 9 → **10.0** (capped) |
| **META-004** Mod history clean | `metadata` perturbation sets modDate > 1 day from creationDate. | 0% | 14% | +0.14 | 6 → 6.49 |
| **META-002** Authoring software pro | `metadata` perturbation injects consumer creators ("Microsoft Word", personal-name authors). | 2% | 13% | +0.11 | 7 → 7.46 |
| **FORG-007** Localized pixelation | `jpeg_regions` / `dpi_quality` perturbations leave low-sharpness patches in otherwise sharp images. | 15% | 24% | +0.09 | 10 → 10.0 (capped) |

These five rules carry essentially all of the calibrated fake-detection signal. **Combined coverage is broad**: FMT-003 catches text-rewrite perturbations, XREF-004 catches date perturbations, FORG-007 catches image-quality perturbations, META-002/004 catch metadata perturbations.

## Anti-discriminative — weight decreased

| Rule | Why it backfires | Orig | Fake | D | Weight |
|------|------------------|------|------|----|--------|
| **FMT-005** No clone-stamp artifacts | Originals contain repeated embedded image bytes (logos reused across pages); perturbations *break* the duplication. | 79% | 43% | −0.36 | 9 → **7.38** |
| **NUM-007** HPLC wavelength standard | Some originals show non-standard wavelengths; fakes don't introduce new ones. | 25% | 0% | −0.25 | 5 → 4.38 |
| **FMT-002** Uniform resolution | DPI-variance heuristic noisy on multi-image originals. | 85% | 78% | −0.07 | 8 → 7.73 |
| **METH-005** MS technique type | Minor noise. | 97% | 91% | −0.06 | 5 → 4.85 |

`FMT-005` is the most important warning: the byte-level dedup implementation actively *prefers* originals. Either re-implement with localized pixel-correlation or replace it.

## No-signal rules (held at original weight)

48 evaluable rules fire at essentially equal rates on originals and fakes (|D| < 0.05). The common pattern: **the perturbation does not change whether the field is *present*, only its *value***. Examples:

- `STRUCT-002` (batch present): 15% orig / 14% fake — `batch_number` perturbation substitutes the ID, doesn't delete it. To catch a fake batch ID you'd need a vendor registry (out of scope for self-contained PDF analysis).
- `STRUCT-008` (purity present): 68% / 72% — `test_values` perturbation rewrites the number, doesn't remove it.
- `LAB-002` (ISO 17025 stated), `METH-003` (C18), `METH-004` (mobile phase), `METH-010..012` (LAL/ICP-MS/net peptide): fire 96–100% on **both** classes because these source COAs simply don't mention those terms. Not a rule problem; a corpus problem. Weight retained.

These rules are not removed because the *concept* is still sound — they just can't be calibrated against this particular set of perturbations on this particular corpus.

## Non-evaluable (24 rules)

Need data outside the PDF: theoretical MS mass tables, vendor product registries, vendor outreach, market data, multi-COA corpus-level comparison. Original weights preserved; flagged in calibrated JSON with explanatory note.

## Recommendations

1. **Trust the 5 discriminative rules in scoring.** They cover the four main perturbation classes that exist in this dataset.
2. **Replace or repair FMT-005** — the current byte-dedup proxy is actively wrong on this corpus.
3. **Don't penalize the 48 no-signal rules** — they're either uncatchable from a single PDF (need a registry) or the corpus doesn't exercise them. Keep as flags for human review.
4. **To catch value-substitution attacks** (the dominant perturbation class: 435 `test_values` + 230 `batch_number` + 43 `dates` + 10 `names`), add cross-reference rules backed by **a peptide MW table + a vendor batch registry**. That's the next calibration ceiling.

## Calibration formula

```
factor = 1 + clip(discrim, -1, 1) * (0.6 if discrim > 0 else 0.5)
new_weight = clip(original_weight * factor, 1.0, 10.0)
```

|D| < 0.05 → keep original weight. Non-evaluable rules → keep original weight, mark with note.

## Outputs

- `Rules/calibration/calibrate.py` — OCR + evaluator + calibration driver. Re-run any time; OCR is cached so subsequent runs are fast.
- `Rules/calibration/calibration_results.json` — full per-rule numbers (sample sizes, fire rates, discrimination, before/after weight).
- `Rules/calibration/coa_rules_calibrated.json` — drop-in replacement for `coa_rules.json` (v1.1-calibrated). Each rule has a `calibration` object with metrics that drove the new weight.
- `Rules/calibration/ocr_cache/` — per-PDF OCR text (255 files, ~172 KB).
