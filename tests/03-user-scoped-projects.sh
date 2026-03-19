#!/usr/bin/env bash
set -euo pipefail
#
# Script 3: User-Scoped Projects
# Adds owner_email column to projects table, updates routes to filter by user.
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Add owner_email to the Project model ==="

# We need to patch questionnaire.py to add owner_email to the Project class.
# This script creates a helper migration script since you may not have Alembic set up.

cat > backend/src/clarity/db/add_owner_email.py << 'MIGEOF'
"""
One-time migration: Add owner_email column to the project table.

Run once:
    cd backend
    python -m src.clarity.db.add_owner_email

This adds the column and backfills existing rows with 'dev@clarity.local'.
"""

from sqlalchemy import text
from .manager import engine


def migrate():
    with engine.connect() as conn:
        # Check if column already exists
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'project' AND column_name = 'owner_email'
        """))
        if result.fetchone():
            print("Column 'owner_email' already exists — skipping.")
            return

        print("Adding 'owner_email' column to 'project' table...")
        conn.execute(text(
            "ALTER TABLE project ADD COLUMN owner_email VARCHAR(255)"
        ))

        print("Backfilling existing rows with 'dev@clarity.local'...")
        conn.execute(text(
            "UPDATE project SET owner_email = 'dev@clarity.local' WHERE owner_email IS NULL"
        ))

        conn.commit()
        print("Migration complete.")


if __name__ == "__main__":
    migrate()
MIGEOF

echo "  Created backend/src/clarity/db/add_owner_email.py"

echo ""
echo "=== Step 2: Update Project model in questionnaire.py ==="

# We'll create a patch file that adds owner_email to the Project model.
# Since the exact file varies, here's what needs to change:

cat > backend/src/clarity/models/_patch_instructions.md << 'PATCHEOF'
# Patch: Add owner_email to Project model

Open `backend/src/clarity/models/questionnaire.py` and find the `Project` class.

Add this field AFTER the `user_id` field (or anywhere in the class body):

```python
    owner_email: str | None = sqlm.Field(default=None, max_length=255)
```

The full Project class should look like:

```python
class Project(SQLModel, table=True):
    id: str = sqlm.Field(default_factory=lambda: str(uuid4()), primary_key=True)
    title: str = sqlm.Field(unique=True)
    description: str = sqlm.Field(max_length=5000)
    tags: list[str] = sqlm.Field(default_factory=list, sa_column=Column(JSONB))
    user_id: str = sqlm.Field(foreign_key="user_entity.id")
    owner_email: str | None = sqlm.Field(default=None, max_length=255)
    questionnaire_id: int = sqlm.Field(foreign_key="questionnaire.id")
    # ... rest unchanged ...
```

Note: We keep `user_id` for backward compat but `owner_email` is what
the auth system uses going forward.
PATCHEOF

echo "  Created patch instructions at backend/src/clarity/models/_patch_instructions.md"

echo ""
echo "=== Step 3: Update project_routes.py with user-scoped endpoints ==="

cat > backend/src/clarity/routes/project_routes.py << 'ROUTESEOF'
"""Project CRUD routes — user-scoped via auth dependency."""

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.attributes import flag_modified

from ..core.auth import CurrentUser, get_current_user
from ..db.manager import get_session
from ..models.questionnaire import Attribute, Project, Questionnaire
from ..schemas.project_schema import (
    CreateProjectRequest,
    UpdateProjectRequest,
    AssignAttributesRequest,
    ProjectResponse,
)
from ..schemas.questionnaire_schema import (
    CreateQuestionResponseRequest,
    QuestionResponseResponse,
)

project_router = APIRouter(prefix="/project", tags=["Projects"])


# ---------------------------------------------------------------------------
# CREATE
# ---------------------------------------------------------------------------

@project_router.post("/", response_model=ProjectResponse)
async def create_project(
    body: CreateProjectRequest,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """Create a new project, automatically scoped to the authenticated user."""
    # Check questionnaire exists
    q = session.get(Questionnaire, body.questionnaire_id)
    if not q:
        raise HTTPException(status_code=404, detail="Questionnaire not found")

    project_data = body.model_dump()
    project_data["attributes"] = [
        Attribute(**a.model_dump()) for a in body.attributes
    ] if body.attributes else []

    # Inject owner from auth context
    project_data["owner_email"] = user.email

    new_project = Project(**project_data)
    session.add(new_project)
    session.commit()
    session.refresh(new_project)
    return new_project


# ---------------------------------------------------------------------------
# READ — user only sees their own projects
# ---------------------------------------------------------------------------

@project_router.get("/", response_model=list[ProjectResponse])
async def list_projects(
    project_id: str | None = None,
    title: str | None = None,
    include_questionnaire: bool = False,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """List projects belonging to the authenticated user."""
    statement = select(Project).where(Project.owner_email == user.email)

    if project_id:
        statement = statement.where(Project.id == project_id)
    if title:
        statement = statement.where(Project.title == title)
    if include_questionnaire:
        statement = statement.options(selectinload(Project.questionnaire))

    projects = session.exec(statement).all()
    return projects


@project_router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(
    project_id: str,
    include_questionnaire: bool = False,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """Get a specific project (must belong to authenticated user)."""
    statement = select(Project).where(
        Project.id == project_id,
        Project.owner_email == user.email,
    )
    if include_questionnaire:
        statement = statement.options(selectinload(Project.questionnaire))

    project = session.exec(statement).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")
    return project


# ---------------------------------------------------------------------------
# UPDATE
# ---------------------------------------------------------------------------

@project_router.put("/", response_model=ProjectResponse)
async def update_project(
    body: UpdateProjectRequest,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """Update a project (must belong to authenticated user)."""
    project = session.exec(
        select(Project).where(
            Project.id == body.project_id,
            Project.owner_email == user.email,
        )
    ).first()

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    update_data = body.model_dump(exclude_unset=True, exclude={"project_id"})
    for key, val in update_data.items():
        setattr(project, key, val)

    session.add(project)
    session.commit()
    session.refresh(project)
    return project


# ---------------------------------------------------------------------------
# DELETE
# ---------------------------------------------------------------------------

@project_router.delete("/")
async def delete_projects(
    project_id: str | None = None,
    title: str | None = None,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """Delete project(s) belonging to the authenticated user."""
    if not project_id and not title:
        raise HTTPException(
            status_code=400,
            detail="Provide project_id or title to delete",
        )

    statement = select(Project).where(Project.owner_email == user.email)
    if project_id:
        statement = statement.where(Project.id == project_id)
    if title:
        statement = statement.where(Project.title == title)

    projects = session.exec(statement).all()
    if not projects:
        raise HTTPException(status_code=404, detail="No matching projects found")

    for p in projects:
        session.delete(p)
    session.commit()

    return {"deleted": len(projects)}


# ---------------------------------------------------------------------------
# ANSWER UPSERT — save/update a question response
# ---------------------------------------------------------------------------

@project_router.post("/answer/create", response_model=QuestionResponseResponse)
async def upsert_answer(
    body: CreateQuestionResponseRequest,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """Save or update an answer for a question within a project."""
    # Verify ownership
    project = session.exec(
        select(Project).where(
            Project.id == body.project_id,
            Project.owner_email == user.email,
        )
    ).first()

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    # Upsert the response
    responses = list(project.responses_json or [])
    existing_idx = next(
        (i for i, r in enumerate(responses) if r.get("question_id") == body.question_id),
        None,
    )

    response_data = {
        "question_id": body.question_id,
        "answer": body.answer,
        "justification": body.justification,
    }

    if existing_idx is not None:
        responses[existing_idx] = response_data
    else:
        responses.append(response_data)

    project.responses_json = responses
    flag_modified(project, "responses_json")
    session.add(project)
    session.commit()
    session.refresh(project)

    return QuestionResponseResponse(
        project_id=project.id,
        question_id=body.question_id,
        answer=body.answer,
        justification=body.justification,
    )


# ---------------------------------------------------------------------------
# ATTRIBUTES
# ---------------------------------------------------------------------------

@project_router.post("/attributes", response_model=ProjectResponse)
async def assign_attributes(
    body: AssignAttributesRequest,
    user: CurrentUser = Depends(get_current_user()),
    session: Session = Depends(get_session),
):
    """Assign attributes to a project."""
    project = session.exec(
        select(Project).where(
            Project.id == body.project_id,
            Project.owner_email == user.email,
        )
    ).first()

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    new_attrs = [Attribute(text=a.text) for a in body.attributes]
    project.attributes = new_attrs
    session.add(project)
    session.commit()
    session.refresh(project)
    return project
ROUTESEOF

echo "  Updated backend/src/clarity/routes/project_routes.py"

echo ""
echo "=== Step 4: Update project_services.py (simplified — logic moved to routes) ==="

cat > backend/src/clarity/services/project_services.py << 'SVCEOF'
"""
Project services — utility functions.

