#!/usr/bin/env bash
# =============================================================================
# CLARITY REWRITE — Part 1: Backend + Infrastructure
# =============================================================================
# Copy-paste this entire script into Git Bash (Windows) or terminal (Linux).
# Creates all backend code, Docker configs, nginx, and seed data.
# After Part 1, run Part 2 for the frontend.
# =============================================================================
set -euo pipefail
P="clarity-rewrite"
echo "Creating Clarity backend + infrastructure..."

# Create directories
mkdir -p "$P"/{backend/src/clarity/{core,db,models/{rag,review},routes,schemas,services,templates,seed},backend/seed,nginx/conf.d,scripts,docs}

cat > "$P/.env.example" << '_CLARITY_EOF_'
# PostgreSQL
CLARITY_SQL_DB=clarity
CLARITY_SQL_USER=clarity
CLARITY_SQL_PASSWORD=clarity
CLARITY_SQL_HOST=localhost
CLARITY_SQL_PORT=5432

# Keycloak
CLARITY_KC_REALM=clarity
CLARITY_KC_ADMIN=admin
CLARITY_KC_ADMIN_PASSWORD=admin
CLARITY_KC_MGMT_CLIENT_SECRET=
COMP_OIDC_CLIENT_ID=clarity-app
COMP_OIDC_CLIENT_SECRET=

# OIDC Endpoints (set after Keycloak is configured)
CORP_OIDC_DISCOVERY_ENDPOINT=
CORP_OIDC_ISSUER=
CORP_OIDC_AUTHORIZATION_URL=
CORP_OIDC_TOKEN_URL=
CORP_OIDC_JWKS_URL=
CORP_OIDC_USER_INFO_URL=

# RTX Model Hub (placeholder)
META_OPENAI_URL=
META_OPENAI_URL_BASE=
META_OPENAI_KEY=

# Archer GRC
ARCHER_USERNAME=
ARCHER_PASSWORD=
ARCHER_INSTANCE_NAME=ArcherRTX PROD
ARCHER_BASE_URI=https://archergrc.corp.ray.com
ARCHER_SOAP_SEARCH_URI=
ARCHER_SOAP_GENERAL_URI=
MAPPING_REPORT=

# Seeding
SEED_DATA=true
SEED_RAG=false

# Frontend
NUXT_API_BASE=/api
NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=
NUXT_SESSION_PASSWORD=your-session-password-at-least-32-chars
_CLARITY_EOF_

cat > "$P/.gitignore" << '_CLARITY_EOF_'
# Python
__pycache__/
*.py[cod]
.venv/
*.egg-info/
dist/
build/

# Node
node_modules/
.nuxt/
.output/
.nitro/

# Environment
.env
*.env.local

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Docker
postgres_data/

# Generated
start-backend.bat
start-frontend.bat
start-backend.sh
start-frontend.sh
start-all.sh
_CLARITY_EOF_

cat > "$P/README.md" << '_CLARITY_EOF_'
# Clarity — IRAMP/ATO Management System

Questionnaire-driven security authorization workflow tool. Captures application risk posture and submits Authorization Packages to RSA Archer GRC.

## Quick Start — Windows (Local Dev)

```powershell
# 1. Start infra
docker compose up -d db keycloak

# 2. Start backend
cd backend
pip install -r requirements.txt
$env:SEED_DATA="true"
uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload

# 3. Start frontend
cd frontend
npm install
npm run dev    # http://localhost:3001
```

## Quick Start — Linux (Docker)

```bash
cp .env.example .env   # Edit with your values
docker compose up -d
```

See the master architecture document for full details.
_CLARITY_EOF_

