"""
Archer Export Routes

FastAPI routes for generating Archer-consumable JSON payloads
from questionnaire responses stored in Postgres.

Endpoints:
    GET  /projects/{project_id}/archer-payload
         → Returns the Archer JSON payload for the given project

    POST /projects/{project_id}/archer-payload/export
         → Generates and returns the payload (same as GET but POST for
           clients that prefer it)
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session

from ..core.settings import ClaritySettings
from ..db.session import get_session
from ..services.archer_export_service import (
    ArcherExportConfig,
    generate_archer_payload_for_project,
)

log = logging.getLogger(__name__)

router = APIRouter(prefix="/projects", tags=["archer-export"])


# ---------------------------------------------------------------------------
# Response Models
# ---------------------------------------------------------------------------

class ArcherPayloadResponse(BaseModel):
    """Response wrapper for the Archer payload."""
    success: bool
    project_id: str
    payload: dict | None = None
    error: str | None = None


class ArcherExportConfigRequest(BaseModel):
    """Optional override for Archer export configuration."""
    module_name: str | None = None
    module_id: str | None = None
    level_id: str | None = None
    instance_name: str | None = None


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _get_export_config(
    settings: ClaritySettings,
    overrides: ArcherExportConfigRequest | None = None,
) -> ArcherExportConfig:
    """Build ArcherExportConfig from settings + optional overrides."""
    config = ArcherExportConfig(
        module_name=getattr(settings, "archer_module_name", "IRAMP_ATO"),
        module_id=getattr(settings, "archer_module_id", ""),
        level_id=getattr(settings, "archer_level_id", ""),
        instance_name=getattr(settings, "archer_instance_name", ""),
    )

    if overrides:
        if overrides.module_name:
            config.module_name = overrides.module_name
        if overrides.module_id:
            config.module_id = overrides.module_id
        if overrides.level_id:
            config.level_id = overrides.level_id
        if overrides.instance_name:
            config.instance_name = overrides.instance_name

    return config


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get(
    "/{project_id}/archer-payload",
    response_model=ArcherPayloadResponse,
    summary="Get Archer payload for a project",
    description=(
        "Reads questionnaire responses for the given project from Postgres "
        "and generates a JSON payload consumable by RSA Archer GRC. "
        "The payload maps Clarity question IDs to Archer field names."
    ),
)
async def get_archer_payload(
    project_id: str,
    session: Session = Depends(get_session),
):
    """Generate and return the Archer JSON payload for a project."""
    settings = ClaritySettings()
    config = _get_export_config(settings)

    payload = generate_archer_payload_for_project(session, project_id, config)

    if payload is None:
        raise HTTPException(
            status_code=404,
            detail=f"Project {project_id} not found",
        )

    return ArcherPayloadResponse(
        success=True,
        project_id=project_id,
        payload=payload,
    )


@router.post(
    "/{project_id}/archer-payload/export",
    response_model=ArcherPayloadResponse,
    summary="Export Archer payload with custom config",
    description=(
        "Same as GET but accepts optional Archer configuration overrides "
        "for module ID, level ID, etc."
    ),
)
async def export_archer_payload(
    project_id: str,
    config_request: ArcherExportConfigRequest | None = None,
    session: Session = Depends(get_session),
):
    """Generate Archer payload with optional config overrides."""
    settings = ClaritySettings()
    config = _get_export_config(settings, config_request)

    payload = generate_archer_payload_for_project(session, project_id, config)

    if payload is None:
        raise HTTPException(
            status_code=404,
            detail=f"Project {project_id} not found",
        )

    return ArcherPayloadResponse(
        success=True,
        project_id=project_id,
        payload=payload,
    )
