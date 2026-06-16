# Backend container for the Peptide COA Scanner (FastAPI).
#
# IMPORTANT: this Dockerfile lives at the REPO ROOT, not in backend/, because
# the backend loads its rules data from the repo-root `Rules/` directory at
# runtime (app code computes ROOT = parents[2] == repo root). The image must
# therefore contain BOTH `backend/` and `Rules/` in the same layout.
#
# On Railway: leave "Root Directory" at the repo root (default) so this
# Dockerfile is detected and the build context includes Rules/.
FROM python:3.12-slim

# System dependency: the tesseract OCR binary that `pytesseract` shells out to.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first so this layer is cached unless requirements change.
COPY backend/requirements.txt ./backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

# App code + the repo-root rules data the backend reads at runtime.
# Layout under /app must mirror the repo so parents[2] -> /app and
# /app/Rules/... resolves correctly.
COPY backend ./backend
COPY Rules ./Rules

# Run uvicorn from inside backend/ so `app.main:app` imports and ROOT == /app.
WORKDIR /app/backend
EXPOSE 8000

# Railway injects $PORT; fall back to 8000 for local `docker run`.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
