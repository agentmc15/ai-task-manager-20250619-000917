BEGIN;

-- Q12 Hosting Environment: append "Other" to the options list
-- Current options: PDC1, PDC2, Newington, Commercial Cloud, Gov Cloud
-- After:           PDC1, PDC2, Newington, Commercial Cloud, Gov Cloud, Other
--
-- Note: phases_json is `json` not `jsonb`, so we cast for jsonb operators.
-- The UPDATE writes back as jsonb which the json column accepts.

UPDATE questionnaire
SET phases_json = (
    SELECT jsonb_agg(
        CASE
            WHEN phase ? 'questions' THEN
                jsonb_set(
                    phase,
                    '{questions}',
                    (
                        SELECT jsonb_agg(
                            CASE
                                WHEN q->>'id' = 'hosting_environment'
                                 AND NOT (q->'options' @> '["Other"]'::jsonb)
                                THEN jsonb_set(q, '{options}', (q->'options') || '["Other"]'::jsonb)
                                ELSE q
                            END
                        )
                        FROM jsonb_array_elements(phase->'questions') AS q
                    )
                )
            ELSE phase
        END
    )
    FROM jsonb_array_elements(phases_json::jsonb) AS phase
)
WHERE id = 1;

-- Verify
SELECT q->>'id' AS question_id, q->'options' AS options
FROM questionnaire,
     jsonb_array_elements(phases_json::jsonb) AS phase,
     jsonb_array_elements(phase->'questions') AS q
WHERE id = 1 AND q->>'id' = 'hosting_environment';

COMMIT;
