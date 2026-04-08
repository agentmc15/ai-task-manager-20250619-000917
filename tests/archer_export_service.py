"""
Archer Export Service

Reads questionnaire responses for a given project from Postgres
and generates a JSON payload consumable by RSA Archer GRC.

The JSON output maps Clarity questionnaire question IDs to Archer
field names based on the original C# ArcherCSharp integration.

Another developer will take this JSON payload and handle the actual
Archer API submission (login, content record creation, workflow transitions).
"""

import json
import logging
from datetime import datetime
from typing import Any, Optional

from sqlmodel import Session, select

from ..models.questionnaire import (
    Project,
    Questionnaire,
    QuestionResponse,
)

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Archer Field Mapping
# ---------------------------------------------------------------------------
# Maps Clarity questionnaire question IDs → Archer field names.
# Based on the original C# ArcherCSharp integration classes:
#   - ArcherIntegration (hardware/system info)
#   - archerSecurity (auth package metadata)
#   - archerNetworks (connectivity)
#   - archerHardware (hardware inventory)
#
# The Archer module ID and level ID are configurable via environment
# variables since they differ per Archer instance.
# ---------------------------------------------------------------------------

QUESTION_TO_ARCHER_FIELD = {
    # --- General / Information System Details ---
    "authorization_package_name": {
        "archer_field": "AUTHORIZATION_PACKAGE_NAME",
        "archer_type": "text",       # Archer field type 1
        "section": "general",
    },
    "clara_id": {
        "archer_field": "CLARA_ID",
        "archer_type": "text",
        "section": "general",
    },
    "entity": {
        "archer_field": "ENTITY",
        "archer_type": "values_list",  # Archer field type 4
        "section": "general",
        "values_map": {
            "No Selection": None,
            "Advanced Concepts and Technology (MIST)": "Advanced Concepts and Technology (MIST)",
            "Advanced Missile System (CMA)": "Advanced Missile System (CMA)",
        },
    },
    "rtx_business": {
        "archer_field": "BUSINESS",
        "archer_type": "values_list",
        "section": "general",
        "values_map": {
            "Collins Aerospace": "Collins Aerospace",
            "Pratt & Whitney": "Pratt & Whitney",
            "Raytheon": "Raytheon",
        },
    },
    "mission_purpose": {
        "archer_field": "MISSION_PURPOSE",
        "archer_type": "text",
        "section": "general",
    },
    "information_classification": {
        "archer_field": "INFORMATION_CLASSIFICATION",
        "archer_type": "values_list_multi",  # Archer field type 4 (multi-select)
        "section": "information_system_details",
        "values_map": {
            "CUI/CDI (DFARS)": "CUI/CDI (DFARS)",
            "Competitive Sensitive": "Competitive Sensitive",
            "CUI (non-CDI)": "CUI (non-CDI)",
            "ITAR (ITAR, EAR)": "ITAR (ITAR, EAR)",
            "Internal Use Only": "Internal Use Only",
            "Not Privy": "Not Privy",
            "Personal Information (PI)": "Personal Information (PI)",
            "Proprietary": "Proprietary",
            "Public": "Public",
            "Unclassified/Identity": "Unclassified/Identity",
        },
    },
    "connectivity": {
        "archer_field": "CONNECTIVITY",
        "archer_type": "values_list_multi",
        "section": "information_system_details",
        "values_map": {
            "Global - IONIN": "Global - IONIN",
            "Extranet/Interconnected System - Contractor-to-Government (C2G)": "Extranet/Interconnected System - Contractor-to-Government (C2G)",
            "Internal Only": "Internal Only",
            "Classified": "Classified",
            "Lab/dev/test": "Lab/dev/test",
            "Network Segregated": "Network Segregated",
            "Networked - Internal within ORIEN": "Networked - Internal within ORIEN",
            "Other - Zscaler-owned/managed Government Cloud": "Other - Zscaler-owned/managed Government Cloud",
            "Proxy/Scanner": "Proxy/Scanner",
            "Public": "Public",
            "Standalone": "Standalone",
            "Stand-alone": "Stand-alone",
        },
    },
    "authorization_boundary_description": {
        "archer_field": "AUTHORIZATION_BOUNDARY_DESCRIPTION",
        "archer_type": "text",
        "section": "information_system_details",
    },

    # --- Personnel ---
    "system_administrator_id": {
        "archer_field": "SYSTEM_ADMINISTRATOR_ID",
        "archer_type": "text",
        "section": "personnel",
    },

    # --- Hardware (KV Table) ---
    "hardware_entry": {
        "archer_field": "HARDWARE_INVENTORY",
        "archer_type": "sub_record_table",
        "section": "information_system_details",
        "column_mapping": {
            "hardware_name": "HARDWARE_NAME",
            "ip_address": "IP_ADDRESS",
            "hardware_type": "HARDWARE_TYPE",
            "business": "BUSINESS_UNIT",
            "mac_address": "MAC_ADDRESS",
        },
    },
}


