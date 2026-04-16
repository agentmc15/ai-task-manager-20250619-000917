"""
Enrichment service for Clarity submissions.

Takes the 13-answer questionnaire response stored on a Project and produces
a 22-entry enriched payload consumed by the downstream Archer publisher
service. The function is pure and side-effect-free: it does not touch the
database, the session, or any I/O. The caller is responsible for assigning
the returned list to ``project.enriched_json`` and flipping
``project.enriched`` within its own transaction.

Classification rules (from Linda Ciulla's mapping spec):

* Q10 ``information_classification`` is choose-many. CUI trumps: if ANY
  selected value maps to CUI, the category is CUI. Otherwise Non-CUI.
* Q11 ``connectivity`` is choose-many. External trumps: if ANY selected
  value maps to External, the category is External. Otherwise Internal.

Baseline recommendation:

* CUI                              -> "Advanced"
* Non-CUI + External connectivity  -> "Enhanced"
* Non-CUI + Internal connectivity  -> "Basic"

Authorization package name format (Example 1 from Linda's Word doc):

    {BU}_{CMMC_CATEGORY}_{CONNECTIVITY}_{SAP_NAME}

e.g. ``CORP_CUI_INT_Archer5``.
"""

from __future__ import annotations

import logging
from typing import Any, Iterable

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Mapping constants (Linda Ciulla's IRAMP mapping spec)
# ---------------------------------------------------------------------------

# Q10 information_classification values that count as CUI.
# Any value not in this set is treated as Non-CUI.
INFO_CLASSIFICATION_CUI_VALUES: frozenset[str] = frozenset({
    "CDI/CUI(DFARS)",
})

# Q11 connectivity values that count as External.
# Any value not in this set is treated as Internal.
CONNECTIVITY_EXTERNAL_VALUES: frozenset[str] = frozenset({
    "External",
    "Global Orion",
    "Interconnected System - Contractor to Government (C2G)",
    "Public",
})

# Q7 rtx_business display value -> BU code used in the enriched name.
BU_CODE_MAP: dict[str, str] = {
    "Corporate": "CORP",
    "P & W": "PW",
    "Raytheon": "RAY",
    "Collins Aerospace": "COL",
}

# Question IDs we read from responses_json.
_Q_AUTHORIZATION_PACKAGE_NAME = "authorization_package_name"  # Q1
_Q_RTX_BUSINESS = "rtx_business"                              # Q7
_Q_INFORMATION_CLASSIFICATION = "information_classification"  # Q10
_Q_CONNECTIVITY = "connectivity"                              # Q11


# ---------------------------------------------------------------------------
# Answer-shape helpers (defensive: handle pydantic objects OR raw dicts)
# ---------------------------------------------------------------------------

def _get_field(obj: Any, name: str, default: Any = None) -> Any:
    """Read a field from either a pydantic/SQLModel object or a plain dict."""
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


def _answers_by_qid(responses: Iterable[Any]) -> dict[str, Any]:
    """Index responses by question_id, tolerating pydantic or dict entries."""
    out: dict[str, Any] = {}
    for entry in responses or []:
        qid = _get_field(entry, "question_id")
        if qid is None:
            continue
        out[str(qid)] = _get_field(entry, "answer")
    return out


def _as_str_list(answer: Any) -> list[str]:
    """
    Normalise a choose-many answer to list[str].

    Accepts: list[str], a single str, or None/anything else (returns []).
    Strips whitespace and drops empties so the classifiers don't match on "".
    """
    if answer is None:
        return []
    if isinstance(answer, str):
        return [answer.strip()] if answer.strip() else []
    if isinstance(answer, list):
        result: list[str] = []
        for v in answer:
            if v is None:
                continue
            s = str(v).strip()
            if s:
                result.append(s)
        return result
    # Anything else (dict, number, etc.) isn't a valid choose-many answer.
    return []


def _as_str(answer: Any) -> str:
    """Normalise a single-answer field to a stripped string."""
    if answer is None:
        return ""
    if isinstance(answer, str):
        return answer.strip()
    # Unexpected shape - stringify defensively.
    return str(answer).strip()


# ---------------------------------------------------------------------------
# Classifiers
# ---------------------------------------------------------------------------

def _classify_information(answer: Any) -> str:
    """
    Classify Q10 answer as 'CUI' or 'Non-CUI'.

    CUI trumps: if any selected value is in INFO_CLASSIFICATION_CUI_VALUES,
    the whole set is CUI.
    """
    selected = _as_str_list(answer)
    for value in selected:
        if value in INFO_CLASSIFICATION_CUI_VALUES:
            return "CUI"
    return "Non-CUI"


def _classify_connectivity(answer: Any) -> str:
    """
    Classify Q11 answer as 'External' or 'Internal'.

    External trumps: if any selected value is in
    CONNECTIVITY_EXTERNAL_VALUES, the whole set is External.
    """
    selected = _as_str_list(answer)
    for value in selected:
        if value in CONNECTIVITY_EXTERNAL_VALUES:
            return "External"
    return "Internal"


def _compute_baseline(info_category: str, conn_category: str) -> str:
    """Map (info_category, conn_category) to the baseline recommendation."""
    if info_category == "CUI":
        return "Advanced"
    if conn_category == "External":
        return "Enhanced"
    return "Basic"


def _build_enriched_name(
    bu_code: str,
    cmmc_category: str,
    connectivity_category: str,
    sap_name: str,
) -> str:
    """
    Build the {BU}_{CMMC}_{CONN}_{SAP_NAME} enriched package name.

    * CMMC: 'CUI' stays 'CUI'; 'Non-CUI' becomes 'CRM'.
    * CONN: 'External' -> 'EXT'; 'Internal' -> 'INT'.
    """
    cmmc_code = "CUI" if cmmc_category == "CUI" else "CRM"
    conn_code = "EXT" if connectivity_category == "External" else "INT"
    return f"{bu_code}_{cmmc_code}_{conn_code}_{sap_name}"


# ---------------------------------------------------------------------------
# Entry builder
# ---------------------------------------------------------------------------

def _make_entry(question_id: str, answer: Any) -> dict[str, Any]:
    """
    Build a single enriched entry matching the shape of existing responses:
    ``{"question_id": ..., "answer": ..., "justification": None}``.

    Justification is left as None for enriched entries - they are
    system-derived, not user-provided.
    """
    return {
        "question_id": question_id,
        "answer": answer,
        "justification": None,
    }


def _original_entries_as_dicts(responses: Iterable[Any]) -> list[dict[str, Any]]:
    """
    Copy the original 13 entries into a new list of plain dicts, preserving
    ``question_id``, ``answer``, and ``justification``. Any other fields
    (e.g. ``submitted_at``) are preserved too, so downstream consumers that
    might rely on them don't regress.
    """
    out: list[dict[str, Any]] = []
    for entry in responses or []:
        if entry is None:
            continue
        if isinstance(entry, dict):
            out.append(dict(entry))
            continue
        # pydantic / SQLModel object - prefer model_dump if available.
        dump = getattr(entry, "model_dump", None)
        if callable(dump):
            try:
                out.append(dump())
                continue
            except Exception:  # pragma: no cover - defensive
                pass
        # Fallback: build manually from known fields.
        out.append({
            "question_id": _get_field(entry, "question_id"),
            "answer": _get_field(entry, "answer"),
            "justification": _get_field(entry, "justification"),
        })
    return out


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def enrich_project(project: Any) -> list[dict[str, Any]]:
    """
    Produce the 22-entry enriched payload for a submitted project.

    Reads ``project.responses_json`` (the 13 user-provided answers),
    derives the classification categories and the baseline recommendation,
    and appends the 9 enriched entries to a COPY of the original list.
    The input project is not mutated.

    Raises ``ValueError`` when required fields are missing (e.g. Q1 is
    empty, or Q7 holds an unrecognised BU value). Raising here is
    intentional: the calling route catches it and rolls the submit back so
    the user sees an error rather than a half-populated export payload.
    """
    responses = _get_field(project, "responses_json") or []
    by_qid = _answers_by_qid(responses)

    # --- Pull the inputs we need for the derived fields ---------------------
    sap_name = _as_str(by_qid.get(_Q_AUTHORIZATION_PACKAGE_NAME))
    rtx_business = _as_str(by_qid.get(_Q_RTX_BUSINESS))
    info_answer = by_qid.get(_Q_INFORMATION_CLASSIFICATION)
    conn_answer = by_qid.get(_Q_CONNECTIVITY)

    if not sap_name:
        raise ValueError(
            "Enrichment failed: Q1 authorization_package_name is empty. "
            "Cannot build authorization_package_name_enriched."
        )

    if rtx_business not in BU_CODE_MAP:
        raise ValueError(
            f"Enrichment failed: Q7 rtx_business value "
            f"{rtx_business!r} is not in BU_CODE_MAP. "
            f"Expected one of {sorted(BU_CODE_MAP)}."
        )

    bu_code = BU_CODE_MAP[rtx_business]

    # --- Classify ------------------------------------------------------------
    info_category = _classify_information(info_answer)
    conn_category = _classify_connectivity(conn_answer)
    baseline = _compute_baseline(info_category, conn_category)
    enriched_name = _build_enriched_name(
        bu_code=bu_code,
        cmmc_category=info_category,
        connectivity_category=conn_category,
        sap_name=sap_name,
    )

    project_id = _get_field(project, "id", "<unknown>")
    log.info(
        "Enriching project %s: info_category=%s, conn_category=%s, "
        "baseline=%s, enriched_name=%s",
        project_id, info_category, conn_category, baseline, enriched_name,
    )

    # --- Build the enriched list --------------------------------------------
    enriched_list: list[dict[str, Any]] = _original_entries_as_dicts(responses)

    # 7 static entries + 2 derived entries, in the spec order.
    enriched_list.append(_make_entry("package_type", "Information System"))
    enriched_list.append(_make_entry("baseline_recommendation", baseline))
    enriched_list.append(_make_entry("control_set_version_number", "NIST 800-171"))
    enriched_list.append(_make_entry("methodology", "NIST RMF"))
    enriched_list.append(_make_entry("authorization_package_source", "Clarity"))
    enriched_list.append(_make_entry("acronym", ""))  # "Leave Blank" -> ""
    enriched_list.append(_make_entry("lock_clara_id", "Local Clara ID"))  # static per spec
    enriched_list.append(_make_entry("in_continuous_monitoring", ""))  # "Leave Blank" -> ""
    enriched_list.append(_make_entry("authorization_package_name_enriched", enriched_name))

    return enriched_list
