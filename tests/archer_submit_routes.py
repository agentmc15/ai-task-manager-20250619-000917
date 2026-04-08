"""
Archer Submit Routes

Single endpoint that ties together:
1. Loading project questionnaire responses from Postgres
2. Generating the Archer JSON payload via archer_export_service
3. Publishing to Archer via archer_publisher_service
4. Marking the project as submitted (one-way for MVP)

Endpoint:
    POST /project/{project_id}/submit-to-archer
        → Runs the full submission flow and returns the result

This is called by the frontend's "Submit for Review" button.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from ..core.auth import CurrentUser, get_current_user
from ..core.settings import ClaritySettings
from ..db.manager import get_session
from ..models.questionnaire import Project
from ..services.archer_export_service import (
    ArcherExportConfig,
    generate_archer_payload_for_project,
)
from ..services.archer_publisher_service import (
    ALL_STEPS,
    STEP_LABELS,
    STEP_SAVE,
    STEP_GENERATE,
    build_publisher_from_settings,
)

log = logging.getLogger(__name__)

router = APIRouter(prefix="/project", tags=["archer-submit"])


class SubmitToArcherResponse(BaseModel):
    """Response for submit-to-archer endpoint."""
    success: bool
    dry_run: bool
    project_id: str
    auth_package_content_id: str | None = None
    hardware_content_ids: list[str] = []
    steps_completed: list[str] = []
    all_steps: list[dict] = []
    errors: list[str] = []
    warnings: list[str] = []
    submitted_at: str | None = None


@router.post(
    "/{project_id}/submit-to-archer",
    response_model=SubmitToArcherResponse,
    summary="Submit a project's questionnaire to Archer",
    description=(
        "Runs the full submission pipeline: loads responses from Postgres, "
        "generates the Archer payload, publishes to Archer via REST API, "
        "and marks the project as submitted. If CLARITY_ARCHER_PUBLISH_ENABLED "
        "is false, runs in dry-run mode and logs the payload without calling Archer."
    ),
)
async def submit_to_archer(
    project_id: str,
    user: CurrentUser = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Submit a project to Archer (full pipeline)."""
    settings = ClaritySettings()

    # Verify ownership
    project = session.exec(
        select(Project).where(
            Project.id == project_id,
            Project.owner_email == user.email,
        )
    ).first()

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    # Prevent re-submission (one-way for MVP)
    if getattr(project, "archer_submitted_at", None):
        raise HTTPException(
            status_code=409,
            detail=(
                f"Project already submitted to Archer at {project.archer_submitted_at}"
                f" (content ID: {project.archer_content_id})"
            ),
        )

    steps_completed = [STEP_SAVE]  # responses are already saved by this point

    # Step 1: Generate the Archer payload
    export_config = ArcherExportConfig(
        module_name=getattr(settings, "archer_auth_package_module", "IRAMP_ATO"),
        module_id=getattr(settings, "archer_module_id", ""),
        level_id=getattr(settings, "archer_level_id", ""),
        instance_name=getattr(settings, "archer_instance", ""),
    )

    payload = generate_archer_payload_for_project(session, project_id, export_config)
    if payload is None:
        raise HTTPException(
            status_code=500,
            detail="Failed to generate Archer payload",
        )
    steps_completed.append(STEP_GENERATE)

    # Step 2: Publish to Archer (or dry-run)
    publisher = build_publisher_from_settings(settings)

    def on_progress(step_name: str) -> None:
        log.info("Archer publish step: %s", step_name)

    publish_result = await publisher.publish(
        payload,
        progress_callback=on_progress,
    )

    # Merge steps_completed from both phases
    steps_completed.extend(publish_result.steps_completed)

    # Step 3: Mark project as submitted if successful
    submitted_at_str: str | None = None
    if publish_result.success and not publish_result.dry_run:
        submitted_at = datetime.now(timezone.utc)
        project.archer_submitted_at = submitted_at
        project.archer_content_id = publish_result.auth_package_content_id
        session.add(project)
        session.commit()
        session.refresh(project)
        submitted_at_str = submitted_at.isoformat()
        log.info(
            "Project %s submitted to Archer with content ID %s",
            project_id,
            publish_result.auth_package_content_id,
        )

    # Build the all_steps list for the UI (labels + completion status)
    all_steps = [
        {
            "name": step_name,
            "label": STEP_LABELS.get(step_name, step_name),
            "completed": step_name in steps_completed,
        }
        for step_name in ALL_STEPS
    ]

    return SubmitToArcherResponse(
        success=publish_result.success,
        dry_run=publish_result.dry_run,
        project_id=project_id,
        auth_package_content_id=publish_result.auth_package_content_id,
        hardware_content_ids=publish_result.hardware_content_ids,
        steps_completed=steps_completed,
        all_steps=all_steps,
        errors=publish_result.errors,
        warnings=publish_result.warnings,
        submitted_at=submitted_at_str,
    )
