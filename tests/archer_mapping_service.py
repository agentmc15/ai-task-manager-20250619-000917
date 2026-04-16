"""
Archer mapping service for Clarity submissions.

Takes the 22-entry ``enriched_json`` payload produced by
``enrichment_service.enrich_project`` and builds a 28-entry ``archer_json``
payload consumed by the downstream Archer publisher.

Transformation:

* All 22 enriched entries are preserved verbatim.
* 5 new ``*_archer_id`` entries are appended, each resolved by looking up
  the corresponding original answer against an in-memory CSV lookup.
* 1 new static entry is appended: ``authorization_package_source_id`` is
  hardcoded to ``"177473"`` (the Archer ID for the Clarity package source).

CSV lookups are loaded once at module import from ``backend/data/lookups/``.
Column headers are ignored - column 0 is always the clarity_id, column 1
is always the archer_id. Matching is case-insensitive and whitespace-
trimmed on both sides. A missing or unreadable CSV logs a warning and
falls back to an empty dict - every lookup against that table will then
miss and return ``""``.

The public entry point, ``build_archer_json``, is a pure function: it
mutates nothing, performs no I/O, and is safe to call inside the submit
transaction. The caller assigns the returned list to
``project.archer_json``.
"""

from __future__ import annotations

import csv
import logging
from pathlib import Path
from typing import Any, Iterable

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# This file lives at:
#   backend/src/clarity/services/archer_mapping_service.py
# The lookups live at:
#   backend/data/lookups/*.csv
# So we walk up 3 parents (services -> clarity -> src -> backend) and
# descend into data/lookups.
_LOOKUPS_DIR: Path = Path(__file__).resolve().parents[3] / "data" / "lookups"

# Map of logical lookup name -> filename in _LOOKUPS_DIR.
# ISO and SA both consume clarity_archer_lookup.csv, so we reuse the same
# logical name ("personnel") for both and reference it twice below.
_LOOKUP_FILES: dict[str, str] = {
    "personnel": "clarity_archer_lookup.csv",
    "rtx_business": "business_ids.csv",
    "sbu_organization": "sbu_archer_ids.csv",
    "entity": "entities_archer_id.csv",
}


# ---------------------------------------------------------------------------
# Static overrides
# ---------------------------------------------------------------------------

# authorization_package_source is always "Clarity" in enriched_json.
# The corresponding Archer ID is a fixed constant.
_AUTHORIZATION_PACKAGE_SOURCE_ARCHER_ID: str = "177473"


# ---------------------------------------------------------------------------
# Enriched question IDs we need to pull answers from, and the new keys we
# emit when appending the _archer_id entries.
# ---------------------------------------------------------------------------

# (enriched_question_id, archer_question_id, lookup_name)
_ARCHER_ID_MAPPINGS: list[tuple[str, str, str]] = [
    ("information_system_owner",  "information_system_owner_archer_id",  "personnel"),
    ("system_administrator_sa",   "system_administrator_sa_archer_id",   "personnel"),
    ("rtx_business",              "rtx_business_archer_id",              "rtx_business"),
    ("sbu_organization",          "sbu_organization_archer_id",          "sbu_organization"),
    ("entity",                    "entity_archer_id",                    "entity"),
]


# ---------------------------------------------------------------------------
# CSV loader
# ---------------------------------------------------------------------------

def _normalize_key(value: Any) -> str:
    """
    Canonical form for lookup keys: trimmed and lowercased.
    Non-strings are stringified first.
    """
    if value is None:
        return ""
    return str(value).strip().casefold()


def _load_lookup(filename: str) -> dict[str, str]:
    """
    Load a two-column CSV into a normalized dict.

    * Column 0 is the clarity_id (lookup key).
    * Column 1 is the archer_id (lookup value).
    * The first row is assumed to be a header and is skipped.
    * Both columns are stripped. The key is also casefolded for
      case-insensitive matching.
    * Rows with a blank clarity_id are included - they map the empty key
      to whatever archer_id is present, which effectively means any
      lookup for a missing answer still returns ``""`` (because we
      reject empty keys at the ``get_archer_id`` boundary).

    A missing or unreadable file logs a warning and returns an empty dict.
    """
    path = _LOOKUPS_DIR / filename
    if not path.is_file():
        log.warning(
            "Archer lookup file not found: %s. Lookups against this table "
            "will miss and return empty strings.",
            path,
        )
        return {}

    out: dict[str, str] = {}
    try:
        with path.open(encoding="utf-8-sig", newline="") as f:
            reader = csv.reader(f)
            try:
                next(reader)  # drop header row
            except StopIteration:
                log.warning("Archer lookup file %s is empty.", path)
                return {}

            for row_num, row in enumerate(reader, start=2):
                if len(row) < 2:
                    continue  # malformed / short row - skip silently
                clarity_id_raw = row[0]
                archer_id_raw = row[1]
                key = _normalize_key(clarity_id_raw)
                value = str(archer_id_raw).strip() if archer_id_raw is not None else ""
                if not value:
                    # Blank archer_id is useless - skip.
                    continue
                out[key] = value
    except OSError as e:
        log.warning(
            "Failed to read Archer lookup file %s: %s. Lookups against "
            "this table will miss and return empty strings.",
            path, e,
        )
        return {}
    except csv.Error as e:
        log.warning(
            "Malformed CSV in %s: %s. Lookups against this table will miss "
            "and return empty strings.",
            path, e,
        )
        return {}

    log.info("Loaded %d Archer lookup entries from %s", len(out), path.name)
    return out


