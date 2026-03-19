#!/usr/bin/env bash
set -euo pipefail
#
# Script 4: Replace archer_service.py with the clean version
# Fixes f-string JSON building, uses json.dumps, proper async httpx.
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Replacing archer_service.py ==="

# Back up the old one
if [ -f backend/src/clarity/services/archer_service.py ]; then
    cp backend/src/clarity/services/archer_service.py \
       backend/src/clarity/services/archer_service.py.bak
    echo "  Backed up old file to archer_service.py.bak"
fi

cat > backend/src/clarity/services/archer_service.py << 'ARCHEREOF'
"""
Archer GRC REST API Client.

Ported from the C# ArcherCSharp implementation.
Handles login, content creation, user lookup, and workflow transitions.

All JSON payloads use json.dumps() — no f-string JSON construction.
"""

import json
import re
import logging
from typing import Any

import httpx

from ..core.settings import ClaritySettings
from ..schemas.archer_schema import (
    CreateAuthPackageRequest,
    AuthPackage,
    Hardware,
    ArcherFieldDef,
    ArcherValuesListValue,
    ArcherLevel,
)

log = logging.getLogger(__name__)


class ArcherClient:
    """Client for interacting with RSA Archer GRC REST API."""

    def __init__(self, settings: ClaritySettings | None = None):
        settings = settings or ClaritySettings()
        self.base_uri = settings.archer_base_uri
        self.username = settings.archer_username
        self.password = settings.archer_password
        self.instance_name = settings.archer_instance_name
        self.session_token: str | None = None

    def _auth_headers(self) -> dict[str, str]:
        """Build headers with the current session token."""
        return {
            "Authorization": f"Archer session-id={self.session_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    # ------------------------------------------------------------------
    # Authentication
    # ------------------------------------------------------------------

    async def login(self) -> str:
        """Authenticate to Archer and return a session token."""
        url = f"{self.base_uri}/api/core/security/login"
        payload = json.dumps({
            "InstanceName": self.instance_name,
            "UserName": self.username,
            "UserDomain": "",
            "Password": self.password,
        })

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url,
                content=payload,
                headers={"Content-Type": "application/json"},
            )

        if response.is_success:
            data = response.json()
            session_token = data.get("RequestedObject", {}).get("SessionToken", "")
            if session_token:
                self.session_token = session_token
                log.info("Archer login successful")
                return session_token

        log.error("Archer login failed: %s", response.text)
        raise RuntimeError(f"Archer login failed: {response.status_code}")

    # ------------------------------------------------------------------
    # Field Definitions
    # ------------------------------------------------------------------

    async def get_field_definitions(self, level_id: str) -> list[ArcherFieldDef]:
        """Get field definitions for a given Archer level."""
        url = f"{self.base_uri}/api/core/system/fielddefinition/level/{level_id}"

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(url, headers=self._auth_headers())

        if not response.is_success:
            log.error("Failed to get field defs: %s", response.text)
            return []

        data = response.json()
        raw_fields = data if isinstance(data, list) else data.get("RequestedObject", [])

        fields = []
        for f in raw_fields:
            try:
                fields.append(ArcherFieldDef.model_validate(f))
            except Exception as e:
                log.warning("Skipping field: %s", e)

        return fields

    # ------------------------------------------------------------------
    # Values Lists
    # ------------------------------------------------------------------

    async def get_values_list(self, list_id: str) -> list[ArcherValuesListValue]:
        """Get values for a given Archer values list."""
        url = f"{self.base_uri}/api/core/system/valueslistvalue/flat/valueslist/{list_id}"

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(url, headers=self._auth_headers())

        if not response.is_success:
            return []

        data = response.json()
        raw_values = data if isinstance(data, list) else data.get("RequestedObject", [])

        values = []
        for v in raw_values:
            try:
                values.append(ArcherValuesListValue.model_validate(v))
            except Exception as e:
                log.warning("Skipping value: %s", e)

        return values

    # ------------------------------------------------------------------
    # Levels
    # ------------------------------------------------------------------

    async def get_levels(self, module_id: str) -> list[ArcherLevel]:
        """Get levels for a given Archer module/application."""
        url = f"{self.base_uri}/api/core/system/level/module/{module_id}"

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(url, headers=self._auth_headers())

        if not response.is_success:
            return []

        data = response.json()
        raw_levels = data if isinstance(data, list) else data.get("RequestedObject", [])

        levels = []
        for lvl in raw_levels:
            try:
                levels.append(ArcherLevel.model_validate(lvl))
            except Exception as e:
                log.warning("Skipping level: %s", e)

        return levels

    # ------------------------------------------------------------------
    # Content Record Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _base_content_line(
        field_id: int, field_type: int, value: Any
    ) -> dict:
        """Build a single content field line for Archer content API."""
        return {
            "Content": {
                "FieldId": field_id,
                "Type": field_type,
                "Value": value,
            },
            "FieldId": field_id,
            "IsNewContent": True,
            "LevelId": None,
        }

    @staticmethod
    def _value_content_line(
        field_id: int, field_type: int, value_ids: list[int]
    ) -> dict:
        """Build a values-list content field line."""
        value_objects = [{"ValuesListValueId": vid} for vid in value_ids]
        return {
            "Content": {
                "FieldId": field_id,
                "Type": field_type,
                "Value": {"ValuesListValues": value_objects},
            },
            "FieldId": field_id,
            "IsNewContent": True,
            "LevelId": None,
        }

    # ------------------------------------------------------------------
    # Content Record CRUD
    # ------------------------------------------------------------------

    async def create_content_record(
        self,
        level_id: str,
        field_contents: list[dict],
    ) -> str | None:
        """Create a new content record in Archer."""
        url = f"{self.base_uri}/api/core/content"
        payload = json.dumps({
            "Content": {
                "LevelId": level_id,
                "FieldContents": field_contents,
            },
        })

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url,
                content=payload,
                headers=self._auth_headers(),
            )

        if response.is_success:
            data = response.json()
            content_id = data.get("RequestedObject", {}).get("Id")
            if content_id:
                log.info("Created Archer content record: %s", content_id)
                return str(content_id)

        log.error("Failed to create content record: %s", response.text)
        return None

    async def get_content_record(self, content_id: str) -> dict | None:
        """Retrieve a content record by ID."""
        url = f"{self.base_uri}/api/core/content/{content_id}"

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(url, headers=self._auth_headers())

        if response.is_success:
            return response.json().get("RequestedObject")

        log.warning("Content record %s not found", content_id)
        return None

    # ------------------------------------------------------------------
    # User Lookup
    # ------------------------------------------------------------------

    async def find_user_by_login(self, login_name: str) -> dict | None:
        """Find an Archer user by login name."""
        url = f"{self.base_uri}/api/core/system/user"
        # Archer user search uses query params
        params = {"loginName": login_name}

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get(
                url, params=params, headers=self._auth_headers()
            )

        if response.is_success:
            data = response.json()
            users = data if isinstance(data, list) else [data.get("RequestedObject")]
            for u in users:
                if u and u.get("UserName", "").lower() == login_name.lower():
                    return u

        return None

    # ------------------------------------------------------------------
    # Auth Package Submission (high-level workflow)
    # ------------------------------------------------------------------

    async def create_auth_package(
        self,
        request: CreateAuthPackageRequest,
    ) -> str | None:
        """
        Submit a complete authorization package to Archer.

        This is the primary integration point — takes the questionnaire
        responses and creates the appropriate Archer records.
        """
        # Ensure we have a session
        if not self.session_token:
            await self.login()

        log.info(
            "Creating auth package for: %s",
            request.auth_package.system_name if request.auth_package else "unknown",
        )

        # TODO: Map questionnaire responses → Archer field contents
        # This requires the field definition mapping for the target module.
        # For now, return a placeholder indicating the flow works.
        return "PENDING_IMPLEMENTATION"

    # ------------------------------------------------------------------
    # Workflow Transitions
    # ------------------------------------------------------------------

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

    async def choose_transition(
        self, content_id: str, transition_id: str
    ) -> str:
        """Execute a workflow transition on a content record."""
        url = f"{self.base_uri}/api/core/system/WorkflowAction"
        payload = json.dumps({
            "ContentId": content_id,
            "TransitionId": transition_id,
        })

        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url,
                content=payload,
                headers=self._auth_headers(),
            )

        if response.is_success:
            return "Success"

        log.error("Workflow transition failed: %s", response.text)
        return "Failed"
ARCHEREOF

echo "  Replaced backend/src/clarity/services/archer_service.py"
echo "  (Old file backed up to archer_service.py.bak)"

echo ""
echo "=== Done ==="
echo ""
echo "Key changes from the old version:"
echo "  - All JSON payloads use json.dumps() — no more f-string JSON"
echo "  - Proper dict construction in _base_content_line / _value_content_line"
echo "  - Added logging throughout (replaces print statements)"
echo "  - Consistent async httpx usage"
echo "  - Type hints on all methods"
