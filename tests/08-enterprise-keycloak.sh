#!/usr/bin/env bash
set -euo pipefail
#
# Script 8: Three-way AUTH_MODE — dev | keycloak | keycloak-enterprise
# Supports local Keycloak AND RTX enterprise Keycloak via env vars.
# Run from: ~/desktop/repos/clarity-rewrite (or GRCAA-Clarity/projects/clarity-rewrite)
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Update settings.py — add enterprise Keycloak fields ==="

cat > backend/src/clarity/core/settings.py << 'SETTINGSEOF'
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class ClaritySettings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        populate_by_name=True,
        extra="ignore",
    )

    # --- Auth Mode ---
    # 'dev'                  = mock user bypass (dev@clarity.local)
    # 'keycloak'             = local Keycloak instance
    # 'keycloak-enterprise'  = shared RTX enterprise Keycloak
    auth_mode: str = Field(alias="AUTH_MODE", default="dev")

    # --- Local Keycloak ---
    keycloak_host: str = Field(alias="CLARITY_KC_HOST", default="localhost")
    keycloak_port: int = Field(alias="CLARITY_KC_PORT", default=8080)
    keycloak_realm: str = Field(alias="CLARITY_KC_REALM", default="clarity")
    keycloak_client_secret: str = Field(alias="CLARITY_KC_MGMT_CLIENT_SECRET", default="")
    oidc_client_id: str = Field(alias="COMP_OIDC_CLIENT_ID", default="")
    oidc_client_secret: str = Field(alias="COMP_OIDC_CLIENT_SECRET", default="")

    # --- Enterprise Keycloak (RTX shared instance) ---
    enterprise_kc_server_url: str = Field(
        alias="ENTERPRISE_KC_SERVER_URL",
        default="https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com",
    )
    enterprise_kc_realm: str = Field(alias="ENTERPRISE_KC_REALM", default="DE-Toolchain")
    enterprise_kc_client_id: str = Field(alias="ENTERPRISE_KC_CLIENT_ID", default="clarity-dev")
    enterprise_kc_client_secret: str = Field(
        alias="ENTERPRISE_KC_CLIENT_SECRET", default=""
    )

    # --- PostgreSQL ---
    sql_username: str = Field(alias="CLARITY_SQL_USER", default="clarity")
    sql_password: str = Field(alias="CLARITY_SQL_PASSWORD", default="clarity")
    sql_host: str = Field(alias="CLARITY_SQL_HOST", default="localhost")
    sql_port: int = Field(alias="CLARITY_SQL_PORT", default=5432)
    sql_db_name: str = Field(alias="CLARITY_SQL_DB", default="clarity")

    # --- RTX Model Hub Gateway ---
    meta_openai_uri: str = Field(alias="META_OPENAI_URL", default="")
    meta_openai_key: str = Field(alias="META_OPENAI_KEY", default="")

    # --- Archer GRC ---
    archer_username: str = Field(alias="ARCHER_USERNAME", default="")
    archer_password: str = Field(alias="ARCHER_PASSWORD", default="")
    archer_instance_name: str = Field(alias="ARCHER_INSTANCE_NAME", default="ArcherRTX PROD")
    archer_base_uri: str = Field(alias="ARCHER_BASE_URI", default="https://archergrc.corp.ray.com")
    soap_search_uri: str = Field(alias="ARCHER_SOAP_SEARCH_URI", default="")
    soap_general_uri: str = Field(alias="ARCHER_SOAP_GENERAL_URI", default="")
    mapping_report: str = Field(alias="MAPPING_REPORT", default="")

    # --- Computed Keycloak URLs ---

    @property
    def active_kc_issuer_url(self) -> str:
        """Returns the issuer URL for whichever Keycloak mode is active."""
        if self.auth_mode == "keycloak-enterprise":
            base = self.enterprise_kc_server_url.rstrip("/")
            return f"{base}/realms/{self.enterprise_kc_realm}"
        # Local keycloak
        return f"http://{self.keycloak_host}:{self.keycloak_port}/kc/realms/{self.keycloak_realm}"

    @property
    def active_kc_jwks_url(self) -> str:
        """JWKS endpoint for the active Keycloak."""
        return f"{self.active_kc_issuer_url}/protocol/openid-connect/certs"

    @property
    def active_kc_client_id(self) -> str:
        """Client ID for the active Keycloak."""
        if self.auth_mode == "keycloak-enterprise":
            return self.enterprise_kc_client_id
        return "nuxt-frontend"

    @property
    def active_kc_client_secret(self) -> str:
        """Client secret for the active Keycloak."""
        if self.auth_mode == "keycloak-enterprise":
            return self.enterprise_kc_client_secret
        return self.keycloak_client_secret
SETTINGSEOF

echo "  Updated backend/src/clarity/core/settings.py"

echo ""
echo "=== Step 2: Update auth.py — support enterprise Keycloak JWT validation ==="