def _load_all_lookups() -> dict[str, dict[str, str]]:
    """Load every configured lookup table. Called once at module import."""
    return {name: _load_lookup(filename) for name, filename in _LOOKUP_FILES.items()}


# Loaded once at module import. Module is imported once per process, so
# the dicts are effectively global constants for the life of the container.
_LOOKUPS: dict[str, dict[str, str]] = _load_all_lookups()


# ---------------------------------------------------------------------------
# Lookup API
# ---------------------------------------------------------------------------

def get_archer_id(lookup_name: str, clarity_value: Any) -> str:
    """
    Resolve a Clarity-side answer to its Archer-side ID.

    Returns ``""`` on any of: unknown lookup_name, empty input, or
    lookup miss. This is deliberately permissive because submits have
    already passed UI validation by this point - we do not want to
    reject a submission because the lookup table is behind.
    """
    key = _normalize_key(clarity_value)
    if not key:
        return ""
    table = _LOOKUPS.get(lookup_name)
    if not table:
        return ""
    return table.get(key, "")


# ---------------------------------------------------------------------------
# Enriched-list helpers (tolerant of dict OR pydantic objects)
# ---------------------------------------------------------------------------

def _get_field(obj: Any, name: str, default: Any = None) -> Any:
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


def _entry_as_dict(entry: Any) -> dict[str, Any]:
    """Copy one entry into a plain dict, preserving all known fields."""
    if entry is None:
        return {}
    if isinstance(entry, dict):
        return dict(entry)
    dump = getattr(entry, "model_dump", None)
    if callable(dump):
        try:
            return dump()
        except Exception:  # pragma: no cover - defensive
            pass
    return {
        "question_id": _get_field(entry, "question_id"),
        "answer": _get_field(entry, "answer"),
        "justification": _get_field(entry, "justification"),
    }


def _index_answers(entries: Iterable[Any]) -> dict[str, Any]:
    """Build a question_id -> answer index from a list of enriched entries."""
    out: dict[str, Any] = {}
    for entry in entries or []:
        qid = _get_field(entry, "question_id")
        if qid is None:
            continue
        out[str(qid)] = _get_field(entry, "answer")
    return out


def _make_entry(question_id: str, answer: Any) -> dict[str, Any]:
    """
    Build an appended entry in the standard shape. justification is None
    because these entries are system-derived, not user-provided.
    """
    return {
        "question_id": question_id,
        "answer": answer,
        "justification": None,
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def build_archer_json(enriched: Iterable[Any]) -> list[dict[str, Any]]:
    """
    Build the 28-entry ``archer_json`` payload from ``enriched_json``.

    * Copies all 22 enriched entries verbatim.
    * Appends 5 ``*_archer_id`` entries resolved via CSV lookup.
    * Appends 1 static ``authorization_package_source_id`` entry.

    Pure function, no I/O, no mutation of the input.
    """
    enriched_list = list(enriched or [])
    answers = _index_answers(enriched_list)

    # Start with a copy of the enriched entries.
    archer_list: list[dict[str, Any]] = [_entry_as_dict(e) for e in enriched_list]

    # Append the 5 CSV-backed lookup entries.
    for enriched_qid, archer_qid, lookup_name in _ARCHER_ID_MAPPINGS:
        clarity_value = answers.get(enriched_qid, "")
        archer_id = get_archer_id(lookup_name, clarity_value)
        if not archer_id and _normalize_key(clarity_value):
            # We had a non-empty input but the lookup missed. Worth
            # flagging because it usually means the CSV is out of date
            # or the questionnaire option list drifted.
            log.info(
                "Archer lookup miss: %s=%r not found in %s",
                enriched_qid, clarity_value, lookup_name,
            )
        archer_list.append(_make_entry(archer_qid, archer_id))

    # Append the static authorization_package_source_id entry.
    archer_list.append(_make_entry(
        "authorization_package_source_id",
        _AUTHORIZATION_PACKAGE_SOURCE_ARCHER_ID,
    ))

    return archer_list