cat > "$P/docker-compose.yaml" << '_CLARITY_EOF_'
# Local development docker-compose
# Usage: docker compose up -d
services:
  clarity-api:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: clarity-api
    environment:
      - CLARITY_SQL_DB=${CLARITY_SQL_DB:-clarity}
      - CLARITY_SQL_USER=${CLARITY_SQL_USER:-clarity}
      - CLARITY_SQL_PASSWORD=${CLARITY_SQL_PASSWORD:-clarity}
      - CLARITY_SQL_HOST=db
      - CLARITY_SQL_PORT=5432
      - CLARITY_KC_REALM=${CLARITY_KC_REALM:-clarity}
      - CLARITY_KC_MGMT_CLIENT_SECRET=${CLARITY_KC_MGMT_CLIENT_SECRET:-}
      - COMP_OIDC_CLIENT_ID=${COMP_OIDC_CLIENT_ID:-}
      - COMP_OIDC_CLIENT_SECRET=${COMP_OIDC_CLIENT_SECRET:-}
      - META_OPENAI_URL=${META_OPENAI_URL:-}
      - META_OPENAI_KEY=${META_OPENAI_KEY:-}
      - ARCHER_USERNAME=${ARCHER_USERNAME:-}
      - ARCHER_PASSWORD=${ARCHER_PASSWORD:-}
      - ARCHER_INSTANCE_NAME=${ARCHER_INSTANCE_NAME:-ArcherRTX PROD}
      - ARCHER_BASE_URI=${ARCHER_BASE_URI:-https://archergrc.corp.ray.com}
      - ARCHER_SOAP_SEARCH_URI=${ARCHER_SOAP_SEARCH_URI:-}
      - ARCHER_SOAP_GENERAL_URI=${ARCHER_SOAP_GENERAL_URI:-}
      - MAPPING_REPORT=${MAPPING_REPORT:-}
      - SEED_DATA=${SEED_DATA:-true}
    ports:
      - "4000:4000"
    depends_on:
      - db
      - keycloak
    networks:
      - clarity_network
    volumes:
      - ./backend:/app

  db:
    image: postgres:17
    container_name: clarity-db
    environment:
      POSTGRES_DB: ${CLARITY_SQL_DB:-clarity}
      POSTGRES_USER: ${CLARITY_SQL_USER:-clarity}
      POSTGRES_PASSWORD: ${CLARITY_SQL_PASSWORD:-clarity}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - clarity_network
    ports:
      - "5432:5432"

  keycloak:
    image: quay.io/keycloak/keycloak:26.2.1
    container_name: clarity-keycloak
    depends_on:
      - db
    environment:
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://db:5432/${CLARITY_SQL_DB:-clarity}
      - KC_DB_USERNAME=${CLARITY_SQL_USER:-clarity}
      - KC_DB_PASSWORD=${CLARITY_SQL_PASSWORD:-clarity}
      - KC_BOOTSTRAP_ADMIN_USERNAME=${CLARITY_KC_ADMIN:-admin}
      - KC_BOOTSTRAP_ADMIN_PASSWORD=${CLARITY_KC_ADMIN_PASSWORD:-admin}
      - JAVA_OPTS=-Xms512m -Xmx1024m
      - KC_HTTP_ENABLED=true
      - KC_HTTP_HOST=0.0.0.0
      - KC_HTTP_PORT=8080
      - KC_HTTP_RELATIVE_PATH=/kc
      - KC_PROXY_HEADERS=xforwarded
    command:
      - start-dev
    ports:
      - "8080:8080"
    networks:
      - clarity_network

networks:
  clarity_network:
    driver: bridge

volumes:
  postgres_data:
_CLARITY_EOF_

cat > "$P/docker-compose.production.yaml" << '_CLARITY_EOF_'
# Production docker-compose
services:
  clarity-api:
    image: art/clarity:production
    container_name: clarity-api
    environment:
      - CLARITY_SQL_DB=${CLARITY_SQL_DB}
      - CLARITY_SQL_USER=${CLARITY_SQL_USER}
      - CLARITY_SQL_PASSWORD=${CLARITY_SQL_PASSWORD}
      - CLARITY_SQL_HOST=${CLARITY_SQL_HOST}
      - CLARITY_SQL_PORT=${CLARITY_SQL_PORT}
      - CLARITY_KC_HOST=${CLARITY_KC_HOST}
      - CLARITY_KC_PORT=${CLARITY_KC_PORT}
      - CLARITY_KC_REALM=${CLARITY_KC_REALM}
      - CLARITY_KC_ADMIN=${CLARITY_KC_ADMIN}
      - CLARITY_KC_ADMIN_PASSWORD=${CLARITY_KC_ADMIN_PASSWORD}
      - COMP_OIDC_CLIENT_ID=${COMP_OIDC_CLIENT_ID}
      - COMP_OIDC_CLIENT_SECRET=${COMP_OIDC_CLIENT_SECRET}
      - CORP_OIDC_DISCOVERY_ENDPOINT=${CORP_OIDC_DISCOVERY_ENDPOINT}
      - CORP_OIDC_ISSUER=${CORP_OIDC_ISSUER}
      - CORP_OIDC_AUTHORIZATION_URL=${CORP_OIDC_AUTHORIZATION_URL}
      - CORP_OIDC_TOKEN_URL=${CORP_OIDC_TOKEN_URL}
      - CORP_OIDC_JWKS_URL=${CORP_OIDC_JWKS_URL}
      - CORP_OIDC_USER_INFO_URL=${CORP_OIDC_USER_INFO_URL}
      - META_OPENAI_URL_BASE=${META_OPENAI_URL_BASE}
      - META_OPENAI_URL=${META_OPENAI_URL}
      - META_OPENAI_KEY=${META_OPENAI_KEY}
      - ARCHER_USERNAME=${ARCHER_USERNAME}
      - ARCHER_PASSWORD=${ARCHER_PASSWORD}
      - ARCHER_INSTANCE_NAME=${ARCHER_INSTANCE_NAME}
      - ARCHER_BASE_URI=${ARCHER_BASE_URI}
      - ARCHER_SOAP_SEARCH_URI=${ARCHER_SOAP_SEARCH_URI}
      - ARCHER_SOAP_GENERAL_URI=${ARCHER_SOAP_GENERAL_URI}
      - MAPPING_REPORT=${MAPPING_REPORT}
      - SEED_DATA=${SEED_DATA}
    ports:
      - "4000:4000"
    depends_on:
      - db
      - keycloak
    networks:
      - clarity_network

  db:
    image: postgres:17
    container_name: clarity-db
    environment:
      POSTGRES_DB: ${CLARITY_SQL_DB}
      POSTGRES_USER: ${CLARITY_SQL_USER}
      POSTGRES_PASSWORD: ${CLARITY_SQL_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - clarity_network
    ports:
      - "5432:5432"

  keycloak:
    image: quay.io/keycloak/keycloak:26.2.1
    container_name: clarity-keycloak
    depends_on:
      - db
    environment:
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://${CLARITY_SQL_HOST}:${CLARITY_SQL_PORT}/${CLARITY_SQL_DB}
      - KC_DB_USERNAME=${CLARITY_SQL_USER}
      - KC_DB_PASSWORD=${CLARITY_SQL_PASSWORD}
      - KC_BOOTSTRAP_ADMIN_USERNAME=${CLARITY_KC_ADMIN}
      - KC_BOOTSTRAP_ADMIN_PASSWORD=${CLARITY_KC_ADMIN_PASSWORD}
      - JAVA_OPTS=-Xms512m -Xmx1024m
      - KC_HOSTNAME=${KC_HOSTNAME}
      - KC_PROFILE=${KC_PROFILE}
      - KC_HTTP_ENABLED=true
      - KC_HTTP_HOST=0.0.0.0
      - KC_HTTP_PORT=8080
      - KC_PROXY_HEADERS=xforwarded
      - KC_HTTP_RELATIVE_PATH=/kc
    command:
      - start
    ports:
      - "8080:8080"
    networks:
      - clarity_network

networks:
  clarity_network:
    driver: bridge

volumes:
  postgres_data:
_CLARITY_EOF_

cat > "$P/nginx/conf.d/clarity.conf" << '_CLARITY_EOF_'
server {
    listen 80;
    server_name clarity.onertx.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name clarity.onertx.com;

    error_log /var/log/nginx/error.log debug;

    ssl_certificate /etc/letsencrypt/live/clarity.onertx.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/clarity.onertx.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
_CLARITY_EOF_

cat > "$P/nginx/conf.d/keycloak.conf" << '_CLARITY_EOF_'
server {
    listen 443;
    server_name sso.clarity.onertx.com;

    ssl_certificate /etc/letsencrypt/live/clarity.onertx.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/clarity.onertx.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
    }
}
_CLARITY_EOF_

cat > "$P/nginx/conf.d/nuxt.conf" << '_CLARITY_EOF_'
server {
    listen 3000;
    server_name _;

    # Keycloak redirect
    location /kc {
        return 301 https://clarity.onertx.com/kc/;
    }

    # Proxy /kc/* to Keycloak
    location /kc/ {
        proxy_pass http://localhost:8080/kc/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Backend API redirect
    location /be {
        return 301 https://clarity.onertx.com/be/;
    }

    # Main API proxy - rewrites /be/* to /* before sending to FastAPI
    location /be/ {
        rewrite ^/be/(.*)$ /$1 break;
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Proxy everything else to Nuxt
    location / {
        proxy_pass http://localhost:3001/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cache_bypass $http_upgrade;
    }
}
_CLARITY_EOF_

cat > "$P/backend/Dockerfile" << '_CLARITY_EOF_'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 4000

CMD ["uvicorn", "src.clarity.api:api", "--host", "0.0.0.0", "--port", "4000", "--reload"]
_CLARITY_EOF_

cat > "$P/backend/requirements.txt" << '_CLARITY_EOF_'
fastapi==0.115.6
uvicorn[standard]==0.34.0
sqlmodel==0.0.22
sqlalchemy==2.0.36
psycopg2-binary==2.9.10
pydantic==2.10.3
pydantic-settings==2.7.0
httpx==0.28.1
python-jose[cryptography]==3.3.0
python-multipart==0.0.18
alembic==1.14.0
zeep==4.3.1
lxml==5.3.0
snowflake-connector-python==3.12.3
_CLARITY_EOF_

touch "$P/backend/src/__init__.py"

touch "$P/backend/src/clarity/__init__.py"

cat > "$P/backend/src/clarity/api.py" << '_CLARITY_EOF_'
"""FastAPI application entry point."""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routes.auth import auth_router
from .routes.questionnaire_routes import questionnaire_router
from .routes.completion_routes import completion_router
from .routes.project_routes import project_router
from .routes.review_routes import review_router
from .routes.archer_routes import archer_router
from .db.manager import (
    engine,
    init_sql_tables,
    seed_data,
    create_vector_extension,
)

import os


async def init_app_state(app: FastAPI):
    """Lifespan handler: init DB, seed data on startup."""
    create_vector_extension(engine)
    init_sql_tables(engine)
    # Seed questionnaire data if SEED_DATA=true
    if os.getenv("SEED_DATA", "false").lower() == "true":
        await seed_data(engine)
    yield


def build_api_instance() -> FastAPI:
    api = FastAPI(debug=True, title="Clarity API", lifespan=init_app_state)
    api.add_middleware(
        CORSMiddleware,
        allow_origins=[
            "http://localhost",
            "http://localhost:3000",
            "http://localhost:3001",
            "https://clarity.onertx.com",
        ],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    api.include_router(auth_router)
    api.include_router(questionnaire_router)
    api.include_router(completion_router)
    api.include_router(project_router)
    api.include_router(review_router)
    api.include_router(archer_router)
    return api


try:
    api = build_api_instance()
except Exception as e:
    raise Exception("Failed to start API") from e
_CLARITY_EOF_

touch "$P/backend/src/clarity/core/__init__.py"

cat > "$P/backend/src/clarity/core/message.py" << '_CLARITY_EOF_'
from pydantic import BaseModel


class Message(BaseModel):
    """A single message in a chat conversation."""
    role: str
    content: str
_CLARITY_EOF_

cat > "$P/backend/src/clarity/core/settings.py" << '_CLARITY_EOF_'
from pydantic_settings import BaseSettings
from pydantic import Field


class ClaritySettings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Keycloak SSO
    keycloak_realm: str = Field(alias="CLARITY_KC_REALM")
    keycloak_client_secret: str = Field(alias="CLARITY_KC_MGMT_CLIENT_SECRET", default="")
    oidc_client_id: str = Field(alias="COMP_OIDC_CLIENT_ID")
    oidc_client_secret: str = Field(alias="COMP_OIDC_CLIENT_SECRET", default="")

    # PostgreSQL
    sql_username: str = Field(alias="CLARITY_SQL_USER")
    sql_password: str = Field(alias="CLARITY_SQL_PASSWORD")
    sql_host: str = Field(alias="CLARITY_SQL_HOST")
    sql_port: int = Field(alias="CLARITY_SQL_PORT")
    sql_db_name: str = Field(alias="CLARITY_SQL_DB")

    # RTX Model Hub Gateway (placeholder)
    meta_openai_uri: str = Field(alias="META_OPENAI_URL", default="")
    meta_openai_key: str = Field(alias="META_OPENAI_KEY", default="")

    # Archer GRC
    archer_username: str = Field(alias="ARCHER_USERNAME", default="")
    archer_password: str = Field(alias="ARCHER_PASSWORD", default="")
    archer_instance_name: str = Field(alias="ARCHER_INSTANCE_NAME", default="")
    archer_base_uri: str = Field(alias="ARCHER_BASE_URI", default="")
    soap_search_uri: str = Field(alias="ARCHER_SOAP_SEARCH_URI", default="")
    soap_general_uri: str = Field(alias="ARCHER_SOAP_GENERAL_URI", default="")

    # Misc
    mapping_report: str = Field(alias="MAPPING_REPORT", default="")
_CLARITY_EOF_

touch "$P/backend/src/clarity/db/__init__.py"

cat > "$P/backend/src/clarity/db/manager.py" << '_CLARITY_EOF_'
from sqlmodel import SQLModel, Session, select
from sqlalchemy import Engine, create_engine, MetaData, text

from ..models.questionnaire import Questionnaire, QuestionnairePhase, Question, QUESTION_TYPE_MAP
from ..core.settings import ClaritySettings

import os
import json


def create_connection_string(settings: ClaritySettings | None = None) -> str:
    settings = settings or ClaritySettings()
    return (
        f"postgresql://{settings.sql_username}:{settings.sql_password}"
        f"@{settings.sql_host}:{settings.sql_port}/{settings.sql_db_name}"
    )


def init_sql_tables(engine: Engine):
    """Create all SQLModel tables and reflect Keycloak user_entity."""
    metadata = MetaData()
    try:
        metadata.reflect(bind=engine, only=["user_entity"])
        SQLModel.metadata.add_table(
            "user_entity", metadata.schema, metadata.tables["user_entity"]
        )
    except Exception:
        # user_entity may not exist yet if Keycloak hasn't started
        pass
    SQLModel.metadata.create_all(engine, checkfirst=True)


def get_session():
    """FastAPI dependency that yields a database session."""
    with Session(engine) as session:
        yield session


def normalize_question_type(raw_type: str) -> str:
    """Convert seed JSON question types to internal QuestionType enum values."""
    mapped = QUESTION_TYPE_MAP.get(raw_type)
    if mapped:
        return mapped.value
    return raw_type


def normalize_seed_data(raw: dict) -> dict:
    """Normalize the seed JSON to match internal model expectations."""
    content = raw.get("content", raw)
    phases = content.get("phases", [])

    normalized_phases = []
    for phase in phases:
        nodes = phase.get("nodes", [])
        normalized_nodes = []
        for node in nodes:
            node_copy = dict(node)
            # Normalize type
            node_copy["type"] = normalize_question_type(node_copy.get("type", "text"))
            # Normalize options
            opts = node_copy.get("options")
            if opts == "none" or opts == "None" or opts is None:
                node_copy["options"] = None
            elif isinstance(opts, str):
                node_copy["options"] = [opts] if opts else None
            normalized_nodes.append(node_copy)

        normalized_phases.append({
            "title": phase["title"],
            "description": phase.get("description"),
            "nodes": normalized_nodes,
            "edges": phase.get("edges", []),
        })

    return normalized_phases


async def seed_data(engine: Engine) -> None:
    """Seed the database with the questionnaire from seed/data.json."""
    try:
        import json

        data_path = os.path.join(os.path.dirname(__file__), "..", "seed", "data.json")
        with open(data_path, "r") as f:
            raw = json.load(f)

        phases_dicts = normalize_seed_data(raw)

        with Session(engine) as session:
            # Check if already seeded
            existing = session.exec(select(Questionnaire)).first()
            if existing:
                print("INFO:\tQuestionnaire already seeded, skipping.", flush=True)
                return

            questionnaire = Questionnaire(
                version=raw.get("version", "v1"),
                active=raw.get("active", True),
                phases_json=phases_dicts,
            )
            session.add(questionnaire)
            session.commit()
            print("INFO:\tSeeded questionnaire data.", flush=True)

    except Exception as e:
        raise e


async def seed_rag_documents(engine: Engine):
    """Placeholder for RAG document seeding."""
    print("INFO:\tRAG seeding is a placeholder - skipping.", flush=True)


# Create engine at module level
engine = create_engine(create_connection_string())
_CLARITY_EOF_

touch "$P/backend/src/clarity/models/__init__.py"

touch "$P/backend/src/clarity/models/rag/__init__.py"

touch "$P/backend/src/clarity/models/review/__init__.py"

cat > "$P/backend/src/clarity/models/questionnaire.py" << '_CLARITY_EOF_'
from datetime import datetime, timezone
from enum import Enum
from typing import Literal
from uuid import uuid4

import pydantic as pyd
from pydantic import BaseModel
from sqlalchemy import Column
from sqlalchemy.dialects.postgresql import JSON as JSONB
import sqlmodel
from sqlmodel import SQLModel, Relationship, String, Field


# =============================================================================
# Questionnaire Phase & Graph Models (Pydantic, not DB tables)
# =============================================================================

class QuestionnairePhase(BaseModel):
    """A phase within a questionnaire with questions and flow edges."""
    title: str
    description: str | None = pyd.Field(default=None)
    questions: list["Question"] = pyd.Field(
        serialization_alias="nodes", validation_alias="nodes"
    )
    edges: list["FlowEdge"] = pyd.Field()

    class Config:
        populate_by_name = True
        from_attributes = True


class FlowOperator(str, Enum):
    EQUALS = "EQUALS"
    IN = "IN"
    NOT_IN = "NOT-IN"
    NE = "NE"


class FlowEdge(BaseModel):
    """Directed edge in the questionnaire DAG."""
    operator: FlowOperator | None = pyd.Field(default=None)
    criteria_value: str | list[str] | None = pyd.Field(
        default=None, serialization_alias="criteria", validation_alias="criteria"
    )
    source_question_id: str = pyd.Field(
        serialization_alias="sourceId", validation_alias="sourceId"
    )
    target_question_id: str = pyd.Field(
        serialization_alias="targetId", validation_alias="targetId"
    )

    class Config:
        populate_by_name = True
        from_attributes = True


class QuestionType(str, Enum):
    TEXT = "text"
    CHOOSE_ONE = "choose-one"
    CHOOSE_MANY = "choose-many"
    KV = "key-value-table"


QUESTION_TYPE_MAP = {
    "Text": QuestionType.TEXT,
    "MultiChoice - single select": QuestionType.CHOOSE_ONE,
    "MultiChoice - multiple select": QuestionType.CHOOSE_MANY,
    "yes-no": QuestionType.CHOOSE_ONE,
    "key-value-table": QuestionType.KV,
    "text": QuestionType.TEXT,
    "choose-one": QuestionType.CHOOSE_ONE,
    "choose-many": QuestionType.CHOOSE_MANY,
}


class Question(BaseModel):
    """A node in the questionnaire DAG."""
    id: str = pyd.Field(default_factory=lambda: str(uuid4()))
    title: str = pyd.Field(...)
    text: str
    description: str | None = pyd.Field(default=None)
    type: QuestionType = pyd.Field(...)
    columns: list["KVColumn"] | None = pyd.Field(default=None)
    subphase: str | None = pyd.Field(default=None)
    options: list[str] | None = pyd.Field(default=None)
    justification_required: bool = pyd.Field(
        default=False,
        validation_alias="justificationRequired",
        serialization_alias="justificationRequired",
    )
    review: bool = pyd.Field(default=False)

    class Config:
        populate_by_name = True
        from_attributes = True


class KVColumn(BaseModel):
    col_id: str = pyd.Field(default_factory=lambda: str(uuid4()))
    name: str = pyd.Field(...)
    schema_key: str | None = pyd.Field(default=None)
    required: bool = pyd.Field(default=True)
    dtype: Literal["text", "float", "int", "select"] = pyd.Field(default="text")
    options: list[str] | None = pyd.Field(default=None)


class KVCellValue(BaseModel):
    col_id: str
    value: str | float | int | None = pyd.Field(default=None)


class KVRow(BaseModel):
    entry: list[KVCellValue] = pyd.Field(...)


class KeyValueTableResponse(BaseModel):
    rows: list[KVRow] = pyd.Field(default_factory=list)


class QuestionResponse(BaseModel):
    """Captures a user's answer to a question."""
    question_id: str = pyd.Field(
        validation_alias="questionId", serialization_alias="questionId"
    )
    answer: str | list[str] | KeyValueTableResponse = pyd.Field(
        serialization_alias="value", validation_alias="value",
    )
    submitted_at: str = pyd.Field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        validation_alias="submittedAt", serialization_alias="submittedAt",
    )
    justification: str | None = pyd.Field(default=None)

    class Config:
        populate_by_name = True
        from_attributes = True


# =============================================================================
# Database Tables (SQLModel)
# =============================================================================

class Questionnaire(SQLModel, table=True):
    """Questionnaire with phases stored as JSON."""
    id: int | None = sqlmodel.Field(default=None, primary_key=True)
    version: str = sqlmodel.Field(sa_type=String(125))
    projects: list["Project"] = Relationship(back_populates="questionnaire")
    active: bool = sqlmodel.Field(default=True)
    phases_json: list[QuestionnairePhase] = sqlmodel.Field(sa_column=Column(JSONB))


class ProjectAttributeLink(SQLModel, table=True):
    """Many-to-many join table for projects and attributes."""
    project_id: str | None = sqlmodel.Field(
        default=None, foreign_key="project.id", primary_key=True
    )
    attribute_id: int | None = sqlmodel.Field(
        default=None, foreign_key="attribute.id", primary_key=True
    )


class Attribute(SQLModel, table=True):
    """An attribute that can be associated with projects."""
    id: int | None = sqlmodel.Field(default=None, primary_key=True)
    text: str = sqlmodel.Field()
    projects: list["Project"] = Relationship(
        back_populates="attributes", link_model=ProjectAttributeLink
    )


class Project(SQLModel, table=True):
    """An IRAMP/ATO project evaluated using a questionnaire."""
    id: str = sqlmodel.Field(default_factory=lambda: str(uuid4()), primary_key=True)
    title: str = sqlmodel.Field(unique=True)
    description: str = sqlmodel.Field(max_length=5000)
    tags: list[str] = sqlmodel.Field(default_factory=list, sa_column=Column(JSONB))
    user_id: str = sqlmodel.Field(foreign_key="user_entity.id")
    questionnaire_id: int = sqlmodel.Field(foreign_key="questionnaire.id")
    questionnaire: Questionnaire | None = Relationship(back_populates="projects")
    created: datetime = sqlmodel.Field(default_factory=lambda: datetime.now(timezone.utc))
    updated: datetime = sqlmodel.Field(default_factory=lambda: datetime.now(timezone.utc))
    responses_json: list[QuestionResponse] = sqlmodel.Field(
        default_factory=list, sa_column=Column(JSONB)
    )
    attributes: list["Attribute"] = Relationship(
        back_populates="projects", link_model=ProjectAttributeLink
    )
_CLARITY_EOF_

touch "$P/backend/src/clarity/routes/__init__.py"

cat > "$P/backend/src/clarity/routes/auth.py" << '_CLARITY_EOF_'
from fastapi import APIRouter

auth_router = APIRouter(prefix="/auth", tags=["Authentication"])


@auth_router.get("/")
async def health():
    return 200
_CLARITY_EOF_

cat > "$P/backend/src/clarity/routes/project_routes.py" << '_CLARITY_EOF_'
from fastapi import APIRouter, Depends, Query, Body
from sqlmodel import Session

from ..models.questionnaire import Project
from ..services.project_services import (
    create_project, get_project, delete_project,
    update_project, create_question_response, assign_attributes_to_project,
)
from ..schemas.project_schema import (
    CreateProjectRequest, UpdateProjectRequest,
    AssignAttributesRequest, ProjectResponse,
)
from ..schemas.questionnaire_schema import (
    CreateQuestionResponseRequest, QuestionResponseResponse,
)
from ..db.manager import get_session
from ..models.questionnaire import Attribute

project_router = APIRouter(prefix="/project", tags=["Projects"])


@project_router.post(path="/", response_model=ProjectResponse)
async def create_project_endpoint(
    project: CreateProjectRequest = Body(..., description="The project details to create"),
    session: Session = Depends(get_session),
) -> Project:
    """Create a new project."""
    return create_project(session, project)


@project_router.get(
    path="/",
    response_model=ProjectResponse | list[ProjectResponse],
    response_model_exclude_none=True,
)
async def get_project_endpoint(
    project_id: str | None = Query(default=None),
    title: str | None = Query(default=None),
    user_id: str | None = Query(default=None),
    questionnaire_id: int | None = Query(default=None),
    include_questionnaire: bool | None = Query(default=None),
    session: Session = Depends(get_session),
) -> Project | list[Project]:
    """Retrieve projects by filters or all if no filters are applied."""
    return get_project(
        session,
        project_id=project_id,
        title=title,
        user_id=user_id,
        questionnaire_id=questionnaire_id,
        include_questionnaire=include_questionnaire,
    )


@project_router.delete(path="/", status_code=204)
async def delete_project_endpoint(
    project_id: str | None = Query(default=None),
    title: str | None = Query(default=None),
    user_id: str | None = Query(default=None),
    questionnaire_id: int | None = Query(default=None),
    session: Session = Depends(get_session),
) -> dict:
    """Delete one or more projects matching the provided filters."""
    return delete_project(session, project_id, title, user_id, questionnaire_id)


@project_router.put(path="/", response_model=ProjectResponse)
async def update_project_endpoint(
    updated_data: UpdateProjectRequest = Body(...),
    session: Session = Depends(get_session),
) -> ProjectResponse:
    """Update project title, description or tags."""
    return update_project(session, updated_data)


@project_router.post(path="/answer/create", response_model=QuestionResponseResponse)
async def create_question_response_endpoint(
    answer: CreateQuestionResponseRequest = Body(...),
    session: Session = Depends(get_session),
) -> CreateQuestionResponseRequest:
    """Create an answer to the question."""
    return create_question_response(session, answer)


@project_router.post(path="/attributes", response_model=list[Attribute])
async def assign_attributes_to_project_endpoint(
    request: AssignAttributesRequest = Body(...),
    session: Session = Depends(get_session),
) -> list[Attribute]:
    """Assign attributes to a project."""
    return assign_attributes_to_project(session, request)
_CLARITY_EOF_

cat > "$P/backend/src/clarity/routes/questionnaire_routes.py" << '_CLARITY_EOF_'
from fastapi import APIRouter, Depends, Query, Body
from sqlmodel import Session

from ..models.questionnaire import Questionnaire
from ..services.questionnaire_services import (
    create_questionnaire, get_questionnaire,
    delete_questionnaire, get_all_attributes,
)
from ..db.manager import get_session
from ..schemas.questionnaire_schema import (
    CreateQuestionnaireRequest, QuestionnaireResponse, AttributeResponse,
)

questionnaire_router = APIRouter(prefix="/questionnaire", tags=["Questionnaires"])


@questionnaire_router.post(path="/", response_model=QuestionnaireResponse)
async def create_questionnaire_endpoint(
    questionnaire: CreateQuestionnaireRequest = Body(...),
    session: Session = Depends(get_session),
) -> Questionnaire:
    return create_questionnaire(session, questionnaire)


@questionnaire_router.get(
    path="/",
    response_model=QuestionnaireResponse | list[QuestionnaireResponse],
    response_model_exclude_none=True,
)
async def get_questionnaire_endpoint(
    questionnaire_id: int | None = Query(default=None),
    version: str | None = Query(default=None),
    active: bool | None = Query(default=None),
    session: Session = Depends(get_session),
) -> Questionnaire | list[Questionnaire]:
    return get_questionnaire(session, questionnaire_id=questionnaire_id,
                             version=version, active=active)


@questionnaire_router.delete(path="/", status_code=204)
async def delete_questionnaire_endpoint(
    questionnaire_id: int | None = Query(default=None),
    version: str | None = Query(default=None),
    active: bool | None = Query(default=None),
    session: Session = Depends(get_session),
) -> None:
    return delete_questionnaire(session, questionnaire_id, version, active)


@questionnaire_router.get(path="/attributes", response_model=list[AttributeResponse])
async def get_all_attributes_endpoint(
    project_id: str | None = Query(default=None),
    questionnaire_id: int | None = Query(default=None),
    session: Session = Depends(get_session),
) -> list:
    return get_all_attributes(session, project_id, questionnaire_id)
_CLARITY_EOF_

cat > "$P/backend/src/clarity/routes/completion_routes.py" << '_CLARITY_EOF_'
from fastapi import APIRouter
from fastapi.responses import JSONResponse

completion_router = APIRouter(prefix="/completions", tags=["Completions"])


@completion_router.post("/chat_response")
async def chat_response():
    """Placeholder - AI chat completion."""
    return JSONResponse(
        status_code=501,
        content={"detail": "AI completion not implemented. This is a placeholder."}
    )


@completion_router.post("/suggest_response")
async def suggest_response():
    """Placeholder - AI suggestion."""
    return JSONResponse(
        status_code=501,
        content={"detail": "AI suggestion not implemented. This is a placeholder."}
    )
_CLARITY_EOF_

cat > "$P/backend/src/clarity/routes/review_routes.py" << '_CLARITY_EOF_'
from fastapi import APIRouter
from fastapi.responses import JSONResponse

review_router = APIRouter(prefix="/review", tags=["Review"])


@review_router.post("/project/{project_id}")
async def do_assessment(project_id: str):
    """Placeholder - project assessment."""
    return JSONResponse(
        status_code=501,
        content={"detail": "Review assessment not implemented."}
    )


@review_router.post("/project/{project_id}/question/{question_id}")
async def set_questionnaire_answer(project_id: str, question_id: str):
    """Placeholder - pass/fail review."""
    return JSONResponse(
        status_code=501,
        content={"detail": "Review answer not implemented."}
    )
_CLARITY_EOF_

cat > "$P/backend/src/clarity/routes/archer_routes.py" << '_CLARITY_EOF_'
from fastapi import APIRouter, Body
from ..services.archer_service import ArcherClient
from ..schemas.archer_schema import (
    CreateAuthPackageRequest, CreateAuthPackageResponse,
    ArcherLoginRequest,
)
from ..core.settings import ClaritySettings

archer_router = APIRouter(prefix="/archer", tags=["Archer GRC"])


@archer_router.post("/login")
async def archer_login():
    """Login to Archer and return a session token."""
    settings = ClaritySettings()
    client = ArcherClient(settings)
    token = await client.login()
    return {"session_token": token}


@archer_router.post("/logout")
async def archer_logout(session_token: str = Body(..., embed=True)):
    """Logout from Archer."""
    settings = ClaritySettings()
    client = ArcherClient(settings)
    result = await client.logout(session_token)
    return {"result": result}


@archer_router.post("/package", response_model=CreateAuthPackageResponse)
async def create_auth_package(
    request: CreateAuthPackageRequest = Body(...),
):
    """Create an authorization package in Archer."""
    settings = ClaritySettings()
    client = ArcherClient(settings)
    content_id = await client.create_auth_package(request)
    return CreateAuthPackageResponse(content_id=content_id)
_CLARITY_EOF_

touch "$P/backend/src/clarity/schemas/__init__.py"

cat > "$P/backend/src/clarity/schemas/project_schema.py" << '_CLARITY_EOF_'
from pydantic import BaseModel, Field
from datetime import datetime

from ..models.questionnaire import QuestionResponse, Attribute
from .questionnaire_schema import QuestionnaireResponse


class CreateProjectRequest(BaseModel):
    title: str = Field(...)
    description: str = Field(...)
    tags: list[str] = Field(default_factory=list)
    user_id: str = Field(...)
    questionnaire_id: int = Field(validation_alias="questionnaireId")
    attributes: list["Attribute"] = Field(default_factory=list, max_length=15)


class ProjectResponse(BaseModel):
    id: str = Field(...)
    title: str = Field(...)
    description: str = Field(...)
    tags: list[str] = Field(...)
    user_id: str = Field(serialization_alias="userId")
    questionnaire_id: int = Field(serialization_alias="questionnaireId")
    created: datetime = Field(...)
    updated: datetime = Field(...)
    responses_json: list["QuestionResponse"] = Field(serialization_alias="responses")
    attributes: list["Attribute"] = Field(...)
    questionnaire: QuestionnaireResponse | None = Field(
        default=None, serialization_alias="graph"
    )

    class Config:
        populate_by_name = True
        from_attributes = True


class UpdateProjectRequest(BaseModel):
    id: str = Field(...)
    title: str | None = Field(default=None)
    description: str | None = Field(default=None)
    tags: list[str] | None = Field(default=None)
    questionnaire_id: int | None = Field(default=None, validation_alias="questionnaireId")
    user_id: str = Field(validation_alias="userId")


class AssignAttributesRequest(BaseModel):
    project_id: str = Field(...)
    attribute_ids: list[int] | None = Field(default=None)
_CLARITY_EOF_

cat > "$P/backend/src/clarity/schemas/questionnaire_schema.py" << '_CLARITY_EOF_'
from pydantic import BaseModel, Field

from ..models.questionnaire import QuestionnairePhase, KeyValueTableResponse


class CreateQuestionnaireRequest(BaseModel):
    version: str | None = Field(default=None)
    active: bool = Field(default=True)
    phases_json: list[QuestionnairePhase] | None = Field(default_factory=list)


class QuestionnaireResponse(BaseModel):
    id: int = Field(...)
    version: str | None = Field(default=None)
    active: bool = Field(default=True)
    phases_json: list[QuestionnairePhase] | None = Field(
        default_factory=lambda: [], serialization_alias="phases"
    )

    class Config:
        populate_by_name = True
        from_attributes = True


class CreateQuestionResponseRequest(BaseModel):
    project_id: str = Field(validation_alias="projectId", serialization_alias="projectId")
    question_id: str = Field(validation_alias="questionId", serialization_alias="questionId")
    answer: str | list[str] | KeyValueTableResponse = Field(
        validation_alias="value", serialization_alias="value",
    )
    justification: str | None = Field(default=None)


class QuestionResponseResponse(BaseModel):
    question_id: str = Field(
        serialization_alias="questionId", validation_alias="questionId"
    )
    answer: str | list[str] | KeyValueTableResponse = Field(
        serialization_alias="value", validation_alias="value"
    )
    justification: str | None = Field(default=None)

    class Config:
        populate_by_name = True
        from_attributes = True


class AttributeResponse(BaseModel):
    id: int | None = Field(default=None)
    name: str = Field(...)
    value: str = Field(...)
    attribute_text: str = Field(...)
_CLARITY_EOF_

cat > "$P/backend/src/clarity/schemas/completion_schema.py" << '_CLARITY_EOF_'
from pydantic import BaseModel, Field

from ..core.message import Message


class CreateChatRequest(BaseModel):
    project_id: str = Field(...)
    question_id: str = Field(...)
    user_query: Message = Field(...)
    previous_messages: list[Message] | None = Field(default=None)


class CreateSuggestionRequest(BaseModel):
    project_id: str = Field(...)
    question_id: str = Field(...)
_CLARITY_EOF_

cat > "$P/backend/src/clarity/schemas/archer_schema.py" << '_CLARITY_EOF_'
"""Archer GRC schema definitions.
Contains all Pydantic models for Archer API interactions.
"""
from typing import Generator, Literal
from pydantic import BaseModel, Field
from enum import Enum


class ArcherLoginRequest(BaseModel):
    instance_name: str = Field(validation_alias="InstanceName")
    username: str = Field(validation_alias="Username")
    password: str = Field(validation_alias="Password")
    user_domain: str = Field(default="", serialization_alias="UserDomain")


class ArcherLogoutRequest(BaseModel):
    session_token: str = Field(serialization_alias="Value")


class ArcherFieldDef(BaseModel):
    field_id: str = Field(...)
    guid: str = Field(...)
    name: str | None = Field(default=None)
    field_name: str | None = Field(default=None)
    type_id: int | None = Field(default=None)
    field_type: str | None = Field(default=None)
    level_id: str | None = Field(default=None)
    max_selection: int | None = Field(default=None)
    related_values_list_id: str | None = Field(default=None)
    is_key: bool = Field(default=False)
    ref_level_id: str | None = Field(default=None)
    ref_field_id: str | None = Field(default=None)


class ArcherValuesListValue(BaseModel):
    values_list_id: str = Field(...)
    value_id: str = Field(...)
    value_name: str = Field(...)
    other_text: bool = Field(...)
    related_values_list_id: str | None = Field(default=None)


class ArcherCrossReference(BaseModel):
    ref_field_id: str = Field(...)
    ref_content_id: str = Field(...)


class ArcherLevel(BaseModel):
    level_id: str = Field(...)
    level_guid: str | None = Field(default=None)
    module_id: str | None = Field(default=None)
    module_name: str | None = Field(default=None)
    level_name: str | None = Field(default=None)
    key_field_id: str | None = Field(default=None)


class Hardware(BaseModel):
    archer_hw_id: str | None = Field(default=None)
    snow_id: str | None = Field(default=None)
    fqdn: str | None = Field(default=None)
    guid: str | None = Field(default=None)
    no_exceptions: str | None = Field(default=None)
    hw_types: str | None = Field(default=None)
    asset_username: str | None = Field(default=None)
    business_key: str | None = Field(default=None)
    location: str | None = Field(default=None)
    category: str | None = Field(default=None)
    platform: str | None = Field(default=None)
    environment: str | None = Field(default=None)
    is_archer: bool = Field(default=False)


class AuthPackage(BaseModel):
    """The IRAMP/ATO authorization package payload for Archer."""
    # Required fields
    sa: str = Field(description="System Administrator Employee ID", examples=["E10233551"])
    entity: str = Field(description="Business Entity", examples=["Enterprise Cybersecurity Services (ECS)"])
    auth_pkg_business: str = Field(description="RTX Business Identifier", examples=["Corporate"])
    information_classification: str = Field(...)
    connectivity: str = Field(...)
    auth_pkg_name: str = Field(...)
    mission_purpose: str = Field(...)
    auth_boundary_desc: str = Field(...)
    clara_id: str = Field(...)

    # Defaulted fields
    executive_summary: str = Field(default="This is an executive summary")
    scope: str = Field(default="This is the scope")
    considerations_assumptions: str = Field(default="")
    conclusion: str = Field(default="")
    recommendations: str = Field(default="")
    clarity_pkg: str = Field(default="Clarity")
    atdato_date: str = Field(default="2025-10-13T00:00:00.000")
    auth_pkg_submit_date: str = Field(default="2025-10-13T00:00:00.000")
    atdato_exp: str = Field(default="2025-10-13T00:00:00.000")
    annual_review_due: str = Field(default="2026-10-13T00:00:00.000")
    operational_status: str = Field(default="Operational")
    package_type: str = Field(default="Information System")
    authorization_decision: str = Field(default="ATO")
    ctrl_set_version_num: str = Field(default="NIST 800-171 Rev 1")
    auth_pkg_submission_status: str = Field(default="Submitted")
    methodology: str = Field(default="NIST RMF")
    ongoing_authorization: str = Field(default="Yes")
    workflow_status: str = Field(default="Workflow Complete")
    assessment_type: str = Field(default="Assessment Supporting Security Authorization or Reauthorization")

    # Security posture defaults (all Yes)
    uses_splunk: str = Field(default="Yes")
    uses_enterprise_patching: str = Field(default="Yes")
    uses_vuln_scanning: str = Field(default="Yes")
    connected_internal_rtx: str = Field(default="Yes")
    uses_enterprise_vpn: str = Field(default="Yes")
    uses_enterprise_antivirus: str = Field(default="Yes")
    onprem_ray_approved_facility: str = Field(default="Yes")
    enterprise_backup_recon_services_share_only: str = Field(default="Yes")
    security_training_reqd: str = Field(default="Yes")
    sso_integration: str = Field(default="Yes")
    aerocloud_azure: str = Field(default="Yes")
    aerocloud_aws: str = Field(default="Yes")
    maintenance: str = Field(default="Yes")
    media_protection: str = Field(default="Yes")
    personnel_security: str = Field(default="Yes")
    security_assessment: str = Field(default="Yes")
    rtx_security_category: str = Field(default="Low")
    system_hosting_env: str = Field(default="Other (Specify): DC App Migration")
    lock_clara_id: str = Field(default="Lock Clara ID")
    continuous_compliance_onboard: str = Field(default="Yes")
    auth_pkg_source: str = Field(default="Clarity")
    sot: str = Field(default="E10233551")
    tsot: str = Field(default="E10240000")
    sca: str = Field(default="")
    ebon: str = Field(default="Enterprise Services")


class CreateAuthPackageRequest(BaseModel):
    auth_pkg: AuthPackage = Field(...)
    host: list[Hardware] | None = Field(default=None)


class CreateAuthPackageResponse(BaseModel):
    content_id: str = Field(...)
_CLARITY_EOF_

touch "$P/backend/src/clarity/services/__init__.py"

cat > "$P/backend/src/clarity/services/project_services.py" << '_CLARITY_EOF_'
from fastapi import HTTPException
from sqlmodel import Session, select
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy.orm import selectinload

from ..models.questionnaire import Attribute, Project
from ..schemas.project_schema import (
    CreateProjectRequest, UpdateProjectRequest,
    AssignAttributesRequest, ProjectResponse,
)
from ..schemas.questionnaire_schema import (
    CreateQuestionResponseRequest, QuestionResponseResponse,
)


def create_project(session: Session, project: CreateProjectRequest) -> Project:
    """Create and save a new project in the database."""
    project_data = project.model_dump()
    project_data["attributes"] = [
        Attribute(**a.model_dump()) for a in project.attributes
    ]
    new_project = Project(**project_data)
    session.add(new_project)
    session.commit()
    session.refresh(new_project)
    return new_project


def get_project(
    session: Session,
    *,
    project_id: str | None = None,
    title: str | None = None,
    user_id: str | None = None,
    questionnaire_id: int | None = None,
    include_questionnaire: bool | None = None,
) -> Project | list[Project]:
    """Retrieve projects from the database based on optional filters."""
    statement = select(Project).options(selectinload(Project.attributes))

    if include_questionnaire:
        statement = statement.options(selectinload(Project.questionnaire))

    if project_id is not None:
        statement = statement.where(Project.id == project_id)
    if title is not None:
        statement = statement.where(Project.title == title)
    if user_id is not None:
        statement = statement.where(Project.user_id == user_id)
    if questionnaire_id is not None:
        statement = statement.where(Project.questionnaire_id == questionnaire_id)

    projects = session.exec(statement).all()

    if not projects:
        raise HTTPException(status_code=404, detail="No matching projects found")

    for project in projects:
        project.attributes = list(project.attributes)
        if not include_questionnaire:
            project.questionnaire = None

    if any([project_id, title, user_id, questionnaire_id]) and len(projects) == 1:
        return projects[0]

    return list(projects)


def delete_project(
    session: Session,
    project_id: str | None = None,
    title: str | None = None,
    user_id: str | None = None,
    questionnaire_id: int | None = None,
) -> dict:
    """Delete projects from the database matching the provided filters."""
    statement = select(Project)

    if project_id is not None:
        statement = statement.where(Project.id == project_id)
    if title is not None:
        statement = statement.where(Project.title == title)
    if user_id is not None:
        statement = statement.where(Project.user_id == user_id)
    if questionnaire_id is not None:
        statement = statement.where(Project.questionnaire_id == questionnaire_id)

    projects_to_delete = session.exec(statement).all()

    if not projects_to_delete:
        raise HTTPException(status_code=404, detail="No matching projects found to delete")

    for project in projects_to_delete:
        session.delete(project)
        session.commit()

    return {"deleted": len(projects_to_delete)}


def update_project(
    session: Session, updated_data: UpdateProjectRequest
) -> ProjectResponse:
    """Update an existing project with new data."""
    project_id = updated_data.id
    project = session.get(Project, project_id)

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    update_dict = updated_data.model_dump(exclude_unset=True)
    for k, v in update_dict.items():
        setattr(project, k, v)

    session.add(project)
    session.commit()
    session.refresh(project)
    return project


def create_question_response(
    session: Session, answer: CreateQuestionResponseRequest
) -> QuestionResponseResponse:
    """Add a user's answer to the project's responses_json field."""
    project_id = answer.project_id
    project = session.get(Project, project_id)
    if not project:
        raise ValueError(f"Project {project_id} not found.")

    answer_dict = answer.model_dump()
    found = False
    for i, response in enumerate(project.responses_json):
        if response["question_id"] == answer_dict["question_id"]:
            project.responses_json[i] = answer_dict
            found = True
            break

    if not found:
        project.responses_json.append(answer_dict)

    flag_modified(project, "responses_json")
    session.add(project)
    session.commit()
    session.refresh(project)
    return QuestionResponseResponse(
        question_id=answer_dict["question_id"],
        answer=answer_dict["answer"],
        justification=answer_dict["justification"],
    )


def assign_attributes_to_project(
    session: Session, request: AssignAttributesRequest
) -> list[Attribute]:
    """Assigns attributes to a project."""
    project_id = request.project_id
    attribute_ids = request.attribute_ids

    project = session.get(Project, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    attributes = session.exec(
        select(Attribute).where(Attribute.id.in_(attribute_ids))
    ).all()

    if len(attributes) != len(attribute_ids):
        raise HTTPException(status_code=404, detail="One or more attributes not found")

    project.attributes = attributes
    session.add(project)
    session.commit()
    session.refresh(project)
    return project.attributes
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/questionnaire_services.py" << '_CLARITY_EOF_'
from fastapi import HTTPException
from sqlmodel import Session, select

from ..models.questionnaire import (
    Questionnaire, Project, Attribute, ProjectAttributeLink,
)
from ..schemas.questionnaire_schema import CreateQuestionnaireRequest


def create_questionnaire(
    session: Session, questionnaire: CreateQuestionnaireRequest
) -> Questionnaire:
    """Create and save a new questionnaire in the database."""
    phases_json_dicts = [phase.model_dump() for phase in questionnaire.phases_json]

    new_questionnaire = Questionnaire(
        version=questionnaire.version,
        active=questionnaire.active,
        phases_json=phases_json_dicts,
    )
    session.add(new_questionnaire)
    session.commit()
    session.refresh(new_questionnaire)
    return new_questionnaire


def get_questionnaire(
    session: Session,
    *,
    questionnaire_id: int | None = None,
    version: str | None = None,
    active: bool | None = None,
) -> Questionnaire | list[Questionnaire]:
    """Retrieve questionnaires filtered by ID, version, and/or active status."""
    statement = select(Questionnaire)

    if questionnaire_id is not None:
        statement = statement.where(Questionnaire.id == questionnaire_id)
    if version is not None:
        statement = statement.where(Questionnaire.version == version)
    if active is not None:
        statement = statement.where(Questionnaire.active == active)

    questionnaires = session.exec(statement).all()

    if not questionnaires:
        raise HTTPException(status_code=404, detail="No matching questionnaires found")

    if any([questionnaire_id, version, active]) and len(questionnaires) == 1:
        return questionnaires[0]

    return questionnaires


def delete_questionnaire(
    session: Session,
    questionnaire_id: int | None = None,
    version: str | None = None,
    active: bool | None = None,
) -> None:
    """Delete questionnaires. Raises 400 if referenced by projects."""
    statement = select(Questionnaire)

    if questionnaire_id is not None:
        statement = statement.where(Questionnaire.id == questionnaire_id)
    if version is not None:
        statement = statement.where(Questionnaire.version == version)
    if active is not None:
        statement = statement.where(Questionnaire.active == active)

    questionnaires = session.exec(statement).all()

    if not questionnaires:
        raise HTTPException(status_code=404, detail="No matching questionnaires found")

    for q in questionnaires:
        project_exists = (
            session.query(Project).filter(Project.questionnaire_id == q.id).first()
        )
        if project_exists:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Cannot delete questionnaire {q.id} because it is used by "
                    "one or more projects."
                ),
            )

    for q in questionnaires:
        session.delete(q)

    session.commit()


def get_all_attributes(
    session: Session,
    project_id: str | None = None,
    questionnaire_id: int | None = None,
) -> list[Attribute]:
    """Retrieve attributes, optionally filtered by project or questionnaire."""
    statement = select(Attribute)

    if project_id is not None:
        statement = statement.join(
            ProjectAttributeLink,
            ProjectAttributeLink.attribute_id == Attribute.id
        ).where(ProjectAttributeLink.project_id == project_id)
    elif questionnaire_id is not None:
        statement = (
            statement.join(
                ProjectAttributeLink,
                ProjectAttributeLink.attribute_id == Attribute.id
            )
            .join(Project, Project.id == ProjectAttributeLink.project_id)
            .where(Project.questionnaire_id == questionnaire_id)
        )

    results = session.exec(statement).all()
    return results
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/archer_service.py" << '_CLARITY_EOF_'
"""
Archer GRC REST API Client.
Ported from the C# ArcherCSharp implementation.
Handles login, content creation, user lookup, and workflow transitions.
"""
import json
import re
import httpx

from ..core.settings import ClaritySettings
from ..schemas.archer_schema import (
    CreateAuthPackageRequest, AuthPackage, Hardware,
    ArcherFieldDef, ArcherValuesListValue, ArcherLevel,
)


class ArcherClient:
    """Client for interacting with RSA Archer GRC REST API."""

    def __init__(self, settings: ClaritySettings):
        self.base_uri = settings.archer_base_uri
        self.username = settings.archer_username
        self.password = settings.archer_password
        self.instance_name = settings.archer_instance_name
        self.session_token: str | None = None

    async def login(self) -> str:
        """Authenticate to Archer and return a session token."""
        url = f"{self.base_uri}/api/core/security/login"
        payload = json.dumps({
            "InstanceName": self.instance_name,
            "Username": self.username,
            "Password": self.password,
            "UserDomain": "",
        })

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url, content=payload,
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            data = response.json()
            self.session_token = data.get("RequestedObject", {}).get("SessionToken", "")
            return self.session_token

    async def logout(self, session_token: str) -> str:
        """Logout from Archer."""
        url = f"{self.base_uri}/api/core/security/logout"
        payload = json.dumps({"Value": session_token})

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url, content=payload,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Archer session-id=\"{session_token}\"",
                },
            )
            if response.is_success:
                data = response.json()
                if data.get("IsSuccessful"):
                    return "Logout of Archer Successful"
            return f"Logout Failed: {response.status_code}"

    def _auth_headers(self) -> dict:
        return {
            "Content-Type": "application/json",
            "Authorization": f"Archer session-id=\"{self.session_token}\"",
        }

    @staticmethod
    def _base_content_line(content: str, field: ArcherFieldDef) -> str:
        """Build a content line for text-type fields (type 1)."""
        if field.field_type == "19":
            return (
                f"\"{field.field_id}\":{{\"Type\":\"19\",\"Tag\":\"{field.field_name}\",'
                f'\"IpAddressBytes\":\"{content}\",\"FieldId\":\"{field.field_id}\"}}'
            )
        return (
            f"\"{field.field_id}\":{{\"Type\":\"1\",\"Tag\":\"{field.field_name}\",'
            f'\"Value\":\"{content}\",\"FieldId\":\"{field.field_id}\"}}'
        )

    @staticmethod
    def _value_content_line(
        content: str, field: ArcherFieldDef, values: list[ArcherValuesListValue]
    ) -> str:
        """Build a content line for values-list fields (type 4)."""
        items = [s.strip() for s in content.split(",") if s.strip()]
        val_ids = []
        other_text = ""
        for item in items:
            for v in values:
                if v.other_text and (
                    item.lower() == v.value_name.lower()[:len(item)]
                ):
                    val_ids.append(v.value_id)
                    other_text = item[len(v.value_name):].strip() if len(item) > len(v.value_name) else ""
                elif v.related_values_list_id == v.values_list_id and v.value_name == item:
                    val_ids.append(v.value_id)

        val_string = ",".join(val_ids)
        return (
            f"\"{field.field_id}\":{{\"Type\":\"4\",\"Tag\":\"{field.field_name}\",'
            f'\"Value\":{{\"ValuesListIds\":\"{val_string}\"}},'
            f'\"FieldId\":\"{field.field_id}\"}}'
        )

    async def _create_content(self, record_json: str) -> str | None:
        """POST a content record to Archer and return the content ID."""
        url = f"{self.base_uri}/api/core/content"
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url, content=record_json, headers=self._auth_headers()
            )
            if response.is_success:
                data = response.json()
                success = data.get("IsSuccessful", False)
                if success:
                    return str(data.get("RequestedObject", {}).get("Id", ""))
        return None

    async def create_auth_package(self, request: CreateAuthPackageRequest) -> str:
        """Create an authorization package in Archer.

        This is the main entry point that:
        1. Logs in
        2. Creates hardware records
        3. Creates the auth package record linking hardware
        4. Returns the content ID
        """
        await self.login()

        # TODO: In full implementation, this would:
        # - Load field/level/value mappings from Snowflake
        # - Create hardware records first
        # - Build auth package JSON with field-type-appropriate builders
        # - POST to /api/core/content
        # - Handle workflow transitions

        # For now, return a placeholder
        return "PENDING_IMPLEMENTATION"

    async def get_transitions(self, content_id: str) -> list[dict]:
        """Get available workflow transitions for a content record."""
        url = f"{self.base_uri}/api/core/system/store/action/{content_id}"
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(url, headers=self._auth_headers())
            if response.is_success:
                data = response.json()
                actions = data.get("RequestedObject", {}).get("Actions", [])
                return [
                    {
                        "nodeID": str(a.get("WorkflowNodeId", "")),
                        "transID": str(a.get("WorkflowTransitionId", "")),
                        "transName": str(a.get("WorkflowTransitionName", "")),
                    }
                    for a in actions
                ]
        return []

    async def choose_transition(self, content_id: str, transition_id: str) -> str:
        """Execute a workflow transition on a content record."""
        url = f"{self.base_uri}/api/core/system/WorkflowAction"
        payload = json.dumps({
            "ContentId": content_id,
            "TransitionId": transition_id,
        })
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url, content=payload, headers=self._auth_headers()
            )
            if response.is_success:
                return "Success"
        return "Failed"
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/completion_service.py" << '_CLARITY_EOF_'
"""Placeholder - Completion service for AI chat (not connected)."""
pass
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/embedding_service.py" << '_CLARITY_EOF_'
"""Placeholder - Embedding service for RAG (not connected)."""


