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
11. [Questionnaire System](#questionnaire-system)
12. [Keycloak Configuration](#keycloak-configuration)
13. [Multi-User Support](#multi-user-support)
14. [Archer GRC Integration](#archer-grc-integration)
15. [Deployment](#deployment)
16. [Development Workflow](#development-workflow)
17. [Troubleshooting](#troubleshooting)

---

## Overview

Clarity is a full-stack application that replaces the manual IRAMP authorization process with a structured, questionnaire-driven workflow. It supports RTX business units (Collins Aerospace, Pratt & Whitney, Raytheon, Corporate) in managing information system authorizations.

### What It Does

1. **Project Creation** — 3-step wizard (Project Details, Attributes, Tags)
2. **Questionnaire Flow** — Guided questions organized by subphase with text, single-select, multi-select, and key-value table inputs
3. **Hardware Entry** — Dynamic table capturing hardware inventory (Name, IP, Hardware Type, Business Unit, MAC Address)
4. **Review & Submit** — Summary view with answer status before Archer submission
5. **Archer GRC Submission** — Maps responses to Archer field definitions via REST API

### Key Concepts

- **IRAMP** — RTX framework for categorizing systems by risk (LOE A through DFARS) per NIST 800-37
- **ATO** — Authorization to Operate granted after security assessment
- **LOE** — Level of Effort tiers: A (20 controls), B (38), C (56), D (70), DFARS (110)

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Nuxt 3 UI     │────▶│  FastAPI Backend  │────▶│   PostgreSQL     │
│   Port :3000    │     │   Port :4000      │     │   Port :5432     │
└─────────────────┘     └──────────────────┘     └──────────────────┘
        │                       │
        │ OIDC                  │ JWT Validation
        ▼                       ▼
┌─────────────────┐     ┌──────────────────┐
│  Keycloak SSO   │     │  RSA Archer GRC  │
│  (Local or      │     │  (Corp Network)  │
│   Enterprise)   │     └──────────────────┘
└─────────────────┘
```

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | Nuxt 3 (Vue 3 + TypeScript) | 3.x |
| UI | Tailwind CSS + shadcn-vue | 4.x |
| Auth (Frontend) | nuxt-auth-utils (OIDC) | latest |
| Backend | FastAPI (Python) | 0.115+ |
| ORM | SQLModel (SQLAlchemy 2.0) | 0.0.22+ |
| Database | PostgreSQL | 17 |
| Identity Provider | Keycloak | 26.2.1 |
| JWT | PyJWT[crypto] | 2.9+ |
| HTTP Client | httpx (async) | 0.27+ |
| GRC | RSA Archer (REST + SOAP) | Enterprise |

---

## Getting Started

### Prerequisites

- Python 3.11+, Node.js 18+, Docker Desktop, Git Bash (Windows)

### Quick Start

```bash
git clone https://github-us.utc.com/us-persons-only/GRCAA-Clarity.git
cd GRCAA-Clarity/projects/clarity-rewrite

cp .env.example .env && cp .env backend/.env
docker compose up -d

# Backend (terminal 1)
cd backend && python -m venv venv && source venv/Scripts/activate
pip install -r requirements.txt && pip install PyJWT[crypto]
export SEED_DATA=true
python -m uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload

# Frontend (terminal 2)
cd frontend && npm install --legacy-peer-deps
npx nuxt dev --port 3000
```

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:4000/docs |
| Keycloak Admin | http://localhost:8080/kc/admin (admin/admin) |

---

## Environment Variables

### Root `.env`

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTH_MODE` | `dev` | `dev`, `keycloak`, or `keycloak-enterprise` |
| `SEED_DATA` | `false` | Seed questionnaire on startup |
| `CLARITY_SQL_*` | `clarity` | PostgreSQL connection |
| `CLARITY_KC_*` | `localhost:8080` | Local Keycloak |
| `ENTERPRISE_KC_SERVER_URL` | *(enterprise URL)* | Enterprise Keycloak base URL |
| `ENTERPRISE_KC_REALM` | `DE-Toolchain` | Enterprise realm |
| `ENTERPRISE_KC_CLIENT_ID` | `clarity-dev` | Enterprise client |
| `ENTERPRISE_KC_CLIENT_SECRET` | *(required)* | Enterprise secret |
| `ARCHER_*` | *(required)* | Archer GRC credentials |

### Frontend `.env`

| Variable | Description |
|----------|-------------|
| `NUXT_SESSION_PASSWORD` | Session encryption (32+ chars) |
| `NUXT_PUBLIC_AUTH_MODE` | `dev`, `keycloak`, or `keycloak-enterprise` |
| `NUXT_OAUTH_KEYCLOAK_REALM` | Realm name |
| `NUXT_OAUTH_KEYCLOAK_CLIENT_ID` | OIDC client ID |
| `NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET` | OIDC client secret |
| `NUXT_OAUTH_KEYCLOAK_SERVER_URL` | Keycloak URL (include `/kc` for local) |
| `NUXT_OAUTH_KEYCLOAK_REDIRECT_URL` | Callback URL |

---

## Authentication

### Three Auth Modes

| Mode | `AUTH_MODE` | Description |
|------|-----------|-------------|
| Dev | `dev` | Mock users, no login, X-Dev-User header switching |
| Local KC | `keycloak` | Docker Keycloak, `clarity` realm, OIDC flow |
| Enterprise | `keycloak-enterprise` | RTX shared Keycloak, `DE-Toolchain` realm |

### Dev Mode Users

| Email | Name | Roles |
|-------|------|-------|
| `dev@clarity.local` | Dev User | clarity-user, clarity-admin |
| `alice@clarity.local` | Alice Engineer | clarity-user |
| `bob@clarity.local` | Bob Manager | clarity-user, clarity-admin |

Switch users via header: `curl -H "X-Dev-User: alice@clarity.local" localhost:4000/auth/me`

### Local Keycloak Test Accounts

| Username | Password | Roles |
|----------|----------|-------|
| `dev@clarity.local` | `dev123` | clarity-user, clarity-admin |
| `testuser@clarity.local` | `test123` | clarity-user |

### Enterprise Keycloak

| Setting | Value |
|---------|-------|
| Server | `https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com` |
| Realm | `DE-Toolchain` |
| Client | `clarity-dev` |
| Contact | Christopher Michael |

Required claims: email, given_name, family_name, preferred_username, realm_access.roles

### Frontend `.env` Examples

**Local Keycloak:**
```env
NUXT_PUBLIC_AUTH_MODE=keycloak
NUXT_OAUTH_KEYCLOAK_REALM=clarity
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=nuxt-frontend
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=nEMT2PXHmL9shdQPP8UpQLHeHfrGX1tF
NUXT_OAUTH_KEYCLOAK_SERVER_URL=http://localhost:8080/kc
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/keycloak
```

**Enterprise Keycloak:**
```env
NUXT_PUBLIC_AUTH_MODE=keycloak-enterprise
NUXT_OAUTH_KEYCLOAK_REALM=DE-Toolchain
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=clarity-dev
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=YqkwlPJ01GlyxZ2NbFrKOq2Mlx3u94x1
NUXT_OAUTH_KEYCLOAK_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/keycloak
```

### User Scoping

All project operations filter by `owner_email` extracted from JWT (keycloak) or X-Dev-User header (dev). Each user sees only their own projects.

---

## Database

### Connection Pooling

- `pool_size=5`, `max_overflow=10`, `pool_pre_ping=True`, `pool_recycle=300`
- Session-per-request isolation with automatic rollback

### Data Model

- **Questionnaire** — Versioned, contains phases with questions and flow edges
- **Project** — User-scoped (`owner_email`), stores responses as JSONB
- **Attribute** — Security attributes (EAR, ITAR, CUI) linked to projects
- **Question types** — text, choose-one, choose-many, key-value-table

### Seed Data (10 questions)

| # | Question | Type |
|---|----------|------|
| Q1 | Authorization Package Name | text |
| Q2 | Clara ID | text |
| Q3 | Entity | choose-one |
| Q4 | RTX Business | choose-one (Corporate, Collins, P&W, Raytheon) |
| Q5 | Mission/Purpose | text |
| Q6 | Information Classification | choose-many |
| Q7 | Connectivity | choose-one |
| Q8 | Authorization Boundary Description | text |
| Q9 | System Administrator (SA) | text |
| Q10 | Hardware Entry | key-value-table (5 columns) |

---

## API Reference

Base: `http://localhost:4000` | Docs: `http://localhost:4000/docs`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/auth/` | Health check |
| `GET` | `/auth/me` | Current user info |
| `POST` | `/project/` | Create project |
| `GET` | `/project/` | List user's projects |
| `GET` | `/project/{id}` | Get project |
| `PUT` | `/project/` | Update project |
| `DELETE` | `/project/` | Delete project(s) |
| `POST` | `/project/answer/create` | Save answer |
| `POST` | `/project/attributes` | Assign attributes |
| `GET/POST/DELETE` | `/questionnaire/` | Questionnaire CRUD |
| `POST` | `/completions/chat_response` | AI chat (LLM) |
| `POST` | `/completions/suggest_response` | AI suggest (LLM) |
| `POST` | `/archer/login` | Archer auth |
| `POST` | `/archer/submit` | Submit to Archer |

---

## Frontend

### UI Flow

Login → Home → Project List → Creation Wizard (3 steps) → Questionnaire (10 questions with sidebar nav) → Hardware Entry (KV table) → Review → Submit

### Key Components

| Component | Purpose |
|-----------|---------|
| `KVTableInput.vue` | Dynamic table with text/select columns, add/remove rows |
| `DevUserSwitcher.vue` | Dev mode user switching dropdown |

### Key Composables

| Composable | Purpose |
|------------|---------|
| `useAuth()` | Auth state, user info, headers — adapts to AUTH_MODE |
| `useApi()` | API client with auto-injected auth + X-Dev-User headers |

### Server Routes

| Route | Purpose |
|-------|---------|
| `/auth/keycloak` | OIDC callback — exchanges code for tokens, creates session |

---

## Keycloak Configuration

### Local (Auto-Import)

`keycloak/clarity-realm.json` is mounted into Docker and imported on first boot via `--import-realm`.

Creates: `clarity` realm, `nuxt-frontend` client, `clarity-backend` client, `clarity-user`/`clarity-admin` roles, two test users.

### Reset Keycloak

```bash
docker compose down -v && docker compose up -d
```

### Enterprise

Managed by Christopher Michael at `keycloak-npd.c32p1-colk8s.wg1.aws.ray.com`. Contact for redirect URI changes, US Persons attribute, SAML/OIDC issues.

---

## Multi-User Support

- Connection pooling for concurrent access
- `owner_email` on every project, auto-set from auth context
- Dev mode: 3 built-in users, switchable via dropdown or X-Dev-User header
- Keycloak mode: JWT email determines ownership
- `GET /auth/me` returns current user info

---

## Archer GRC Integration

Async client using httpx with json.dumps (no f-string JSON). Supports: login, field definitions, values lists, content record CRUD, workflow transitions, auth package submission.

### Hardware → Archer Mapping

| Column | Archer Field |
|--------|-------------|
| name | Hardware.name |
| ip_address | Hardware.ip_address |
| hardware_type | Hardware.hardware_type |
| business | Hardware.business_unit |
| mac_address | Hardware.mac_address |

---

## Deployment

### Local: Native backend/frontend + Docker for Postgres/Keycloak
### Production: `clarity.onertx.com` — Nginx SSL termination, Docker services

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Missing env vars | `cp .env backend/.env` |
| Seed not loading | Check `manager.py` seed path (4x `.parent`) |
| 403 on API | Check AUTH_MODE matches between backend/frontend |
| 422 on create project | Check `project_schema.py` — `user_id` needs default |
| Keycloak "Resource not found" | Add `/kc` to server URL |
| OIDC callback 404 | Ensure `server/routes/auth/keycloak.get.ts` exists |
| Frontend ignores AUTH_MODE | Use `NUXT_PUBLIC_AUTH_MODE` in `frontend/.env`, clear `.nuxt` cache |
| Can't push to GitHub | Connect VPN, re-auth: `gh auth login --hostname github-us.utc.com` |
| SAML error on enterprise KC | Christopher needs to fix SAML subject mapping |
| npm peer deps | Use `--legacy-peer-deps` |

---

## Repository

- **Monorepo:** [GRCAA-Clarity](https://github-us.utc.com/us-persons-only/GRCAA-Clarity)
- **Path:** `projects/clarity-rewrite/`
- **Branch:** `main` (protected), work on feature branches
- **Organization:** `us-persons-only` on `github-us.utc.com`

---

## License

Internal use only. RTX proprietary — no technical data permitted.
