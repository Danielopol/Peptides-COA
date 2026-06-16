# Claude Code Prompt — Peptide COA Scanner (Flutter Frontend, Local MVP)

> Paste everything below into Claude Code, running from the repo root. It builds **only** the Flutter client (`app/`). The Python/FastAPI backend already exists in `backend/` — do not build, stub, or modify it. This MVP frontend codes against the backend's **actual** API as it exists today and is meant to be run locally against the live backend so we can validate the backend pipeline and the UI together.
>
> **Scope for this phase (locked):** NO authentication, NO accounts, NO database, NO billing, NO quota/paywall. Anonymous single-user local testing only. Keep the backend's **two-axis** scoring (authenticity + completeness) — do not collapse it. Auth, persistence, and billing are explicitly out of scope and will be a later phase; do not scaffold Firebase, Stripe, or Play Billing now.

---

## Role & scope

You are building the **Flutter frontend** for a Certificate of Analysis (COA) scanner for research peptides. The app lets a user pick a peptide COA (PDF or image), uploads it to the local backend, and presents the backend's analysis — two scores (authenticity and completeness), hard-check results, fired rules, and a verification deeplink — in a trustworthy, legible way. Primary target is **Flutter Web** (easiest for local dev); keep the code **Android-compatible** from the same codebase, but web is what we test first.

Build **only** the client in the `app/` directory. Do NOT:
- write, stub, or modify any backend, FastAPI, OCR, LLM, or rule-engine code,
- invent backend logic or scoring — treat the backend as a black box and render exactly what it returns,
- add auth, accounts, billing, quota, or a database in this phase.

You may and should: build a clean `ApiClient` interface with **two implementations** — `HttpApiClient` (real `dio` calls to the local backend, the default) and `MockApiClient` (canned fixtures that mirror the real response shape, for offline UI iteration). A `--dart-define=USE_MOCK=true/false` flag selects which. The point of this phase is to run the **real** backend, so `HttpApiClient` is the default; the mock exists so the UI can be refined without the backend running.

---

## The backend you are coding against (ground truth)

The backend lives in `backend/app/`. Run it locally with:

```bash
cd backend
uvicorn app.main:app --reload   # serves http://localhost:8000
```

CORS is already wide-open (`allow_origins=["*"]`), so Flutter Web can call it directly. There are **exactly two endpoints**: `GET /api/health` and `POST /api/scan`. There is **no** `/api/me`, `/api/history`, `/api/rules`, auth, or billing — do not call or assume them.

Sample COAs for testing live in the repo: real ones under `COAs/` (ACCUMARK LABS, BIOVIRIDIAN, Freedom Diagnostic, Janoshik_Tests, VANGUARD LABORATORY) and fakes under `FAKE/` (Fake1–5). Use these to exercise the UI.

### `GET /api/health`
→ `200 { "status": "ok" }`. Use this for a connection indicator on the home screen and to fail fast with a clear "backend not reachable" message.

### `POST /api/scan` — multipart upload
- Request: `multipart/form-data`, field **`file`** = the COA. Accepted extensions: **`.pdf .png .jpg .jpeg .webp`**. Max 20 MB. No auth header.
- **`200`** → either a full scan result (below) **or** a "not a COA" body — both come back as HTTP 200, so you must branch on the JSON body, not the status code.

**Error responses (note: these differ from a typical REST design — match them exactly):**
- **`400`** → unsupported file type (`{"detail": "Unsupported file type: .xyz"}`) OR file < 1 KB (`{"detail": "File too small to be a valid COA"}`).
- **`413`** → file > 20 MB (`{"detail": "File exceeds 20 MB limit"}`).
- There is **no** `402`, **no** `415`, **no** `422`. Do not implement quota/paywall handling.

### `POST /api/scan` → 200 "not a COA" body
When OCR yields < 100 characters, the backend returns **HTTP 200** with:
```jsonc
{
  "filename": "blank.pdf",
  "error": "input_not_coa",
  "message": "OCR yielded <100 chars; input is likely not a COA",
  "ocr_chars": 12
}
```
Detect `error == "input_not_coa"` and show a friendly "this doesn't look like a COA" state — **not** a score screen.

