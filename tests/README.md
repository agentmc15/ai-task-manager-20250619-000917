# Clarity — IRAMP Workflow Automation

> **Internal Risk Assessment & Management Process (IRAMP) tool for RTX Authorization-to-Operate (ATO) workflows.**
>
> Clarity automates the collection, review, and submission of security authorization packages to RSA Archer GRC. Users complete a guided questionnaire that captures system categorization, stakeholder information, and technical details, then submits the structured data as an Archer content record.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Tech Stack](#tech-stack)
4. [Project Structure](#project-structure)
5. [Getting Started](#getting-started)
6. [Environment Variables](#environment-variables)
7. [Authentication](#authentication)
8. [Database](#database)
9. [API Reference](#api-reference)
10. [Frontend](#frontend)
11. [Keycloak Configuration](#keycloak-configuration)
12. [Archer GRC Integration](#archer-grc-integration)
13. [Deployment](#deployment)
14. [Development Workflow](#development-workflow)
15. [Troubleshooting](#troubleshooting)

---

## Overview

Clarity is a full-stack application that replaces the manual IRAMP authorization process with a structured, questionnaire-driven workflow. It was built to support RTX business units (Collins, Pratt & Whitney, Raytheon, Corporate) in managing their information system authorizations.

### What It Does

1. **Project Creation** — Users create an IRAMP/ATO project through a 3-step wizard (Project Details → Attributes → Tags).
2. **Questionnaire Flow** — A configurable questionnaire walks users through security-relevant questions. Questions are organized by subphase (General, Information System Details, Personnel/Stakeholders) and support text input, single-select, and multi-select response types.
3. **Review & Submit** — Users review all answers in a summary view before submitting the completed authorization package.
4. **Archer GRC Submission** — The structured responses are mapped to RSA Archer field definitions and submitted as content records via the Archer REST API, triggering the downstream A&A workflow.

### Key Concepts

- **IRAMP** — Information Risk Assessment & Management Process. The RTX enterprise framework for categorizing systems by risk level (LOE A through DFARS) and applying appropriate security controls based on NIST 800-37.
- **ATO** — Authorization to Operate. The formal approval granted after a system's security posture has been assessed.
- **LOE (Level of Effort)** — Risk categorization tiers: LOE A (20 controls, pilot systems), LOE B (38, public data), LOE C (56, internal), LOE D (70, external), DFARS (110, CUI/ITAR/EAR).
- **Authorization Package** — The collection of questionnaire responses, attributes, and metadata that gets submitted to Archer for review and approval.

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Nuxt 3 UI     │────▶│  FastAPI Backend  │────▶│   PostgreSQL     │
│   Port :3001    │     │   Port :4000      │     │   Port :5432     │
└─────────────────┘     └──────────────────┘     └──────────────────┘
        │                       │                         │
        │ OIDC                  │ REST                    │ Shared DB
        ▼                       ▼                         ▼
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Keycloak SSO  │     │  RSA Archer GRC  │     │   Keycloak       │
│   Port :8080    │     │  (Corp Network)  │     │   (realm data)   │
└─────────────────┘     └──────────────────┘     └──────────────────┘
```

### Request Flow

1. User accesses the Nuxt frontend at `:3001`.
2. In `keycloak` auth mode, the frontend redirects to Keycloak for OIDC authentication. In `dev` mode, a mock user is injected automatically.
3. Authenticated requests hit the FastAPI backend at `:4000` with a Bearer token (keycloak mode) or no token (dev mode).
4. The backend validates the token, extracts the user's email, and scopes all project operations to that user.
5. On submission, the backend maps questionnaire responses to Archer field definitions and POSTs content records via the Archer REST API.

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | Nuxt 3 (Vue 3 + TypeScript) | 3.x |
| UI Components | Tailwind CSS + shadcn-vue | 4.x / latest |
| Auth (Frontend) | nuxt-auth-utils (OIDC) | latest |
| Backend | FastAPI (Python) | 0.115+ |
| ORM | SQLModel (SQLAlchemy 2.0) | 0.0.22+ |
| Database | PostgreSQL | 17 |
| Identity Provider | Keycloak | 26.2.1 |
| GRC Platform | RSA Archer (REST + SOAP) | Enterprise |
| Containerization | Docker / Docker Compose | latest |
| Package Validation | Pydantic v2 | 2.9+ |

---

## Project Structure

```
projects/clarity-rewrite/
├── backend/
│   ├── src/
│   │   ├── __init__.py
│   │   └── clarity/
│   │       ├── __init__.py
│   │       ├── api.py                     # FastAPI entry point, routers, CORS, lifespan
│   │       ├── core/
│   │       │   ├── __init__.py
│   │       │   ├── auth.py                # AUTH_MODE dependency (dev mock / keycloak JWT)
│   │       │   ├── message.py             # Chat message model
│   │       │   └── settings.py            # ClaritySettings (Pydantic BaseSettings)
│   │       ├── db/
│   │       │   ├── __init__.py
│   │       │   ├── manager.py             # Engine, session factory, table init, seed data
│   │       │   └── add_owner_email.py     # Migration: add owner_email to project table
│   │       ├── models/
│   │       │   ├── __init__.py
│   │       │   └── questionnaire.py       # Core data model (all SQLModel entities)
│   │       ├── routes/
│   │       │   ├── __init__.py
│   │       │   ├── auth.py                # GET /auth/ health check
│   │       │   ├── project_routes.py      # User-scoped project CRUD + answer upsert
│   │       │   ├── questionnaire_routes.py# Questionnaire CRUD + attributes
│   │       │   ├── archer_routes.py       # Archer login + auth package submission
│   │       │   ├── completion_routes.py   # AI chat (stub)
│   │       │   └── review_routes.py       # Assessment review (stub)
│   │       ├── schemas/
│   │       │   ├── __init__.py
│   │       │   ├── project_schema.py      # Create/Update/Response + AssignAttributes
│   │       │   ├── questionnaire_schema.py# Create/Response + QuestionResponse
│   │       │   ├── archer_schema.py       # Full Archer data contract (AuthPackage, Hardware)
│   │       │   └── completion_schema.py   # Chat/Suggestion request
│   │       └── services/
│   │           ├── __init__.py
│   │           ├── project_services.py    # Helper utilities (ownership transfer)
│   │           ├── questionnaire_services.py # CRUD + referential integrity
│   │           ├── archer_service.py      # Archer REST client (async httpx)
│   │           ├── completion_service.py  # AI completion (placeholder)
│   │           └── review_service.py      # Assessment logic (placeholder)
│   ├── seed/
│   │   └── data.json                      # Questionnaire seed data (8 questions)
│   ├── requirements.txt
│   └── Dockerfile
│
├── frontend/
│   ├── app.vue                            # Root: NuxtLayout + NuxtPage
│   ├── auth.d.ts                          # User/UserSession type declarations
│   ├── nuxt.config.ts                     # Tailwind, shadcn, nuxt-auth-utils, runtime config
│   ├── package.json
│   ├── assets/css/tailwind.css
│   ├── composables/
│   │   ├── useApi.ts                      # API client with auto-injected auth headers
│   │   └── useAuth.ts                     # Auth state + headers (dev/keycloak modes)
│   ├── layouts/
│   │   └── default.vue                    # Clarity header bar + nav
│   ├── middleware/
│   │   └── auth.ts                        # Route guard (no-op in dev mode)
│   ├── pages/
│   │   ├── index.vue                      # Home / landing page
│   │   ├── login.vue                      # SSO login page
│   │   └── clara/
│   │       ├── index.vue                  # Project list + 3-step creation wizard
│   │       └── [projectId].vue            # Questionnaire flow + review
│   ├── types/
│   │   ├── project.ts
│   │   ├── questionnaire.ts
│   │   ├── completion.ts
│   │   └── review.ts
│   └── Dockerfile
│
├── keycloak/
│   └── clarity-realm.json                 # Auto-import: realm, clients, test users, roles
│
├── nginx/conf.d/
│   ├── clarity.conf                       # SSL proxy: clarity.onertx.com → :3000
│   ├── keycloak.conf                      # SSL proxy: sso.clarity.onertx.com → :8080
│   └── nuxt.conf                          # Internal router: /kc/* /be/* /* routing
│
├── docker-compose.yaml                    # Local dev (Postgres + Keycloak)
├── docker-compose.production.yaml         # Production with all services
├── .env.example                           # Environment variable template
├── .gitignore
├── start-docker.sh / .bat / .ps1          # Start Docker services
├── start-backend.sh / .bat / .ps1         # Start FastAPI dev server
├── start-frontend.sh / .bat / .ps1        # Start Nuxt dev server
└── README.md                              # This file
```

---

## Getting Started

### Prerequisites

- **Python 3.11+** with `pip`
- **Node.js 18+** with `npm`
- **Docker Desktop** (for PostgreSQL and Keycloak)
- **Git Bash** (Windows) or any Bash shell

### 1. Clone the Repository

```bash
git clone https://github-us.utc.com/us-persons-only/GRCAA-Clarity.git
cd GRCAA-Clarity/projects/clarity-rewrite
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your credentials (Keycloak, Postgres, Archer, etc.)
```

### 3. Start Infrastructure (Docker)

```bash
docker compose up -d
```

This starts PostgreSQL (`:5432`) and Keycloak (`:8080`). On first boot, Keycloak auto-imports the `clarity` realm from `keycloak/clarity-realm.json`, creating the `nuxt-frontend` client and two test users.

### 4. Start the Backend

```bash
cd backend
python -m venv venv

# Windows (Git Bash)
source venv/Scripts/activate

# macOS/Linux
source venv/bin/activate

pip install -r requirements.txt

# Seed the questionnaire data on first run
export SEED_DATA=true
python -m uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
```

Verify at: http://localhost:4000/docs (Swagger UI)

### 5. Start the Frontend

```bash
cd frontend
npm install --legacy-peer-deps
npx nuxt dev --port 3001
```

Access at: http://localhost:3001

### 6. Verify the Full Stack

- **Frontend:** http://localhost:3001 → Login page (or auto-bypass in dev mode)
- **Backend API:** http://localhost:4000/docs → Swagger interactive docs
- **Keycloak Admin:** http://localhost:8080/kc/admin → Login with `admin` / `admin`

---

## Environment Variables

All configuration is managed through a single `.env` file at the project root. See `.env.example` for the full template.

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTH_MODE` | `dev` | Authentication mode: `dev` (mock user) or `keycloak` (real OIDC) |
| `SEED_DATA` | `false` | Set to `true` to seed questionnaire data on startup |

### PostgreSQL

| Variable | Default | Description |
|----------|---------|-------------|
| `CLARITY_SQL_DB` | `clarity` | Database name |
| `CLARITY_SQL_USER` | `clarity` | Database user |
| `CLARITY_SQL_PASSWORD` | `clarity` | Database password |
| `CLARITY_SQL_HOST` | `localhost` | Host (use `localhost` for local dev, `db` inside Docker) |
| `CLARITY_SQL_PORT` | `5432` | Port |

### Keycloak

| Variable | Default | Description |
|----------|---------|-------------|
| `CLARITY_KC_HOST` | `localhost` | Keycloak hostname |
| `CLARITY_KC_PORT` | `8080` | Keycloak port |
| `CLARITY_KC_REALM` | `clarity` | Realm name |
| `CLARITY_KC_ADMIN` | `admin` | Admin console username |
| `CLARITY_KC_ADMIN_PASSWORD` | `admin` | Admin console password |

### Nuxt Frontend

| Variable | Default | Description |
|----------|---------|-------------|
| `NUXT_API_BASE` | `http://localhost:4000` | Backend API URL |
| `NUXT_OAUTH_KEYCLOAK_CLIENT_ID` | `nuxt-frontend` | OIDC client ID |
| `NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET` | *(required for keycloak mode)* | OIDC client secret |
| `NUXT_OAUTH_KEYCLOAK_SERVER_URL` | `http://localhost:8080` | Keycloak base URL |
| `NUXT_SESSION_PASSWORD` | *(required)* | Session encryption key (32+ chars) |

### Archer GRC

| Variable | Description |
|----------|-------------|
| `ARCHER_USERNAME` | Archer API service account |
| `ARCHER_PASSWORD` | Archer API password |
| `ARCHER_INSTANCE_NAME` | Archer instance (e.g., `ArcherPOC`) |
| `ARCHER_BASE_URI` | Archer base URL |
| `ARCHER_SOAP_SEARCH_URI` | SOAP search WSDL endpoint |
| `ARCHER_SOAP_GENERAL_URI` | SOAP general WSDL endpoint |
| `MAPPING_REPORT` | Archer mapping report GUID |

---

## Authentication

Clarity supports two authentication modes, controlled by the `AUTH_MODE` environment variable.

### Dev Mode (`AUTH_MODE=dev`)

Default for local development. No login required. All requests use a hardcoded mock user:

- **Email:** `dev@clarity.local`
- **Name:** Dev User
- **Roles:** `clarity-user`, `clarity-admin`

All projects created in dev mode are owned by `dev@clarity.local`.

### Keycloak Mode (`AUTH_MODE=keycloak`)

Production authentication via Keycloak OIDC. The flow:

1. Frontend redirects to Keycloak login page.
2. User authenticates (local Keycloak user or federated via RTX SSO).
3. Keycloak issues a JWT with user claims (email, name, roles).
4. Frontend stores the token and includes it as a Bearer header on API requests.
5. Backend validates the JWT against Keycloak's JWKS endpoint and extracts the user's email for project scoping.

### User Scoping

Projects are scoped by `owner_email`. Each user only sees projects where `owner_email` matches their authenticated email. This applies to all CRUD operations — list, get, update, delete, and answer submission.

---

## Database

### Data Model

The core data model is defined in `backend/src/clarity/models/questionnaire.py`:

**`Questionnaire`** (table) — A versioned questionnaire containing one or more phases.
- `id` (int, PK), `version` (str), `active` (bool), `phases_json` (JSONB)

**`QuestionnairePhase`** (Pydantic) — A phase within a questionnaire containing questions and flow edges.
- `title`, `description`, `questions` (list of Question), `edges` (list of FlowEdge)

**`Question`** (Pydantic) — A single question node in the questionnaire DAG.
- `id` (str), `title`, `text`, `type` (text | choose-one | choose-many | key-value-table), `options`, `subphase`, `justification_required`

**`FlowEdge`** (Pydantic) — Directed edge between questions, supporting conditional branching.
- `source_question_id`, `target_question_id`, `operator` (EQUALS | IN | NOT_IN | NE), `criteria_value`

**`Project`** (table) — A user's IRAMP/ATO project with questionnaire responses.
- `id` (uuid, PK), `title` (unique), `description`, `tags` (JSONB), `owner_email`, `questionnaire_id` (FK), `responses_json` (JSONB), `created`, `updated`

**`Attribute`** (table) — Security attributes (EAR, ITAR, CUI, etc.) assignable to projects.

**`ProjectAttributeLink`** (table) — Many-to-many join between projects and attributes.

### Seed Data

The questionnaire seed data lives in `backend/seed/data.json`. Currently 8 questions across three subphases:

| Subphase | Questions | Types |
|----------|-----------|-------|
| General | Authorization Package Name, Control Set Version, Methodology, Entity | text, choose-one |
| Information System Details | Requested Authorization Type, Authorization Boundary Description | choose-one, text |
| Personnel | CLARA ID, Mission/Purpose | text |

Question IDs are designed to map directly to Archer field names for seamless submission.

### Migrations

The project uses lightweight migration scripts (not Alembic) for schema changes:

```bash
# Add owner_email column to existing project table
cd backend
python -m src.clarity.db.add_owner_email
```

---

## API Reference

Base URL: `http://localhost:4000`

Interactive docs: `http://localhost:4000/docs` (Swagger UI)

### Projects

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/project/` | Create a new project (auto-scoped to authenticated user) |
| `GET` | `/project/` | List user's projects (with optional filters) |
| `GET` | `/project/{project_id}` | Get a specific project |
| `PUT` | `/project/` | Update a project |
| `DELETE` | `/project/` | Delete project(s) by ID or title |
| `POST` | `/project/answer/create` | Save or update a question response |
| `POST` | `/project/attributes` | Assign attributes to a project |

### Questionnaires

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/questionnaire/` | Create a questionnaire |
| `GET` | `/questionnaire/` | Get questionnaire(s) with filters |
| `DELETE` | `/questionnaire/` | Delete a questionnaire (with referential integrity check) |
| `GET` | `/questionnaire/attributes` | Get attributes for a questionnaire |

### Archer GRC

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/archer/login` | Authenticate to Archer and get a session token |
| `POST` | `/archer/submit` | Submit an authorization package to Archer |

### Other

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/auth/` | Health check |
| `POST` | `/completions/chat_response` | AI chat (stub) |
| `POST` | `/completions/suggest_response` | AI suggestion (stub) |
| `POST` | `/review/project/{id}` | Run assessment (stub) |

---

## Frontend

### UI Flow

1. **Login** (`/login`) — RTX SSO button + dev bypass link. In dev mode, auto-redirects to `/clara`.

2. **Project List** (`/clara`) — "Your IRAMP/ATOs" table showing the user's projects. "+ Start a New IRAMP/ATO" button opens the creation wizard.

3. **Creation Wizard** (`/clara` modal) — Three-step stepper:
   - **Step 1: Project Details** — Title (required) + Description (250 char max)
   - **Step 2: Attributes** — Checkboxes: EAR, ITAR, CUI, Foreign National Access, Cloud, On-Prem, Collins Internal Data, Third-Party Data
   - **Step 3: Tags** — Freeform metadata tags

4. **Questionnaire** (`/clara/[projectId]`) — Left sidebar shows question navigation with status indicators (green = answered, red = current, gray = unanswered). Main panel renders the current question with the appropriate input type. Previous/Next buttons navigate the flow.

5. **Review** (`/clara/[projectId]#review`) — Summary table of all answers with status indicators. "Submit for Review" button triggers the Archer submission workflow.

### Key Composables

- **`useAuth()`** — Authentication state, user info, auth headers, login/logout methods. Adapts behavior based on `AUTH_MODE`.
- **`useApi()`** — Type-safe API client that auto-injects auth headers. All backend calls go through this.

### Styling

The frontend uses Tailwind CSS with RTX brand colors: dark header (#1a1a2e), red-800 accent for primary actions, clean white cards. shadcn-vue components are available but the core UI is built with Tailwind utilities for simplicity.

---

## Keycloak Configuration

### Auto-Import (Recommended)

The `keycloak/clarity-realm.json` file is mounted into the Keycloak container and imported on first boot via the `--import-realm` flag in `docker-compose.yaml`. This creates:

- **Realm:** `clarity`
- **Clients:** `nuxt-frontend` (confidential, OIDC), `clarity-backend` (bearer-only)
- **Roles:** `clarity-user`, `clarity-admin`
- **Test Users:**
  - `dev@clarity.local` / `dev123` (admin + user roles)
  - `testuser@clarity.local` / `test123` (user role only)

### Manual Setup

If the realm already exists or auto-import didn't run:

1. Access Keycloak Admin: http://localhost:8080/kc/admin (admin/admin)
2. Create realm `clarity`
3. Create client `nuxt-frontend` → Client authentication ON → Set redirect URIs to `http://localhost:3001/*`
4. Copy the client secret to `NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET` in `.env`
5. Create test users as needed

### Resetting Keycloak

To force a fresh import (destroys all data):

```bash
docker compose down -v
docker compose up -d
```

---

## Archer GRC Integration

The Archer integration is handled by `backend/src/clarity/services/archer_service.py`, an async client built with `httpx`.

### Capabilities

- **Authentication** — Login via username/password, session token management
- **Field Definitions** — Fetch field definitions for a given Archer level/module
- **Values Lists** — Retrieve picklist values for dropdown fields
- **Content Records** — Create, read content records with structured field data
- **Workflow Transitions** — Query and execute workflow state changes
- **Auth Package Submission** — High-level method that maps questionnaire responses to Archer fields

### Field Mapping

Question IDs in `seed/data.json` are designed to map directly to Archer field names in `archer_schema.py`:

| Question ID | Archer Field | Type |
|-------------|-------------|------|
| `authorization_package_name` | `auth_pkg_name` | Text |
| `control_set_version` | `control_set_version` | Values List |
| `methodology` | `methodology` | Values List |
| `entity` | `entity` | Values List |
| `requested_authorization_type` | `requested_auth_type` | Values List |
| `authorization_boundary_description` | `auth_boundary_desc` | Text |
| `clara_id` | `clara_id` | Text |
| `mission_purpose` | `mission_purpose` | Text |

---

## Deployment

### Local Development

See [Getting Started](#getting-started). All services run natively on Windows (backend + frontend) with Docker for infrastructure (Postgres + Keycloak).

### Production (AWS)

The production instance runs at `clarity.onertx.com` on an EC2 instance (`c32d1clarac7997`).

```bash
# Production repos on the server
/root/ART-clarity-api        # Backend
/root/ART-CLARA-Copilot      # Frontend

# Start/restart services (use plain docker, not docker compose)
docker restart clarity-api
docker restart clarity-keycloak
docker restart clarity-db
```

Nginx handles SSL termination and routing:
- `clarity.onertx.com` → Nuxt frontend (`:3000`)
- `sso.clarity.onertx.com` → Keycloak (`:8080`)
- `/be/*` → FastAPI backend (`:4000`)
- `/kc/*` → Keycloak (`:8080`)

---

## Development Workflow

### Running All Services

```bash
# Terminal 1: Docker (Postgres + Keycloak)
cd projects/clarity-rewrite
docker compose up -d

# Terminal 2: Backend
cd backend
source venv/Scripts/activate   # Windows
export SEED_DATA=true           # Only needed on first run or after DB reset
python -m uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload

# Terminal 3: Frontend
cd frontend
npx nuxt dev --port 3001
```

### Switching Auth Modes

```bash
# Dev mode (default) — no login, mock user
export AUTH_MODE=dev

# Keycloak mode — real OIDC flow
export AUTH_MODE=keycloak
```

Restart the backend after changing `AUTH_MODE`.

### Adding Questions

Edit `backend/seed/data.json` to add questions. Each question needs:
- `id` — Unique identifier (should map to Archer field name)
- `subphase` — Grouping for the sidebar (e.g., "General", "Stakeholders")
- `title` — Short label shown in the sidebar
- `text` — Full question text shown in the main panel
- `type` — One of: `Text`, `MultiChoice - single select`, `MultiChoice - multiple select`, `yes-no`
- `options` — Comma-separated values for choice questions, or `"none"` for text

Add edges to maintain the linear flow (each question's `sourceId` → next question's `targetId`).

After editing, restart the backend with `SEED_DATA=true` to re-seed.

### Known Issues

- **`SEED_DATA` must be exported manually** — `os.getenv` doesn't pick it up from `.env` reliably. Use `export SEED_DATA=true` before starting the backend.
- **Ctrl+C doesn't kill uvicorn in Git Bash** — Close the terminal window or use `taskkill /F /IM python.exe` in PowerShell.
- **`--legacy-peer-deps` required for npm install** — Some shadcn-vue peer dependencies conflict. Always use `npm install --legacy-peer-deps`.

---

## Troubleshooting

**Backend won't start — missing environment variables**
Pydantic can't find the `.env` file. Either copy `.env` into the `backend/` folder or export the variables:
```bash
cd projects/clarity-rewrite
export $(grep -v '^#' .env | xargs)
cd backend
python -m uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
```

**"Extra inputs are not permitted"**
The `.env` has variables that don't match `ClaritySettings` fields. Ensure `settings.py` has `extra="ignore"` in its `model_config`.

**UniqueViolation on project title**
Project titles must be unique. Use a different title or delete the existing project first.

**Keycloak client secret mismatch**
If Keycloak was reset (e.g., `docker compose down -v`), the client secret regenerates. Copy the new secret from Keycloak Admin → Clients → `nuxt-frontend` → Credentials → Client secret, and update `NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET` in `.env`.

**Frontend shows blank page or CORS errors**
Ensure the backend CORS config includes `http://localhost:3001` and the frontend's `NUXT_API_BASE` points to `http://localhost:4000`.

**Archer connection fails**
Archer endpoints are only accessible from the RTX corporate network. The service uses `verify=False` for SSL since the corporate CA isn't in the default trust store.

---

## Repository

- **Monorepo:** [GRCAA-Clarity](https://github-us.utc.com/us-persons-only/GRCAA-Clarity)
- **Path:** `projects/clarity-rewrite/`
- **Branch:** `main` (protected — changes via PR from feature branches)
- **Organization:** `us-persons-only` on `github-us.utc.com`

---

## License

Internal use only. RTX proprietary — no technical data permitted in this repository.
