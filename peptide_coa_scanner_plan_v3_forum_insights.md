# COA Scanner — Implementation Plan v3 (forum-insight-driven)

Derived from `FAKE/Forum.txt` analysis (see memory `peptides-forum-insights`).
Goal: shift the app from "is this COA real?" toward "should I trust this, verify
it, or walk away?" — and stop implying that an authentic COA means a safe product.

Grounded against the real code: `backend/app/scan.py` orchestrates OCR → rules
engine → `hard_checks` → LLM → `scoring.aggregate`. Two axes: `authenticity`,
`completeness` (`Rules/rule_axis_mapping.json`). Registry at `Rules/registry.json`
(38 labs). Flutter UI in `app/lib` already has `disclaimer.dart`, `lab_badge.dart`,
`hard_check_tile.dart`, `score_gauge.dart`, `verdict.dart`.

Guiding principles (keep):
- Never render "Fake/Forged" as a definitive claim; stay evidence-based/probabilistic.
- Hard-check overrides to authenticity are **downward-only** except recognized-lab bonus.
- Frontend consumes raw backend JSON (no adapter). Additive response fields only.

---

## Phase 0 — Data correctness (small, do first)

The registry trust data contradicts community consensus and the `untrusted`
level is defined but unused.

**File:** `Rules/registry.json`
1. Re-grade against forum consensus + verify each independently:
   - `krause_analytical`: `high` → `untrusted` (community: "worst lab there is").
   - Finnrick, AFI: add if missing; grade `untrusted` (AFI returned positive on
     known-0% vials; Finnrick farms tests out / data-collection concerns).
   - Keep Janoshik `high` but add a `caveat` field noting it is the grey-market
     gold standard, not an accredited pharma lab (per in-thread pharma pros).
2. Add an optional `caveat: string` field to the schema for these nuances.
3. Audit the 11 labs that already have `verification` blocks; add `verification`
   (url, method, requires_*) to any others that publish a portal
   (Freedom Diagnostics, Vanguard, Peptide Test, Trustpointe, Chromate).

**Scoring impact:** `scan.py` already branches on `trust`. Add handling so
`untrusted` caps authenticity hard (e.g. `min(score, 30)` + explanatory copy).
Currently `untrusted` falls into the generic else-branch and is under-penalized.

No new tests needed beyond a registry-schema sanity check.

---

## Phase 1 — Tier-1 features (highest leverage)

### 1A. Generalized verifiability signal + verify deeplink

Today only Janoshik gets a verify path (`checks/janoshik.py`, XREF-010). Promote
"can this be independently verified?" to a lab-agnostic first-class signal.

**New file:** `backend/app/checks/verifiability.py`
- `check(ocr_text, matched_lab) -> dict`
- Detect any verification affordance in OCR text:
  - a known lab `verification.url` (from registry) present in text,
  - a generic verification URL / "verify at" phrase,
  - a lookup/sample key or QR reference (`unique key`, `report id`, `verify`,
    `scan to verify`).
