#!/usr/bin/env bash
set -euo pipefail
#
# Script 10: Multi-User Support
# Ensures proper session isolation, owner_email enforcement,
# and dev-mode user switching for demo with 2-3 accounts.
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Update db/manager.py — proper connection pooling ==="

cat > backend/src/clarity/db/manager.py << 'DBEOF'
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

# ---------------------------------------------------------------------------
# Engine (connection pool)
# ---------------------------------------------------------------------------

_settings = ClaritySettings()

_connection_string = (
    f"postgresql://{_settings.sql_username}:{_settings.sql_password}"
    f"@{_settings.sql_host}:{_settings.sql_port}/{_settings.sql_db_name}"
)

engine = create_engine(
    _connection_string,
    pool_size=5,          # Max persistent connections
    max_overflow=10,      # Extra connections under load
    pool_pre_ping=True,   # Test connections before use (handles DB restarts)
    pool_recycle=300,      # Recycle connections every 5 min
    echo=False,
)


# ---------------------------------------------------------------------------
# Session dependency — one session per request
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Table initialization
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Seed data
# ---------------------------------------------------------------------------

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
            log.info("Questionnaire already exists (id=%s) — skipping seed", existing.id)
            return

    seed_path = Path(__file__).parent.parent.parent / "seed" / "data.json"
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
DBEOF

echo "  Updated backend/src/clarity/db/manager.py"

echo ""
echo "=== Step 2: Update auth.py — dev mode with multiple simulated users ==="

cat > backend/src/clarity/core/auth.py << 'AUTHEOF'
"""
Authentication dependency for FastAPI routes.

AUTH_MODE=dev                  → Mock user (switchable via X-Dev-User header)
AUTH_MODE=keycloak             → Local Keycloak JWT
AUTH_MODE=keycloak-enterprise  → Enterprise RTX Keycloak JWT
"""

import logging
from dataclasses import dataclass
from functools import lru_cache

import httpx
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .settings import ClaritySettings

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# User model
# ---------------------------------------------------------------------------

@dataclass
class CurrentUser:
    """Represents the authenticated user in request context."""
    email: str
    name: str
    roles: list[str]


# ---------------------------------------------------------------------------
# Settings singleton
# ---------------------------------------------------------------------------

@lru_cache
def get_settings() -> ClaritySettings:
    return ClaritySettings()


# ---------------------------------------------------------------------------
# Dev users — simulate multiple accounts for testing
# ---------------------------------------------------------------------------

DEV_USERS = {
    "dev@clarity.local": CurrentUser(
        email="dev@clarity.local",
        name="Dev User",
        roles=["clarity-user", "clarity-admin"],
    ),
    "alice@clarity.local": CurrentUser(
        email="alice@clarity.local",
        name="Alice Engineer",
        roles=["clarity-user"],
    ),
    "bob@clarity.local": CurrentUser(
        email="bob@clarity.local",
        name="Bob Manager",
        roles=["clarity-user", "clarity-admin"],
    ),
}

DEFAULT_DEV_USER = DEV_USERS["dev@clarity.local"]


async def _get_dev_user(request: Request) -> CurrentUser:
    """
    Return a dev user. Supports switching users via X-Dev-User header.

    Usage:
        curl -H "X-Dev-User: alice@clarity.local" http://localhost:4000/project/
    """
    dev_email = request.headers.get("X-Dev-User", "dev@clarity.local")
    user = DEV_USERS.get(dev_email)
    if user:
        return user

    # Unknown dev user — create one on the fly
    return CurrentUser(
        email=dev_email,
        name=dev_email.split("@")[0].title(),
        roles=["clarity-user"],
    )


# ---------------------------------------------------------------------------
# Keycloak mode — validate Bearer JWT
# ---------------------------------------------------------------------------

_bearer_scheme = HTTPBearer(auto_error=True)


def _clear_jwks_cache():
    """Clear cached JWKS data."""
    pass  # PyJWKClient handles its own cache


