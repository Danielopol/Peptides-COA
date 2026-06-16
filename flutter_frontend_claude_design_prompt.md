# Claude Design Brief — Peptide COA Scanner (Flutter, visual & interaction redesign)

> Paste everything below into Claude Design. This is **not** a build task and **not** a code task. A working Flutter app already exists in `app/` and is feature-complete — its behavior, data, and logic are settled. Your job is to design the **visual layer only**: deliver **high-fidelity visual mockups and a design system** (tokens, components, screens) that I will hand-implement in Flutter afterward. **Do not write app code, Dart, or wiring** — produce the *design*, not the implementation.

---

## What this product is (the one thing to internalize)

A scanner for **Certificates of Analysis (COAs)** for research peptides. A user uploads a COA (PDF/image); a backend analyzes it and returns **two scores** — **authenticity** (is this document real / untampered?) and **completeness** (how thorough is the report?) — plus human-readable findings and a verify-with-the-lab deeplink. People make real purchasing decisions off this, so the design must read as **sober and trustworthy, never gimmicky or alarmist.**

**The product's central truth (this must shape the design, not just live in fine print):** *a clean, authentic COA does NOT mean the product in the user's vial is safe.* The tested sample isn't their vial; purity isn't safety; the document can be genuine and the vial still bad. The dominant failure mode of this category is users seeing a green score and feeling falsely safe. **Your design must make "verified ≠ safe" structurally impossible to miss** — the "What this can't tell you" content is a first-class citizen near the verdict, not a footer.

There is also an **educational onboarding "Trust Journey"** that precedes scanning: ~7 questions that build a personal **Trust Profile** (a qualitative green/amber/red signal checklist — never a number) and then offer either "scan a COA" or a "pre-purchase checklist." Framing is **research-use-only (RUO)**: reagent language, never dosing/injection language.

---

## Your mandate & hard constraints

**DO:** redesign the visual language, layout, hierarchy, color system, typography, spacing, iconography, motion (described, not coded), empty/loading/error states, and component styling. Improve information architecture and the emotional arc of each screen. Propose a cohesive, distinctive design system that still feels clinical and credible. Deliver it as **visual mockups + a documented design system** (see "What to deliver").

**DON'T:**
- Write Flutter/Dart, component code, or any implementation. Visual design only — I implement.
- Redesign away the data: you're presenting the *same* fields the app already shows (listed below), only better. Don't invent data the backend doesn't return, and don't drop fields it does.
- Soften, remove, or rewrite the legally required copy or the backend's verdict `copy`/`message` strings (see "Locked copy rules").
- Collapse the two axes into one score, or recolor completeness into the verdict (red/amber/green) palette — that palette is reserved as *signal*.

The target stack is Material 3 / Flutter, so keep the design **buildable in that idiom** (M3-friendly components, standard touch targets, themeable light + dark). If a design idea would require new data or a logic change, describe it separately as a "future" note — don't assume it.

---

## The app as it exists today (your starting point)

Flutter (stable, Dart 3, Material 3), web-first + Android-compatible. State: Riverpod. Routing: `go_router` (hash routing). HTTP: `dio`. Files: `file_picker`/`image_picker`. Links: `url_launcher`. Local prefs: `shared_preferences`. No auth, accounts, DB, or billing (out of scope).

### Current design language (what to evolve, not necessarily keep)
- **Seed color:** deep indigo `#3949AB`, M3 `ColorScheme.fromSeed`, light + dark.
- **Verdict palette (reserved for the authenticity signal only):** green `#1B873F`, amber `#B7791F`, orange `#C2410C`, red `#C0392B`. Completeness uses neutral teal `#0F766E` / dim teal `#5B8A86`.
- **Cards:** elevation 0, 16px radius, hairline `outlineVariant` border. Buttons: 52px min height, 12px radius. Flat app bar.
- **The authenticity gauge** is a custom-painted circular 0–100 dial with an animated fill (900ms easeOutCubic), big number, `/100`, optional icon + label. Completeness reuses it in a smaller/`compact` form.

This is competent but generic — a stock M3 indigo app. **The opportunity is to give it a deliberate, ownable visual identity** that signals "lab-grade / forensic / trustworthy" without becoming cold or sterile, and to sharpen hierarchy so the verdict and the "can't tell you" reframe dominate.

### Screens & components in place (redesign these)
Routes via `go_router`:
- `/onboarding` → `/onboarding/summary` → (`/onboarding/checklist` | `/` scan) — the Trust Journey.
- `/` Home / Scan, `/scanning`, results (rendered in-place), `/about`, optional `/history`.