# ---------------------------------------------------------------------------
# Archer Export Configuration (from environment / settings)
# ---------------------------------------------------------------------------

class ArcherExportConfig:
    """
    Configuration for Archer export.
    These values should come from environment variables or ClaritySettings.
    Defaults are placeholders that must be updated per Archer instance.
    """

    def __init__(
        self,
        module_name: str = "IRAMP_ATO",
        module_id: str = "",
        level_id: str = "",
        instance_name: str = "",
    ):
        self.module_name = module_name
        self.module_id = module_id
        self.level_id = level_id
        self.instance_name = instance_name


# ---------------------------------------------------------------------------
# Payload Builder
# ---------------------------------------------------------------------------

def _build_text_field(archer_field: str, value: Any) -> dict:
    """Build a text field entry for the Archer payload."""
    return {
        "field_name": archer_field,
        "field_type": "text",
        "value": str(value) if value is not None else "",
    }


def _build_values_list_field(
    archer_field: str,
    value: Any,
    values_map: dict,
    multi: bool = False,
) -> dict:
    """Build a values-list field entry for the Archer payload."""
    if multi:
        # value is a list of selected options
        selected = value if isinstance(value, list) else [value]
        mapped = []
        for v in selected:
            mapped_val = values_map.get(v, v)
            if mapped_val is not None:
                mapped.append(mapped_val)
        return {
            "field_name": archer_field,
            "field_type": "values_list",
            "multi_select": True,
            "values": mapped,
        }
    else:
        # value is a single selection
        mapped_val = values_map.get(value, value) if values_map else value
        return {
            "field_name": archer_field,
            "field_type": "values_list",
            "multi_select": False,
            "value": mapped_val,
        }


def _build_hardware_records(
    archer_field: str,
    entries: list[dict],
    column_mapping: dict,
) -> dict:
    """Build hardware sub-record entries for the Archer payload."""
    records = []
    for entry in entries:
        record = {}
        for clarity_col, archer_col in column_mapping.items():
            record[archer_col] = entry.get(clarity_col, "")
        records.append(record)

    return {
        "field_name": archer_field,
        "field_type": "sub_record",
        "records": records,
    }


