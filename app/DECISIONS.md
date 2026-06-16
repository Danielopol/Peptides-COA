# DECISIONS

Assumptions, deviations, and substitutions made while building the Flutter
frontend MVP. The companion spec is `../flutter_frontend_claude_code_prompt.md`.

## Scope (this phase)

- **Local MVP only.** No authentication, accounts, database, billing, or
  quota/paywall. Single anonymous user hitting the local FastAPI backend. The
  goal is to validate the backend pipeline and the UI together before adding
  auth/DB/billing later.
- The backend exposes only `GET /api/health` and `POST /api/scan`. There is no
  `/api/me`, `/api/history`, `/api/rules`, or billing — so none are called.

## Backend contract (verified against the live backend)

- Two-axis result: `authenticity` and `completeness`, each with
  `score`/`label`/`copy`. **Both axes are shown** (two gauges); authenticity is
  the primary signal and carries the verdict colour, completeness is secondary
  and neutral (teal).
- "Not a COA" is returned as **HTTP 200** with `{"error":"input_not_coa",...}`,
  not a 4xx. Handled by branching on the body.
- Error codes: `400` (unsupported type / file < 1 KB) and `413` (> 20 MB).
  There is **no** `402`/`415`/`422`.
- **Findings are driven by `hard_checks`**, because `rule_results` carry no
  human-readable detail (only `rule_id`/`name`/`category`/`severity`/`status`).
  The readable text lives in `hard_checks[*].message`. Fired `rule_results` are
  shown in the collapsible "Advanced" panel.
- `authenticity.copy` is rendered **verbatim**. When a critical hard check fires
  (janoshik / mw_table / visual_lab) the backend overrides `copy` with that
  check's specific message — we never substitute our own wording.
- Severity enum is `critical`/`major`/`minor`. Authenticity band labels:
  `likely_authentic` / `verify_recommended` / `suspicious` / `likely_forged`.

## Deviations / substitutions

1. **Hand-written models, no codegen.** The spec suggested `freezed` +
   `json_serializable`. We use plain immutable Dart classes with manual
   `fromJson` (in `lib/models/models.dart`) so the app compiles after
   `flutter pub get` with **no `build_runner` step**. Parsing is defensive
   (tolerant of int/double/string/null) and keeps the raw payload for the debug
   panel. Trade-off: no generated `copyWith`/`==`, which we don't need here.
2. **Riverpod 3.x.** `pub` resolved `flutter_riverpod ^3.x`. `StateProvider` is
   legacy there, so all mutable state uses `Notifier`/`NotifierProvider`
   (`ScanController`, `HistoryNotifier`, `SelectedResultNotifier`).
3. **`file_picker` 11.x API.** `pickFiles` is now a **static** method
   (`FilePicker.pickFiles(...)`), not `FilePicker.platform.pickFiles(...)`.
4. **`ApiClient` interface depends on dio's `CancelToken`.** For MVP simplicity
   the cancel mechanism is dio's token (the mock ignores it). If a non-dio
   client is ever needed, abstract this behind our own cancel handle.
5. **History is in-memory only** (session-scoped, not persisted). Labelled as
   local-only in the UI. No `shared_preferences` to keep dependencies minimal.
6. **`USE_MOCK` defaults to `false`** so the app talks to the real local backend
   by default (the point of this phase). `API_BASE_URL` defaults to
   `http://localhost:8000`. The `MockApiClient` is kept for offline UI work and
   picks a fixture by filename keyword (`fake`, `caution`/`mw`, `blank`, else
   authentic).
7. **`services/` reserved.** It currently holds only `file_input.dart`. Auth and
   billing services will live here in a later phase (none added now).
8. **Theme/colour.** Indigo seed for chrome; verdict greens/ambers/reds are
   reserved strictly for the authenticity signal (see `core/verdict.dart`), and
   colour is always paired with an icon + text (never colour-only).

## Legal/safety

- The required disclaimer is shown verbatim on Results and About
  (`DisclaimerBanner`). We never render "Forged"/"Fake"/"Counterfeit" — the
  internal `likely_forged` label maps to colour/icon only; user-facing text is
  always the backend's `copy`/`message`.

## Verification performed

- `flutter analyze` — clean.
- `flutter test` — 5/5 pass (ScoreGauge + verdict-colour mapping).
- `flutter build web` — succeeds.
- `dart run tool/smoke.dart` — real backend responses (real Janoshik COA + a
  fake) parse correctly into the models.
- Browser smoke (built web): app boots with 0 console errors and its health
  check round-trips to the backend.
