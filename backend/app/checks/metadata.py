"""PDF metadata sanity check (rules META-003 / META-004 as hard overrides).

Fires HARD only on logically-impossible metadata that a genuine PDF can never
produce:
  - modDate earlier than creationDate (a file cannot be modified before it
    was created)
  - creationDate or modDate in the future

Soft heuristics (consumer authoring software, personal-name author) are left
to the weighted rule engine (META-002) — they have weak discrimination and
many legitimate COAs trip them, so they must not force a verdict.

Images carry no PDF metadata and return not_applicable.
"""
from __future__ import annotations
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

import fitz

# Clock skew / timezone tolerance so a few minutes' difference never fires.
SKEW = 60 * 60 * 24  # 1 day in seconds


def _parse_pdf_date(s: str | None) -> datetime | None:
    if not s:
        return None
    m = re.match(r"D:(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?", s)
    if not m:
        return None
    parts = [int(x) if x else 0 for x in m.groups()]
    try:
        return datetime(parts[0], parts[1], parts[2],
                        parts[3], parts[4], parts[5], tzinfo=timezone.utc)
    except ValueError:
        return None


def check(file_bytes: bytes, filename: str, now: datetime | None = None) -> dict:
    if Path(filename).suffix.lower() != ".pdf":
        return {"status": "not_applicable", "reason": "no PDF metadata on image input"}
    now = now or datetime.now(timezone.utc)

    try:
        doc = fitz.open(stream=file_bytes, filetype="pdf")
        try:
            meta = dict(doc.metadata or {})
        finally:
            doc.close()
    except Exception as e:  # noqa: BLE001
        return {"status": "not_applicable", "reason": f"could not read metadata: {e}"}

    created = _parse_pdf_date(meta.get("creationDate"))
    modified = _parse_pdf_date(meta.get("modDate"))

    problems = []
    if created and modified and modified < created - timedelta(seconds=SKEW):
        problems.append(
            f"Modification date ({modified.date()}) precedes creation date "
            f"({created.date()}) — impossible for a genuine PDF."
        )
    future = now + timedelta(seconds=SKEW)
    if created and created > future:
        problems.append(f"Creation date ({created.date()}) is in the future.")
    if modified and modified > future:
        problems.append(f"Modification date ({modified.date()}) is in the future.")

    base = {
        "rule_id": "META-004",
        "creation_date": created.isoformat() if created else None,
        "mod_date": modified.isoformat() if modified else None,
    }
    if problems:
        return {
            **base,
            "status": "fired",
            "severity": "critical",
            "problems": problems,
            "message": "Impossible PDF metadata: " + " ".join(problems),
        }
    return {**base, "status": "pass"}