### `POST /api/scan` → 200 full result (the real shape — model this exactly)
```jsonc
{
  "filename": "janoshik_bpc157.pdf",
  "input_type": "pdf",                     // "pdf" | "image"
  "authenticity": {
    "score": 88,                           // 0–100
    "label": "likely_authentic",           // see band labels below
    "copy": "This COA appears authentic. No tampering or forgery indicators detected.",
    "weight_in_axis": 42.0,
    "weight_fired": 5.0,
    "fired_rule_ids": ["NUM-006"],
    "passed_rule_ids": ["XREF-001", "LAB-003"]
  },
  "completeness": {
    "score": 71,                           // 0–100
    "label": "partial_report",             // see band labels below
    "copy": "Some expected sections are missing. Ask vendor for the full report.",
    "weight_in_axis": 30.0,
    "weight_fired": 8.0,
    "fired_rule_ids": ["METH-004"],
    "passed_rule_ids": ["STRUCT-001"],
    "checklist": [                         // COMPLETENESS ONLY (absent/empty on authenticity); informational present/absent breakdown — render as a ✓/✗ list under the completeness gauge
      {"section": "identity", "label": "Identity confirmation", "present": true},
      {"section": "endotoxin", "label": "Bacterial endotoxin", "present": false}
      // ...14 items: identity, purity, assay_mass, heavy_metals, endotoxin, sterility, residual_solvents, impurity_profile, water_content, batch_lot, vial_photo, accreditation, verification, test_date
    ]
  },
  "summary": {
    "fired_critical_authenticity_rules": [],
    "rule_counts": { "pass": 40, "fired": 3, "not_applicable": 20, "error": 0 },
    "peptide_detected": "BPC-157",         // nullable
    "peptide_detect_method": "name",       // "name"|"cas"|"sequence"|"fuzzy"|"legacy"|null
    "ms_technique_detected": "ESI-MS",     // nullable
    "labeled_mass_mg": 10.0,               // nullable — parsed labeled strength (from assay_mass)
    "measured_assay_mg": 8.45,             // nullable — parsed measured content; show next to purity
    "batch_lot": "RT10426",                // nullable — parsed batch/lot token; echo in the batch-match prompt
    "purity_pct": 99.05,                    // nullable — parsed purity %; render a coloured "Purity X% · <grade>" chip
    "purity_grade": "excellent"            // nullable — band: below grade/marginal/acceptable/good/excellent/pharma grade
  },
  "notes": [                               // e.g. image-input caveats; may be empty
    "Image input: PDF-metadata rules (META-*) are not evaluable; authenticity score may be lower-confidence."
  ],
  "limitations": [                         // FIXED copy, always present — the document-vs-product reframe; render prominently ("What this can't tell you")
    "Even a genuine, verifiable COA only proves the specific sample that was tested — not the vial you received...",
    "Purity is not safety. Sterility, endotoxins, heavy metals and residual solvents are usually NOT tested...",
    "The only way to know what is in your vial is independent testing of that vial (or a group test of the same batch)."
  ],
  "hard_checks": {                         // each value has a "status"; OTHER FIELDS VARY PER CHECK — only some carry "message"
    "mw_table":    { "status": "fired" | "pass" | "not_applicable" | "suspicious", "reason": "...", "message": "...", "mismatch_kind": "mw" | "formula", "formula_status": "match" | "mismatch" | "not_found" | "unparsed" | "inconclusive", "claimed_formula": "C28H48CuN12O8" },  // "message" present when fired/suspicious; "reason" when not_applicable; mismatch_kind tells whether the mass or the molecular formula failed (formula = e.g. a copper formula on a peptide)
    "known_lab":   { "status": "pass" | "unrecognized_named" | "no_issuer", "lab_name": "Janoshik Analytical", "entity_id": "janoshik", "entity_kind": "lab", "trust": "high", "caveat": "...", "verification": { "url": "...", "method": "..." }, "message": "..." },  // lab_name/trust only when pass; caveat/verification optional (present only when the registry has them); message only when not pass
    "janoshik":    { "status": "pending_user_verification" | "fired" | "not_applicable", "task_number": "100491", "unique_key": "DAWP5HCLAV5W", "verification_url": "https://janoshik.com/verify/?key=...", "missing_fields": [...], "message": "..." },  // task/key/url when pending; missing_fields+message when fired; bare {status,reason} when n/a
    "verifiability": { "status": "verifiable" | "no_verification_path" | "redacted" | "deferred_to_janoshik", "rule_id": "XREF-012", "verification_url": "https://coa.lab.com", "via": "registry_lab" | "document", "severity": "major", "message": "..." },  // verification_url+via only when verifiable; severity when redacted/no_verification_path; deferred_to_janoshik means the janoshik check owns verification for this COA
    "doc_type":    { "status": "third_party_lab" | "manufacturer_qc" | "unknown", "rule_id": "DOC-001", "confidence": "high" | "medium" | "low", "signals": ["..."], "message": "..." },  // informational only — does NOT affect authenticity score; manufacturer_qc = in-house/vendor report (weak evidence per community)
    "assay_mass":  { "status": "pass" | "underdosed" | "overfilled" | "not_applicable", "rule_id": "FORG-018", "labeled_mg": 10.0, "measured_mg": 8.45, "deviation_pct": -15.5, "severity": "minor" | "major", "message": "..." },  // labeled/measured present when parsed; underdosed penalizes authenticity (severe= -25%+); overfilled is informational (benign)
    "visual_lab":  { "status": "pass" | "no_match" | "suspicious" | "fired", "matched_lab_name": "Janoshik Analytical", "confidence": "strong", "distance": 0, "message": "..." },  // matched_* only when pass
    "multi_mass":  { "status": "pass" | "suspicious" | "fired", "rule_id": "FORG-017", "message": "..." },
    "metadata":    { "status": "pass" | "fired" | "not_applicable", "creation_date": "...", "mod_date": "...", "message": "..." },  // not_applicable for image input
    "recency":     { "status": "pass" | "stale" | "not_applicable", "rule_id": "META-006", "coa_date": "2025-06-01", "age_days": 365, "severity": "minor", "message": "..." },  // advisory: stale = COA date >~6 months old; amber, caps authenticity to ≤70 only
    "purity_sanity": { "status": "pass" | "vague" | "too_perfect" | "not_applicable", "rule_id": "FORG-019", "purity": 100.0, "operator": ">", "grade": "excellent", "severity": "minor", "message": "..." },  // ADVISORY caution (too-perfect ≥99.99% / vague ">99%"), no score change. "grade" = purity band (below grade/marginal/acceptable/good/excellent/pharma grade)
    "methods": { "status": "multi" | "single" | "not_applicable", "rule_id": "METH-013", "families": ["HPLC","MS"], "severity": "minor", "message": "..." },  // ADVISORY method-coverage: multi=cross-verified(green), single=caution(amber, "HPLC only"), not_applicable=none detected/hidden. No score change
    "blur_tamper": { "status": "metrics_only", "word_count": 74, "median_conf": 96.0, "low_conf_frac": 0.027 }  // advisory only — no message, do not surface as a finding
  },
  "rule_results": [                        // every rule evaluated (~84 entries)
    { "rule_id": "STRUCT-003", "name": "Analysis Date Present", "category": "structure", "weight": 9, "severity": "critical", "status": "fired" }
    // status:   "pass" | "fired" | "not_applicable" | "error"
    // severity: "critical" | "major" | "minor"   (NOT high/medium/low)
    // category: structure | numerical | analytical_methods | lab_credentials |
    //           formatting | metadata | cross_reference | forgery_indicators
    // weight may be a float. NOTE: rule_results carry NO human-readable detail —
    // only name/category/severity/status. Readable explanations live in hard_checks[*].message.
  ],
  "features": {                            // raw extracted features — debug panel only, not the main UI
    "path": "/tmp/...", "name": "...", "pages": 3,
    "meta": { "format": "PDF 1.7", "creator": "Chromium", "producer": "pdf-lib",
              "creationDate": "D:2026...", "modDate": "D:2026...", "...": "..." },
    "has_text_layer": false, "image_dpis": [197,103], "image_jpeg": [false,true],
    "blank_page_pages": 0, "duplicate_image_pages": 1,
    "ocr_text": "TEST REPORT — Janoshik ...",   // full OCR dump (can be long)
    "semantic": { "peptide_name_found": "bpc-157", "batch": "...", "max_purity": null,
                  "has_lab_keyword": true, "has_hplc": false, "has_ms": false, "...": "..." }
  },
  // llm — gated: only runs when 30 < authenticity.score < 85 AND backend ENABLE_LLM=true.
  "llm": { "enabled": false, "note": "not run (gated)" }
  // when it DID run:
  // { "enabled": true, "model": "gemini-2.5-flash-lite",
  //   "usage": { "input_tokens": 790, "output_tokens": 71, "total_tokens": 861 },
  //   "verdict": "authentic"|"suspicious"|"likely_forged", "confidence": 1.0,
  //   "visual_tampering": false, "lab_name_altered": false,
  //   "findings": [], "summary": "..." }
  ,
  // llm_completeness — vision PRESENCE-AUDIT of OCR-missed completeness fields. Runs
  // whenever ENABLE_LLM=true and some presence-rules fired. Presence-only: a confirmed
  // field flips its rule fired->pass and RAISES completeness; never affects authenticity.
  "llm_completeness": { "enabled": false, "note": "not run" }
  // when it ran: { "enabled": true, "model": "...", "usage": {...},
  //   "confirmed_rule_ids": ["STRUCT-008"],          // fired rules the model confirmed (move the score)
  //   "confirmed_sections": ["purity","vial_photo"], // checklist sections lit up (rules + no-rule sections)
  //   "fields": { "STRUCT-008": {"present": true, "value": "99.856%"}, "vial_photo": {"present": true, "value": "..."}, ... } }
  // Audited over ALL pages. Confirmed checklist items gain "confirmed_by":"visual"; confirmed rule_results gain "confirmed_by":"visual" + "visual_value".
}
```

