# Clarity → Postgres → Archer JSON Pipeline

## Overview

This document describes the data flow from user questionnaire input through
Postgres storage to Archer-consumable JSON payload generation.

## Pipeline

```
User fills out questionnaire (frontend)
        │
        ▼
POST /projects/{id}/responses  (FastAPI)
        │
        ▼
Responses stored in Postgres   (Project.responses JSON column)
        │
        ▼
GET /projects/{id}/archer-payload  (FastAPI)
        │
        ▼
Archer-consumable JSON payload  (handed off to Archer developer)
```

## Files to Add

### 1. `backend/src/clarity/services/archer_export_service.py`
Drop-in service file. No changes to existing files needed.

### 2. `backend/src/clarity/routes/archer_export_routes.py`
Drop-in route file. Register in your FastAPI app.

### 3. Register the routes in your API

In your main API file (e.g., `backend/src/clarity/api.py` or wherever
routers are included), add:

```python
from .routes.archer_export_routes import router as archer_export_router
api.include_router(archer_export_router)
```

## Questionnaire Response Storage Format

Responses are stored on the `Project` model's `responses` JSON column.
Each response is a dict:

```json
{
  "question_id": "authorization_package_name",
  "answer": "CLARITY-2026-001",
  "submitted_at": "2026-04-06T12:00:00Z",
  "justification": null
}
```

### Hardware Entry (KV Table) Storage

The `hardware_entry` question stores its answer as a JSON array:

```json
{
  "question_id": "hardware_entry",
  "answer": [
    {
      "hardware_name": "APP-SVR-01",
      "ip_address": "10.50.1.10",
      "hardware_type": "Windows Server",
      "business": "Collins",
      "mac_address": "AA:BB:CC:11:22:33"
    },
    {
      "hardware_name": "DB-SVR-01",
      "ip_address": "10.50.1.20",
      "hardware_type": "Linux",
      "business": "Collins",
      "mac_address": "AA:BB:CC:44:55:66"
    }
  ],
  "submitted_at": "2026-04-06T12:00:00Z",
  "justification": null
}
```

Each hardware row becomes an element in the array. The `KVTableInput.vue`
component on the frontend should serialize the table rows into this format
before POSTing.

## Archer Field Mapping

| Clarity Question ID              | Archer Field Name                  | Type              |
|----------------------------------|------------------------------------|-------------------|
| authorization_package_name       | AUTHORIZATION_PACKAGE_NAME         | text              |
| clara_id                         | CLARA_ID                           | text              |
| entity                           | ENTITY                             | values_list       |
| rtx_business                     | BUSINESS                           | values_list       |
| mission_purpose                  | MISSION_PURPOSE                    | text              |
| information_classification       | INFORMATION_CLASSIFICATION         | values_list_multi |
| connectivity                     | CONNECTIVITY                       | values_list_multi |
| authorization_boundary_description | AUTHORIZATION_BOUNDARY_DESCRIPTION | text             |
| system_administrator_id          | SYSTEM_ADMINISTRATOR_ID            | text              |
| hardware_entry                   | HARDWARE_INVENTORY                 | sub_record        |

### Hardware Sub-Record Column Mapping

| Clarity Column   | Archer Column   |
|------------------|-----------------|
| hardware_name    | HARDWARE_NAME   |
| ip_address       | IP_ADDRESS      |
| hardware_type    | HARDWARE_TYPE   |
| business         | BUSINESS_UNIT   |
| mac_address      | MAC_ADDRESS     |

## Environment Variables (Optional)

The Archer module/level IDs are configurable. Add to your `.env`:

```
ARCHER_MODULE_NAME=IRAMP_ATO
ARCHER_MODULE_ID=<your_module_id>
ARCHER_LEVEL_ID=<your_level_id>
ARCHER_INSTANCE_NAME=<your_instance_name>
```

These flow through `ClaritySettings` into `ArcherExportConfig`.

## API Usage

### Get Archer payload
```
GET /projects/{project_id}/archer-payload
```

Returns:
```json
{
  "success": true,
  "project_id": "a1b2c3d4",
  "payload": { ... }
}
```

### Export with custom config
```
POST /projects/{project_id}/archer-payload/export
Content-Type: application/json

{
  "module_name": "IRAMP_ATO",
  "module_id": "123",
  "level_id": "456"
}
```

## Handoff to Archer Developer

The JSON payload from `GET /projects/{id}/archer-payload` contains
everything needed to create Archer content records:

- `metadata` — project info, Archer module/level IDs
- `content.fields` — flat list of all fields with types and values
- `sections` — same fields grouped by Archer section

The Archer developer needs to:
1. Use `archer_service.py` (existing) to log in to Archer
2. Map `field_name` values to actual Archer field IDs using `get_field_definitions()`
3. Use `_make_content_line()` / `_value_content_line()` to build content payloads
4. Call `create_content_record()` to create the records
5. Handle workflow transitions as needed

## Testing

```bash
# Create a project with responses first, then:
curl http://localhost:4000/projects/<project_id>/archer-payload | python -m json.tool
```
