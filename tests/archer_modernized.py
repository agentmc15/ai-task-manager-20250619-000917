"""
Modern Archer REST API Client for Python 3.10+
Refactored with httpx, pydantic, async support, and proper type hints
"""

import logging
from typing import Any, Optional
from pathlib import Path
from collections.abc import Sequence

import httpx
from pydantic import BaseModel, Field, ConfigDict
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
)

from .user import User
from .record import Record

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)-8s %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
log = logging.getLogger(__name__)


# Custom Exceptions
class ArcherAPIError(Exception):
    """Base exception for Archer API errors"""
    pass


class AuthenticationError(ArcherAPIError):
    """Raised when authentication fails"""
    pass


class ApplicationNotFoundError(ArcherAPIError):
    """Raised when application is not found"""
    pass


class GroupNotFoundError(ArcherAPIError):
    """Raised when group is not found"""
    pass


class RecordNotFoundError(ArcherAPIError):
    """Raised when record is not found"""
    pass


class FieldNotFoundError(ArcherAPIError):
    """Raised when field is not found"""
    pass


# Pydantic Models
class AuthCredentials(BaseModel):
    """Authentication credentials"""
    instance_name: str
    username: str
    password: str
    user_domain: str = ""

    model_config = ConfigDict(frozen=True)


class TokenAuth(BaseModel):
    """Token-based authentication"""
    session_token: str

    model_config = ConfigDict(frozen=True)


class SSLConfig(BaseModel):
    """SSL Configuration"""
    verify: bool = True
    ca_cert_path: Optional[Path] = None

    model_config = ConfigDict(arbitrary_types_allowed=True)

    def get_verify_param(self) -> bool | str:
        """Get the verify parameter for httpx"""
        if not self.verify:
            return False
        if self.ca_cert_path:
            return str(self.ca_cert_path)
        return True


class FieldDefinition(BaseModel):
    """Field definition model"""
    field_id: int = Field(alias="FieldId")
    field_type: int = Field(alias="Type")
    name: str = Field(default="")

    model_config = ConfigDict(populate_by_name=True)


