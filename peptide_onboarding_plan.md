# Onboarding "Trust Journey" — design spec

Educational, question-based onboarding that precedes COA verification. Grounded in
`Articles/` (beginner COA guide, what-is-a-COA, RUO complete guide, verify-COAs
deep dive, vendor-selection & red-flag PDFs) and the forum analysis.

## Locked decisions (2026-06-06)
- Depth: **Standard (~7 questions)** + welcome + summary.
- Answers: **build a personalized Trust Profile** (answers + COA scan).
- Framing: **Research-Use-Only (RUO)** — research-reagent language, "research
  subject (RS)", "for laboratory research use"; AVOID inject/dose wording; keep
  RUO + not-medical-advice disclaimer visible.
- Entry: **onboarding first on first launch (skippable)**; later launches → scanner.
- Trust Profile format: **qualitative signal checklist** (green/amber/red + a
  one-line verdict) — NO single number (preserves the app's anti-overclaim stance).
- Reconciliation: **YES** — cross-check the user's answers against the live scan
  and flag contradictions.
- No-product path: summary **offers both** "Upload a COA" and "Pre-purchase checklist".

## Screen flow
Persistent **"Skip to COA verification"** on every screen; top progress bar;
back/next; "Why this matters" expandable. "Restart guide" available later from
the menu/About.

| # | Screen | Options | Teaches / red flags (source) |
|---|---|---|---|
| 0 | Welcome | Start · Skip to COA check | Value prop: know what's really in the vial; quick questions then verify your COA. |
| 1 | **Vendor** | domestic reseller · overseas/China-direct · group buy · telehealth/503a pharmacy · just researching | Vendor triage (RUO guide): physical address, responsive support, transparent testing partners. Red flags: no storefront, WhatsApp/IG-only, crypto-only (irreversible). Group buy + community testing = strongest. |
| 2 | **COA source** | third-party lab (named) · in-house/manufacturer · unsure who · none | Third-party (independent, accredited) vs in-house ("grading your own exam"). First question: which lab produced it? |
| 3 | **Verifiability** | QR/key/portal · none · unsure | #1 litmus test: a key/QR you can cross-check on the lab's site. Can't verify → assume fake. |
| 4 | **Batch match** | matches · different · no batch on vial · haven't checked | Batch-specific COAs; lot on vial must match; cap/crimp colour; no real batch traceability — tested sample ≠ your vial. |
| 5 | **Recency** | <6 mo · 6–12 mo · >12 mo / unknown | Stale COAs may not reflect current stock; degradation; retest date. |
| 6 | **Test scope** (multi) | purity · assay/mass · MS identity · heavy metals · endotoxin · sterility · not sure | Purity ≠ safety; identity needs MS not just HPLC; contaminant tests usually absent; purity vs net-peptide-content. |
| 7 | **If the COA is weak — your options** | acknowledge · skip | RUO-safe (replaces human harm-reduction): independent lab test (e.g. Janoshik), community/group testing, request refund/replacement, or walk away; brief handling/storage/retest-date note. |
| 8 | **Trust Profile** (summary) | Upload a COA → · Pre-purchase checklist → | Green/amber/red signals from answers + one-line verdict + dual CTA. |
| 9 | **Upload & verify** | (existing results) | Main event; Trust Profile reconciled with the live scan. |

## Trust Profile model
`TrustProfile` = list of `Signal{ id, label, level (green|amber|red), note }` +
a one-line `verdict`. Built client-side from `OnboardingAnswers`, then merged
with the `ScanResult` JSON on the results screen.

Answer → signal:
- vendor: telehealth=green; domestic/group-buy/overseas=amber; (no storefront/crypto cues → amber-red)
- coa_source: third-party=green; in-house/unsure=amber; none=red
- verifiability: yes=green; unsure=amber; no=red
- batch_match: matches=green; no-batch/unchecked=amber; different=red
- recency: <6=green; 6–12=amber; >12/unknown=red
- test_scope: contaminants+MS=green; purity+assay only=amber; purity-only/none=red

**Reconciliation (answer vs scan) → red "contradiction" signals:**
- claimed third-party but `doc_type=manufacturer_qc`
- claimed verifiable but `verifiability ∈ {no_verification_path, redacted}`
- claimed <6 mo but `recency=stale`
- claimed a test present but checklist shows it absent (and not audit-confirmed)
- claimed MS identity but checklist `identity` ✗

Verdict: mostly-green → "Strong signals — still verify on the lab's site & consider
testing"; mixed → "Mixed — verify and consider an independent test"; several red /
any contradiction → "Weak/contradicted — treat as unreliable; test independently or
walk away." (Mirrors the triage repositioning: not bother / verify / walk away / test.)

## Data + architecture
- `OnboardingAnswers { vendorType, coaSource, verifiableClaim, batchMatch, recencyClaim, testScope:Set, hasProduct }` (hasProduct = vendorType != just_researching).
- Flutter `features/onboarding/`: config-driven step list + a generic question
  screen; `onboardingControllerProvider` (Riverpod) holds answers; `TrustProfile`
  builder + card widget (reused on summary and results).
- Router: `/onboarding`; first-run redirect; persist `onboarding_seen` (+ optional
  last answers) via `shared_preferences`.
- **No backend change** — Trust Profile is computed client-side by merging local
  answers with the existing scan JSON.

## Suggested build order
- Phase A: onboarding screens + skip + progress + persistence + `OnboardingAnswers`.
- Phase B: Trust Profile (answers-only) summary screen + dual ending + pre-purchase checklist.
- Phase C: reconciliation on the results screen (Trust Profile card merging answers + scan, mismatch flags).