Most CRUD logic has been moved directly into project_routes.py
for clarity. This file retains helpers that may be useful for
non-route contexts (e.g., background tasks, CLI scripts).
"""

from sqlmodel import Session, select
from ..models.questionnaire import Project


def get_projects_by_owner(session: Session, owner_email: str) -> list[Project]:
    """Get all projects for a given owner email."""
    return list(session.exec(
        select(Project).where(Project.owner_email == owner_email)
    ).all())


def transfer_project_ownership(
    session: Session,
    project_id: str,
    new_owner_email: str,
) -> Project | None:
    """Transfer project ownership to a different user."""
    project = session.get(Project, project_id)
    if project:
        project.owner_email = new_owner_email
        session.add(project)
        session.commit()
        session.refresh(project)
    return project
SVCEOF

echo "  Updated backend/src/clarity/services/project_services.py"

echo ""
echo "=== Done ==="
echo ""
echo "Steps to apply:"
echo "  1. Manually add 'owner_email' field to Project model in questionnaire.py"
echo "     (see backend/src/clarity/models/_patch_instructions.md)"
echo ""
echo "  2. Run the migration (with backend venv active + Postgres running):"
echo "     cd backend"
echo "     python -m src.clarity.db.add_owner_email"
echo ""
echo "  3. Restart uvicorn — project routes now filter by authenticated user's email"
echo ""
echo "  In dev mode (AUTH_MODE=dev), all projects are owned by 'dev@clarity.local'."
echo "  In keycloak mode, each user only sees projects where owner_email matches"
echo "  the email claim in their JWT."