class ArcherInstance:
    """
    Modern Archer instance client with async support.
    
    Args:
        inst_url: Archer instance base URL (without https://)
        instance_name: Archer instance name
        username: API user username (if using password auth)
        password: API user password (if using password auth)
        session_token: Session token (if using token auth)
        ssl_verify: Enable SSL verification (default: True)
        ca_cert_path: Path to custom CA certificate
        timeout: Request timeout in seconds (default: 30.0)
    """

    def __init__(
        self,
        inst_url: str,
        instance_name: str,
        username: str | None = None,
        password: str | None = None,
        session_token: str | None = None,
        ssl_verify: bool = True,
        ca_cert_path: Path | str | None = None,
        timeout: float = 30.0,
    ):
        self.api_url_base = f"https://{inst_url}/RSAarcher/api/"
        self.content_api_url_base = f"https://{inst_url}/RSAarcher/contentapi/"
        self.instance_name = instance_name
        self.timeout = timeout

        # SSL Configuration
        ca_path = Path(ca_cert_path) if ca_cert_path else None
        self.ssl_config = SSLConfig(verify=ssl_verify, ca_cert_path=ca_path)

        # Authentication
        self._credentials: AuthCredentials | None = None
        self._session_token: str | None = session_token

        if username and password:
            self._credentials = AuthCredentials(
                instance_name=instance_name,
                username=username,
                password=password
            )
        elif not session_token:
            raise ValueError("Either username/password or session_token must be provided")

        # HTTP Client (created lazily)
        self._client: httpx.AsyncClient | None = None

        # Application state
        self.application_level_id: str = ""
        self.application_fields_json: dict[str | int, Any] = {}
        self.all_application_fields_array: list[int] = []
        self.vl_name_to_vl_id: dict[str, int] = {}
        self.subforms_json_by_sf_name: dict[str, dict[str, Any]] = {}
        self.key_field_value_to_system_id: dict[str, int] = {}
        self.archer_groups_name_to_id: dict[str, int] = {}

    async def __aenter__(self):
        """Async context manager entry"""
        await self._ensure_client()
        if not self._session_token:
            await self.get_session_token()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.close()

    async def _ensure_client(self) -> None:
        """Ensure HTTP client is initialized"""
        if self._client is None:
            self._client = httpx.AsyncClient(
                verify=self.ssl_config.get_verify_param(),
                timeout=self.timeout,
            )

    async def close(self) -> None:
        """Close the HTTP client"""
        if self._client:
            await self._client.aclose()
            self._client = None

    @property
    def _headers(self) -> dict[str, str]:
        """Get headers for API requests"""
        headers = {
            "Accept": "application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Content-Type": "application/json",
        }
        if self._session_token:
            headers["Authorization"] = f"Archer session-id={self._session_token}"
        return headers

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type(httpx.NetworkError),
        reraise=True
    )
    async def get_session_token(self) -> str:
        """
        Acquire or refresh session token.
        
        Returns:
            Session token string
            
        Raises:
            AuthenticationError: If authentication fails
        """
        if not self._credentials:
            raise AuthenticationError("No credentials provided for token acquisition")

        await self._ensure_client()
        api_url = f"{self.api_url_base}core/security/login"
        
        headers = {
            "Accept": "application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Content-Type": "application/json"
        }

        try:
            response = await self._client.post(
                api_url,
                headers=headers,
                json={
                    "InstanceName": self._credentials.instance_name,
                    "Username": self._credentials.username,
                    "UserDomain": self._credentials.user_domain,
                    "Password": self._credentials.password,
                }
            )
            response.raise_for_status()
            data = response.json()

            self._session_token = data["RequestedObject"]["SessionToken"]
            log.info("Successfully acquired session token")
            return self._session_token

        except httpx.HTTPStatusError as e:
            log.error(f"Authentication failed: {e}")
            raise AuthenticationError(f"Failed to acquire session token: {e}") from e
        except (KeyError, TypeError) as e:
            log.error(f"Invalid response format: {e}")
            raise AuthenticationError("Invalid authentication response format") from e

    async def get_users(self, params: str = "") -> list[User]:
        """
        Get users from Archer.
        
        Args:
            params: OData query parameters
                Example: "?$select=Id,UserName,DisplayName&$filter=AccountStatus eq '1'"
                
        Returns:
            List of User objects
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/system/user/{params}"

        try:
            response = await self._client.post(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            return [User(self, user) for user in data]

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get users: {e}")
            raise ArcherAPIError(f"Failed to retrieve users: {e}") from e

    async def get_all_groups(self) -> dict[str, int]:
        """
        Get all Archer groups.
        
        Returns:
            Dictionary mapping group names to IDs
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/system/group/"

        try:
            response = await self._client.post(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            self.archer_groups_name_to_id = {
                group["RequestedObject"]["Name"]: group["RequestedObject"]["Id"]
                for group in data
            }
            
            log.info(f"Downloaded {len(self.archer_groups_name_to_id)} groups")
            return self.archer_groups_name_to_id

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get groups: {e}")
            raise ArcherAPIError(f"Failed to retrieve groups: {e}") from e

    def find_group(self, name: str) -> list[str]:
        """
        Find groups matching the given name.
        
        Args:
            name: Group name or partial name to search for
            
        Returns:
            List of matching group names
            
        Raises:
            GroupNotFoundError: If no matching groups found
        """
        if not name:
            return list(self.archer_groups_name_to_id.keys())

        matches = [
            group_name 
            for group_name in self.archer_groups_name_to_id 
            if name in group_name
        ]

        if not matches:
            log.warning(f"No groups found matching '{name}'")
            raise GroupNotFoundError(
                f"No groups found matching '{name}'. "
                f"Available groups: {', '.join(self.archer_groups_name_to_id.keys())}"
            )

        return matches

    def get_group_id(self, group_name: str) -> int:
        """
        Get group ID by name.
        
        Args:
            group_name: Exact name of Archer group
            
        Returns:
            Group ID
            
        Raises:
            GroupNotFoundError: If group not found
        """
        if group_name not in self.archer_groups_name_to_id:
            available = ', '.join(self.archer_groups_name_to_id.keys())
            raise GroupNotFoundError(
                f"Group '{group_name}' not found. Available: {available}"
            )
        
        return self.archer_groups_name_to_id[group_name]

    async def get_user_by_id(self, user_id: int) -> User:
        """
        Get user by ID.
        
        Args:
            user_id: Internal Archer user ID
            
        Returns:
            User object
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/system/user/{user_id}"

        try:
            response = await self._client.post(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            return User(self, data)

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get user {user_id}: {e}")
            raise ArcherAPIError(f"Failed to retrieve user {user_id}: {e}") from e

    async def get_active_users_with_no_login(self) -> list[User]:
        """
        Get active users who have never logged in.
        
        Returns:
            List of User objects
        """
        return await self.get_users(
            "?$select=Id,UserName,DisplayName&$filter=AccountStatus eq '1' "
            "and LastLoginDate eq null&$orderby=LastName"
        )

    async def from_application(self, app_name: str) -> "ArcherInstance":
        """
        Set the application context for subsequent operations.
        
        Args:
            app_name: Application name as it appears in Archer
            
        Returns:
            Self for method chaining
            
        Raises:
            ApplicationNotFoundError: If application not found
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/system/application/"

        try:
            response = await self._client.get(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            for application in data:
                if application["RequestedObject"]["Name"] == app_name:
                    application_id = application["RequestedObject"]["Id"]
                    await self.get_application_fields(application_id)
                    log.info(f"Loaded application: {app_name}")
                    return self

            # Application not found
            available = [app["RequestedObject"]["Name"] for app in data]
            raise ApplicationNotFoundError(
                f'Application "{app_name}" not found. Available: {available}'
            )

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to load application: {e}")
            raise ArcherAPIError(f"Failed to load application: {e}") from e

    async def get_application_fields(self, application_id: int) -> None:
        """
        Load all active fields for an application.
        
        Args:
            application_id: Internal Archer application ID
        """
        await self._ensure_client()
        api_url = (
            f"{self.api_url_base}core/system/fielddefinition/application/"
            f"{application_id}?$filter=IsActive eq true"
        )

        try:
            response = await self._client.get(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            for field in data:
                req_obj = field["RequestedObject"]
                name = req_obj["Name"]
                field_id = req_obj["Id"]
                level_id = req_obj["LevelId"]
                field_type = req_obj["Type"]

                self.all_application_fields_array.append(field_id)
                self.application_fields_json[name] = field_id
                self.application_fields_json[field_id] = {
                    "Type": field_type,
                    "FieldId": field_id
                }

                match field_type:
                    case 4:  # Values list
                        self.vl_name_to_vl_id[name] = req_obj["RelatedValuesListId"]
                    case 24:  # Subform
                        subform_id = req_obj["RelatedSubformId"]
                        subform_fields, all_fields = await self.get_subform_fields_by_id(subform_id)
                        self.subforms_json_by_sf_name[name] = subform_fields
                        self.subforms_json_by_sf_name[name]["AllFields"] = all_fields

            self.application_level_id = str(level_id)
            log.info(f"Loaded {len(self.all_application_fields_array)} fields")

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get application fields: {e}")
            raise ArcherAPIError(f"Failed to retrieve application fields: {e}") from e

    async def get_subform_fields_by_id(
        self, 
        subform_id: int
    ) -> tuple[dict[str, Any], list[int]]:
        """
        Get fields for a subform.
        
        Args:
            subform_id: Subform ID
            
        Returns:
            Tuple of (field definitions dict, list of field IDs)
        """
        await self._ensure_client()
        api_url = (
            f"{self.api_url_base}core/system/fielddefinition/application/"
            f"{subform_id}?$filter=IsActive eq true"
        )

        try:
            response = await self._client.get(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            subform_fields = {}
            field_ids = []

            for field in data:
                req_obj = field["RequestedObject"]
                field_name = req_obj["Name"]
                field_id = req_obj["Id"]
                field_type = req_obj["Type"]
                level_id = req_obj["LevelId"]

                field_ids.append(field_id)
                subform_fields[field_name] = field_id
                subform_fields["LevelId"] = level_id
                subform_fields[field_id] = {
                    "Type": field_type,
                    "FieldId": field_id
                }

            return subform_fields, field_ids

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get subform fields: {e}")
            raise ArcherAPIError(f"Failed to retrieve subform fields: {e}") from e

    def get_vl_id_by_field_name(self, vl_field_name: str) -> int:
        """
        Get values list ID by field name.
        
        Args:
            vl_field_name: Values list field name
            
        Returns:
            Values list ID
            
        Raises:
            FieldNotFoundError: If field not found
        """
        if vl_field_name not in self.vl_name_to_vl_id:
            raise FieldNotFoundError(f"Values list field '{vl_field_name}' not found")
        return self.vl_name_to_vl_id[vl_field_name]

    async def get_value_id_by_field_name_and_value(
        self, 
        field_name: str, 
        value: str
    ) -> list[int]:
        """
        Get value ID from a values list field.
        
        Args:
            field_name: Values list field name
            value: Value to find
            
        Returns:
            List containing the value ID
            
        Raises:
            FieldNotFoundError: If value not found
        """
        values_list_id = self.get_vl_id_by_field_name(field_name)
        await self._ensure_client()
        api_url = (
            f"{self.api_url_base}core/system/valueslistvalue/flat/valueslist/"
            f"{values_list_id}"
        )

        try:
            response = await self._client.get(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            for ind_value in data:
                if ind_value["RequestedObject"]["Name"] == value:
                    return [ind_value["RequestedObject"]["Id"]]

            raise FieldNotFoundError(
                f"Value '{value}' not found in values list '{field_name}'"
            )

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get value ID: {e}")
            raise ArcherAPIError(f"Failed to retrieve value ID: {e}") from e

    def get_field_id_by_name(
        self, 
        field_name: str, 
        subform_name: str | None = None
    ) -> int:
        """
        Get field ID by name.
        
        Args:
            field_name: Field name as shown in application
            subform_name: Subform name if field is in subform
            
        Returns:
            Field ID
            
        Raises:
            FieldNotFoundError: If field not found
        """
        try:
            if subform_name:
                return self.subforms_json_by_sf_name[subform_name][field_name]
            return self.application_fields_json[field_name]
        except KeyError:
            location = f"subform '{subform_name}'" if subform_name else "application"
            raise FieldNotFoundError(f"Field '{field_name}' not found in {location}")

    def _prepare_field_value(self, field_id: int, value_content: Any) -> dict[str, Any]:
        """
        Prepare field value for API submission.
        
        Args:
            field_id: Field ID
            value_content: Value to set
            
        Returns:
            Field definition with value
        """
        field_def = dict(self.application_fields_json[field_id])
        field_def["Value"] = value_content
        return field_def

    async def create_content_record(
        self,
        fields_json: dict[str, Any],
        record_id: int | None = None
    ) -> int:
        """
        Create or update a content record.
        
        Args:
            fields_json: Dict mapping field names to values
            record_id: Record ID if updating existing record
            
        Returns:
            Record ID (created or updated)
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/content/"

        # Transform field names to IDs
        transformed_json = {}
        for field_name, value in fields_json.items():
            field_id = self.get_field_id_by_name(field_name)
            transformed_json[field_id] = self._prepare_field_value(field_id, value)

        # Prepare request
        headers = dict(self._headers)
        
        if record_id:
            headers["X-Http-Method-Override"] = "PUT"
            body = {
                "Content": {
                    "Id": record_id,
                    "LevelId": self.application_level_id,
                    "FieldContents": transformed_json
                }
            }
            method = "put"
            action = "updated"
        else:
            headers["X-Http-Method-Override"] = "POST"
            body = {
                "Content": {
                    "LevelId": self.application_level_id,
                    "FieldContents": transformed_json
                }
            }
            method = "post"
            action = "created"

        try:
            response = await getattr(self._client, method)(
                api_url,
                headers=headers,
                json=body
            )
            response.raise_for_status()
            data = response.json()
            
            result_id = data["RequestedObject"]["Id"]
            log.info(f"Record {action}: {result_id}")
            return result_id

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to {action.rstrip('d')} record: {e}")
            raise ArcherAPIError(f"Failed to {action.rstrip('d')} record: {e}") from e

    async def create_sub_record(
        self,
        fields_json: dict[str, Any],
        subform_name: str
    ) -> int:
        """
        Create a subform record.
        
        Args:
            fields_json: Dict mapping field names to values
            subform_name: Subform name as shown in application
            
        Returns:
            Subrecord ID
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/content/"

        subform_field_id = self.get_field_id_by_name(subform_name)
        subform_level_id = self.subforms_json_by_sf_name[subform_name]["LevelId"]

        # Transform field names to IDs
        transformed_json = {}
        for field_name, value in fields_json.items():
            field_id = self.subforms_json_by_sf_name[subform_name][field_name]
            field_def = dict(self.subforms_json_by_sf_name[subform_name][field_id])
            field_def["Value"] = value
            transformed_json[field_id] = field_def

        headers = dict(self._headers)
        headers["X-Http-Method-Override"] = "POST"

        body = {
            "Content": {
                "LevelId": subform_level_id,
                "FieldContents": transformed_json
            },
            "SubformFieldId": subform_field_id
        }

        try:
            response = await self._client.post(api_url, headers=headers, json=body)
            response.raise_for_status()
            data = response.json()
            
            result_id = data["RequestedObject"]["Id"]
            log.info(f"Subrecord created: {result_id}")
            return result_id

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to create subrecord: {e}")
            raise ArcherAPIError(f"Failed to create subrecord: {e}") from e

    async def delete_record(self, record_id: int) -> None:
        """
        Delete a content record.
        
        Args:
            record_id: Record ID to delete
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/content/{record_id}"

        headers = dict(self._headers)
        headers["X-Http-Method-Override"] = "DELETE"

        body = {
            "Content": {
                "Id": record_id,
                "LevelId": self.application_level_id
            }
        }

        try:
            response = await self._client.delete(api_url, headers=headers, json=body)
            response.raise_for_status()
            log.info(f"Record deleted: {record_id}")

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to delete record {record_id}: {e}")
            raise ArcherAPIError(f"Failed to delete record: {e}") from e

    async def post_attachment(self, name: str, base64_string: str) -> int:
        """
        Upload an attachment.
        
        Args:
            name: Attachment name
            base64_string: File content as base64 string
            
        Returns:
            Attachment ID
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/content/attachment"

        headers = dict(self._headers)
        headers["X-Http-Method-Override"] = "POST"

        body = {
            "AttachmentName": name,
            "AttachmentBytes": base64_string
        }

        try:
            response = await self._client.post(api_url, headers=headers, json=body)
            response.raise_for_status()
            data = response.json()
            
            attachment_id = data["RequestedObject"]["Id"]
            log.info(f"Attachment posted: {attachment_id}")
            return attachment_id

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to post attachment: {e}")
            raise ArcherAPIError(f"Failed to post attachment: {e}") from e

    async def update_content_record(
        self,
        updated_json: dict[str, Any],
        record_id: int
    ) -> int:
        """
        Update an existing content record.
        
        Args:
            updated_json: Dict mapping field names to new values
            record_id: Record ID to update
            
        Returns:
            Record ID
        """
        return await self.create_content_record(updated_json, record_id)

    async def get_record(self, record_id: int) -> Record:
        """
        Get a record by ID.
        
        Args:
            record_id: Internal Archer record ID
            
        Returns:
            Record object
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/content/fieldcontent/"

        headers = dict(self._headers)
        headers["X-Http-Method-Override"] = "POST"

        body = {
            "FieldIds": self.all_application_fields_array,
            "ContentIds": [str(record_id)]
        }

        try:
            response = await self._client.post(api_url, headers=headers, json=body)
            response.raise_for_status()
            data = response.json()

            if not data:
                raise RecordNotFoundError(f"Record {record_id} not found")

            return Record(self, data[0]["RequestedObject"])

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get record {record_id}: {e}")
            raise ArcherAPIError(f"Failed to retrieve record: {e}") from e

    async def get_sub_record(self, sub_record_id: int, sub_record_name: str) -> Record:
        """
        Get a subform record.
        
        Args:
            sub_record_id: Subrecord ID
            sub_record_name: Subform name
            
        Returns:
            Record object
        """
        await self._ensure_client()
        api_url = f"{self.api_url_base}core/content/fieldcontent/"

        all_fields = self.subforms_json_by_sf_name[sub_record_name]["AllFields"]

        headers = dict(self._headers)
        headers["X-Http-Method-Override"] = "POST"

        body = {
            "FieldIds": all_fields,
            "ContentIds": [str(sub_record_id)]
        }

        try:
            response = await self._client.post(api_url, headers=headers, json=body)
            response.raise_for_status()
            data = response.json()

            if not data:
                raise RecordNotFoundError(f"Subrecord {sub_record_id} not found")

            return Record(self, data[0]["RequestedObject"])

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get subrecord {sub_record_id}: {e}")
            raise ArcherAPIError(f"Failed to retrieve subrecord: {e}") from e

    # GRC API Methods (Content API)

    async def find_grc_endpoint_url(self, app_name: str) -> list[str]:
        """
        Find GRC API endpoint URLs matching app name.
        
        Args:
            app_name: Application name to search for
            
        Returns:
            List of matching endpoint URLs
        """
        await self._ensure_client()

        try:
            response = await self._client.get(
                self.content_api_url_base,
                headers=self._headers
            )
            response.raise_for_status()
            data = response.json()

            matches = [
                endpoint["url"]
                for endpoint in data["value"]
                if app_name in endpoint["name"]
            ]

            if matches:
                log.info(f"Found {len(matches)} matching endpoints")
            else:
                log.warning(f"No endpoints found matching '{app_name}'")

            return matches

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to find GRC endpoints: {e}")
            raise ArcherAPIError(f"Failed to find GRC endpoints: {e}") from e

    async def get_grc_endpoint_records(
        self,
        endpoint_url: str,
        skip: int | None = None
    ) -> list[dict[str, Any]]:
        """
        Get records from GRC API endpoint (max 1000 per call).
        
        Args:
            endpoint_url: Endpoint URL from find_grc_endpoint_url()
            skip: Number of records to skip
            
        Returns:
            List of record dicts
        """
        await self._ensure_client()
        
        api_url = f"{self.content_api_url_base}{endpoint_url}"
        if skip is not None:
            api_url += f"?$skip={skip}"

        try:
            response = await self._client.get(api_url, headers=self._headers)
            response.raise_for_status()
            data = response.json()

            return data["value"]

        except httpx.HTTPStatusError as e:
            log.error(f"Failed to get GRC records: {e}")
            raise ArcherAPIError(f"Failed to retrieve GRC records: {e}") from e

    async def build_unique_value_to_id_mapping(
        self,
        endpoint_url: str,
        key_value_field: str,
        prefix: str = "",
        max_records: int = 22000
    ) -> dict[str, int]:
        """
        Build mapping of unique field values to record IDs.
        
        Args:
            endpoint_url: Endpoint URL
            key_value_field: Name of field with unique values
            prefix: Optional prefix to add to field values
            max_records: Maximum records to retrieve
            
        Returns:
            Dict mapping field values to content IDs
        """
        all_records = []
        skip = 0
        consecutive_full_batches = 0

        while skip < max_records:
            batch = await self.get_grc_endpoint_records(endpoint_url, skip)
            
            if not batch:
                break

            all_records.extend(batch)

            if len(batch) == 1000:
                consecutive_full_batches += 1
                if consecutive_full_batches > 21:
                    log.warning("Max batch limit reached, consider increasing max_records")
                    break
            else:
                break

            skip += 1000

        # Build mapping
        for record in all_records:
            if key_value_field in record:
                field_value = f"{prefix}{record[key_value_field]}"
                system_id = record[f"{endpoint_url}_Id"]
                self.key_field_value_to_system_id[field_value] = system_id

        log.info(
            f"Built mapping with {len(self.key_field_value_to_system_id)} records"
        )
        return self.key_field_value_to_system_id

    def get_record_id_by_unique_value(self, key_value: str) -> int:
        """
        Get record ID by unique field value.
        
        Args:
            key_value: Unique field value
            
        Returns:
            Record ID
            
        Raises:
            RecordNotFoundError: If value not found
        """
        if key_value not in self.key_field_value_to_system_id:
            raise RecordNotFoundError(
                f"No record found with key value '{key_value}'"
            )
        return self.key_field_value_to_system_id[key_value]

    def add_record_id_to_mapping(
        self,
        key_value: str,
        system_id: int,
        prefix: str = ""
    ) -> None:
        """
        Add a record to the unique value mapping.
        
        Args:
            key_value: Unique field value
            system_id: Record ID
            prefix: Optional prefix
        """
        field_value = f"{prefix}{key_value}"
        self.key_field_value_to_system_id[field_value] = system_id
        log.debug(f"Added mapping: {field_value} -> {system_id}")
