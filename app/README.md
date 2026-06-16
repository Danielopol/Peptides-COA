# Peptide COA Scanner — Flutter frontend (local MVP)

A Flutter client for the Peptide Certificate of Analysis (COA) scanner. Upload a
COA (PDF or image); the local FastAPI backend reads it, cross-checks the lab and
known peptide masses, and returns two scores — **authenticity** and
**completeness** — plus findings and (for some labs) a "verify with the lab"
link.

> **Scope:** local MVP — no auth, accounts, database, or billing. Single
> anonymous user against the local backend. See `DECISIONS.md`.

## Prerequisites

- Flutter (stable). Verified with **Flutter 3.44 / Dart 3**.
- For the real backend: Python backend in `../backend` running (see below).
- A Chromium browser for web (`flutter run -d chrome`), or use `-d web-server`
  and open the URL in any browser.

## 1. Start the backend (real mode)

```bash
cd ../backend
uvicorn app.main:app --reload        # serves http://localhost:8000
```

Requires the system `tesseract` OCR binary. `ENABLE_LLM` in `backend/.env`
controls the (billable) Gemini vision pass — set it to `false` for deterministic
offline-ish runs.

## 2. Run the app

Real backend (default):

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=USE_MOCK=false
```

No backend needed (canned fixtures):

```bash
flutter run -d chrome --dart-define=USE_MOCK=true
```

Android:

```bash
flutter run -d <android-device> \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000   # 10.0.2.2 = host from the emulator
```

### `--dart-define` flags

| Flag | Default | Meaning |
|------|---------|---------|
| `API_BASE_URL` | `http://localhost:8000` | Backend base URL |
| `USE_MOCK` | `false` | `true` → use `MockApiClient` (no backend) |

In mock mode, the returned fixture is chosen by filename keyword: a name
containing `fake` → likely-forged, `caution`/`mw` → suspicious (wrong MW),
`blank` → not-a-COA, anything else → authentic.

## What you'll see

- **Home** — backend connection indicator (tap to recheck), pick a PDF/image (or
  take a photo on Android). Client-side type/size validation (PDF/PNG/JPG/WEBP,
  ≤ 20 MB).
- **Scanning** — upload progress then an indeterminate "analyzing" state;
  cancelable.
- **Results** — authenticity gauge (verdict-coloured) + completeness gauge
  (neutral), the recognized-lab badge, a "verify with the lab" deeplink when
  present, findings (from hard checks), detected peptide/technique chips, image
  notes, a collapsible Advanced panel (fired rules, counts, LLM, raw JSON), and
  the persistent safety disclaimer.
- **Not-a-COA** and **error** states (400 / 413 / unreachable).
- **History** — session-local list (not persisted).
- **About** — how the two-axis scan works.

## Tests & checks

```bash
flutter analyze        # clean
flutter test           # ScoreGauge + verdict-colour mapping

# End-to-end data-layer check against a running backend (not part of flutter test):
dart run tool/smoke.dart http://localhost:8000
```

## Project layout

```
lib/
  main.dart, app.dart
  core/         config.dart · theme.dart · router.dart · verdict.dart
  models/       models.dart            (hand-written, no codegen)
  data/         api_client.dart · http_api_client.dart · mock_api_client.dart · fixtures.dart
  providers/    providers.dart         (Riverpod 3.x Notifiers)
  services/     file_input.dart        (auth/billing reserved for later)
  features/     home · scanning · results · history · about · shared/widgets
tool/smoke.dart                         (live-backend data-layer check)
```
