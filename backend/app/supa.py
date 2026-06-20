"""Supabase integration for the entitlement gate.

- User verification: calls Supabase `/auth/v1/user` with the caller's bearer
  token (needs only the public anon key — no JWT secret to manage, works
  regardless of HS256/asymmetric signing).
- Data access: server-side reads/writes via PostgREST using the SERVICE ROLE
  key, which bypasses Row Level Security (so the backend is the only thing that
  can grant credits / write subscriptions).

Env vars (set in Railway):
  SUPABASE_URL                 e.g. https://xxxx.supabase.co
  SUPABASE_ANON_KEY            public anon key (for user verification)
  SUPABASE_SERVICE_ROLE_KEY    SECRET (for privileged DB access)
"""
from __future__ import annotations

import os
from datetime import datetime, timezone

import httpx

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "")
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

_TIMEOUT = httpx.Timeout(10.0)


def configured() -> bool:
    """True when the env vars needed for the entitlement gate are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SERVICE_ROLE_KEY)


def _rest_headers() -> dict:
    return {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


async def verify_user(token: str | None) -> dict | None:
    """Return the Supabase user dict ({id, email, ...}) for a valid access
    token, or None if missing/invalid."""
    if not token or not SUPABASE_URL or not SUPABASE_ANON_KEY:
        return None
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as c:
            r = await c.get(
                f"{SUPABASE_URL}/auth/v1/user",
                headers={"apikey": SUPABASE_ANON_KEY,
                         "Authorization": f"Bearer {token}"},
            )
        if r.status_code == 200:
            return r.json()
    except httpx.HTTPError:
        pass
    return None


def _month_start_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0).isoformat()


async def get_entitlement(user_id: str) -> dict:
    """Compute the user's scan entitlement from subscriptions / credit_ledger /
    this-month's free usage."""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as c:
        sub_r, cred_r, free_r = (
            await c.get(
                f"{SUPABASE_URL}/rest/v1/subscriptions",
                headers=_rest_headers(),
                params={"user_id": f"eq.{user_id}",
                        "select": "plan,status,current_period_end", "limit": "1"},
            ),
            await c.get(
                f"{SUPABASE_URL}/rest/v1/credit_ledger",
                headers=_rest_headers(),
                params={"user_id": f"eq.{user_id}", "select": "delta"},
            ),
            await c.get(
                f"{SUPABASE_URL}/rest/v1/scans",
                headers=_rest_headers(),
                params={"user_id": f"eq.{user_id}", "billed_as": "eq.free",
                        "created_at": f"gte.{_month_start_iso()}",
                        "select": "id", "limit": "1"},
            ),
        )

    subscription = None
    sub_active = False
    rows = sub_r.json() if sub_r.status_code == 200 else []
    if rows:
        row = rows[0]
        end = row.get("current_period_end")
        active = row.get("status") == "active" and bool(end) and (
            datetime.fromisoformat(end) > datetime.now(timezone.utc)
        )
        sub_active = active
        subscription = {"plan": row.get("plan"), "active": active,
                        "current_period_end": end}

    credits = 0
    if cred_r.status_code == 200:
        credits = sum(int(x.get("delta", 0)) for x in cred_r.json())

    free_used = bool(free_r.json()) if free_r.status_code == 200 else False
    free_available = not free_used

    can_scan = sub_active or free_available or credits > 0
    return {
        "subscription": subscription,
        "credits": credits,
        "free_scan_available": free_available,
        "can_scan": can_scan,
    }


def decide_billing(ent: dict) -> str | None:
    """Pick how this scan is paid for, free-first. None => not entitled (402)."""
    sub = ent.get("subscription")
    if sub and sub.get("active"):
        return "subscription"
    if ent.get("free_scan_available"):
        return "free"
    if ent.get("credits", 0) > 0:
        return "credit"
    return None


async def record_scan(user_id: str, result: dict, filename: str, origin: str,
                      billed_as: str) -> None:
    """Insert the scan into history and consume a credit when billed_as=credit.
    Best-effort: a Supabase write failure must not break the user's result."""
    auth = result.get("authenticity") or {}
    comp = result.get("completeness") or {}
    row = {
        "user_id": user_id,
        "filename": filename,
        "origin": origin,
        "authenticity_score": auth.get("score"),
        "authenticity_label": auth.get("label"),
        "completeness_score": comp.get("score"),
        "completeness_label": comp.get("label"),
        "result": result,
        "billed_as": billed_as,
    }
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as c:
            r = await c.post(
                f"{SUPABASE_URL}/rest/v1/scans",
                headers={**_rest_headers(), "Prefer": "return=representation"},
                json=row,
            )
            scan_id = None
            if r.status_code in (200, 201):
                created = r.json()
                if created:
                    scan_id = created[0].get("id")
            if billed_as == "credit":
                await c.post(
                    f"{SUPABASE_URL}/rest/v1/credit_ledger",
                    headers=_rest_headers(),
                    json={"user_id": user_id, "delta": -1, "reason": "scan",
                          "scan_id": scan_id},
                )
    except httpx.HTTPError:
        pass