**Authenticity band labels** (highest→lowest): `likely_authentic` (≥85), `verify_recommended` (≥60), `suspicious` (≥30), `likely_forged` (<30).
**Completeness band labels**: `full_report` (≥75), `partial_report` (≥45), `minimal_report` (≥20), `skeletal` (<20).

Map authenticity labels to semantic color: `likely_authentic`→green, `verify_recommended`→amber, `suspicious`→deep-amber/orange, `likely_forged`→red. Completeness is informational (use a neutral/teal accent, **not** the red/amber verdict palette — only authenticity carries the safety signal).

---

## Decisions & assumptions (record each in `app/DECISIONS.md`)

1. **No auth / no quota / no billing this phase.** Single anonymous user, local backend. Keep the codebase structured so an auth + history + billing phase can be added later without a rewrite (e.g. `ApiClient` interface, a `services/` folder), but build none of it now.
2. **Frontend consumes the raw backend JSON directly** (no backend adapter). Models live in `app/lib/models/` and map the exact shape above. If the backend response changes, only `models/` + fixtures change. This is intentional: rendering the real payload makes the UI a debugging surface for the backend pipeline.
3. **Two axes, two gauges.** Show **both** authenticity and completeness. Authenticity is the primary/larger gauge and carries the verdict color; completeness is secondary and neutral-colored.
4. **`hard_checks` drive the human-readable findings**, since `rule_results` have no detail text. Render each applicable hard check (skip `not_applicable`) with its `message`, an icon/color from its `status`, and surface fired `rule_results` (grouped by severity) as a secondary, more technical list.
5. **Verdict copy is intentionally soft** (legal risk). Render the backend's `authenticity.copy`/`completeness.copy` and `hard_checks[*].message` verbatim. Never render "Forged"/"Fake"/"Counterfeit" yourself — even though the backend uses the internal label `likely_forged`, display its human `copy` string, not the raw label. **Note:** when a critical hard check fires (e.g. `janoshik`, `mw_table`, `visual_lab`), the backend **overrides** `authenticity.copy` with that check's specific message — so `copy` may be a long, specific sentence rather than the generic band text. Always render whatever `copy` contains; don't substitute your own.
6. **Janoshik verification:** when `hard_checks.janoshik.status == "pending_user_verification"` and a `verification_url` is present, show a prominent "Tap to verify with the lab" button that opens the URL with `url_launcher`.
7. **Lab trust badge:** when `hard_checks.known_lab.status == "pass"`, show a "Recognized lab: {lab_name}" badge tinted by `trust` (high/established → green; `untrusted` → red warning). If `hard_checks.known_lab.caveat` is present, show it under the badge — it carries lab-specific warnings (e.g. documented accuracy issues) even for otherwise-recognized labs.
8. **Verifiability (generalized):** `hard_checks.verifiability` answers "can the user independently verify this COA?" — the community's strongest single trust signal. When `status == "verifiable"` and a `verification_url` is present (and `status != "deferred_to_janoshik"`, which means the Janoshik button above already covers it), show a "Verify on the lab's site" button (`url_launcher`). When `status` is `no_verification_path` or `redacted`, surface its `message` as a prominent red/amber finding.
9. **Document type:** `hard_checks.doc_type` classifies the report as `third_party_lab` / `manufacturer_qc` / `unknown`. It does NOT affect the authenticity score — render it as an informational chip near the verdict. Treat `manufacturer_qc` as a caution ("in-house / vendor report — not independent testing") using its `message`; `third_party_lab` is reassuring. Low `confidence` should be worded tentatively.
10. **Limitations reframe:** top-level `limitations[]` is fixed copy that's always present. Render it prominently (a "What this can't tell you" card near the verdict) so an authentic/verifiable result is never mistaken for "safe to use" — the dominant community misconception. Don't bury it in the footer disclaimer.
11. **Completeness checklist:** `completeness.checklist[]` is a 14-item present/absent breakdown — render as a ✓/✗ list under the completeness gauge with an "X of N present" header and a "missing isn't proof" caption.
12. **Batch-match prompt:** always show a "Match it to your vial" card (the one check only the user can do): two confirmations (lot/batch matches, cap/crimp colour matches), echoing `summary.batch_lot` when present. Local UI state only — nothing is persisted or sent back.