class EmbeddingService:
    """Stub embedding service."""
    pass
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/rag_ingestion.py" << '_CLARITY_EOF_'
"""Placeholder - RAG ingestion service (not connected)."""


async def index_rag_guide(session, embedding_service, path):
    """Stub for RAG document ingestion."""
    pass
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/retrieval_service.py" << '_CLARITY_EOF_'
"""Placeholder - Retrieval service for RAG (not connected)."""
pass
_CLARITY_EOF_

cat > "$P/backend/src/clarity/services/review_service.py" << '_CLARITY_EOF_'
"""Placeholder - Review service (not connected)."""
pass
_CLARITY_EOF_

touch "$P/backend/src/clarity/templates/__init__.py"

cat > "$P/backend/seed/data.json" << '_CLARITY_EOF_'
{
  "id": "1",
  "version": "v1",
  "active": true,
  "content": {
    "phases": [
      {
        "title": "General Questions",
        "description": "Questions which broadly cover multiple topics but establish a baseline of information.",
        "edges": [
          {
            "sourceId": "Authorization Package Name:",
            "targetId": "Control Set Version Number:"
          },
          {
            "sourceId": "Control Set Version Number:",
            "targetId": "Methodology:"
          },
          {
            "sourceId": "Methodology:",
            "targetId": "Entity:"
          },
          {
            "sourceId": "Entity:",
            "targetId": "Requested Authorization Type:"
          },
          {
            "sourceId": "Requested Authorization Type:",
            "targetId": "Data Center Application Migration:"
          },
          {
            "sourceId": "Data Center Application Migration:",
            "targetId": "CLARA ID:"
          },
          {
            "sourceId": "CLARA ID:",
            "targetId": "Mission/Purpose:"
          },
          {
            "sourceId": "Mission/Purpose:",
            "targetId": "Information Classification:"
          },
          {
            "sourceId": "Information Classification:",
            "targetId": "System Hosting Environment:"
          },
          {
            "sourceId": "System Hosting Environment:",
            "targetId": "Information System Type:"
          },
          {
            "sourceId": "Information System Type:",
            "targetId": "User Access Requirements:"
          },
          {
            "sourceId": "User Access Requirements:",
            "targetId": "Managed By:"
          },
          {
            "sourceId": "Managed By:",
            "targetId": "Connectivity:"
          },
          {
            "sourceId": "Connectivity:",
            "targetId": "Requestor:"
          },
          {
            "sourceId": "Requestor:",
            "targetId": "Information System Owner (ISO) Name:"
          },
          {
            "sourceId": "Information System Owner (ISO) Name:",
            "targetId": "Information System Owner Employee ID:"
          },
          {
            "sourceId": "Information System Owner Employee ID:",
            "targetId": "Information Owner (IO):"
          },
          {
            "sourceId": "Information Owner (IO):",
            "targetId": "System Administrator:"
          },
          {
            "sourceId": "System Administrator:",
            "targetId": "Additional Visibility:"
          }
        ],
        "nodes": [
          {
            "id": "Authorization Package Name:",
            "subphase": "General",
            "title": "Authorization Package Name:",
            "text": "Enter the desired name of the Security Authorization Package (SAP).",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Control Set Version Number:",
            "subphase": "General",
            "title": "Control Set Version Number:",
            "text": "In MOST cases this response will be the default response of NIST 800-171 Rev 1, if not select the appropriate security control assessment baseline.",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "NIST 800-171 Rev 1"
            ]
          },
          {
            "id": "Methodology:",
            "subphase": "General",
            "title": "Methodology:",
            "text": "In MOST cases this response will be the default response of NIST RMF. If not, select the appropriate authorization package methodology. This selection will drive the control set.",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "NIST RMF"
            ]
          },
          {
            "id": "Entity:",
            "subphase": "General",
            "title": "Entity:",
            "text": "Select the Business entity/program/function that owns the authorization package.",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "No Selection",
              "Advanced Concepts and Technology (RaCIS)",
              "Advanced Missile Systems (Temp)"
            ]
          },
          {
            "id": "Requested Authorization Type:",
            "subphase": "General",
            "title": "Requested Authorization Type:",
            "text": "Select ATC (Authorization to Connect) if system will be used for short duration, non-operational testing and integration, otherwise select ATO (Authorization to Operate).",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "ATO",
              "Re-Authorization",
              "ATC"
            ]
          },
          {
            "id": "Data Center Application Migration:",
            "subphase": "General",
            "title": "Data Center Application Migration:",
            "text": "Check this box if the application is in scope of the Data Center Application Migration effort.",
            "description": "TBA",
            "type": "yes-no",
            "options": [
              "Yes",
              "No"
            ]
          },
          {
            "id": "CLARA ID:",
            "subphase": "General",
            "title": "CLARA ID:",
            "text": "TBA",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Mission/Purpose:",
            "subphase": "General",
            "title": "Mission/Purpose:",
            "text": "Describe in detail the Mission / Purpose for the information system/application (i.e., what is it used for).",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Information Classification:",
            "subphase": "General",
            "title": "Information Classification:",
            "text": "Select all of the information data type classifications that will be processed by the information system. If Other is selected, describe the information data type classification.",
            "description": "TBA",
            "type": "MultiChoice - multiple select",
            "options": [
              "CDI/CUI (DFARS)",
              "Competition Sensitive",
              "CUI (non-CUI)",
              "EXIM (ITAR, EAR)",
              "Internal Use Only",
              "Personal Information (PI)",
              "Most Private",
              "Proprietary",
              "Public",
              "Other (Specify)"
            ]
          },
          {
            "id": "System Hosting Environment:",
            "subphase": "General",
            "title": "System Hosting Environment:",
            "text": "Select all location(s) of the environment. If Other is selected, describe the locations within the provided text field.",
            "description": "TBA",
            "type": "MultiChoice - multiple select",
            "options": [
              "mDC1",
              "mDC5",
              "mDC9",
              "NovaBridge",
              "Commercial Cloud",
              "Gov Cloud",
              "Other (Specify)"
            ]
          },
          {
            "id": "Information System Type:",
            "subphase": "General",
            "title": "Information System Type:",
            "text": "Select the appropriate information system type. If Other is selected, describe the information system type within the provided text field.",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "No Selection",
              "Application",
              "Infrastructure",
              "Commercial Cloud",
              "Gov Cloud",
              "Laboratory/Pilot System",
              "Manufacturing",
              "3rd Party",
              "Other (Specify)"
            ]
          },
          {
            "id": "User Access Requirements:",
            "subphase": "General",
            "title": "User Access Requirements:",
            "text": "Select all applicable user categories that will access the information system.",
            "description": "TBA",
            "type": "MultiChoice - multiple select",
            "options": [
              "US Employees",
              "US Contractors",
              "US Business Partners",
              "International Business Partners",
              "International Employees",
              "International Contractors"
            ]
          },
          {
            "id": "Managed By:",
            "subphase": "General",
            "title": "Managed By:",
            "text": "Select who will be managing the system. RTX (includes subcontractors e.g., DXC and IBM) or 3rd Party Vendor.",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "No Selection",
              "RTX",
              "Third-Party Vendor"
            ]
          },
          {
            "id": "Connectivity:",
            "subphase": "General",
            "title": "Connectivity:",
            "text": "Select the applicable method(s) by which this information system is connected. Externally Accessible Systems: RTX systems with customer or business partners that have accessibility from non-RTX networks. Global - INRCEN: International Raytheon Corporate networks in support of international business units (e.g. Raytheon UK, Raytheon Germany, Canada, Australia). Interconnected System - Contractor-to-Government (C2G): Raytheon connected systems contractually obligated to government customers. LAN / Wide Area Network (WAN) / MAN: Primarily used for network infrastructure. Networked - Internal within Studio: Typically desktop/laptop/communications computers are connected to the Studio network. Printer/Scanner: Connections used for printers/scanners. Standalone: Standalone computers, without a network connection (e.g. SIPRLN, DREN) or connection to another computer (e.g. computers used to burn CD/DVD or perform virus checks or removable media). If other is selected, describe the connectivity within the provided text field.",
            "description": "TBA",
            "type": "MultiChoice - single select",
            "options": [
              "No Selection",
              "Internal Only",
              "External"
            ]
          },
          {
            "id": "Requestor:",
            "subphase": "Stakeholders",
            "title": "Requestor:",
            "text": "The name of the person requesting the SAP intake.",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Information System Owner (ISO) Name:",
            "subphase": "Stakeholders",
            "title": "Information System Owner (ISO) Name:",
            "text": "The name of the Information System Owner.",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Information System Owner Employee ID:",
            "subphase": "Stakeholders",
            "title": "Information System Owner Employee ID:",
            "text": "The employee ID of the person requesting the SAP intake.",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Information Owner (IO):",
            "subphase": "Stakeholders",
            "title": "Information Owner (IO):",
            "text": "An individual responsible for establishing the controls for the generation, collection, processing, dissemination, and disposal of the information on the IS. The IO is responsible for determining the classification of data on the system such as CUI, ITAR, etc.",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "System Administrator:",
            "subphase": "Stakeholders",
            "title": "System Administrator:",
            "text": "To be assigned as a System Administrator (SA) individuals must have been assigned the SA role in Archer. To be assigned as an SA, requestor must complete the RITSCHEDULER Privileged User/ System Administrator Overview course in Empowery and then submit an Archer Service Request for user access.",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          },
          {
            "id": "Additional Visibility:",
            "subphase": "Stakeholders",
            "title": "Additional Visibility:",
            "text": "List program managers, technical leads, etc. who require read only. Persons listed here will have READ-ONLY access to the SAP.",
            "description": "TBA",
            "type": "Text",
            "options": "none"
          }
        ]
      }
    ]
  }
}
_CLARITY_EOF_

cp "$P/backend/seed/data.json" "$P/backend/src/clarity/seed/data.json"

echo ""
echo "============================================="
echo "  Part 1 Complete! Backend + infra created."
echo "============================================="
echo "  Next: Run Part 2 for the frontend."
echo "  Then: cd clarity-rewrite && docker compose up -d db keycloak"
echo "         cd backend && pip install -r requirements.txt"
echo "         SEED_DATA=true uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload"
echo ""
