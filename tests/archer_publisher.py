"""
Archer Publisher (Python port of ArcherCSharp)

MVP wrapper that takes a Clarity-generated JSON payload and creates
corresponding content records in RSA Archer GRC via the Archer REST API.

Input:
    - JSON file (or dict) produced by Clarity's /project/{id}/archer-payload endpoint
    - Archer credentials from environment variables

Output:
    - Dict with success status, created hardware content IDs, auth package content ID,
      and any errors encountered

Scope (MVP):
    - Discovers Archer field IDs dynamically via REST API (no Snowflake dependency)
    - Maps Clarity question answers → Archer content record payloads
    - Creates hardware records (sub-records for each row in the KV table)
    - Creates the auth package record with cross-references to the hardware records
    - Handles text, values-list (single + multi), and reference content line types

Out of scope (future):
    - User lookups (ArcherUserContentLine) — uses text fallback
    - Business / Entity / SubOrganization cross-references from Snowflake
    - Workflow transitions after creation
    - Duplicate detection / update (create-only)

Usage:
    python archer_publisher.py path/to/archer_payload.json

    Or as a library:
        from archer_publisher import ArcherPublisher
        publisher = ArcherPublisher.from_env()
        result = publisher.publish_from_file("archer_payload.json")
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from dataclasses import dataclass, field
from typing import Any

import httpx

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Archer Field Types (from the C# ArcherCSharp reference)
# ---------------------------------------------------------------------------
# 1  = Text
# 4  = Values List (single-select or multi-select)
# 8  = User/Groups List
# 9  = Cross-Reference (to other records)
# 19 = Sub-form / Sub-record
# ---------------------------------------------------------------------------

FIELD_TYPE_TEXT = "1"
FIELD_TYPE_VALUES_LIST = "4"
FIELD_TYPE_USER = "8"
FIELD_TYPE_CROSS_REFERENCE = "9"
FIELD_TYPE_SUBFORM = "19"


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

@dataclass
class ArcherConfig:
    """Archer instance connection configuration."""
    base_url: str
    instance_name: str
    username: str
    password: str
    user_domain: str = ""
    verify_ssl: bool = False

    # Module names we'll write to (Archer discovers their level IDs at runtime)
    auth_package_module_name: str = "RTX GRC Authorization Package"
    hardware_module_name: str = "RTX GRC Hardware"

    @classmethod
    def from_env(cls) -> "ArcherConfig":
        """Build config from environment variables."""
        return cls(
            base_url=os.environ.get("ARCHER_BASE_URL", "https://archergrc.corp.rtx.com/"),
            instance_name=os.environ.get("ARCHER_INSTANCE", "ArcherPOC"),
            username=os.environ.get("ARCHER_USERNAME", ""),
            password=os.environ.get("ARCHER_PASSWORD", ""),
            user_domain=os.environ.get("ARCHER_USER_DOMAIN", ""),
            verify_ssl=os.environ.get("ARCHER_VERIFY_SSL", "false").lower() == "true",
            auth_package_module_name=os.environ.get(
                "ARCHER_AUTH_PACKAGE_MODULE",
                "RTX GRC Authorization Package",
            ),
            hardware_module_name=os.environ.get(
                "ARCHER_HARDWARE_MODULE",
                "RTX GRC Hardware",
            ),
        )


# ---------------------------------------------------------------------------
# Result container
# ---------------------------------------------------------------------------

@dataclass
class PublishResult:
    """Result of a publish operation."""
    success: bool
    auth_package_content_id: str | None = None
    hardware_content_ids: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "success": self.success,
            "auth_package_content_id": self.auth_package_content_id,
            "hardware_content_ids": self.hardware_content_ids,
            "errors": self.errors,
            "warnings": self.warnings,
        }


# ---------------------------------------------------------------------------
# Archer REST client
# ---------------------------------------------------------------------------

class ArcherRestClient:
    """
    Minimal Archer REST API client for the publisher.
    Port of the subset of ArcherCSharp that we need for MVP.
    """

    def __init__(self, config: ArcherConfig):
        self.config = config
        self.session_token: str | None = None
        self._http = httpx.Client(
            base_url=config.base_url.rstrip("/"),
            verify=config.verify_ssl,
            timeout=30.0,
        )

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> "ArcherRestClient":
        self.login()
        return self

    def __exit__(self, *exc) -> None:
        try:
            self.logout()
        finally:
            self.close()

    # ----- Auth -----

    def login(self) -> str:
        """Authenticate to Archer and cache the session token."""
        payload = {
            "InstanceName": self.config.instance_name,
            "Username": self.config.username,
            "UserDomain": self.config.user_domain,
            "Password": self.config.password,
        }
        resp = self._http.post(
            "/api/core/security/login",
            content=json.dumps(payload),
            headers={"Content-Type": "application/json"},
        )
        resp.raise_for_status()
        data = resp.json()
        token = data.get("RequestedObject", {}).get("SessionToken")
        if not token:
            raise RuntimeError(f"Archer login failed: {data}")
        self.session_token = token
        log.info("Archer login successful")
        return token

    def logout(self) -> None:
        """Release the session token."""
        if not self.session_token:
            return
        try:
            self._http.post(
                "/api/core/security/logout",
                headers=self._auth_headers(),
            )
            log.info("Archer logout successful")
        except Exception as e:
            log.warning("Archer logout failed: %s", e)
        finally:
            self.session_token = None

    def _auth_headers(self) -> dict[str, str]:
        if not self.session_token:
            raise RuntimeError("Not logged in to Archer")
        return {
            "Authorization": f'Archer session-id="{self.session_token}"',
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Http-Method-Override": "GET",
        }

    # ----- Discovery -----

    def get_application_by_name(self, name: str) -> dict | None:
        """Find an Archer application (module) by its display name."""
        resp = self._http.get(
            "/api/core/system/application",
            headers=self._get_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        apps = data if isinstance(data, list) else data.get("RequestedObject", [])
        for app_wrapper in apps:
            app = app_wrapper.get("RequestedObject", app_wrapper)
            if (app.get("Name") or "").strip().lower() == name.strip().lower():
                return app
        return None

    def get_levels_for_module(self, module_id: int) -> list[dict]:
        """Get all levels defined in a module."""
        resp = self._http.get(
            f"/api/core/system/level/module/{module_id}",
            headers=self._get_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data if isinstance(data, list) else data.get("RequestedObject", [])
        return [item.get("RequestedObject", item) for item in raw]

    def get_field_definitions(self, level_id: int) -> list[dict]:
        """Get all field definitions for a given level."""
        resp = self._http.get(
            f"/api/core/system/fielddefinition/level/{level_id}",
            headers=self._get_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data if isinstance(data, list) else data.get("RequestedObject", [])
        return [item.get("RequestedObject", item) for item in raw]

    def get_values_list(self, values_list_id: int) -> list[dict]:
        """Get all values for a values-list field."""
        resp = self._http.get(
            f"/api/core/system/valueslistvalue/flat/valueslist/{values_list_id}",
            headers=self._get_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data if isinstance(data, list) else data.get("RequestedObject", [])
        return [item.get("RequestedObject", item) for item in raw]

    def _get_headers(self) -> dict[str, str]:
        """Headers for GET requests (without method override)."""
        if not self.session_token:
            raise RuntimeError("Not logged in to Archer")
        return {
            "Authorization": f'Archer session-id="{self.session_token}"',
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    # ----- Content creation -----

    def create_content_record(
        self,
        level_id: int,
        field_contents: dict,
    ) -> str | None:
        """
        Create a new content record in Archer.
        Returns the content ID on success, None on failure.
        """
        payload = {
            "Content": {
                "LevelId": level_id,
                "FieldContents": field_contents,
            }
        }
        resp = self._http.post(
            "/api/core/content",
            content=json.dumps(payload),
            headers={
                "Authorization": f'Archer session-id="{self.session_token}"',
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        if not resp.is_success:
            log.error(
                "Failed to create content record (HTTP %s): %s",
                resp.status_code,
                resp.text,
            )
            return None
        data = resp.json()
        content_id = data.get("RequestedObject", {}).get("Id")
        if content_id is None:
            log.error("Create content returned no Id: %s", data)
            return None
        return str(content_id)


# ---------------------------------------------------------------------------
# Field mapping registry
# ---------------------------------------------------------------------------
# Maps the field names emitted by Clarity's archer export service to the
# expected Archer field names in the Authorization Package module.
#
# Clarity export already uses Archer-style field names (AUTHORIZATION_PACKAGE_NAME
# etc.), so this is effectively an identity mapping for MVP. Keeping it explicit
# here in case Archer's actual field names diverge later.
# ---------------------------------------------------------------------------

AUTH_PACKAGE_FIELD_ALIASES = {
    "AUTHORIZATION_PACKAGE_NAME": ["AUTHORIZATION_PACKAGE_NAME", "Authorization Package Name"],
    "CLARA_ID": ["CLARA_ID", "Clara ID", "CLARA"],
    "ENTITY": ["ENTITY", "Entity"],
    "BUSINESS": ["BUSINESS", "Business"],
    "MISSION_PURPOSE": ["MISSION_PURPOSE", "Mission Purpose", "Mission/Purpose"],
    "INFORMATION_CLASSIFICATION": ["INFORMATION_CLASSIFICATION", "Information Classification"],
    "CONNECTIVITY": ["CONNECTIVITY", "Connectivity"],
    "AUTHORIZATION_BOUNDARY_DESCRIPTION": [
        "AUTHORIZATION_BOUNDARY_DESCRIPTION",
        "Authorization Boundary Description",
    ],
    "SYSTEM_ADMINISTRATOR_ID": [
        "SYSTEM_ADMINISTRATOR_ID",
        "System Administrator (SA)",
        "System Administrator",
    ],
}

HARDWARE_FIELD_ALIASES = {
    "HARDWARE_NAME": ["HARDWARE_NAME", "Hardware Name"],
    "IP_ADDRESS": ["IP_ADDRESS", "IP Address", "INTERNAL_IP_ADDRESS", "Internal IP Address"],
    "HARDWARE_TYPE": ["HARDWARE_TYPE", "Hardware Type", "Type", "TYPE"],
    "BUSINESS_UNIT": ["BUSINESS_UNIT", "Business Unit", "BUSINESS", "Business"],
    "MAC_ADDRESS": ["MAC_ADDRESS", "MAC Address"],
}


def _resolve_field(
    field_defs: list[dict],
    aliases: list[str],
) -> dict | None:
    """Find an Archer field definition matching any of the given aliases."""
    alias_lower = {a.lower() for a in aliases}
    for fd in field_defs:
        name = (fd.get("Name") or "").strip().lower()
        if name in alias_lower:
            return fd
    return None


# ---------------------------------------------------------------------------
# Archer Publisher (main class)
# ---------------------------------------------------------------------------

class ArcherPublisher:
    """
    Consumes a Clarity-generated JSON payload and creates the corresponding
    records in Archer.
    """

    def __init__(self, config: ArcherConfig):
        self.config = config
        self._hw_level_id: int | None = None
        self._hw_field_defs: list[dict] = []
        self._ap_level_id: int | None = None
        self._ap_field_defs: list[dict] = []
        self._values_list_cache: dict[int, list[dict]] = {}

    @classmethod
    def from_env(cls) -> "ArcherPublisher":
        return cls(ArcherConfig.from_env())

    # ----- Public entry points -----

    def publish_from_file(self, json_path: str) -> PublishResult:
        """Load a Clarity payload JSON file and publish it to Archer."""
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return self.publish(data)

    def publish(self, clarity_response: dict) -> PublishResult:
        """
        Publish a Clarity payload (as returned by /project/{id}/archer-payload)
        to Archer.

        The input can be either:
          - The full wrapper: {"success": bool, "payload": {...}}
          - Just the inner payload: {"metadata": {...}, "content": {...}}
        """
        result = PublishResult(success=False)

        # Unwrap the payload if it's the full response envelope
        if "payload" in clarity_response and "content" in clarity_response.get("payload", {}):
            payload = clarity_response["payload"]
        else:
            payload = clarity_response

        fields = payload.get("content", {}).get("fields", [])
        if not fields:
            result.errors.append("No fields found in Clarity payload")
            return result

        # Index fields by name for easy lookup
        fields_by_name: dict[str, dict] = {
            f.get("field_name", ""): f for f in fields
        }

        try:
            with ArcherRestClient(self.config) as client:
                # Resolve module metadata (level IDs + field defs) once
                self._discover_modules(client, result)

                if self._ap_level_id is None:
                    result.errors.append(
                        f"Could not find Archer module '{self.config.auth_package_module_name}'"
                    )
                    return result

                # Step 1: Create hardware sub-records first, collect their content IDs
                hardware_field = fields_by_name.get("HARDWARE_INVENTORY")
                hw_content_ids: list[str] = []
                if hardware_field and self._hw_level_id is not None:
                    hw_content_ids = self._publish_hardware_records(
                        client, hardware_field, result
                    )
                    result.hardware_content_ids = hw_content_ids
                elif hardware_field:
                    result.warnings.append(
                        f"Hardware module '{self.config.hardware_module_name}' not found; "
                        "skipping hardware records"
                    )

                # Step 2: Create the auth package record with cross-refs to hardware
                ap_content_id = self._publish_auth_package(
                    client, fields_by_name, hw_content_ids, result
                )
                result.auth_package_content_id = ap_content_id

                result.success = ap_content_id is not None

        except Exception as e:
            log.exception("Publish failed")
            result.errors.append(f"Publish exception: {e}")

        return result

    # ----- Module discovery -----

    def _discover_modules(
        self,
        client: ArcherRestClient,
        result: PublishResult,
    ) -> None:
        """Look up level IDs and field definitions for both target modules."""
        # Auth package module
        ap_app = client.get_application_by_name(self.config.auth_package_module_name)
        if ap_app:
            ap_module_id = ap_app.get("Id")
            levels = client.get_levels_for_module(ap_module_id)
            if levels:
                self._ap_level_id = levels[0].get("Id")
                self._ap_field_defs = client.get_field_definitions(self._ap_level_id)
                log.info(
                    "Discovered auth package module: level_id=%s, fields=%d",
                    self._ap_level_id,
                    len(self._ap_field_defs),
                )
            else:
                result.warnings.append(
                    f"No levels found for module '{self.config.auth_package_module_name}'"
                )
        else:
            result.warnings.append(
                f"Auth package module '{self.config.auth_package_module_name}' not found"
            )

        # Hardware module
        hw_app = client.get_application_by_name(self.config.hardware_module_name)
        if hw_app:
            hw_module_id = hw_app.get("Id")
            levels = client.get_levels_for_module(hw_module_id)
            if levels:
                self._hw_level_id = levels[0].get("Id")
                self._hw_field_defs = client.get_field_definitions(self._hw_level_id)
                log.info(
                    "Discovered hardware module: level_id=%s, fields=%d",
                    self._hw_level_id,
                    len(self._hw_field_defs),
                )

    # ----- Hardware records -----

    def _publish_hardware_records(
        self,
        client: ArcherRestClient,
        hardware_field: dict,
        result: PublishResult,
    ) -> list[str]:
        """Create one Archer content record per hardware row."""
        created_ids: list[str] = []
        records = hardware_field.get("records", [])
        if not records:
            return created_ids

        for idx, record in enumerate(records):
            field_contents = self._build_hardware_field_contents(
                client, record, result
            )
            if not field_contents:
                result.warnings.append(f"Hardware row {idx} produced no field contents; skipped")
                continue

            content_id = client.create_content_record(
                self._hw_level_id,
                field_contents,
            )
            if content_id:
                created_ids.append(content_id)
                log.info("Created hardware record %s for row %d", content_id, idx)
            else:
                result.errors.append(f"Failed to create hardware record for row {idx}")

        return created_ids

    def _build_hardware_field_contents(
        self,
        client: ArcherRestClient,
        record: dict,
        result: PublishResult,
    ) -> dict:
        """Build the FieldContents dict for a single hardware record."""
        contents: dict = {}

        for clarity_field, aliases in HARDWARE_FIELD_ALIASES.items():
            value = record.get(clarity_field, "")
            if value is None or value == "":
                continue

            field_def = _resolve_field(self._hw_field_defs, aliases)
            if not field_def:
                result.warnings.append(
                    f"Hardware field not found in Archer: {clarity_field}"
                )
                continue

            field_id = field_def.get("Id")
            field_type = str(field_def.get("Type", ""))

            if field_type == FIELD_TYPE_TEXT:
                contents[str(field_id)] = self._text_line(field_id, value)
            elif field_type == FIELD_TYPE_VALUES_LIST:
                vl_id = field_def.get("RelatedValuesListId") or field_def.get("ValuesListId")
                if vl_id:
                    vl_entry = self._resolve_values_list_value(client, vl_id, value)
                    if vl_entry:
                        contents[str(field_id)] = self._values_list_line(
                            field_id, [vl_entry]
                        )
                    else:
                        result.warnings.append(
                            f"Values list value not found: {clarity_field}={value}"
                        )
            else:
                # Fallback: treat as text
                contents[str(field_id)] = self._text_line(field_id, value)

        return contents

    # ----- Auth package record -----

    def _publish_auth_package(
        self,
        client: ArcherRestClient,
        fields_by_name: dict,
        hardware_content_ids: list[str],
        result: PublishResult,
    ) -> str | None:
        """Build and submit the auth package content record."""
        contents: dict = {}

        for clarity_field, aliases in AUTH_PACKAGE_FIELD_ALIASES.items():
            clarity_entry = fields_by_name.get(clarity_field)
            if not clarity_entry:
                continue

            field_def = _resolve_field(self._ap_field_defs, aliases)
            if not field_def:
                result.warnings.append(
                    f"Auth package field not found in Archer: {clarity_field}"
                )
                continue

            field_id = field_def.get("Id")
            field_type = str(field_def.get("Type", ""))
            clarity_type = clarity_entry.get("field_type")

            if clarity_type == "text":
                value = clarity_entry.get("value", "")
                if value:
                    contents[str(field_id)] = self._text_line(field_id, value)

            elif clarity_type == "values_list":
                if clarity_entry.get("multi_select"):
                    values = clarity_entry.get("values", []) or []
                else:
                    single = clarity_entry.get("value")
                    values = [single] if single else []

                if not values:
                    continue

                if field_type == FIELD_TYPE_VALUES_LIST:
                    vl_id = field_def.get("RelatedValuesListId") or field_def.get("ValuesListId")
                    resolved_ids = []
                    if vl_id:
                        for v in values:
                            vl_entry = self._resolve_values_list_value(client, vl_id, v)
                            if vl_entry:
                                resolved_ids.append(vl_entry)
                            else:
                                result.warnings.append(
                                    f"Values list value not found: {clarity_field}={v}"
                                )
                    if resolved_ids:
                        contents[str(field_id)] = self._values_list_line(
                            field_id, resolved_ids
                        )
                else:
                    # Archer field is actually text; join multi-values
                    contents[str(field_id)] = self._text_line(
                        field_id, ", ".join(str(v) for v in values)
                    )

        # Cross-reference to hardware records
        if hardware_content_ids:
            hw_ref_field = _resolve_field(
                self._ap_field_defs,
                ["HARDWARE", "Hardware", "HARDWARE_INVENTORY", "Hardware Inventory"],
            )
            if hw_ref_field:
                ref_field_id = hw_ref_field.get("Id")
                contents[str(ref_field_id)] = self._reference_line(
                    ref_field_id, hardware_content_ids
                )
            else:
                result.warnings.append(
                    "Hardware cross-reference field not found on auth package module"
                )

        if not contents:
            result.errors.append("Auth package has no field contents to submit")
            return None

        content_id = client.create_content_record(self._ap_level_id, contents)
        if content_id:
            log.info("Created auth package content record %s", content_id)
        else:
            result.errors.append("Failed to create auth package content record")
        return content_id

    # ----- Content line builders -----

    @staticmethod
    def _text_line(field_id: int, value: Any) -> dict:
        return {
            "Type": int(FIELD_TYPE_TEXT),
            "Tag": None,
            "FieldId": field_id,
            "Value": str(value),
        }

    @staticmethod
    def _values_list_line(field_id: int, value_ids: list[int]) -> dict:
        return {
            "Type": int(FIELD_TYPE_VALUES_LIST),
            "Tag": None,
            "FieldId": field_id,
            "Value": {
                "ValuesListIds": value_ids,
                "OtherText": None,
            },
        }

    @staticmethod
    def _reference_line(field_id: int, content_ids: list[str]) -> dict:
        return {
            "Type": int(FIELD_TYPE_CROSS_REFERENCE),
            "Tag": None,
            "FieldId": field_id,
            "Value": [int(cid) for cid in content_ids],
        }

    # ----- Values-list resolution -----

    def _resolve_values_list_value(
        self,
        client: ArcherRestClient,
        values_list_id: int,
        display_value: str,
    ) -> int | None:
        """Look up the numeric ID of a values-list entry by its display name."""
        if values_list_id not in self._values_list_cache:
            self._values_list_cache[values_list_id] = client.get_values_list(values_list_id)

        entries = self._values_list_cache[values_list_id]
        target = str(display_value).strip().lower()
        for entry in entries:
            name = (entry.get("Name") or "").strip().lower()
            if name == target:
                return entry.get("Id")
        return None


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Publish a Clarity archer-payload JSON to RSA Archer GRC"
    )
    parser.add_argument(
        "json_path",
        help="Path to the JSON file produced by Clarity's /project/{id}/archer-payload endpoint",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    publisher = ArcherPublisher.from_env()
    result = publisher.publish_from_file(args.json_path)

    print(json.dumps(result.to_dict(), indent=2))
    return 0 if result.success else 1


if __name__ == "__main__":
    sys.exit(main())
