"""FastAPI entrypoint. Run with:

    cd backend
    uvicorn app.main:app --reload
"""
from __future__ import annotations
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import stripe
from dotenv import load_dotenv
from fastapi import (Body, FastAPI, File, Form, Header, HTTPException, Request,
                     UploadFile)
from fastapi.middleware.cors import CORSMiddleware

# Load backend/.env before anything reads os.environ (GEMINI_API_KEY, ENABLE_LLM...)
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from . import supa  # noqa: E402
from .scan import run_scan  # noqa: E402  (after env load)

# --- Stripe config -----------------------------------------------------------
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
APP_URL = os.environ.get("APP_URL", "https://www.peptidestrust.com").rstrip("/")
if STRIPE_SECRET_KEY:
    stripe.api_key = STRIPE_SECRET_KEY

# Frontend sends a plan key; the backend maps it to a Stripe price. Price IDs
# are env-overridable so switching test->live is just a Railway change (defaults
# are the current sandbox/test prices). Packs are one-time; subs are recurring.
PRICE_BY_PLAN = {
    "monthly": os.environ.get("STRIPE_PRICE_MONTHLY", "price_1TkLjWJDZavg79YTnhIr0MCs"),
    "yearly": os.environ.get("STRIPE_PRICE_YEARLY", "price_1TkLkrJDZavg79YTmqDgt4VK"),
    "pack3": os.environ.get("STRIPE_PRICE_PACK3", "price_1TkLlsJDZavg79YT5WcFUsTR"),
    "pack10": os.environ.get("STRIPE_PRICE_PACK10", "price_1TkLmMJDZavg79YTvv8CqlLU"),
}
SUBSCRIPTION_PLANS = {"monthly", "yearly"}
PACK_CREDITS = {"pack3": 3, "pack10": 10}


def _sub_period_end(sub: dict) -> int | None:
    """Subscription period end (epoch s). Top-level in older API versions,
    on the first item in newer ones."""
    cpe = sub.get("current_period_end")
    if not cpe:
        try:
            cpe = sub["items"]["data"][0]["current_period_end"]
        except (KeyError, IndexError, TypeError):
            cpe = None
    return cpe

MAX_BYTES = 20 * 1024 * 1024  # 20 MB
ALLOWED_SUFFIXES = {".pdf", ".png", ".jpg", ".jpeg", ".webp"}

# When true, /api/scan requires a signed-in, entitled user. Kept OFF by default
# so deploying the gate doesn't break the live (still open) app until the
# frontend is updated to send the user's access token. Flip to "true" in Railway
# once the frontend ships token + paywall handling.
REQUIRE_AUTH = os.environ.get("REQUIRE_AUTH", "false").lower() == "true"


def _bearer(authorization: str | None) -> str | None:
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    return None

# Allowed browser origins. Comma-separated list via the ALLOWED_ORIGINS env var
# (set in Railway). Defaults to the Vercel production domain. Add a custom
# domain by appending it, e.g.
#   ALLOWED_ORIGINS=https://peptides-coa.vercel.app,https://app.yourdomain.com
_DEFAULT_ORIGINS = ",".join([
    "https://peptidestrust.com",
    "https://www.peptidestrust.com",
    "https://peptides-coa.vercel.app",
])
_origins = os.environ.get("ALLOWED_ORIGINS", _DEFAULT_ORIGINS)
ALLOWED_ORIGINS = [o.strip() for o in _origins.split(",") if o.strip()]

app = FastAPI(title="Peptide COA Scanner — Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/me")
async def me(authorization: str | None = Header(default=None)) -> dict:
    """Current user's identity + scan entitlement. Requires a valid token."""
    if not supa.configured():
        raise HTTPException(503, "Auth/entitlement not configured")
    user = await supa.verify_user(_bearer(authorization))
    if not user:
        raise HTTPException(401, "Not signed in")
    ent = await supa.get_entitlement(user["id"])
    return {"email": user.get("email"), **ent}