---

## Tech stack (use exactly these; note any substitution in `DECISIONS.md`)

- **Flutter** (stable), Dart 3, null-safe. Single codebase; **web-first**, Android-compatible.
- **State management:** Riverpod (`flutter_riverpod`, optionally `riverpod_annotation` codegen).
- **Routing:** `go_router` (simple routes — **no** auth redirect/gating this phase).
- **HTTP:** `dio` (no auth interceptor needed — there are no tokens). Configure `baseUrl` from `--dart-define=API_BASE_URL` (default `http://localhost:8000`). Multipart upload with `dio`'s `FormData` + `MultipartFile`. Wire upload progress via `onSendProgress`.
- **File input:** `file_picker` (PDF + images, web + Android) and `image_picker` (camera/gallery on Android). Validate **client-side** before upload: size ≤ 20 MB and extension in `.pdf/.png/.jpg/.jpeg/.webp`.
- **Open URLs:** `url_launcher` (Janoshik verify deeplink, any external links).
- **Models:** `freezed` + `json_serializable`.
- **Config:** `--dart-define` for `API_BASE_URL` and `USE_MOCK`. No Firebase, no `in_app_purchase`, no Stripe packages.

Do **not** add: `firebase_core`, `firebase_auth`, `google_sign_in`, `in_app_purchase`, any payments SDK.