The screens that exist today, for context (you're designing the visual treatment of each — I map your mockups onto these):
- **Home / Scan** — pick file / take photo, backend health indicator, client-side validation.
- **Scanning** — upload progress → indeterminate "analyzing" (5–20s), cancelable.
- **Results** — **the centerpiece** (see below), plus Not-a-COA and error states.
- **Onboarding** — paged question flow, Trust Profile summary, pre-purchase checklist.
- **About** — honest "how it works" + glossary + harm-reduction.
- Recurring components — score gauge, lab badge, hard-check finding tile, disclaimer block, trust-profile card, page scaffold, a developer debug panel.

---

## The Results screen (where most of the design value is)

This screen renders everything the backend returns. Today it's a long vertical scroll of cards. **Design a clear emotional/visual hierarchy** so a user instantly gets: *(1) how trustworthy is this document, (2) what it still can't tell me, (3) what I should do next (verify / match to my vial), (4) the supporting detail if I want it.* Elements present, in rough priority:

1. **Authenticity verdict** — the dominant element. Large gauge, colored by band (green/amber/orange/red), with the backend's `authenticity.copy` rendered verbatim beneath. This is the anchor.
2. **"What this can't tell you" card** — the fixed `limitations[]` bullets (sample≠your vial; purity≠safety; only independent testing of *your* vial tells you; purity≠potency). Must sit high and read as essential, not as a disclaimer. **This is the design's moral center — give it real visual weight near the verdict.**
3. **Completeness** — secondary gauge (neutral teal) + a **14-item ✓/✗ checklist** ("X of 14 present", "missing isn't proof" caption) of expected sections (identity, purity, assay, heavy metals, endotoxin, sterility, residual solvents, impurity profile, water content, batch/lot, vial photo, accreditation, verification, test date).
4. **Verify actions** — a prominent "Verify with the lab" button (opens the lab's verification URL) and/or a Janoshik "Tap to verify" button when a verification key is present. Independent verifiability is *the* community trust signal — make these buttons feel like the primary next action.
5. **Lab badge** — "Recognized lab: {name}", tinted by trust tier (trusted/recognized/flagged); shows a caveat line for labs with documented accuracy issues.
6. **Document-type chip** — third-party lab (reassuring) vs manufacturer/in-house QC (caution) vs unknown. Informational, near the verdict.
7. **Findings list** — one tile per applicable hard check, each with its `message`, a status icon + color. Fired critical checks get distinct red treatment. Mixed pass/warning/fail states need clear, scannable iconography.
8. **Detected-info chips** — peptide, MS technique, input type, a "Measured X / Y mg" dose chip, and a **colored "Purity X% · grade" chip** (green good+/amber marginal/red below-grade).
9. **Batch-match prompt** — a card with two checkboxes ("lot matches my vial", "cap/crimp color matches"), echoing the parsed batch token. The one check only the user can do; local UI state only.
10. **Trust Profile card (conditional)** — when the user came through onboarding, a green/amber/red signal card reconciling their answers against this scan (flags contradictions). Renders only when onboarding answers exist; standalone scans look identical to before.
11. **`notes[]`** info banners (e.g., image-input or low-quality-scan caveats).
12. **Advanced / debug (collapsible)** — fired rules grouped by severity, rule counts, raw JSON/features/LLM. A developer surface — make it tuck away cleanly.
13. **Persistent disclaimer** at the bottom.

**Design questions worth solving here:** How do you keep this from feeling like an endless card-stack? Can the verdict + limitations + verify-action form a coherent "hero" zone above the fold, with everything else as progressive disclosure? How do red/amber/green findings stay scannable without turning the screen into a stoplight? How does completeness stay clearly *subordinate* to authenticity?

---

## Other screens

- **Onboarding Trust Journey** — a calm, confidence-building paged flow ("Step X of 8") with per-step "Why this matters" + red-flag context. Should feel educational and reassuring, not like a survey wall. Persistent "Skip to COA check." Ends on a **Trust Profile summary** (qualitative green/amber/red signal list, no number) offering two paths: scan a COA, or a pre-purchase checklist.
- **Home / Scan** — one clear primary action (pick PDF/image or take a photo), a quiet backend-connection indicator, friendly client-side validation errors. Make the first impression credible.
- **Scanning** — upload progress → indeterminate analyzing state with reassuring rotating copy ("Reading the certificate…", "Cross-checking the lab…"). Cancelable. A good moment for tasteful motion.
- **Not-a-COA & error states** — friendly, actionable, never blamey. (backend unreachable / 400 bad type or too small / 413 too large / timeout / not-a-COA.)
- **About / How it works** — honest explanation of the two axes + hard checks + verify-with-lab, a **glossary** (purity vs assay vs potency, endotoxin, sterility, heavy metals, residual solvents/TFA, third-party vs in-house, batch/lot, impurity breakdown), and **harm-reduction** notes. "Replay the trust guide" entry.

---

## Locked copy rules (legal/safety — do not redesign away)

- Render the backend's `authenticity.copy`, `completeness.copy`, and each `hard_checks[*].message` **verbatim**. When a critical check fires, the backend overrides `copy` with a specific sentence — always show whatever `copy` contains; never substitute your own wording.
- **Never** display the words "Forged" / "Fake" / "Counterfeit." Map the internal `likely_forged` label to **color and icon only** — show its human `copy` string.
- Keep this persistent disclaimer on results and About, verbatim:
  > This result is an **indicator, not legal or medical advice**. It does not confirm a product is safe to use. Always verify directly with the issuing lab and vendor before making any decision.
- **RUO framing throughout:** research-reagent language; no dosing/injection guidance.

---

## Design principles to hold yourself to

1. **Credibility over flash.** Forensic/lab-grade feeling. Restraint reads as trustworthy; novelty for its own sake reads as a scam.
2. **Color is signal.** Verdict red/amber/green = authenticity only. Completeness and chrome stay neutral. Never color-only — always pair color with icon + text (a11y).
3. **The reframe is the hero, not the asterisk.** "Verified ≠ safe" must be impossible to overlook.
4. **One primary action per screen.** Especially: verify-with-lab and match-to-your-vial are the actions that actually protect the user.
5. **Hierarchy by importance, not by data order.** The backend returns a flat blob; you impose meaning.
6. **Accessibility:** WCAG-AA contrast in light *and* dark, scalable text, semantic labels, large legible gauge numerals.
7. **Responsive:** excellent on a phone; on wide web, constrain content width — don't stretch full-bleed.
8. **Calm, plain-spoken microcopy.** Non-alarmist even when flagging red.

---

## What to deliver

Visual artifacts and specs only — no code. I'll translate these into Flutter myself.

1. **A documented design system** (the foundation — do this first):
   - **Color:** full light + dark palettes with named roles (surfaces, text, borders, accent) and the **verdict palette** (authenticity green/amber/orange/red) and **completeness neutral** as a distinct, clearly-labeled set. Give hex values and state contrast ratios for key text/background pairs (WCAG-AA).
   - **Typography:** type scale (role, size, weight, line-height) — pick fonts that read as clinical/credible and note them.
   - **Spacing & layout:** spacing scale, grid/margins, content max-width for wide web, card radius/border/elevation language.
   - **Components:** specs + visual examples for the recurring pieces — buttons, chips (incl. the purity-grade chip), cards, the **score gauge**, **hard-check finding tile** (pass/warn/fail variants), **lab badge** (trust tiers), **trust-profile signal row** (green/amber/red), checklist ✓/✗ row, info/note banner, the disclaimer block. Show each component's states.
   - **Iconography & motion:** icon style direction; motion described in words (e.g. gauge fill easing/duration, scanning-state animation) — no code.
2. **High-fidelity screen mockups**, light + dark, phone-width and a wide-web variant for at least the key screens. **Priority order:** Results (the centerpiece) → Onboarding / Trust Profile summary → Home & Scanning → Not-a-COA / error states → About. Use realistic content from the data contract below (e.g. an authentic Janoshik result, a suspicious result with a fired check, a forged result).
3. A short **rationale**: what the new identity is, what changed from the current stock-M3 look and why, and how the design enforces "verified ≠ safe."
4. Note any new dependency a faithful implementation would imply (custom font, an icon set) and flag any idea that would need new backend data as "future."

**Format:** deliver as rendered mockup images / a clickable visual where possible, plus the design-system values in text (hex, sizes, spacing) so they're directly transcribable. Annotate mockups with the token/component names from the system so the mapping to implementation is unambiguous.

---

## Appendix — backend data contract (reference only; do not change how it's consumed)

The full, authoritative API/response contract lives in **`flutter_frontend_claude_code_prompt.md`** (the original build prompt) — read it for exact field shapes. The essentials you'll be presenting:

- Two endpoints: `GET /api/health`, `POST /api/scan` (multipart `file`). Errors: `400` (bad type / <1 KB), `413` (>20 MB). "Not a COA" returns **HTTP 200** with `error: "input_not_coa"` — branch on the body, not the status.
- `POST /api/scan` → 200 full result contains: `authenticity` & `completeness` (each `score` 0–100, `label`, `copy`, plus completeness's `checklist[]`), `summary` (peptide, MS technique, labeled/measured mg, batch_lot, purity_pct + purity_grade, rule_counts), `notes[]`, `limitations[]` (fixed reframe copy), `hard_checks{}` (per-check `status` + `message` — these drive the findings list; includes `known_lab`, `janoshik`, `verifiability`, `doc_type`, `mw_table`, `assay_mass`, `recency`, `methods`, etc.), `rule_results[]` (status/severity/category, no detail text — debug surface), `features` (raw extraction incl. full OCR — debug only), `llm`/`llm_completeness` (debug).
- **Band labels:** authenticity `likely_authentic` (≥85) / `verify_recommended` (≥60) / `suspicious` (≥30) / `likely_forged` (<30) → green/amber/orange/red. Completeness `full_report` (≥75) / `partial_report` (≥45) / `minimal_report` (≥20) / `skeletal` (<20) → neutral teal.

**Test data:** real COAs under `COAs/`, fakes under `FAKE/`. Mock fixtures (`USE_MOCK=true`, no backend needed) cover authentic / suspicious / forged / not-a-COA / error cases — use these to iterate the design offline. Run: `flutter run -d chrome --dart-define=USE_MOCK=true`.