@app.post("/api/scan")
async def scan(
    file: UploadFile = File(...),
    # "vendor" (a seller's COA) or "self" (the user's own independent test).
    # Only adapts result wording / trust signals — never the scores.
    origin: str = Form("vendor"),
    authorization: str | None = Header(default=None),
) -> dict:
    suffix = "." + file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(400, f"Unsupported file type: {suffix}")

    # --- Entitlement gate (only enforced when REQUIRE_AUTH) -----------------
    user = None
    billed_as = None
    if REQUIRE_AUTH:
        if not supa.configured():
            raise HTTPException(503, "Auth/entitlement not configured")
        user = await supa.verify_user(_bearer(authorization))
        if not user:
            raise HTTPException(401, "Sign in to scan")
        ent = await supa.get_entitlement(user["id"])
        billed_as = supa.decide_billing(ent)
        if billed_as is None:
            # No subscription, no free scan left this month, no credits.
            raise HTTPException(402, "No scans remaining — choose a plan")

    body = await file.read()
    if len(body) > MAX_BYTES:
        raise HTTPException(413, "File exceeds 20 MB limit")
    if len(body) < 1024:
        raise HTTPException(400, "File too small to be a valid COA")

    result = run_scan(body, file.filename, origin="self" if origin == "self" else "vendor")

    # Record history + consume entitlement only for a real COA result
    # (not-a-COA and errors never burn a free scan or a credit).
    if user and billed_as and "error" not in result:
        await supa.record_scan(user["id"], result, file.filename,
                               "self" if origin == "self" else "vendor", billed_as)
    return result


@app.post("/api/checkout")
async def checkout(payload: dict = Body(default={}),
                   authorization: str | None = Header(default=None)) -> dict:
    """Create a Stripe Checkout Session for the given plan and return its URL."""
    if not STRIPE_SECRET_KEY or not supa.configured():
        raise HTTPException(503, "Payments not configured")
    user = await supa.verify_user(_bearer(authorization))
    if not user:
        raise HTTPException(401, "Sign in to purchase")
    plan = (payload or {}).get("plan")
    price = PRICE_BY_PLAN.get(plan)
    if not price:
        raise HTTPException(400, "Unknown plan")

    mode = "subscription" if plan in SUBSCRIPTION_PLANS else "payment"
    kwargs = dict(
        mode=mode,
        line_items=[{"price": price, "quantity": 1}],
        success_url=f"{APP_URL}/?checkout=success",
        cancel_url=f"{APP_URL}/?checkout=cancel",
        client_reference_id=user["id"],
        customer_email=user.get("email"),
        metadata={"user_id": user["id"], "plan": plan},
    )
    if mode == "subscription":
        # Carry user_id/plan onto the Subscription so its lifecycle webhooks
        # can map back to the user without an extra lookup.
        kwargs["subscription_data"] = {"metadata": {"user_id": user["id"], "plan": plan}}
    try:
        session = stripe.checkout.Session.create(**kwargs)
    except stripe.StripeError as e:
        raise HTTPException(502, f"Stripe error: {e.user_message or 'checkout failed'}")
    return {"url": session.url}


@app.post("/api/webhooks/stripe")
async def stripe_webhook(request: Request) -> dict:
    """Stripe-authenticated source of truth for entitlements: grants credits on
    pack purchases and writes subscription state on lifecycle events."""
    if not STRIPE_WEBHOOK_SECRET:
        raise HTTPException(503, "Webhook not configured")
    payload = await request.body()
    sig = request.headers.get("stripe-signature")
    try:
        stripe.Webhook.construct_event(payload, sig, STRIPE_WEBHOOK_SECRET)
    except Exception:
        raise HTTPException(400, "Invalid signature")

    # Use the raw JSON (plain dicts) rather than the verified StripeObject —
    # newer stripe-python StripeObjects don't support .get().
    event = json.loads(payload)
    etype = event["type"]
    obj = event["data"]["object"]

    if etype == "checkout.session.completed" and obj.get("mode") == "payment":
        meta = obj.get("metadata") or {}
        uid = obj.get("client_reference_id") or meta.get("user_id")
        plan = meta.get("plan")
        credits = PACK_CREDITS.get(plan)
        if uid and credits:
            reason = f"purchase:{plan}:{obj.get('id')}"
            if not await supa.ledger_reason_exists(reason):  # idempotent
                await supa.add_credits(uid, credits, reason)

    elif etype in ("customer.subscription.created",
                   "customer.subscription.updated",
                   "customer.subscription.deleted"):
        meta = obj.get("metadata") or {}
        uid = meta.get("user_id")
        if uid:
            plan = meta.get("plan") or "monthly"
            status = "canceled" if etype.endswith("deleted") else (
                "active" if obj.get("status") in ("active", "trialing") else obj.get("status")
            )
            cpe = _sub_period_end(obj)
            cpe_iso = (datetime.fromtimestamp(cpe, tz=timezone.utc).isoformat()
                       if cpe else None)
            await supa.upsert_subscription(uid, plan, status, cpe_iso,
                                           obj.get("customer"), obj.get("id"))

    return {"received": True}
