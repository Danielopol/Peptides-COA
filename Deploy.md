Here's the exact sequence, ordered so each step unblocks the next and you have something working you can verify at every stage. Don't skip ahead — each phase depends on the one before.

---

## Phase 1 — Get it into GitHub (foundation for everything)
1. Add `.gitignore` (exclude `.venv`, `.env`, `build/`, `.dart_tool/`).
2. `git init` → `git add .` → `git commit`.
3. Create the GitHub repo, `git push`.

✅ **Verify:** repo is on GitHub, and `.venv`/`.env` are **not** in it.

## Phase 2 — Deploy the backend (Railway)
4. Add a `Dockerfile` in `backend/` (installs `tesseract-ocr` + deps, runs uvicorn on `$PORT`).
5. Railway → New Project → Deploy from GitHub → set **Root Directory = `backend`**.
6. Add env vars in Railway (`GEMINI_API_KEY`, `ENABLE_LLM`, …).

✅ **Verify:** open `https://<your-app>.up.railway.app/api/health` → `{"status":"ok"}`.

## Phase 3 — Deploy the frontend (Vercel)
7. Set Flutter `API_BASE_URL` to the Railway URL (build-time `--dart-define`).
8. Deploy the Flutter **web** build to Vercel (point it at `app/`, build command outputs `build/web`).
9. Lock backend CORS to your Vercel domain (replace the `*` in [main.py](backend/app/main.py)).

✅ **Verify:** your live Vercel site loads and successfully scans a COA against the live backend. **You now have a publicly working app** (free, no accounts) — a real milestone you could soft-launch.

## Phase 4 — Auth + Database (Supabase)
10. Create the Supabase project.
11. Create the schema: `profiles`, `subscriptions`, `credit_ledger`, `scans` + Row Level Security.
12. Add `supabase_flutter`; wire sign-in (email + Google); gate the app behind a session.
13. Write each completed scan to `scans` → real persisted history.

✅ **Verify:** you can sign up, sign in, and your scan history survives a refresh.

## Phase 5 — Server-side entitlement gate
14. FastAPI: middleware to verify the Supabase JWT on requests.
15. Add `GET /api/me` (returns plan / credits / subscription status from Postgres).
16. Make `/api/scan` require auth, check entitlement, and return **402** when not entitled; decrement a credit only on a completed scan (in a transaction).
17. Repoint Flutter `PaymentsController` to read `/api/me` instead of `shared_preferences`; show the paywall on 402.

✅ **Verify:** a fresh account hits the paywall; manually inserting a credit row in Supabase lets it scan once, then blocks again.

## Phase 6 — Payments (Stripe)
18. Create Stripe products: monthly $7, yearly $50, and a **credit pack** (not single $2 scans — fee math).
19. Wire Stripe Checkout from the paywall (web redirect).
20. Add `/api/webhooks/stripe` — verify signature, write the entitlement/credit to Postgres.

✅ **Verify:** a real (test-mode) purchase flows Checkout → webhook → DB → `/api/me` shows the entitlement → scanning unlocks.

## Phase 7 — Launch hardening
21. Stripe test mode → live mode; real domain; HTTPS everywhere.
22. Confirm `.env`/keys only live in Railway/Vercel/Supabase dashboards, never in git.

---

## The principle behind this order
- **Git → Railway → Vercel first** gives you a *live, working app* before you touch auth or money. If something breaks, you know it's the deploy pipeline, not Stripe.
- **Auth/DB before payments** because a payment has nowhere to attach (no user, no store) until those exist.
- **Entitlement gate before Stripe** so you can test access control by hand-inserting DB rows — *before* real money is in the loop.

**Start with Phase 1, Step 1 — the `.gitignore` and `Dockerfile`.** That's the only part that needs files written; everything after is dashboard clicks plus the code in Phases 4–6.

Want me to generate the `.gitignore` and the backend `Dockerfile` right now so you can do Phase 1 → 2 immediately?