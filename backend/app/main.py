"""FastAPI entrypoint. Run with:

    cd backend
    uvicorn app.main:app --reload
"""
from __future__ import annotations
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

# Load backend/.env before anything reads os.environ (GEMINI_API_KEY, ENABLE_LLM...)
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from .scan import run_scan  # noqa: E402  (after env load)

MAX_BYTES = 20 * 1024 * 1024  # 20 MB
ALLOWED_SUFFIXES = {".pdf", ".png", ".jpg", ".jpeg", ".webp"}

app = FastAPI(title="Peptide COA Scanner — Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/api/scan")
async def scan(
    file: UploadFile = File(...),
    # "vendor" (a seller's COA) or "self" (the user's own independent test).
    # Only adapts result wording / trust signals — never the scores.
    origin: str = Form("vendor"),
) -> dict:
    suffix = "." + file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(400, f"Unsupported file type: {suffix}")
    body = await file.read()
    if len(body) > MAX_BYTES:
        raise HTTPException(413, "File exceeds 20 MB limit")
    if len(body) < 1024:
        raise HTTPException(400, "File too small to be a valid COA")
    return run_scan(body, file.filename, origin="self" if origin == "self" else "vendor")
