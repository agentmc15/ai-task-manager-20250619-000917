#!/usr/bin/env bash
set -euo pipefail
#
# Script 2: AUTH_MODE=dev|keycloak toggle (Backend)
# Adds AUTH_MODE to settings, creates auth middleware + dependency.
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Add AUTH_MODE + Keycloak JWKS settings ==="

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
    auth_mode: str = Field(alias="AUTH_MODE", default="dev")
    """'dev' = mock user bypass, 'keycloak' = real OIDC token validation."""

    # Keycloak SSO
    keycloak_host: str = Field(alias="CLARITY_KC_HOST", default="localhost")
    keycloak_port: int = Field(alias="CLARITY_KC_PORT", default=8080)
    keycloak_realm: str = Field(alias="CLARITY_KC_REALM", default="clarity")
    keycloak_client_secret: str = Field(alias="CLARITY_KC_MGMT_CLIENT_SECRET", default="")
    oidc_client_id: str = Field(alias="COMP_OIDC_CLIENT_ID", default="")
    oidc_client_secret: str = Field(alias="COMP_OIDC_CLIENT_SECRET", default="")

    # PostgreSQL
    sql_username: str = Field(alias="CLARITY_SQL_USER", default="clarity")
    sql_password: str = Field(alias="CLARITY_SQL_PASSWORD", default="clarity")
    sql_host: str = Field(alias="CLARITY_SQL_HOST", default="localhost")
    sql_port: int = Field(alias="CLARITY_SQL_PORT", default=5432)
    sql_db_name: str = Field(alias="CLARITY_SQL_DB", default="clarity")

    # RTX Model Hub Gateway (placeholder for future AI features)
    meta_openai_uri: str = Field(alias="META_OPENAI_URL", default="")
    meta_openai_key: str = Field(alias="META_OPENAI_KEY", default="")

    # Archer GRC
    archer_username: str = Field(alias="ARCHER_USERNAME", default="")
    archer_password: str = Field(alias="ARCHER_PASSWORD", default="")
    archer_instance_name: str = Field(alias="ARCHER_INSTANCE_NAME", default="ArcherRTX PROD")
    archer_base_uri: str = Field(alias="ARCHER_BASE_URI", default="https://archergrc.corp.ray.com")
    soap_search_uri: str = Field(alias="ARCHER_SOAP_SEARCH_URI", default="")
    soap_general_uri: str = Field(alias="ARCHER_SOAP_GENERAL_URI", default="")
    mapping_report: str = Field(alias="MAPPING_REPORT", default="")

    @property
    def keycloak_issuer_url(self) -> str:
        """Full Keycloak issuer URL for OIDC token validation."""
        return f"http://{self.keycloak_host}:{self.keycloak_port}/kc/realms/{self.keycloak_realm}"

    @property
    def keycloak_jwks_url(self) -> str:
        """JWKS endpoint for verifying Keycloak JWTs."""
        return f"{self.keycloak_issuer_url}/protocol/openid-connect/certs"
SETTINGSEOF

echo "  Updated backend/src/clarity/core/settings.py"

echo ""
echo "=== Step 2: Create auth dependency (get_current_user) ==="