---

## Screens & flows

Build these under `app/lib/features/<feature>/`, wired through `go_router`:

1. **Home / Scan** — primary CTA to pick a PDF/image (`file_picker`) or take a photo (`image_picker`, Android). A small **backend connection indicator** (pings `/api/health`). Client-side size/type validation with clear errors before upload. A settings affordance to view/override `API_BASE_URL` is nice-to-have for local testing.
2. **Scanning** — upload progress (`onSendProgress`) then an indeterminate "analyzing" state (OCR + rules + LLM can take ~5–20s). Reassuring copy ("Reading the certificate…", "Cross-checking the lab…"). Cancelable.
3. **Results** — the centerpiece:
   - **Authenticity gauge** (0–100), large, colored by the authenticity label (green/amber/orange/red). Render `authenticity.copy` beneath it verbatim.
   - **Completeness gauge** (0–100), secondary, neutral/teal. Render `completeness.copy`.
   - **Lab badge** from `hard_checks.known_lab` (when `status == "pass"`), tinted by `trust`.
   - **Janoshik verify button** from `hard_checks.janoshik.verification_url` (when present) → `url_launcher`.
   - **Findings list** driven by `hard_checks`: one tile per applicable check (skip `not_applicable`), showing its `message`, status icon/color. The `mw_table` "fired" and any `fired` critical check get a distinct **red** treatment.
   - **Detected info** chips: `summary.peptide_detected`, `summary.ms_technique_detected`, `input_type`, and a dose chip ("Measured X / Y mg") when `summary.labeled_mass_mg` + `measured_assay_mg` are present — surfaces the assay next to the purity.
   - **`notes[]`** rendered as info banners (e.g. image-input caveat).
   - **Technical/Advanced (collapsible):** fired `rule_results` grouped by severity (rule `name` + `rule_id` + `category`), `summary.rule_counts`, and a raw-JSON/`features`/`llm` debug panel toggle (handy for validating the backend).
   - **Persistent disclaimer** at the bottom (copy below).
