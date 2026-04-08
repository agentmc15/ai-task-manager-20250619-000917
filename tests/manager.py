"""
Database manager — engine, session factory, table creation, seeding.

Uses SQLAlchemy connection pooling for safe concurrent access.
Each FastAPI request gets its own session via the get_session dependency.
"""

import json
import logging
import os
from pathlib import Path

from sqlalchemy import create_engine, text, MetaData
from sqlmodel import SQLModel, Session

from ..core.settings import ClaritySettings
from ..models.questionnaire import (
    Questionnaire,
    QuestionnairePhase,
    Question,
    FlowEdge,
)

log = logging.getLogger(__name__)

# ----------------------------------------------------------------------
# Engine (connection pool)
# ----------------------------------------------------------------------

_settings = ClaritySettings()

_connection_string = (
    f"postgresql://{_settings.sql_username}:{_settings.sql_password}"
    f"@{_settings.sql_host}:{_settings.sql_port}/{_settings.sql_db_name}"
)

engine = create_engine(
    _connection_string,
    pool_size=5,           # Max persistent connections
    max_overflow=10,       # Extra connections under load
    pool_pre_ping=True,    # Test connections before use (handles DB restarts)
    pool_recycle=300,      # Recycle connections every 5 min
    echo=False,
)


# ----------------------------------------------------------------------
# Session dependency — one session per request
# ----------------------------------------------------------------------

def get_session():
    """
    FastAPI dependency that yields a database session.

    Each request gets its own session. The session is committed
    or rolled back when the request completes.

    Usage:
        @router.get("/")
        def my_route(session: Session = Depends(get_session)):
            ...
    """
    with Session(engine) as session:
        try:
            yield session
        except Exception:
            session.rollback()
            raise


# ----------------------------------------------------------------------
# Table initialization
# ----------------------------------------------------------------------

def init_sql_tables(eng):
    """Create all SQLModel tables if they don't exist."""
    # Try to reflect Keycloak's user_entity table (optional)
    metadata = MetaData()
    try:
        metadata.reflect(bind=eng, only=["user_entity"])
        if "user_entity" in metadata.tables:
            SQLModel.metadata._add_table(
                "user_entity", metadata.schema, metadata.tables["user_entity"]
            )
    except Exception:
        log.info("user_entity table not found (Keycloak may not be initialized)")

    SQLModel.metadata.create_all(eng, checkfirst=True)
    log.info("Database tables initialized")

    # Ensure owner_email column exists on project table
    _ensure_owner_email(eng)

    # Ensure archer tracking columns exist on project table
    _ensure_archer_columns(eng)


def _ensure_owner_email(eng):
    """Add owner_email column to project table if it doesn't exist."""
    with eng.connect() as conn:
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'project' AND column_name = 'owner_email'
        """))
        if not result.fetchone():
            log.info("Adding owner_email column to project table...")
            conn.execute(text(
                "ALTER TABLE project ADD COLUMN owner_email VARCHAR(255)"
            ))
            conn.execute(text(
                "UPDATE project SET owner_email = 'dev@clarity.local' WHERE owner_email IS NULL"
            ))
            conn.commit()
            log.info("owner_email column added and backfilled")


def _ensure_archer_columns(eng):
    """Add archer_submitted_at and archer_content_id columns to project table if they don't exist."""
    with eng.connect() as conn:
        # archer_submitted_at
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'project' AND column_name = 'archer_submitted_at'
        """))
        if not result.fetchone():
            log.info("Adding archer_submitted_at column to project table...")
            conn.execute(text(
                "ALTER TABLE project ADD COLUMN archer_submitted_at TIMESTAMP"
            ))
            conn.commit()
            log.info("archer_submitted_at column added")

        # archer_content_id
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'project' AND column_name = 'archer_content_id'
        """))
        if not result.fetchone():
            log.info("Adding archer_content_id column to project table...")
            conn.execute(text(
                "ALTER TABLE project ADD COLUMN archer_content_id VARCHAR(50)"
            ))
            conn.commit()
            log.info("archer_content_id column added")


# ----------------------------------------------------------------------
# Seed data
# ----------------------------------------------------------------------

# Map seed JSON types to backend QuestionType enum values
QUESTION_TYPE_MAP = {
    "Text": "text",
    "text": "text",
    "MultiChoice - single select": "choose-one",
    "choose-one": "choose-one",
    "MultiChoice - multiple select": "choose-many",
    "choose-many": "choose-many",
    "yes-no": "choose-one",
    "key-value-table": "key-value-table",
}


async def seed_data(eng):
    """Seed the questionnaire data from seed/data.json if no questionnaire exists."""
    with Session(eng) as session:
        existing = session.query(Questionnaire).first()
        if existing:
            log.info("Questionnaire already exists (id=%s) - skipping seed", existing.id)
            return

        seed_path = Path(__file__).parent.parent.parent.parent / "seed" / "data.json"
        if not seed_path.exists():
            log.warning("Seed file not found: %s", seed_path)
            return

        with open(seed_path) as f:
            raw = json.load(f)

        # Navigate to the questionnaire data (handle nested structures)
        q_data = raw.get("questionnaire", raw)
        phases_raw = q_data.get("phases_json", q_data.get("phases", []))

        if not phases_raw:
            log.warning("No phases found in seed data")
            return

        # Normalize question types
        for phase in phases_raw:
            questions = phase.get("questions", phase.get("nodes", []))
            for q in questions:
                raw_type = q.get("type", "text")
                q["type"] = QUESTION_TYPE_MAP.get(raw_type, raw_type)

                # Normalize options
                opts = q.get("options")
                if isinstance(opts, str):
                    if opts.lower() == "none":
                        q["options"] = None
                    else:
                        q["options"] = [o.strip() for o in opts.split(",")]

                # Handle yes-no → choose-one with Yes/No options
                if raw_type == "yes-no" and not q.get("options"):
                    q["options"] = ["Yes", "No"]

        version = q_data.get("version", "1.0")

        with Session(eng) as session:
            questionnaire = Questionnaire(
                version=version,
                active=True,
                phases_json=phases_raw,
            )
            session.add(questionnaire)
            session.commit()
            session.refresh(questionnaire)
            log.info(
                "Seeded questionnaire id=%s version=%s (%d phases)",
                questionnaire.id, version, len(phases_raw),
            )