cat > backend/src/clarity/core/auth.py << 'AUTHEOF'
"""
Authentication dependency for FastAPI routes.

AUTH_MODE=dev                  → Mock user bypass (dev@clarity.local)
AUTH_MODE=keycloak             → Local Keycloak JWT validation
AUTH_MODE=keycloak-enterprise  → Enterprise RTX Keycloak JWT validation
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
# User model returned by the auth dependency
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
# Dev mode — mock user
# ---------------------------------------------------------------------------

MOCK_USER = CurrentUser(
    email="dev@clarity.local",
    name="Dev User",
    roles=["clarity-user", "clarity-admin"],
)


async def _get_mock_user() -> CurrentUser:
    """Return a hardcoded dev user — no token required."""
    return MOCK_USER


# ---------------------------------------------------------------------------
# Keycloak mode (local or enterprise) — validate Bearer JWT
# ---------------------------------------------------------------------------

_bearer_scheme = HTTPBearer(auto_error=True)

# Cache for JWKS keys (keyed by URL so local and enterprise don't collide)
_jwks_cache: dict[str, dict] = {}


def _clear_jwks_cache():
    """Clear all cached JWKS keys."""
    global _jwks_cache
    _jwks_cache = {}


async def _get_keycloak_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    settings: ClaritySettings = Depends(get_settings),
) -> CurrentUser:
    """Validate a Bearer JWT from Keycloak (local or enterprise) and extract user info."""
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
        # Get signing key from JWKS
        jwk_client = PyJWKClient(jwks_url)
        signing_key = jwk_client.get_signing_key_from_jwt(token)

        # Decode and validate
        # Enterprise Keycloak may use different audience claims,
        # so we validate issuer but are flexible on audience.
        payload = pyjwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=issuer_url,
            options={
                "verify_exp": True,
                "verify_aud": False,  # Enterprise may have different audience
            },
        )
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except pyjwt.InvalidTokenError as e:
        log.warning("JWT validation failed (issuer=%s): %s", issuer_url, e)
        _clear_jwks_cache()
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")

    # Extract user info from token claims
    # Enterprise Keycloak uses standard OIDC claims
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

    # Roles: check realm_access.roles (standard Keycloak claim)
    realm_access = payload.get("realm_access", {})
    roles = realm_access.get("roles", [])

    # Also check resource_access for client-specific roles
    client_id = settings.active_kc_client_id
    resource_access = payload.get("resource_access", {})
    client_roles = resource_access.get(client_id, {}).get("roles", [])
    all_roles = list(set(roles + client_roles))

    return CurrentUser(email=email, name=name, roles=all_roles)


# ---------------------------------------------------------------------------
# Public dependency — routes use this
# ---------------------------------------------------------------------------

def get_current_user():
    """
    Returns the appropriate auth dependency based on AUTH_MODE.

    Usage in routes:
        @router.get("/projects")
        async def list_projects(user: CurrentUser = Depends(get_current_user())):
            ...
    """
    settings = get_settings()
    if settings.auth_mode in ("keycloak", "keycloak-enterprise"):
        return _get_keycloak_user
    return _get_mock_user
AUTHEOF

echo "  Updated backend/src/clarity/core/auth.py"

echo ""
echo "=== Step 3: Update .env with enterprise Keycloak vars ==="

ENV_ADDITIONS=""

grep -q "ENTERPRISE_KC_SERVER_URL" .env 2>/dev/null || ENV_ADDITIONS+='
# === Enterprise Keycloak (RTX shared instance) ===
ENTERPRISE_KC_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
ENTERPRISE_KC_REALM=DE-Toolchain
ENTERPRISE_KC_CLIENT_ID=clarity-dev
ENTERPRISE_KC_CLIENT_SECRET=YqkwlPJ01GlyxZ2NbFrKOq2Mlx3u94x1'

if [ -n "$ENV_ADDITIONS" ]; then
    echo "$ENV_ADDITIONS" >> .env
    echo "  Added enterprise Keycloak vars to .env"
else
    echo "  Enterprise Keycloak vars already in .env"
fi

# Sync to backend/.env
if [ -f backend/.env ]; then
    cp .env backend/.env
    echo "  Synced .env → backend/.env"
fi

echo ""
echo "=== Step 4: Update .env.example ==="

# Append enterprise section if not present
if ! grep -q "ENTERPRISE_KC" .env.example 2>/dev/null; then
    cat >> .env.example << 'EXEOF'

# === Enterprise Keycloak (RTX shared instance) ===
# Used when AUTH_MODE=keycloak-enterprise
ENTERPRISE_KC_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
ENTERPRISE_KC_REALM=DE-Toolchain
ENTERPRISE_KC_CLIENT_ID=clarity-dev
ENTERPRISE_KC_CLIENT_SECRET=
EXEOF
    echo "  Updated .env.example with enterprise vars"
fi

echo ""
echo "=== Step 5: Update frontend env + useAuth for enterprise mode ==="

cat > frontend/composables/useAuth.ts << 'AUTHTSEOF'
/**
 * Auth composable — handles dev, keycloak (local), and keycloak-enterprise modes.
 *
 * AUTH_MODE=dev                  → Mock user, no login
 * AUTH_MODE=keycloak             → Local Keycloak OIDC
 * AUTH_MODE=keycloak-enterprise  → Enterprise RTX Keycloak OIDC
 */

interface ClarityUser {
  email: string
  name: string
  roles: string[]
}

const DEV_USER: ClarityUser = {
  email: 'dev@clarity.local',
  name: 'Dev User',
  roles: ['clarity-user', 'clarity-admin'],
}

export function useAuth() {
  const config = useRuntimeConfig()
  const authMode = config.public.authMode || 'dev'
  const isKeycloak = authMode === 'keycloak' || authMode === 'keycloak-enterprise'

  // In any keycloak mode, use nuxt-auth-utils session
  const { loggedIn, user: sessionUser, session, clear } =
    isKeycloak ? useUserSession() : {
      loggedIn: ref(true),
      user: ref(DEV_USER),
      session: ref(null),
      clear: async () => {},
    }

  const user = computed<ClarityUser>(() => {
    if (!isKeycloak) return DEV_USER

    if (sessionUser.value) {
      const u = sessionUser.value as any
      return {
        email: u.email || u.preferred_username || 'unknown',
        name: u.name || `${u.given_name || ''} ${u.family_name || ''}`.trim() || 'Unknown',
        roles: u.roles || u.realm_access?.roles || [],
      }
    }

    return DEV_USER
  })

  const isAuthenticated = computed(() => {
    if (!isKeycloak) return true
    return loggedIn.value
  })

  const isAdmin = computed(() =>
    user.value.roles.includes('clarity-admin')
  )

  function getAuthHeaders(): Record<string, string> {
    if (!isKeycloak) return {}

    const token = (session.value as any)?.accessToken
    if (token) {
      return { Authorization: `Bearer ${token}` }
    }
    return {}
  }

  async function login() {
    if (!isKeycloak) return
    // nuxt-auth-utils handles the OIDC redirect based on the
    // runtime config (which points to either local or enterprise KC)
    await navigateTo('/auth/keycloak', { external: true })
  }

  async function logout() {
    if (!isKeycloak) {
      await navigateTo('/')
      return
    }
    await clear()
    await navigateTo('/')
  }

  return {
    authMode,
    isKeycloak,
    user,
    isAuthenticated,
    isAdmin,
    getAuthHeaders,
    login,
    logout,
  }
}
AUTHTSEOF

echo "  Updated frontend/composables/useAuth.ts"

echo ""
echo "=== Step 6: Create nuxt.config.ts patch for enterprise mode ==="

cat > frontend/_nuxt_config_enterprise_patch.md << 'PATCHEOF'
# Patch: nuxt.config.ts — Enterprise Keycloak support

The nuxt-auth-utils module reads its Keycloak config from runtime config / env vars.
The same NUXT_OAUTH_KEYCLOAK_* vars work for both local and enterprise — you just
change the values in .env when switching modes.

## For local Keycloak (AUTH_MODE=keycloak):
```env
AUTH_MODE=keycloak
NUXT_OAUTH_KEYCLOAK_REALM=clarity
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=nuxt-frontend
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=nEMT2PXHmL9shdQPP8UpQLHeHfrGX1tF
NUXT_OAUTH_KEYCLOAK_SERVER_URL=http://localhost:8080
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3001/auth/sso/callback
```

## For enterprise Keycloak (AUTH_MODE=keycloak-enterprise):
```env
AUTH_MODE=keycloak-enterprise
NUXT_OAUTH_KEYCLOAK_REALM=DE-Toolchain
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=clarity-dev
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=YqkwlPJ01GlyxZ2NbFrKOq2Mlx3u94x1
NUXT_OAUTH_KEYCLOAK_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3001/auth/sso/callback
```

The nuxt.config.ts runtimeConfig should include authMode in public:
```typescript
runtimeConfig: {
  public: {
    apiBase: process.env.NUXT_API_BASE || 'http://localhost:4000',
    authMode: process.env.AUTH_MODE || 'dev',
  },
},
```

No code changes needed in nuxt.config.ts — just swap the env vars.
PATCHEOF

echo "  Created frontend/_nuxt_config_enterprise_patch.md"

echo ""
echo "================================================================"
echo "  Three-Way Auth Complete"
echo "================================================================"
echo ""
echo "AUTH_MODE options:"
echo ""
echo "  dev                   → No login, mock user (dev@clarity.local)"
echo "  keycloak              → Local Keycloak (localhost:8080, realm: clarity)"
echo "  keycloak-enterprise   → RTX enterprise Keycloak"
echo "                          (keycloak-npd.c32p1-colk8s.wg1.aws.ray.com)"
echo "                          realm: DE-Toolchain, client: clarity-dev"
echo ""
echo "To switch modes, change AUTH_MODE in .env and restart both services."
echo ""
echo "Redirect URIs to give Christopher:"
echo "  http://localhost:3001/auth/sso/callback     (local dev)"
echo "  https://clarity.onertx.com/auth/sso/callback (production)"
echo ""
echo "Web origins:"
echo "  http://localhost:3001"
echo "  https://clarity.onertx.com"
echo ""
echo "Claims needed: username, email, firstName, lastName, realm roles"