4. **Not-a-COA state** — when `error == "input_not_coa"`: a friendly screen explaining the upload didn't look like a COA, with `ocr_chars` shown subtly, and a "try another file" CTA.
5. **Error states** — backend unreachable, 400 (bad type/too small), 413 (too large), timeout, generic. Each actionable.
6. **History (local, optional, in-memory or `shared_preferences` only)** — keep the last N scans for this session so you can re-open a result during testing. **No backend, no account.** Skip if it adds risk; if built, label it clearly as local-only.
7. **About / How it works** — explain the scan honestly (two axes, hard checks, verify-with-lab), repeat the disclaimer. (Do **not** call a `/api/rules` endpoint — it doesn't exist; write the copy statically.)

---

## Design direction

This is a **trust and safety** product — people may make decisions off it. The UI must feel **credible, calm, and clinical**, not gimmicky.

- Material 3, light + dark themes. Restrained palette: neutral base, one trustworthy accent (deep teal or indigo), and **semantic colors reserved strictly for the authenticity verdict** (green/amber/orange/red) so they read as signal. Completeness uses the neutral accent.
- Generous whitespace, strong typographic hierarchy, large legible gauge numbers. One clear primary action per screen.
- The **authenticity gauge** is the visual anchor of the results screen — clean, animated fill, unmistakable color coding. Completeness sits beside/below it, visually subordinate.
- Accessibility: WCAG-AA contrast, semantic labels, scalable text, never color-only signaling (pair color with icon + text).
- Responsive: comfortable on a phone and on a wide web viewport (constrain content width; don't stretch full-bleed on desktop).
- Microcopy is plain-spoken and non-alarmist.

---

## Required legal/safety copy (verbatim — do not soften or remove)

Persistent on the results screen and in About:
> This result is an **indicator, not legal or medical advice**. It does not confirm a product is safe to use. Always verify directly with the issuing lab and vendor before making any decision.

Never display "Forged" / "Fake" / "Counterfeit." Render the backend's `copy`/`message` strings; map the `likely_forged` label to color only.

---

## Project structure

```
app/
├── lib/
│   ├── main.dart                 # reads --dart-define: API_BASE_URL (default http://localhost:8000), USE_MOCK (default false)
│   ├── app.dart                  # MaterialApp.router + theme
│   ├── core/
│   │   ├── config.dart           # env / dart-define accessors
│   │   ├── theme.dart            # M3 light/dark, authenticity verdict colors, neutral completeness accent
│   │   └── router.dart           # go_router (plain routes, no auth)
│   ├── models/                   # freezed: ScanResult, AxisScore, Summary, HardChecks (+ per-check), RuleResult, NotACoa
│   ├── data/
│   │   ├── api_client.dart       # abstract interface (scan, health)
│   │   ├── http_api_client.dart  # dio impl (multipart, progress, error mapping)
│   │   ├── mock_api_client.dart  # canned fixtures mirroring the REAL shape
│   │   └── fixtures/             # sample JSON results
│   ├── providers/                # Riverpod providers (health, scan, local history)
│   └── features/
│       ├── home/  scanning/  results/  about/  (history/ optional)
│       └── shared/widgets/       # ScoreGauge, AxisCard, LabBadge, HardCheckTile, RuleResultTile, Disclaimer, DebugPanel
├── DECISIONS.md                  # record every assumption + package substitution
├── README.md                     # run instructions incl. --dart-define examples + how to start the backend
└── pubspec.yaml
```

Keep an empty/placeholder `app/lib/services/` folder reserved for the future auth/billing phase, but add no auth/billing code now.

---

## Mock fixtures (must mirror the real shape)

Provide realistic fixtures in `MockApiClient` and `data/fixtures/` for:
- a `likely_authentic` + `full_report` Janoshik result with `hard_checks.janoshik.status == "pending_user_verification"` (verify button) and `known_lab.status == "pass"` (lab badge),
- a `suspicious` result with `mw_table` fired and an `XREF-009` critical `rule_result`,
- a `likely_forged` result with `visual_lab`/`metadata` fired,
- an `input_not_coa` 200 body,
- error cases: 400 (bad type / too small), 413 (too large), backend-unreachable.

---

## Build order

1. Scaffold project, `pubspec.yaml`, theme, config, `go_router` skeleton, `DECISIONS.md`.
2. Models (`freezed`) for the **exact** backend shape above + fixtures.
3. `ApiClient` interface + `MockApiClient` (fixtures) + `HttpApiClient` (`dio` multipart, progress, error mapping). Wire `USE_MOCK` (default false → real local backend).
4. Scan flow end-to-end **against the running local backend**: home → scanning → results (two gauges, lab badge, hard-check findings, Janoshik verify deeplink, detected-info chips, notes, disclaimer). Get this looking right with the real `COAs/` and `FAKE/` samples.
5. Not-a-COA state + all error states (400 / 413 / unreachable / timeout).
6. Advanced/debug panel (fired rule_results, rule_counts, raw JSON/features/llm) for backend validation.
7. Optional local history; About screen.
8. Polish: loading/empty/error states, responsive web layout, dark mode, a11y pass.
9. README (run + `--dart-define` examples + backend start) and a short widget test for `ScoreGauge` and the authenticity-label→color mapping.

---

## Constraints / what NOT to do

- No backend code, no auth, no accounts, no database, no billing, no quota/paywall this phase.
- No fake scoring — render only what `/api/scan` returns.
- Don't assume `402`/`415`/`422` or any endpoint other than `/api/health` and `/api/scan`.
- Never render "Forged"/"Fake"; never imply medical safety; keep the disclaimer present.
- Keep mock and HTTP clients behind one interface so swapping is a one-flag change.
- Keep both scoring axes — do not collapse to a single score.

## Definition of done

The app runs with `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=USE_MOCK=false` against the locally running backend, and successfully scans the real samples in `COAs/` and `FAKE/`, rendering both axes, the lab badge, hard-check findings, the Janoshik verify deeplink, detected info, notes, the not-a-COA state, and all error states. It also runs fully on `USE_MOCK=true` with no backend. `flutter analyze` is clean. `DECISIONS.md` lists every assumption and substitution.
```