- Outputs:
  - `status: "verifiable"` + `verification_url` (deeplink when lab known) +
    `message` ("Verify yourself on <lab>'s site").
  - `status: "no_verification_path"` + `severity: major` (strong red flag per
    the community's #1 litmus test).
  - `status: "redacted"` when a verification field is present but blanked/blurred
    (reuse `blur_tamper` localized-illegibility signal over the key region).
- Keep Janoshik's existing richer logic; have `verifiability` defer to the
  `janoshik` hard-check result when a Janoshik COA is detected (no double-count).

**Wire-up:** `scan.py`
- Add `"verifiability": verifiability.check(ocr_text, hard_checks["known_lab"])`
  to the `hard_checks` dict.
- Override (downward-only): `no_verification_path` → `min(authenticity, 50)`;
  `redacted` → `min(authenticity, 30)`, label `suspicious`/`likely_forged`.
  `verifiable` → small bonus (+5) only when the lab is also recognized.

**New rule id:** `XREF-012` (add to `authenticity` axis in
`rule_axis_mapping.json`).

### 1B. Document-type classification

The forum treats in-house/manufacturer QC reports as near-worthless and has a
clean tell: **storage/stability instructions on the document**.

**New file:** `backend/app/checks/doc_type.py`
- `classify(ocr_text, matched_lab) -> dict` returning one of:
  - `third_party_lab` — issuer is a recognized independent lab / verification path
    present and no manufacturer markers.
  - `manufacturer_qc` — markers like storage/stability tables (`-80°C`, `36
    months`, "store at"), "manufacturer", vendor-name-as-issuer, QC-report
    phrasing.
  - `unknown`.
- Output `{type, signals: [...], message}`.

**Wire-up:** `scan.py` add to `hard_checks` as `"doc_type"`. No authenticity
override (a real manufacturer COA isn't forged) — but the **frontend** shows it
prominently with the caveat "internal/manufacturer report — not independent
third-party testing." Optionally cap a "fully trusted" presentation.

### 1C. Surface lab trust tier in the response/UI

The data is already computed (`hard_checks.known_lab.trust`) but the UI under-uses
it. No backend change beyond Phase 0; ensure `known_lab` result also carries
`caveat` (from registry) and a human `tier_label`.

**Frontend** (`app/lib`):
- `lab_badge.dart`: render tier (Gold / Decent / Distrusted / Unknown) with color
  + the caveat line. Distrusted labs get a warning treatment.

### 1D. Safety-vs-authenticity reframe (UI + copy)

Biggest conceptual fix. No new check; presentation + one response field.

**Backend:** add a top-level constant block to the response, e.g.
`"limitations": ["Even a genuine, verifiable COA only proves the tested sample
— not the vial you received. No batch traceability exists in this market."]`
(static, but centralizes the message).

**Frontend:**
- `disclaimer.dart` (exists): elevate to a persistent banner on the results
  screen, not a footnote.
- `results_screen.dart`: add a "What this can't tell you" section rendering
  `limitations`.

---

## Phase 2 — Tier-2 forgery checks (named community tells)

Each is a new module under `backend/app/checks/`, added to `hard_checks` in
`scan.py`, with a new rule id on the `authenticity` (or `completeness`) axis.

### 2A. Assay/mass vs labeled strength mismatch — `assay_mass.py` (FORG-018, auth)
- Parse labeled strength (e.g. "Retatrutide 10 mg") and measured assay/content
  (e.g. "assay: 8.45 mg"). Flag deviation beyond ±10%.
- **Always surface assay alongside purity** (the scam relies on readers seeing
  only "99.8%"). Even when not fired, return both numbers for the UI.
- `fired` (underdose/overdose >10%) → `min(authenticity, 45)` + message.

### 2B. Compound-identity vs molecular-formula consistency — extend `mw_table.py` (XREF-009)
- Current check cross-references MW. Add **molecular-formula** cross-check against
  the detected peptide (catches the real GHK-Cu-formula-on-a-Reta-COA case
  directly, not just via MW). Needs a `formula` field in
  `Rules/peptide_mw_table.json` (data task) and a formula parser.
- Formula mismatch → same critical override path as MW mismatch.

### 2C. COA recency flag — `recency.py` (META-006, auth, advisory)
- Parse the test/issue date; warn if older than 6 months (community threshold).
- Advisory cap only (`min(authenticity, 70)`); peptides degrade and stale COAs
  are "suspect," not proof of forgery.

### 2D. Missing issuer contact info — fold into `known_labs.py` / `verifiability.py`
- No email/phone/address/URL for the issuer anywhere → minor red flag,
  contributes to the `no_verification_path` story.

### 2E. "Too-perfect purity" heuristic — `purity_sanity.py` (FORG-019, auth, advisory)
- Purity ≥99.8% with no impurity peaks / no reported impurities table → soft flag
  ("real reports show variation"). Advisory only; weak discriminator, must not
  force a verdict (calibrate before enabling, like `blur_tamper`).

### 2F. Chromatogram sanity — `chromatogram.py` (XREF-013, auth) — STRETCH
- Visual: detect presence of a chromatogram and whether it is a single
  suspiciously-clean spike with no baseline noise. Higher effort (image
  analysis); schedule last, behind a flag, after calibration.

Deferred (need cross-COA database, out of MVP): equipment-serial reuse,
shell-company lab detection.

---

## Phase 3 — Completeness as a visible checklist (UI)

Serves the dominant "I don't know what to look for" pain point.

- **Backend:** completeness rules already exist (STRUCT/METH/NUM/LAB on the
  completeness axis). Add a `completeness.checklist` array to the aggregate in
  `scoring.py`, mapping expected sections to present/missing:
  identity, purity/HPLC, assay/mass, heavy metals, endotoxin, sterility, residual
  solvents, batch/lot#, vial photo, accreditation, verification code, test date.
- **Frontend:** render the checklist (✓/✗) under the completeness gauge.
- Add a short glossary (assay vs purity, EU/mg endotoxin, TFA, TB-500 vs TB-4)
  and an optional harm-reduction note (start low dose, sterile filter, group
  test) — static content in `about_screen.dart` or an expandable panel.

---

## Phase 4 — Batch-match prompt (UX)

The one verification step the user can actually do.

- After a scan, prompt: "Does the lot/batch on this COA match your vial? Does the
  vial photo's cap/crimp color match yours?" Purely client-side
  (`results_screen.dart`); no backend dependency. If the COA exposes a parsed
  batch/lot number, echo it for easy comparison.

---

## Response-contract additions (all additive)

New keys on the `POST /api/scan` 200 response:
- `hard_checks.verifiability`, `hard_checks.doc_type`, `hard_checks.assay_mass`
- `hard_checks.known_lab.caveat`, `.tier_label`
- `completeness.checklist: [{section, present: bool}]`
- top-level `limitations: [string]`
- `summary.labeled_mass`, `summary.measured_assay` (when parsed)

Update `flutter_frontend_claude_code_prompt.md` contract doc + hand-written
models in `app/lib/models/models.dart` accordingly. No breaking changes to
existing fields.

---

## Sequencing & effort

1. **Phase 0** (data) — ~half day. Unblocks correct trust penalties.
2. **Phase 1A + 1B** (verifiability, doc-type) — highest leverage, ~1–2 days.
3. **Phase 1C + 1D** (UI tier + reframe) — ~1 day.
4. **Phase 2A + 2B** (assay, formula) — concrete, high-confidence, ~1–2 days.
5. **Phase 3** (checklist UI) — ~1 day.
6. **Phase 2C/2E/2F, Phase 4** — advisory/stretch; calibrate before enabling.

---

## Testing & calibration

- Every new authenticity override needs evaluation against the real-vs-fake
  corpus (`COAs/`, `FAKE/`) via the existing `Rules/calibration/calibrate.py` /
  `eval_perturbations.py` path — do NOT hand-tune thresholds blind (matches the
  discipline already noted in `blur_tamper.py` / `visual_lab.py`).
- Advisory-only checks (`purity_sanity`, `recency`, `chromatogram`) ship behind
  the same "advisory until recalibrated" gate as `blur_tamper`.
- Unit tests per check module; integration test asserting new response keys.

## Risks / cautions

- Over-firing on legitimate variation (esp. 2E/2F) → keep advisory until proven.
- Don't let the verifiability bonus launder a forgery: only bonus when lab is
  *also* recognized AND visual template doesn't mismatch (mirror the existing
  guard in `scan.py` lab-reconciliation block).
- Formula parsing (2B) must handle OCR noise (subscripts, unicode) — fuzzy match
  with a tolerance, fail closed to "not_applicable" rather than false-firing.
