"""FastAPI entrypoint. Run with:

    cd backend
    uvicorn app.main:app --reload
"""
from __future__ import annotations
import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

# Load backend/.env before anything reads os.environ (GEMINI_API_KEY, ENABLE_LLM...)
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from . import supa  # noqa: E402
from .scan import run_scan  # noqa: E402  (after env load)

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
