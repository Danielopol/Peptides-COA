# Calibration — forum-insight checks (2026-06-01)

Calibrates the checks added from the Reddit/forum analysis (see memory
`peptides-forum-insights`) against the existing labeled corpus, using the
already-cached OCR text in `ocr_cache/` (no re-OCR).

Reproduce: `cd backend && .venv/bin/python calibrate_new_checks.py`

## Corpus (from `ocr_cache/*.txt`)
- `real_labeled` = 155  (`orig_*` — labeled genuine COA renders)
- `real_source`  = 805  (`tmp*`/named — real source COAs)
- `fake`         = 100  (`fake_*` — coa-faker perturbations)
- reference date `now = 2026-06-01`

Headline metric = **false-positive rate on the combined real set (960)**. The
coa-faker fakes perturb metadata/image/layout, not these text fields, so a low
fire rate on `fake` is expected and is NOT evidence the check is weak — the
dedicated forgery checks (janoshik key, visual_lab, metadata) catch those.

## Results (with `known_lab` resolved from text, as the live pipeline does)

| check | FP on REAL | notes |
|---|---|---|
| `mw_formula` (XREF-009) | **0.0%** | never false-fires; high precision. Keep. |
| `assay_mass` (FORG-018) | **0.4%** | 0 underdosed on real; 4 benign `overfilled` (no penalty). Keep. |
| `purity_sanity` (FORG-019) | **0.6%** | a few `vague`, no `too_perfect`; advisory. Keep. |
| `doc_type` (DOC-001) | **4.5%** | 93–100% `third_party_lab`; 5% `manufacturer_qc` (storage text + unrecognized issuer — plausibly correct). Keep. |
| `recency` (META-006) | 17.5% `stale` | ACCURATE, not a false positive — these are genuinely >6-month-old COAs. Advisory (caps to ≤70 only). Keep. |
| `verifiability` (XREF-012) | 24.9% → **tuned** | see below. |

### First pass bug found
Running with `known_lab=None` gave `doc_type` 66.6% FP — because the
recognized-lab → third-party path was disabled. The live pipeline always
supplies the reconciled `known_lab`; with it resolved, FP fell to 4.5%. The
calibration script now mirrors production (resolves `known_lab` from text).

## Tuning applied (scan.py score caps only — check statuses unchanged)

`verifiability` is a **trust/verify** signal, not a forgery signal: ~20% of
GENUINE non-Janoshik COAs have no online verification portal. The old caps
branded them as suspicious/forged. Recalibrated:

- `no_verification_path`: cap **50 → 70** (lands in *verify_recommended*, not
  *suspicious*). Matches the accurate message "verify further", not "likely fake".
- `redacted`: was cap 30 + forced `likely_forged`; now cap **55, no forged
  label** (OCR-noisy heuristic, ~2% real FP). Frontend severity moved red→amber.

All other checks left unchanged (FP already <5% or accurate). Advisory checks
(`purity_sanity`, `recency`) retain gentle/zero score effect.

## Follow-up fix (2026-06-01): LLM false positive on real Freedom COAs

A user-reported genuine Freedom Diagnostics COA scored 55 ("signs of tampering /
template from another lab"). Root causes:
1. **LLM hallucination.** Deterministic score was 75 (known_lab pass, visual_lab
   **pass** = Freedom template matched, doc_type third_party). Because 75 is in
   the 30–85 LLM band, the vision pass ran and mislabeled the client field
   ("Titan Peptides") as a tampered lab name → capped to 55. Fix: **skip the LLM
   when the issuer is recognized AND (visual template matches OR COA is
   verifiable)** — not the ambiguous case the LLM is for, and visual_lab already
   checks template reuse.
2. **Verifiability false-negative.** The COA says "Searchable via
   FreedomDiagnosticsTesting.com" + accession "Tita2603230148", but the regex
   only matched `…/verify`/`coa.<domain>`. Fixes: added a `verification` block to
   the Freedom registry entry; taught verifiability the "searchable via" /
   "accession" cues; made the code-token matcher case-insensitive.
3. **Copy/label mismatch.** Score bonuses lifted the band but the generic copy
   wasn't refreshed. Fix: `scoring.band_copy/band_copies` + refresh at end of scan.

Result: the tested file now scores **91 / likely_authentic / verifiable**, LLM
skipped. Verifiability FP on real fell **24.9% → 8.9%** (now mostly `verifiable`).

## Verification after tuning
- All 7 backend check test files pass (44 tests).
- `flutter analyze` clean; `flutter test` 5/5.
- 6-image FAKE set still flagged (Fake1/3/4 likely_forged, Fake5 suspicious;
  Fake2/6 remain in the LLM band for production — not recognized+template-matched).
