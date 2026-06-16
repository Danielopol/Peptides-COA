"""Tests for the COA recency / stale-date check (META-006).

Uses an explicit `now` so results don't drift with the wall clock. Runs
standalone (`python -m tests.test_recency`) or under pytest.
"""
from __future__ import annotations
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import recency as rc  # noqa: E402

NOW = datetime(2026, 6, 1, tzinfo=timezone.utc)


def test_recent_iso_date_passes():
    r = rc.check("Analysis Date: 2026-04-10\nPurity 99%", now=NOW)
    assert r["status"] == "pass"
    assert r["coa_date"] == "2026-04-10"


def test_old_date_is_stale():
    r = rc.check("Date of Analysis: 2025-06-01", now=NOW)  # ~12 months
    assert r["status"] == "stale"
    assert r["age_days"] > 183


def test_month_name_format():
    r = rc.check("Report Date: 13 May 2026", now=NOW)
    assert r["status"] == "pass"
    assert r["coa_date"] == "2026-05-13"


def test_mdy_month_name():
    r = rc.check("Tested: January 5, 2025", now=NOW)
    assert r["status"] == "stale"
    assert r["coa_date"] == "2025-01-05"


def test_newest_relevant_date_wins():
    # An old manufacture date plus a recent analysis date -> not stale.
    txt = "Manufactured: 2024-01-01\nAnalysis date: 2026-05-01"
    r = rc.check(txt, now=NOW)
    assert r["status"] == "pass"
    assert r["coa_date"] == "2026-05-01"


def test_expiry_date_is_ignored():
    # Only an expiry (future) date present -> no analysis date -> not_applicable.
    r = rc.check("Use by: 2028-01-01\nPurity 99%", now=NOW)
    assert r["status"] == "not_applicable"


def test_unlabeled_date_ignored():
    # A bare date with no relevant label nearby is not used.
    r = rc.check("Lot 2025-01-02-A random text", now=NOW)
    assert r["status"] == "not_applicable"


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
