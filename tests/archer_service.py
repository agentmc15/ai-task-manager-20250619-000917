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
            if response.is_success:
                data = response.json()
                token = data.get("RequestedObject", {}).get("SessionToken", "")
                if token:
                    self.session_token = token
                    return token
            return f"Login Failed: {response.status_code}"

    async def logout(self, session_token: str) -> str:
        """Logout from Archer."""
        url = f"{self.base_uri}/api/core/security/logout"
        payload = json.dumps({"Value": session_token})
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(
                url, content=payload,
                headers={"Content-Type": "application/json"},
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
        """Build a content line for text-type fields (type 1) or IP address (type 19)."""
        if field.field_type == "19":
            entry = {
                field.field_id: {
                    "Type": "19",
                    "Tag": field.field_name,
                    "IpAddressBytes": content,
                    "FieldId": field.field_id,
                }
            }
        else:
            entry = {
                field.field_id: {
                    "Type": "1",
                    "Tag": field.field_name,
                    "Value": content,
                    "FieldId": field.field_id,
                }
            }
        # Strip outer braces — this gets merged into FieldContents
        return json.dumps(entry)[1:-1]

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

        entry = {
            field.field_id: {
                "Type": "4",
                "Tag": field.field_name,
                "Value": {"ValuesListIds": val_string},
                "FieldId": field.field_id,
            }
        }
        return json.dumps(entry)[1:-1]

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
        # - Handle workflow transitions

        # For now, return a placeholder
        """
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