cat > backend/src/clarity/core/auth.py << 'AUTHEOF'
"""
Authentication dependency for FastAPI routes.

AUTH_MODE=dev   → Returns a hardcoded mock user on every request.
AUTH_MODE=keycloak → Validates the Bearer token against Keycloak JWKS.
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
# Keycloak mode — validate Bearer JWT
# ---------------------------------------------------------------------------

_bearer_scheme = HTTPBearer(auto_error=True)

# Cache for JWKS keys (refresh on miss)
_jwks_cache: dict | None = None


async def _fetch_jwks(jwks_url: str) -> dict:
    """Fetch JWKS from Keycloak (cached after first call)."""
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache

    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.get(jwks_url)
        resp.raise_for_status()
        _jwks_cache = resp.json()
        return _jwks_cache


def _clear_jwks_cache():
    """Clear JWKS cache (useful when keys rotate)."""
    global _jwks_cache
    _jwks_cache = None


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

    try:
        # Get signing key from JWKS
        jwk_client = PyJWKClient(settings.keycloak_jwks_url)
        signing_key = jwk_client.get_signing_key_from_jwt(token)

        # Decode and validate
        payload = pyjwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience="account",
            issuer=settings.keycloak_issuer_url,
            options={"verify_exp": True},
        )
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except pyjwt.InvalidTokenError as e:
        log.warning("JWT validation failed: %s", e)
        # Clear JWKS cache and retry once (in case keys rotated)
        _clear_jwks_cache()
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")

    # Extract user info from token claims
    email = payload.get("email", payload.get("preferred_username", "unknown"))
    name = payload.get("name", payload.get("preferred_username", "Unknown"))
    realm_access = payload.get("realm_access", {})
    roles = realm_access.get("roles", [])

    return CurrentUser(email=email, name=name, roles=roles)


# ---------------------------------------------------------------------------
# Public dependency — routes use this
# ---------------------------------------------------------------------------

def get_current_user(settings: ClaritySettings = Depends(get_settings)):
    """
    Returns the appropriate auth dependency based on AUTH_MODE.

    Usage in routes:
        @router.get("/projects")
        async def list_projects(user: CurrentUser = Depends(get_current_user())):
            ...
    """
    if settings.auth_mode == "keycloak":
        return _get_keycloak_user
    return _get_mock_user


# Convenience: pre-built dependency for most routes
def require_user():
    """FastAPI Depends()-compatible auth dependency.

    Usage:
        user: CurrentUser = Depends(require_user())
    """
    settings = get_settings()
    if settings.auth_mode == "keycloak":
        return Depends(_get_keycloak_user)
    return Depends(_get_mock_user)
AUTHEOF

echo "  Created backend/src/clarity/core/auth.py"

echo ""
echo "=== Step 3: Add AUTH_MODE + PyJWT to requirements.txt ==="

# Add PyJWT if not already present
if ! grep -q "PyJWT" backend/requirements.txt 2>/dev/null; then
    echo "PyJWT[crypto]>=2.9.0" >> backend/requirements.txt
    echo "  Added PyJWT[crypto] to requirements.txt"
else
    echo "  PyJWT already in requirements.txt"
fi

echo ""
echo "=== Step 4: Add AUTH_MODE=dev to .env ==="

if ! grep -q "AUTH_MODE" .env 2>/dev/null; then
    echo "" >> .env
    echo "# Auth mode: 'dev' = mock user, 'keycloak' = real OIDC" >> .env
    echo "AUTH_MODE=dev" >> .env
    echo "  Added AUTH_MODE=dev to .env"
else
    echo "  AUTH_MODE already in .env"
fi

# Also add to backend/.env if it exists
if [ -f backend/.env ]; then
    if ! grep -q "AUTH_MODE" backend/.env 2>/dev/null; then
        echo "" >> backend/.env
        echo "AUTH_MODE=dev" >> backend/.env
        echo "  Added AUTH_MODE=dev to backend/.env"
    fi
fi

echo ""
echo "=== Done ==="
echo ""
echo "Usage in routes:"
echo '  from ..core.auth import CurrentUser, get_current_user'
echo ''
echo '  @router.get("/projects")'
echo '  async def list_projects(user: CurrentUser = Depends(get_current_user())):'
echo '      # user.email, user.name, user.roles available'
echo '      ...'
echo ""
echo "To switch modes:"
echo "  AUTH_MODE=dev        → No login required, uses dev@clarity.local"
echo "  AUTH_MODE=keycloak   → Requires valid Keycloak Bearer token"
echo ""
echo "IMPORTANT: Run 'pip install PyJWT[crypto]' in your backend venv"
