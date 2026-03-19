#!/usr/bin/env bash
set -euo pipefail
#
# Script 6: Final wiring — updated api.py + .env additions
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Update api.py with auth mode logging ==="

cat > backend/src/clarity/api.py << 'APIEOF'
"""FastAPI application entry point."""
import logging
import os

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
)
from .core.settings import ClaritySettings

log = logging.getLogger(__name__)


async def init_app_state(app: FastAPI):
    """Lifespan handler: init DB, seed data on startup."""
    settings = ClaritySettings()
    log.info("AUTH_MODE = %s", settings.auth_mode)

    init_sql_tables(engine)

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
            "http://localhost:3000",
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
APIEOF

echo "  Updated backend/src/clarity/api.py"

echo ""
echo "=== Step 2: Ensure .env has all required vars ==="

# Append any missing vars to .env
ENV_ADDITIONS=""

grep -q "AUTH_MODE" .env 2>/dev/null || ENV_ADDITIONS+="
# Auth mode: 'dev' = mock user, 'keycloak' = real OIDC
AUTH_MODE=dev"

grep -q "CLARITY_KC_HOST" .env 2>/dev/null || ENV_ADDITIONS+="
CLARITY_KC_HOST=localhost"

grep -q "CLARITY_KC_PORT" .env 2>/dev/null || ENV_ADDITIONS+="
CLARITY_KC_PORT=8080"

if [ -n "$ENV_ADDITIONS" ]; then
    echo "$ENV_ADDITIONS" >> .env
    echo "  Added missing vars to .env"
else
    echo "  .env already has all required vars"
fi

# Sync to backend/.env if it exists
if [ -f backend/.env ]; then
    cp .env backend/.env
    echo "  Synced .env → backend/.env"
fi

echo ""
echo "=== Step 3: Update .env.example ==="

cat > .env.example << 'EXEOF'
# === Auth Mode ===
# 'dev' = mock user (dev@clarity.local), no login required
# 'keycloak' = real OIDC flow via Keycloak
AUTH_MODE=dev

# === PostgreSQL ===
CLARITY_SQL_DB=clarity
CLARITY_SQL_USER=clarity
CLARITY_SQL_PASSWORD=clarity
CLARITY_SQL_HOST=localhost
CLARITY_SQL_PORT=5432

# === Keycloak ===
CLARITY_KC_HOST=localhost
CLARITY_KC_PORT=8080
CLARITY_KC_REALM=clarity
CLARITY_KC_ADMIN=admin
CLARITY_KC_ADMIN_PASSWORD=admin
CLARITY_KC_MGMT_CLIENT_SECRET=

# === Corporate OIDC (RTX SSO — production only) ===
COMP_OIDC_CLIENT_ID=
COMP_OIDC_CLIENT_SECRET=
CORP_OIDC_DISCOVERY_ENDPOINT=
CORP_OIDC_ISSUER=
CORP_OIDC_AUTHORIZATION_URL=
CORP_OIDC_TOKEN_URL=
CORP_OIDC_JWKS_URL=
CORP_OIDC_USER_INFO_URL=

# === RTX Model Hub (placeholder) ===
META_OPENAI_URL=
META_OPENAI_KEY=

# === Archer GRC ===
ARCHER_USERNAME=
ARCHER_PASSWORD=
ARCHER_INSTANCE_NAME=ArcherPOC
ARCHER_BASE_URI=https://archerpoc.corp.ray.com
ARCHER_SOAP_SEARCH_URI=
ARCHER_SOAP_GENERAL_URI=
MAPPING_REPORT=

# === Seeding ===
SEED_DATA=true

# === Frontend (Nuxt) ===
NUXT_API_BASE=http://localhost:4000
NUXT_OAUTH_KEYCLOAK_REALM=clarity
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=nuxt-frontend
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=
NUXT_OAUTH_KEYCLOAK_SERVER_URL=http://localhost:8080
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback
NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback
NUXT_SESSION_PASSWORD=change-this-to-a-random-string-at-least-32-chars
NODE_TLS_REJECT_UNAUTHORIZED=0
EXEOF

echo "  Updated .env.example"

echo ""
echo "================================================================"
echo "  ALL SCRIPTS COMPLETE — Summary"
echo "================================================================"
echo ""
echo "Files created/modified:"
echo "  keycloak/clarity-realm.json        — Realm auto-import config"
echo "  docker-compose.yaml                — Keycloak --import-realm"
echo "  backend/src/clarity/core/settings.py — AUTH_MODE field added"
echo "  backend/src/clarity/core/auth.py   — Auth dependency (dev/keycloak)"
echo "  backend/src/clarity/api.py         — Updated lifespan"
echo "  backend/src/clarity/routes/project_routes.py — User-scoped CRUD"
echo "  backend/src/clarity/services/project_services.py — Simplified"
echo "  backend/src/clarity/services/archer_service.py — Clean rewrite"
echo "  backend/src/clarity/db/add_owner_email.py — Migration script"
echo "  frontend/composables/useAuth.ts    — Auth composable"
echo "  frontend/composables/useApi.ts     — API client w/ auth headers"
echo "  frontend/middleware/auth.ts        — Route guard"
echo "  .env.example                       — Updated template"
echo ""
echo "Manual steps remaining:"
echo "  1. Add 'owner_email' field to Project model in questionnaire.py"
echo "     (see backend/src/clarity/models/_patch_instructions.md)"
echo ""
echo "  2. Apply nuxt.config.ts patch"
echo "     (see frontend/_nuxt_config_patch.md)"
echo ""
echo "  3. Install PyJWT:  pip install PyJWT[crypto] --break-system-packages"
echo ""
echo "  4. Run migration:  cd backend && python -m src.clarity.db.add_owner_email"
echo ""
echo "  5. Recreate Docker volumes for Keycloak realm import:"
echo "     docker compose down -v && docker compose up -d"
echo ""
echo "  6. Restart backend:  export SEED_DATA=true && py -m uvicorn ..."
echo ""
echo "Test accounts (auto-created by Keycloak):"
echo "  dev@clarity.local / dev123        (admin + user roles)"
echo "  testuser@clarity.local / test123  (user role only)"