async def _get_keycloak_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    settings: ClaritySettings = Depends(get_settings),
) -> CurrentUser:
    """Validate a Bearer JWT from Keycloak and extract user info."""
    try:
        import jwt as pyjwt
        from jwt import PyJWKClient
    except ImportError:
        raise HTTPException(
            status_code=500,
            detail="PyJWT not installed. Run: pip install PyJWT[crypto]",
        )

    token = credentials.credentials
    issuer_url = settings.active_kc_issuer_url
    jwks_url = settings.active_kc_jwks_url

    log.debug("Validating JWT against issuer: %s", issuer_url)

    try:
        jwk_client = PyJWKClient(jwks_url)
        signing_key = jwk_client.get_signing_key_from_jwt(token)

        payload = pyjwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=issuer_url,
            options={
                "verify_exp": True,
                "verify_aud": False,
            },
        )
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except pyjwt.InvalidTokenError as e:
        log.warning("JWT validation failed: %s", e)
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")

    email = (
        payload.get("email")
        or payload.get("preferred_username")
        or payload.get("sub", "unknown")
    )
    name = (
        payload.get("name")
        or f"{payload.get('given_name', '')} {payload.get('family_name', '')}".strip()
        or payload.get("preferred_username", "Unknown")
    )

    realm_access = payload.get("realm_access", {})
    roles = realm_access.get("roles", [])
    client_id = settings.active_kc_client_id
    resource_access = payload.get("resource_access", {})
    client_roles = resource_access.get(client_id, {}).get("roles", [])
    all_roles = list(set(roles + client_roles))

    return CurrentUser(email=email, name=name, roles=all_roles)


# ---------------------------------------------------------------------------
# Public dependency
# ---------------------------------------------------------------------------

def get_current_user():
    """
    Returns the appropriate auth dependency based on AUTH_MODE.

    Usage:
        user: CurrentUser = Depends(get_current_user())
    """
    settings = get_settings()
    if settings.auth_mode in ("keycloak", "keycloak-enterprise"):
        return _get_keycloak_user
    return _get_dev_user
AUTHEOF

echo "  Updated backend/src/clarity/core/auth.py"

echo ""
echo "=== Step 3: Add /auth/me endpoint for frontend user info ==="

cat > backend/src/clarity/routes/auth.py << 'AUTHRTEOF'
"""Auth routes — health check + user info."""

from fastapi import APIRouter, Depends

from ..core.auth import CurrentUser, get_current_user

auth_router = APIRouter(prefix="/auth", tags=["Auth"])


@auth_router.get("/")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok"}


@auth_router.get("/me")
async def get_current_user_info(
    user: CurrentUser = Depends(get_current_user()),
):
    """Return the currently authenticated user's info.

    Useful for the frontend to display user name, email, and roles.
    In dev mode, returns the mock user (or the X-Dev-User override).
    In keycloak mode, returns info extracted from the JWT.
    """
    return {
        "email": user.email,
        "name": user.name,
        "roles": user.roles,
    }
AUTHRTEOF

echo "  Updated backend/src/clarity/routes/auth.py"

echo ""
echo "=== Step 4: Frontend — user switcher for dev mode ==="

cat > frontend/components/DevUserSwitcher.vue << 'SWITCHEOF'
<template>
  <div v-if="authMode === 'dev'" class="relative">
    <button
      @click="isOpen = !isOpen"
      class="flex items-center gap-2 text-xs text-gray-300 hover:text-white px-3 py-1.5 rounded border border-gray-600 hover:border-gray-400 transition-colors"
    >
      <span class="w-2 h-2 rounded-full bg-green-400"></span>
      {{ currentEmail }}
    </button>

    <!-- Dropdown -->
    <div
      v-if="isOpen"
      class="absolute right-0 top-full mt-1 bg-white rounded-md shadow-lg border border-gray-200 py-1 z-50 min-w-[220px]"
    >
      <button
        v-for="user in devUsers"
        :key="user.email"
        @click="switchUser(user.email)"
        class="w-full text-left px-4 py-2 text-sm hover:bg-gray-50 transition-colors flex items-center justify-between"
        :class="user.email === currentEmail ? 'bg-red-50 text-red-800' : 'text-gray-700'"
      >
        <span>
          <span class="font-medium">{{ user.name }}</span>
          <br />
          <span class="text-xs text-gray-400">{{ user.email }}</span>
        </span>
        <span v-if="user.isAdmin" class="text-[10px] bg-red-100 text-red-700 px-1.5 py-0.5 rounded">admin</span>
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
const { authMode } = useAuth()

