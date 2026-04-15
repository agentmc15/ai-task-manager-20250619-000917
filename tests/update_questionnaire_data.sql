-- =============================================================================
-- update_questionnaire_data.sql
--
-- Patches the live `questionnaire.phases_json` row to bring it in sync with
-- the canonical `backend/seed/data.json` for the Phase 3a / feat/render
-- questionnaire (v2). Use this on any environment where the questionnaire
-- was seeded BEFORE these changes were made to data.json.
--
-- This script is idempotent: running it multiple times produces the same
-- final state. It targets questionnaire row id = 1 (the only active row).
--
-- Patches applied:
--   1. Q13 hardware_entry -> hardware_type column options
--      (replaces the 3 placeholder options with the 20 values from
--       Linda's v.2 spec)
--   2. Q12 hosting_environment -> type
--      (choose-one -> choose-many)
--   3. Q12 hosting_environment -> options
--      (replaces the 3 placeholder options with the 6 real values)
--   4. Q12 hosting_environment -> text
--      ("Select the hosting environment for the system."
--       -> "Select all that apply.")
--
-- Run with:
--   docker compose -f docker-compose.production.yaml exec db \
--     psql -U root -d clarity -f /tmp/update_questionnaire_data.sql
--
-- (after `docker cp` ing this file into the container)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Patch 1: Q13 hardware_entry -> hardware_type column options
--   Path: phases[0].questions[12].columns[4].options
-- -----------------------------------------------------------------------------
UPDATE questionnaire
SET phases_json = jsonb_set(
    phases_json::jsonb,
    '{0,questions,12,columns,4,options}',
    '[
        "IP Firewall",
        "IoT Device",
        "IP Phone",
        "KVM",
        "Load Balancer",
        "Printer",
        "Router",
        "Linux Server",
        "Unix Server",
        "Windows Server",
        "Switch",
        "Personal Computer",
        "OT Device",
        "Cloud DataBase",
        "Cloud File Share",
        "Cloud Gateway",
        "Cloud Host",
        "Cloud Load Balancer",
        "Cloud WebServer",
        "Virtual Machine HyperVisor"
    ]'::jsonb
)::json
WHERE id = 1;

-- -----------------------------------------------------------------------------
-- Patch 2 + 3 + 4: Q12 hosting_environment -> type, options, and text
--   Path: phases[0].questions[11]
-- -----------------------------------------------------------------------------
UPDATE questionnaire
SET phases_json = jsonb_set(
    jsonb_set(
        jsonb_set(
            phases_json::jsonb,
            '{0,questions,11,type}',
            '"choose-many"'::jsonb
        ),
        '{0,questions,11,options}',
        '["PDC1","PDC2","Newington","Commercial Cloud","Gov Cloud"]'::jsonb
    ),
    '{0,questions,11,text}',
    '"Select all that apply."'::jsonb
)::json
WHERE id = 1;

-- -----------------------------------------------------------------------------
-- Verification queries (these print but do not modify state)
-- -----------------------------------------------------------------------------
SELECT
    'Q13 hardware_type options'                                AS field,
    phases_json::jsonb #> '{0,questions,12,columns,4,options}' AS value
FROM questionnaire WHERE id = 1
UNION ALL
SELECT
    'Q12 hosting_environment type',
    phases_json::jsonb #> '{0,questions,11,type}'
FROM questionnaire WHERE id = 1
UNION ALL
SELECT
    'Q12 hosting_environment options',
    phases_json::jsonb #> '{0,questions,11,options}'
FROM questionnaire WHERE id = 1
UNION ALL
SELECT
    'Q12 hosting_environment text',
    phases_json::jsonb #> '{0,questions,11,text}'
FROM questionnaire WHERE id = 1;

COMMIT;
