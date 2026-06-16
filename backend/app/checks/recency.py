"""COA recency / stale-date check (rule META-006, advisory).

The community treats a COA older than ~6 months as suspect: peptides degrade,
and an old report is less likely to represent the batch currently being sold
("anything older than 6 months is suspect, especially with peptides that
degrade"). This is a trust/verify signal, not proof of forgery, so it only caps
authenticity modestly and is labelled `stale` (amber), never `fired` (red).

We read the *content* date printed on the COA (analysis / test / report / issue
date), not the PDF metadata (that's metadata.py). To avoid false positives we
only accept a date that sits next to a relevant label and is NOT in an expiry
context, then use the NEWEST such date — if any dated context is recent, the COA
isn't stale.
"""
from __future__ import annotations
import re
from datetime import datetime, timezone

RULE_ID = "META-006"
STALE_DAYS = 183  # ~6 months

_MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

# Date-token patterns, scanned in priority order; spans don't overlap.
_PATTERNS = [
    ("iso", re.compile(r"(?P<y>\d{4})[-/.](?P<m>\d{1,2})[-/.](?P<d>\d{1,2})")),
    ("dmon", re.compile(r"(?P<d>\d{1,2})[ -]?(?P<mon>[A-Za-z]{3,9})[ ,.-]+(?P<y>\d{4})")),
    ("mond", re.compile(r"(?P<mon>[A-Za-z]{3,9})\s+(?P<d>\d{1,2})(?:st|nd|rd|th)?,?\s+(?P<y>\d{4})")),
    ("dmy", re.compile(r"(?P<a>\d{1,2})[-/.](?P<b>\d{1,2})[-/.](?P<y>\d{2,4})")),
    ("mony", re.compile(r"(?P<mon>[A-Za-z]{3,9})\s+(?P<y>\d{4})")),
]

_RELEVANT = re.compile(
    r"analy|tested|test|report|issue|certificate|\bcoa\b|sampl|complet|"
    r"\bdate\b|manufactur|\bmfg\b|production|printed",
    re.I,
)
_EXPIRY = re.compile(r"exp|valid\s*until|use\s*by|best\s*before|retest|shelf", re.I)


def _month(mon: str) -> int | None:
    return _MONTHS.get(mon[:3].lower())


def _mk(y: int, m: int, d: int, now: datetime) -> datetime | None:
    if y < 100:
        y += 2000
    if not (2015 <= y <= now.year + 1) or not (1 <= m <= 12) or not (1 <= d <= 31):
        return None
    try:
        return datetime(y, m, d, tzinfo=timezone.utc)
    except ValueError:
        return None


def _parse(kind: str, gd: dict, now: datetime) -> datetime | None:
    if kind == "iso":
        return _mk(int(gd["y"]), int(gd["m"]), int(gd["d"]), now)
    if kind in ("dmon", "mond"):
        m = _month(gd["mon"])
        return _mk(int(gd["y"]), m, int(gd["d"]), now) if m else None
    if kind == "mony":
        m = _month(gd["mon"])
        return _mk(int(gd["y"]), m, 1, now) if m else None
    if kind == "dmy":
        a, b = int(gd["a"]), int(gd["b"])
        # Ambiguous numeric: try day-first and month-first, keep valid non-future
        # candidates and pick the NEWEST (benefit of the doubt -> fewer false stale).
        cands = []
        for day, mon in ((a, b), (b, a)):
            dt = _mk(int(gd["y"]), mon, day, now)
            if dt and dt <= now:
                cands.append(dt)
        return max(cands) if cands else None
    return None


def check(ocr_text: str, now: datetime | None = None) -> dict:
    text = ocr_text or ""
    now = now or datetime.now(timezone.utc)

    claimed: list[tuple[int, int]] = []  # (start, end) spans already consumed
    dates: list[datetime] = []
    for kind, pat in _PATTERNS:
        for m in pat.finditer(text):
            if any(m.start() < e and s < m.end() for s, e in claimed):
                continue  # overlaps a higher-priority token
            window = text[max(0, m.start() - 32): m.start()].lower()
            if _EXPIRY.search(window):
                claimed.append((m.start(), m.end()))
                continue
            if not _RELEVANT.search(window):
                continue
            dt = _parse(kind, m.groupdict(), now)
            if dt is None or dt > now:  # ignore unparseable / future dates
                continue
            claimed.append((m.start(), m.end()))
            dates.append(dt)

    if not dates:
        return {"status": "not_applicable", "rule_id": RULE_ID,
                "reason": "no dated analysis/report context found"}

    newest = max(dates)
    age_days = (now - newest).days
    base = {"rule_id": RULE_ID, "coa_date": newest.date().isoformat(), "age_days": age_days}
    if age_days > STALE_DAYS:
        months = round(age_days / 30.4)
        return {
            **base, "status": "stale", "severity": "minor",
            "message": (
                f"The most recent date on this COA is {newest.date().isoformat()} "
                f"(~{months} months old). COAs older than ~6 months are considered "
                "stale — peptides degrade and the current batch may differ. Ask for "
                "a recent report or independent testing."
            ),
        }
    return {
        **base, "status": "pass",
        "message": f"COA date {newest.date().isoformat()} is within the last ~6 months.",
    }