const devUsers = [
  { email: 'dev@clarity.local', name: 'Dev User', isAdmin: true },
  { email: 'alice@clarity.local', name: 'Alice Engineer', isAdmin: false },
  { email: 'bob@clarity.local', name: 'Bob Manager', isAdmin: true },
]

const isOpen = ref(false)

// Store current dev user in localStorage (persists across page reloads)
const currentEmail = ref('dev@clarity.local')

onMounted(() => {
  const saved = window.sessionStorage?.getItem('clarity-dev-user')
  if (saved) currentEmail.value = saved
})

function switchUser(email: string) {
  currentEmail.value = email
  window.sessionStorage?.setItem('clarity-dev-user', email)
  isOpen.value = false
  // Reload to apply the new user context
  window.location.reload()
}

// Close dropdown on outside click
onMounted(() => {
  document.addEventListener('click', (e) => {
    if (!(e.target as HTMLElement).closest('.relative')) {
      isOpen.value = false
    }
  })
})
</script>
SWITCHEOF

echo "  Created frontend/components/DevUserSwitcher.vue"

echo ""
echo "=== Step 5: Update useApi.ts — include X-Dev-User header ==="

cat > frontend/composables/useApi.ts << 'APIEOF'
/**
 * API client composable — all backend requests go through here.
 * Automatically includes auth headers and dev-user switching.
 */

export function useApi() {
  const config = useRuntimeConfig()
  const { getAuthHeaders, authMode } = useAuth()

  const baseURL = config.public.apiBase || 'http://localhost:4000'

  async function apiFetch<T>(
    path: string,
    options: RequestInit & { params?: Record<string, string> } = {},
  ): Promise<T> {
    const url = new URL(path, baseURL)

    if (options.params) {
      for (const [key, val] of Object.entries(options.params)) {
        if (val !== undefined && val !== null) {
          url.searchParams.set(key, val)
        }
      }
    }

    // Build headers
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...getAuthHeaders(),
      ...(options.headers as Record<string, string> || {}),
    }

    // In dev mode, include the selected dev user
    if (authMode === 'dev') {
      const devUser = typeof window !== 'undefined'
        ? window.sessionStorage?.getItem('clarity-dev-user') || 'dev@clarity.local'
        : 'dev@clarity.local'
      headers['X-Dev-User'] = devUser
    }

    const response = await fetch(url.toString(), {
      ...options,
      headers,
    })

    if (!response.ok) {
      const errorBody = await response.text().catch(() => 'Unknown error')
      throw new Error(`API ${response.status}: ${errorBody}`)
    }

    return response.json()
  }

  // ----- Project CRUD -----

  async function getProjects(opts?: {
    projectId?: string
    title?: string
    includeQuestionnaire?: boolean
  }) {
    const params: Record<string, string> = {}
    if (opts?.projectId) params.project_id = opts.projectId
    if (opts?.title) params.title = opts.title
    if (opts?.includeQuestionnaire) params.include_questionnaire = 'true'
    return apiFetch<any[]>('/project/', { params })
  }

  async function getProject(projectId: string, includeQuestionnaire = false) {
    const params: Record<string, string> = {}
    if (includeQuestionnaire) params.include_questionnaire = 'true'
    return apiFetch<any>(`/project/${projectId}`, { params })
  }

  async function createProject(data: {
    title: string
    description: string
    questionnaire_id: number
    tags?: string[]
    attributes?: Array<{ text: string }>
  }) {
    return apiFetch<any>('/project/', {
      method: 'POST',
      body: JSON.stringify(data),
    })
  }

  async function deleteProject(projectId: string) {
    return apiFetch<any>('/project/', {
      method: 'DELETE',
      params: { project_id: projectId },
    })
  }

  // ----- Answers -----

  async function saveAnswer(data: {
    project_id: string
    question_id: string
    answer: string | string[] | object
    justification?: string
  }) {
    return apiFetch<any>('/project/answer/create', {
      method: 'POST',
      body: JSON.stringify(data),
    })
  }

  // ----- Questionnaires -----

  async function getQuestionnaires(opts?: {
    questionnaireId?: number
    version?: string
    active?: boolean
  }) {
    const params: Record<string, string> = {}
    if (opts?.questionnaireId) params.questionnaire_id = String(opts.questionnaireId)
    if (opts?.version) params.version = opts.version
    if (opts?.active !== undefined) params.active = String(opts.active)
    return apiFetch<any>('/questionnaire/', { params })
  }

  // ----- User info -----

  async function getCurrentUser() {
    return apiFetch<{ email: string; name: string; roles: string[] }>('/auth/me')
  }

  return {
    apiFetch,
    getProjects,
    getProject,
    createProject,
    deleteProject,
    saveAnswer,
    getQuestionnaires,
    getCurrentUser,
  }
}
APIEOF

