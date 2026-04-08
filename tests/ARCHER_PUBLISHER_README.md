# Archer Publisher (MVP)

Python port of the `ArcherCSharp` publisher. Takes a Clarity-generated JSON
payload and creates corresponding content records in RSA Archer GRC via the
REST API.

## What it does

1. **Reads** a JSON file produced by Clarity's `/project/{id}/archer-payload` endpoint
2. **Logs in** to Archer via REST API using credentials from environment variables
3. **Discovers** the target Archer module field IDs dynamically (no hardcoding)
4. **Creates** one hardware content record per row in the Clarity hardware table
5. **Creates** the auth package content record with cross-references to hardware
6. **Returns** a result dict with created content IDs and any errors

## What it doesn't do (yet)

- No Snowflake integration (fields are discovered via Archer REST API)
- No user lookups (`HARDWARE_OWNER`, `SYSTEM_ADMINISTRATOR_SA`) — text fallback only
- No Business/Entity/SubOrganization cross-references from Snowflake
- No workflow transitions after record creation
- No duplicate detection (create-only)

These are future enhancements.

## Setup

### Install dependencies
```bash
pip install httpx
```

### Environment variables
```bash
export ARCHER_BASE_URL="https://archergrc.corp.rtx.com/"
export ARCHER_INSTANCE="ArcherPOC"
export ARCHER_USERNAME="your_username"
export ARCHER_PASSWORD="your_password"
export ARCHER_USER_DOMAIN=""
export ARCHER_VERIFY_SSL="false"

# Optional overrides for module names
export ARCHER_AUTH_PACKAGE_MODULE="RTX GRC Authorization Package"
export ARCHER_HARDWARE_MODULE="RTX GRC Hardware"
```

## Usage

### As a CLI
```bash
python archer_publisher.py archer_payload_sample.json
```

Output:
```json
{
  "success": true,
  "auth_package_content_id": "54321",
  "hardware_content_ids": ["12345", "12346"],
  "errors": [],
  "warnings": []
}
```

### As a library
```python
from archer_publisher import ArcherPublisher

publisher = ArcherPublisher.from_env()
result = publisher.publish_from_file("archer_payload.json")

if result.success:
    print(f"Created auth package {result.auth_package_content_id}")
    print(f"Created {len(result.hardware_content_ids)} hardware records")
else:
    print(f"Errors: {result.errors}")
```

### End-to-end from Clarity
```python
import httpx
from archer_publisher import ArcherPublisher

# 1. Fetch the payload from Clarity
clarity_resp = httpx.get(
    "http://clarity.onertx.com/be/project/<project_id>/archer-payload",
    headers={"Authorization": "Bearer <token>"},
)
payload = clarity_resp.json()

# 2. Publish to Archer
publisher = ArcherPublisher.from_env()
result = publisher.publish(payload)
```

## Field mapping

The publisher maps Clarity field names to Archer field names using alias lists.
If Archer uses different display names, add them to `AUTH_PACKAGE_FIELD_ALIASES`
or `HARDWARE_FIELD_ALIASES` at the top of the module.

### Auth package fields
| Clarity field                      | Archer field (aliases)                                          |
|------------------------------------|------------------------------------------------------------------|
| AUTHORIZATION_PACKAGE_NAME         | Authorization Package Name                                       |
| CLARA_ID                           | Clara ID, CLARA                                                  |
| ENTITY                             | Entity                                                           |
| BUSINESS                           | Business                                                         |
| MISSION_PURPOSE                    | Mission Purpose, Mission/Purpose                                 |
| INFORMATION_CLASSIFICATION         | Information Classification                                       |
| CONNECTIVITY                       | Connectivity                                                     |
| AUTHORIZATION_BOUNDARY_DESCRIPTION | Authorization Boundary Description                               |
| SYSTEM_ADMINISTRATOR_ID            | System Administrator (SA), System Administrator                  |

### Hardware fields
| Clarity column     | Archer field (aliases)                                    |
|--------------------|-----------------------------------------------------------|
| HARDWARE_NAME      | Hardware Name                                             |
| IP_ADDRESS         | IP Address, Internal IP Address, INTERNAL_IP_ADDRESS      |
| HARDWARE_TYPE      | Hardware Type, Type, TYPE                                 |
| BUSINESS_UNIT      | Business Unit, Business, BUSINESS                         |
| MAC_ADDRESS        | MAC Address                                               |

## Content line types supported

| Archer Type | Name              | Used for                                       |
|-------------|-------------------|------------------------------------------------|
| 1           | Text              | All text fields                                |
| 4           | Values List       | Single + multi-select dropdowns                |
| 9           | Cross-Reference   | Hardware → Auth Package linking                |

Future additions:
- Type 8 (User/Groups List) for system admin and hardware owner lookups

## Testing

To test without hitting real Archer, you can mock the `ArcherRestClient`:

```python
from unittest.mock import MagicMock
from archer_publisher import ArcherPublisher, ArcherConfig

config = ArcherConfig(
    base_url="http://fake",
    instance_name="test",
    username="test",
    password="test",
)
publisher = ArcherPublisher(config)
# ... inject a mock client ...
```

## Troubleshooting

**"Archer login failed"**
- Check `ARCHER_USERNAME`, `ARCHER_PASSWORD`, `ARCHER_INSTANCE`
- If using SSO, you may need a service account with basic auth enabled

**"Module not found"**
- The module display name in Archer may differ. Set
  `ARCHER_AUTH_PACKAGE_MODULE` and `ARCHER_HARDWARE_MODULE` env vars to match

**"Field not found" warnings**
- Add additional aliases to `AUTH_PACKAGE_FIELD_ALIASES` or
  `HARDWARE_FIELD_ALIASES` to match the actual Archer field names

**"Values list value not found"**
- The values list entry in Archer doesn't match the Clarity option string.
  Either update the seed data in Clarity or add a mapping layer
