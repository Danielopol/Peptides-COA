"""Shared loader for the two-level lab+vendor registry (Rules/registry.json).

Falls back to the legacy Rules/known_labs.json if registry.json is absent.
"""
from __future__ import annotations
import json
import re
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "Rules" / "registry.json"
LEGACY_PATH = ROOT / "Rules" / "known_labs.json"


@lru_cache(maxsize=1)
def _load() -> dict:
    if REGISTRY_PATH.exists():
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        return {"labs": data.get("labs", []), "vendors": data.get("vendors", [])}
    if LEGACY_PATH.exists():
        labs = json.loads(LEGACY_PATH.read_text(encoding="utf-8")).get("labs", [])
        return {"labs": labs, "vendors": []}
    return {"labs": [], "vendors": []}


def all_entities() -> list[dict]:
    """Labs and vendors flattened, each tagged with entity_kind."""
    data = _load()
    out = []
    for lab in data["labs"]:
        out.append({**lab, "entity_kind": "lab"})
    for v in data["vendors"]:
        out.append({**v, "entity_kind": "vendor"})
    return out


def by_id() -> dict[str, dict]:
    return {e["id"]: e for e in all_entities()}


def _compact(s: str) -> str:
    """Lowercase and strip everything but [a-z0-9] — collapses spaces and
    punctuation so a spaced alias can match a glued OCR form."""
    return re.sub(r"[^a-z0-9]", "", s.lower())


# Minimum length for a punctuation-insensitive 'compacted' substring match.
# Short compacted tokens lose word boundaries and risk matching inside
# unrelated runs of text, so only distinctive long names use this path.
_COMPACT_MIN = 10


def _domain_core(website: str) -> str | None:
    """Compacted registrable part of a website, e.g.
    'https://freedomdiagnosticstesting.com/' -> 'freedomdiagnosticstesting'."""
    if not website:
        return None
    host = re.sub(r"^https?://", "", website.lower()).split("/")[0]
    host = re.sub(r"^www\.", "", host)
    labels = host.split(".")
    core = "".join(labels[:-1]) if len(labels) >= 2 else host
    return _compact(core) or None


def _match_len(e: dict, low: str, compact: str) -> int:
    """Length of the longest name/alias/domain of entity `e` found in the text,
    or 0. Tries a precise word-boundary match first; falls back to a compacted
    substring match for distinctive (>= _COMPACT_MIN char) names so the issuer
    is still found when its name is glued into a domain or email — e.g. OCR of
    'FreedomDiagnosticsTesting.com' / 'Admin@FreedomDiagnostics.net'."""
    best = 0
    for n in [e["name"]] + list(e.get("aliases", [])):
        nl = n.lower()
        if len(nl) < 3:
            continue
        if re.search(rf"(?<!\w){re.escape(nl)}(?!\w)", low):
            best = max(best, len(nl))
            continue
        nc = _compact(nl)
        if len(nc) >= _COMPACT_MIN and nc in compact:
            best = max(best, len(nl))
    dc = _domain_core(e.get("website", ""))
    if dc and len(dc) >= _COMPACT_MIN and dc in compact:
        best = max(best, len(dc))
    return best


def match_in_text(ocr_text: str) -> dict | None:
    """Return the registry entity whose name/alias/domain appears in the text.

    Word-boundary matching keeps short aliases (e.g. 'PAL') from matching inside
    unrelated words; a compacted fallback catches names glued into URLs/emails.
    Prefers the longest match so a generic short alias can't win over a specific
    full name.
    """
    low = (ocr_text or "").lower()
    compact = _compact(low)
    best: tuple[int, dict] | None = None
    for e in all_entities():
        ml = _match_len(e, low, compact)
        if ml and (best is None or ml > best[0]):
            best = (ml, e)
    return best[1] if best else None


def text_mentions(entity: dict, ocr_text: str) -> bool:
    """Whether `entity`'s name/alias/domain appears in the text (same matching
    rules as match_in_text). Used by the visual-template check to confirm the
    OCR'd issuer agrees with the matched template."""
    low = (ocr_text or "").lower()
    return _match_len(entity, low, _compact(low)) > 0


def template_owners() -> list[dict]:
    """Entities whose visual COA template we fingerprint (coa_template_owner)."""
    return [e for e in all_entities() if e.get("coa_template_owner")]