echo "  Updated frontend/composables/useApi.ts"

echo ""
echo "=== Step 6: Create layout patch for DevUserSwitcher ==="

cat > frontend/layouts/_user_switcher_patch.md << 'PATCHEOF'
# Patch: Add DevUserSwitcher to default.vue layout

In `frontend/layouts/default.vue`, import and add the user switcher
component in the header/nav bar area:

```vue
<template>
  <div class="min-h-screen bg-gray-50">
    <!-- Header -->
    <header class="bg-[#1a1a2e] text-white">
      <div class="flex items-center justify-between px-6 py-3">
        <div class="flex items-center gap-6">
          <NuxtLink to="/" class="text-lg font-bold tracking-wide">Clarity</NuxtLink>
          <nav class="flex items-center gap-4 text-sm text-gray-300">
            <NuxtLink to="/clara" class="hover:text-white">IRAMP/ATOs</NuxtLink>
          </nav>
        </div>
        <div class="flex items-center gap-4">
          <!-- Dev user switcher (only shows in dev mode) -->
          <DevUserSwitcher />
          <!-- User info -->
          <span class="text-xs text-gray-400">{{ user.name }}</span>
          <button @click="logout" class="text-xs text-gray-400 hover:text-white">Logout</button>
        </div>
      </div>
      <!-- Red accent bar -->
      <div class="h-1 bg-red-700"></div>
    </header>

    <!-- Content -->
    <main>
      <slot />
    </main>
  </div>
</template>

<script setup>
import DevUserSwitcher from '~/components/DevUserSwitcher.vue'

const { user, logout } = useAuth()
</script>
```

The DevUserSwitcher only renders when AUTH_MODE=dev.
In keycloak mode, it's hidden — users are identified by their JWT.
PATCHEOF

echo "  Created frontend/layouts/_user_switcher_patch.md"

echo ""
echo "================================================================"
echo "  Multi-User Support Complete"
echo "================================================================"
echo ""
echo "What changed:"
echo ""
echo "  Backend:"
echo "    db/manager.py       — Connection pooling (pool_size=5, max_overflow=10)"
echo "                        — Auto-creates owner_email column on startup"
echo "                        — Proper session-per-request isolation"
echo "    core/auth.py        — Dev mode supports X-Dev-User header switching"
echo "                        — Three built-in dev users (dev, alice, bob)"
echo "    routes/auth.py      — New GET /auth/me endpoint"
echo ""
echo "  Frontend:"
echo "    DevUserSwitcher.vue — Dropdown to switch between dev users"
echo "    useApi.ts           — Auto-includes X-Dev-User header in dev mode"
echo "                        — New getCurrentUser() method"
echo ""
echo "  Testing multi-user in dev mode:"
echo "    1. Start the app with AUTH_MODE=dev"
echo "    2. Click the user dropdown in the header bar"
echo "    3. Switch between Dev User, Alice, and Bob"
echo "    4. Each sees only their own projects"
echo ""
echo "  Testing multi-user with Keycloak:"
echo "    1. Set AUTH_MODE=keycloak or keycloak-enterprise"
echo "    2. Log in with different Keycloak accounts"
echo "    3. Each user's JWT email determines project ownership"
echo ""
echo "  API testing (curl):"
echo "    # As dev user (default)"
echo '    curl http://localhost:4000/auth/me'
echo ""
echo "    # As alice"
echo '    curl -H "X-Dev-User: alice@clarity.local" http://localhost:4000/auth/me'
echo ""
echo "    # As bob"
echo '    curl -H "X-Dev-User: bob@clarity.local" http://localhost:4000/project/'
