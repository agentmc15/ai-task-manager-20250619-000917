"""
Archer Publisher Service

Consumes Clarity's internal Archer payload (from archer_export_service) and
creates corresponding records in RSA Archer GRC via the REST API.

Supports a dry-run mode controlled by CLARITY_SETTINGS.archer_publish_enabled
so the wiring can be tested without a live Archer instance.

MVP scope:
- Dynamic field discovery via Archer REST API (no Snowflake dependency)
- Hardware sub-records created first, then auth package with cross-refs
- Text, values-list (single + multi), and cross-reference field types
- Progress callbacks for step-by-step UI updates

Out of scope (v2):
- User lookups (HARDWARE_OWNER, SYSTEM_ADMINISTRATOR_SA)
- Business/Entity/SubOrganization cross-refs from Snowflake
- Workflow transitions
- Update / duplicate detection
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Callable

import httpx

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Archer Field Types
# ---------------------------------------------------------------------------

FIELD_TYPE_TEXT = "1"
FIELD_TYPE_VALUES_LIST = "4"
FIELD_TYPE_USER = "8"
FIELD_TYPE_CROSS_REFERENCE = "9"
FIELD_TYPE_SUBFORM = "19"


# ---------------------------------------------------------------------------
# Progress steps (for UI feedback)
# ---------------------------------------------------------------------------

STEP_SAVE = "save"
STEP_GENERATE = "generate"
STEP_CONNECT = "connect"
STEP_HARDWARE = "hardware"
STEP_AUTH_PACKAGE = "auth_package"
STEP_COMPLETE = "complete"

ALL_STEPS = [
    STEP_SAVE,
    STEP_GENERATE,
    STEP_CONNECT,
    STEP_HARDWARE,
    STEP_AUTH_PACKAGE,
    STEP_COMPLETE,
]

STEP_LABELS = {
    STEP_SAVE: "Saving questionnaire responses",
    STEP_GENERATE: "Generating Archer payload",
    STEP_CONNECT: "Connecting to Archer",
    STEP_HARDWARE: "Creating hardware records",
    STEP_AUTH_PACKAGE: "Creating authorization package",
    STEP_COMPLETE: "Complete",
}


# ---------------------------------------------------------------------------
# Result container
# ---------------------------------------------------------------------------

@dataclass
class PublishResult:
    """Result of a publish operation."""
    success: bool
    dry_run: bool = False
    auth_package_content_id: str | None = None
    hardware_content_ids: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    steps_completed: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "success": self.success,
            "dry_run": self.dry_run,
            "auth_package_content_id": self.auth_package_content_id,
            "hardware_content_ids": self.hardware_content_ids,
            "errors": self.errors,
            "warnings": self.warnings,
            "steps_completed": self.steps_completed,
        }


# ---------------------------------------------------------------------------
# Field mapping registry
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


def _resolve_field(field_defs: list[dict], aliases: list[str]) -> dict | None:
    """Find an Archer field definition matching any of the given aliases."""
    alias_lower = {a.lower() for a in aliases}
    for fd in field_defs:
        name = (fd.get("Name") or "").strip().lower()
        if name in alias_lower:
            return fd
    return None


# ---------------------------------------------------------------------------
# Archer REST client
# ---------------------------------------------------------------------------

class ArcherRestClient:
    """Async Archer REST API client."""

    def __init__(
        self,
        base_url: str,
        instance_name: str,
        username: str,
        password: str,
        user_domain: str = "",
        verify_ssl: bool = False,
    ):
        self.base_url = base_url.rstrip("/")
        self.instance_name = instance_name
        self.username = username
        self.password = password
        self.user_domain = user_domain
        self.session_token: str | None = None
        self._http = httpx.AsyncClient(
            base_url=self.base_url,
            verify=verify_ssl,
            timeout=30.0,
        )

    async def close(self) -> None:
        await self._http.aclose()

    async def __aenter__(self) -> "ArcherRestClient":
        await self.login()
        return self

    async def __aexit__(self, *exc) -> None:
        try:
            await self.logout()
        finally:
            await self.close()

    async def login(self) -> str:
        payload = {
            "InstanceName": self.instance_name,
            "Username": self.username,
            "UserDomain": self.user_domain,
            "Password": self.password,
        }
        resp = await self._http.post(
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

    async def logout(self) -> None:
        if not self.session_token:
            return
        try:
            await self._http.post(
                "/api/core/security/logout",
                headers=self._auth_headers(),
            )
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
        }

    async def get_application_by_name(self, name: str) -> dict | None:
        resp = await self._http.get(
            "/api/core/system/application",
            headers=self._auth_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        apps = data if isinstance(data, list) else data.get("RequestedObject", [])
        for app_wrapper in apps:
            app = app_wrapper.get("RequestedObject", app_wrapper)
            if (app.get("Name") or "").strip().lower() == name.strip().lower():
                return app
        return None

    async def get_levels_for_module(self, module_id: int) -> list[dict]:
        resp = await self._http.get(
            f"/api/core/system/level/module/{module_id}",
            headers=self._auth_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data if isinstance(data, list) else data.get("RequestedObject", [])
        return [item.get("RequestedObject", item) for item in raw]

    async def get_field_definitions(self, level_id: int) -> list[dict]:
        resp = await self._http.get(
            f"/api/core/system/fielddefinition/level/{level_id}",
            headers=self._auth_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data if isinstance(data, list) else data.get("RequestedObject", [])
        return [item.get("RequestedObject", item) for item in raw]

    async def get_values_list(self, values_list_id: int) -> list[dict]:
        resp = await self._http.get(
            f"/api/core/system/valueslistvalue/flat/valueslist/{values_list_id}",
            headers=self._auth_headers(),
        )
        resp.raise_for_status()
        data = resp.json()
        raw = data if isinstance(data, list) else data.get("RequestedObject", [])
        return [item.get("RequestedObject", item) for item in raw]

    async def create_content_record(
        self,
        level_id: int,
        field_contents: dict,
    ) -> str | None:
        payload = {
            "Content": {
                "LevelId": level_id,
                "FieldContents": field_contents,
            }
        }
        resp = await self._http.post(
            "/api/core/content",
            content=json.dumps(payload),
            headers=self._auth_headers(),
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
        return str(content_id) if content_id is not None else None


# ---------------------------------------------------------------------------
# Archer Publisher
# ---------------------------------------------------------------------------

class ArcherPublisher:
    """
    Consumes a Clarity archer payload and creates records in Archer.
    Supports dry-run mode for testing without live credentials.
    """

    def __init__(
        self,
        enabled: bool,
        base_url: str,
        instance_name: str,
        username: str,
        password: str,
        user_domain: str = "",
        verify_ssl: bool = False,
        auth_package_module_name: str = "RTX GRC Authorization Package",
        hardware_module_name: str = "RTX GRC Hardware",
    ):
        self.enabled = enabled
        self.base_url = base_url
        self.instance_name = instance_name
        self.username = username
        self.password = password
        self.user_domain = user_domain
        self.verify_ssl = verify_ssl
        self.auth_package_module_name = auth_package_module_name
        self.hardware_module_name = hardware_module_name

        self._hw_level_id: int | None = None
        self._hw_field_defs: list[dict] = []
        self._ap_level_id: int | None = None
        self._ap_field_defs: list[dict] = []
        self._values_list_cache: dict[int, list[dict]] = {}

    async def publish(
        self,
        clarity_payload: dict,
        progress_callback: Callable[[str], None] | None = None,
    ) -> PublishResult:
        """
        Publish a Clarity payload to Archer.

        Args:
            clarity_payload: The JSON payload from archer_export_service
                             (either full wrapper or inner payload dict)
            progress_callback: Optional callback invoked with each step name
                               as it completes, for UI updates

        Returns:
            PublishResult with success status and content IDs
        """
        result = PublishResult(success=False, dry_run=not self.enabled)

        def step(name: str) -> None:
            result.steps_completed.append(name)
            if progress_callback:
                progress_callback(name)

        # Unwrap the payload envelope if present
        if "payload" in clarity_payload and "content" in clarity_payload.get("payload", {}):
            payload = clarity_payload["payload"]
        else:
            payload = clarity_payload

        fields = payload.get("content", {}).get("fields", [])
        if not fields:
            result.errors.append("No fields found in Clarity payload")
            return result

        fields_by_name: dict[str, dict] = {
            f.get("field_name", ""): f for f in fields
        }

        # Dry-run short-circuit
        if not self.enabled:
            log.info(
                "Archer publish DRY RUN (enabled=False). Payload has %d fields.",
                len(fields),
            )
            step(STEP_CONNECT)
            step(STEP_HARDWARE)
            step(STEP_AUTH_PACKAGE)
            step(STEP_COMPLETE)
            result.success = True
            result.auth_package_content_id = "DRY_RUN_AP_ID"
            result.hardware_content_ids = [
                f"DRY_RUN_HW_{i}"
                for i in range(len(
                    fields_by_name.get("HARDWARE_INVENTORY", {}).get("records", [])
                ))
            ]
            result.warnings.append(
                "Dry run mode — no actual Archer API calls were made. "
                "Set CLARITY_ARCHER_PUBLISH_ENABLED=true to publish live."
            )
            return result

        # Live publish
        try:
            async with ArcherRestClient(
                base_url=self.base_url,
                instance_name=self.instance_name,
                username=self.username,
                password=self.password,
                user_domain=self.user_domain,
                verify_ssl=self.verify_ssl,
            ) as client:
                step(STEP_CONNECT)

                await self._discover_modules(client, result)

                if self._ap_level_id is None:
                    result.errors.append(
                        f"Could not find Archer module '{self.auth_package_module_name}'"
                    )
                    return result

                # Step 1: hardware records
                hardware_field = fields_by_name.get("HARDWARE_INVENTORY")
                hw_content_ids: list[str] = []
                if hardware_field and self._hw_level_id is not None:
                    hw_content_ids = await self._publish_hardware_records(
                        client, hardware_field, result
                    )
                    result.hardware_content_ids = hw_content_ids
                elif hardware_field:
                    result.warnings.append(
                        f"Hardware module '{self.hardware_module_name}' not found; "
                        "skipping hardware records"
                    )
                step(STEP_HARDWARE)

                # Step 2: auth package
                ap_content_id = await self._publish_auth_package(
                    client, fields_by_name, hw_content_ids, result
                )
                result.auth_package_content_id = ap_content_id
                step(STEP_AUTH_PACKAGE)

                result.success = ap_content_id is not None
                if result.success:
                    step(STEP_COMPLETE)

        except Exception as e:
            log.exception("Publish failed")
            result.errors.append(f"Publish exception: {e}")

        return result

    async def _discover_modules(
        self,
        client: ArcherRestClient,
        result: PublishResult,
    ) -> None:
        ap_app = await client.get_application_by_name(self.auth_package_module_name)
        if ap_app:
            ap_module_id = ap_app.get("Id")
            levels = await client.get_levels_for_module(ap_module_id)
            if levels:
                self._ap_level_id = levels[0].get("Id")
                self._ap_field_defs = await client.get_field_definitions(self._ap_level_id)
                log.info(
                    "Discovered auth package module: level_id=%s, fields=%d",
                    self._ap_level_id,
                    len(self._ap_field_defs),
                )

        hw_app = await client.get_application_by_name(self.hardware_module_name)
        if hw_app:
            hw_module_id = hw_app.get("Id")
            levels = await client.get_levels_for_module(hw_module_id)
            if levels:
                self._hw_level_id = levels[0].get("Id")
                self._hw_field_defs = await client.get_field_definitions(self._hw_level_id)
                log.info(
                    "Discovered hardware module: level_id=%s, fields=%d",
                    self._hw_level_id,
                    len(self._hw_field_defs),
                )

    async def _publish_hardware_records(
        self,
        client: ArcherRestClient,
        hardware_field: dict,
        result: PublishResult,
    ) -> list[str]:
        created_ids: list[str] = []
        records = hardware_field.get("records", [])
        if not records:
            return created_ids

        for idx, record in enumerate(records):
            field_contents = await self._build_hardware_field_contents(
                client, record, result
            )
            if not field_contents:
                result.warnings.append(f"Hardware row {idx} produced no field contents; skipped")
                continue

            content_id = await client.create_content_record(
                self._hw_level_id,
                field_contents,
            )
            if content_id:
                created_ids.append(content_id)
                log.info("Created hardware record %s for row %d", content_id, idx)
            else:
                result.errors.append(f"Failed to create hardware record for row {idx}")

        return created_ids

    async def _build_hardware_field_contents(
        self,
        client: ArcherRestClient,
        record: dict,
        result: PublishResult,
    ) -> dict:
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
                    vl_entry = await self._resolve_values_list_value(client, vl_id, value)
                    if vl_entry:
                        contents[str(field_id)] = self._values_list_line(
                            field_id, [vl_entry]
                        )
                    else:
                        result.warnings.append(
                            f"Values list value not found: {clarity_field}={value}"
                        )
            else:
                contents[str(field_id)] = self._text_line(field_id, value)

        return contents

    async def _publish_auth_package(
        self,
        client: ArcherRestClient,
        fields_by_name: dict,
        hardware_content_ids: list[str],
        result: PublishResult,
    ) -> str | None:
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
                            vl_entry = await self._resolve_values_list_value(client, vl_id, v)
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
                    contents[str(field_id)] = self._text_line(
                        field_id, ", ".join(str(v) for v in values)
                    )

        # Cross-reference to hardware
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

        content_id = await client.create_content_record(self._ap_level_id, contents)
        if content_id:
            log.info("Created auth package content record %s", content_id)
        else:
            result.errors.append("Failed to create auth package content record")
        return content_id

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

    async def _resolve_values_list_value(
        self,
        client: ArcherRestClient,
        values_list_id: int,
        display_value: str,
    ) -> int | None:
        if values_list_id not in self._values_list_cache:
            self._values_list_cache[values_list_id] = await client.get_values_list(values_list_id)

        entries = self._values_list_cache[values_list_id]
        target = str(display_value).strip().lower()
        for entry in entries:
            name = (entry.get("Name") or "").strip().lower()
            if name == target:
                return entry.get("Id")
        return None


def build_publisher_from_settings(settings) -> ArcherPublisher:
    """Construct an ArcherPublisher from ClaritySettings."""
    return ArcherPublisher(
        enabled=getattr(settings, "archer_publish_enabled", False),
        base_url=getattr(settings, "archer_base_url", ""),
        instance_name=getattr(settings, "archer_instance", ""),
        username=getattr(settings, "archer_username", ""),
        password=getattr(settings, "archer_password", ""),
        user_domain=getattr(settings, "archer_user_domain", ""),
        verify_ssl=getattr(settings, "archer_verify_ssl", False),
        auth_package_module_name=getattr(
            settings,
            "archer_auth_package_module",
            "RTX GRC Authorization Package",
        ),
        hardware_module_name=getattr(
            settings,
            "archer_hardware_module",
            "RTX GRC Hardware",
        ),
    )