def build_archer_payload(
    project: Project,
    responses: list[dict],
    config: ArcherExportConfig | None = None,
) -> dict:
    """
    Build the complete Archer-consumable JSON payload from project
    questionnaire responses.

    Args:
        project: The Project SQLModel instance
        responses: List of QuestionResponse dicts with question_id and answer
        config: Optional Archer export configuration

    Returns:
        dict: JSON-serializable payload for Archer consumption
    """
    if config is None:
        config = ArcherExportConfig()

    # Index responses by question_id for quick lookup
    response_map: dict[str, Any] = {}
    for resp in responses:
        qid = resp.get("question_id") or resp.get("questionId")
        answer = resp.get("answer") or resp.get("value")
        if qid:
            response_map[qid] = answer

    # Build field contents
    fields: list[dict] = []

    for question_id, mapping in QUESTION_TO_ARCHER_FIELD.items():
        answer = response_map.get(question_id)
        archer_field = mapping["archer_field"]
        archer_type = mapping["archer_type"]

        if archer_type == "text":
            fields.append(_build_text_field(archer_field, answer))

        elif archer_type == "values_list":
            fields.append(
                _build_values_list_field(
                    archer_field,
                    answer,
                    mapping.get("values_map", {}),
                    multi=False,
                )
            )

        elif archer_type == "values_list_multi":
            fields.append(
                _build_values_list_field(
                    archer_field,
                    answer,
                    mapping.get("values_map", {}),
                    multi=True,
                )
            )

        elif archer_type == "sub_record_table":
            # Hardware entries are stored as {rows: [[{col_id, value}, ...], ...]}
            entries = []
            raw_rows = []

            if answer:
                # Parse if it's a JSON string
                if isinstance(answer, str):
                    try:
                        answer = json.loads(answer)
                    except json.JSONDecodeError:
                        log.warning(
                            "Failed to parse hardware entries for project %s",
                            project.id,
                        )
                        answer = None

                # Extract rows from {rows: [...]} structure
                if isinstance(answer, dict) and "rows" in answer:
                    raw_rows = answer["rows"]
                elif isinstance(answer, list):
                    raw_rows = answer

            # Convert each row from [{col_id, value}, ...] to {col_id: value, ...}
            for row in raw_rows:
                if isinstance(row, list):
                    # Row is a list of {col_id, value} dicts
                    entry = {}
                    for cell in row:
                        if isinstance(cell, dict) and "col_id" in cell:
                            col_id = cell.get("col_id")
                            value = cell.get("value", "")
                            if col_id:
                                entry[col_id] = value
                    # Skip completely empty rows
                    if any(v for v in entry.values()):
                        entries.append(entry)
                elif isinstance(row, dict):
                    # Already a flat dict (for backward compat)
                    if any(v for v in row.values()):
                        entries.append(row)

            fields.append(
                _build_hardware_records(
                    archer_field,
                    entries,
                    mapping.get("column_mapping", {}),
                )
            )

    # Assemble the full payload
    payload = {
        "metadata": {
            "source": "clarity",
            "version": "1.0",
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "project_id": str(project.id),
            "project_title": project.title or "",
            "owner_email": project.owner_email or "",
            "archer_module": config.module_name,
            "archer_module_id": config.module_id,
            "archer_level_id": config.level_id,
            "archer_instance": config.instance_name,
        },
        "content": {
            "fields": fields,
        },
        # Group fields by section for readability
        "sections": _group_by_section(fields),
    }

    return payload


def _group_by_section(fields: list[dict]) -> dict:
    """Group fields by their Archer section for readability."""
    sections: dict[str, list] = {}

    for question_id, mapping in QUESTION_TO_ARCHER_FIELD.items():
        section = mapping.get("section", "other")
        if section not in sections:
            sections[section] = []

        # Find the corresponding built field
        for f in fields:
            if f.get("field_name") == mapping["archer_field"]:
                sections[section].append(f)
                break

    return sections


# ---------------------------------------------------------------------------
# Database Integration
# ---------------------------------------------------------------------------

def get_project_responses(session: Session, project_id: str) -> list[dict]:
    """
    Fetch questionnaire responses for a project from Postgres.

    Responses are stored on the Project model as a JSON field.
    Each response has: question_id, answer, submitted_at, justification
    """
    project = session.get(Project, project_id)
    if not project:
        log.error("Project not found: %s", project_id)
        return []

    # Project.responses is a JSON column storing list of QuestionnaireResponse
    responses = project.responses_json or []

    # If responses is a string (raw JSON), parse it
    if isinstance(responses, str):
        try:
            responses = json.loads(responses)
        except json.JSONDecodeError:
            log.error("Failed to parse responses for project %s", project_id)
            return []

    return responses


def generate_archer_payload_for_project(
    session: Session,
    project_id: str,
    config: ArcherExportConfig | None = None,
) -> dict | None:
    """
    Main entry point: generate the Archer JSON payload for a given project.

    Args:
        session: SQLModel database session
        project_id: The project ID to export
        config: Optional Archer export configuration

    Returns:
        dict: The Archer-consumable JSON payload, or None if project not found
    """
    project = session.get(Project, project_id)
    if not project:
        log.error("Project not found: %s", project_id)
        return None

    responses = get_project_responses(session, project_id)

    if not responses:
        log.warning("No responses found for project %s", project_id)

    payload = build_archer_payload(project, responses, config)

    log.info(
        "Generated Archer payload for project %s with %d fields",
        project_id,
        len(payload.get("content", {}).get("fields", [])),
    )

    return payload
