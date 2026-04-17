-- =====================================================================
-- update_q9_entity_cascade.sql
-- =====================================================================
-- Patches the live questionnaire (id=1) with three changes:
--
--   1. Renames Q8 SBU "Air & Space Defense Systems (ADS)"
--      -> "Air & Space Defense Systems (ASDS)" to match the CSV.
--
--   2. Renames Q8 SBU "Legal/Contracts and Compliance"
--      -> "Legal, Contracts and Compliance" to match the CSV.
--
--   3. Replaces Q9 (entity) with a choose-one-cascade definition that
--      depends on Q8 (sbu_organization). 25 SBU keys, 323 total
--      entity options.
--
-- Idempotent: running again is safe (the renames are no-ops on second
-- run, the Q9 replacement is a full overwrite).
--
-- Wrapped in BEGIN/COMMIT so a failure leaves the DB unchanged.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Step 1: Q8 SBU rename "Air & Space Defense Systems (ADS)" -> "(ASDS)"
-- ---------------------------------------------------------------------
UPDATE questionnaire
SET phases_json = (    SELECT jsonb_agg(
        CASE
            WHEN phase ? 'questions' THEN
                jsonb_set(
                    phase,
                    '{questions}',
                    (
                        SELECT jsonb_agg(
                            CASE
                                WHEN q->>'id' = 'sbu_organization'
                                     AND q->'optionsByParent' ? 'Raytheon' THEN
                                    jsonb_set(
                                        q,
                                        '{optionsByParent,Raytheon}',
                                        (
                                            SELECT jsonb_agg(
                                                CASE
                                                    WHEN val::text = '"Air & Space Defense Systems (ADS)"'
                                                        THEN '"Air & Space Defense Systems (ASDS)"'::jsonb
                                                    ELSE val
                                                END
                                            )
                                            FROM jsonb_array_elements(q->'optionsByParent'->'Raytheon') AS val
                                        )
                                    )
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
)::json
WHERE id = 1;

-- ---------------------------------------------------------------------
-- Step 2: Q8 SBU rename "Legal/Contracts and Compliance" -> with comma
-- ---------------------------------------------------------------------
UPDATE questionnaire
SET phases_json = (    SELECT jsonb_agg(
        CASE
            WHEN phase ? 'questions' THEN
                jsonb_set(
                    phase,
                    '{questions}',
                    (
                        SELECT jsonb_agg(
                            CASE
                                WHEN q->>'id' = 'sbu_organization'
                                     AND q->'optionsByParent' ? 'Corporate' THEN
                                    jsonb_set(
                                        q,
                                        '{optionsByParent,Corporate}',
                                        (
                                            SELECT jsonb_agg(
                                                CASE
                                                    WHEN val::text = '"Legal/Contracts and Compliance"'
                                                        THEN '"Legal, Contracts and Compliance"'::jsonb
                                                    ELSE val
                                                END
                                            )
                                            FROM jsonb_array_elements(q->'optionsByParent'->'Corporate') AS val
                                        )
                                    )
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
)::json
WHERE id = 1;

-- ---------------------------------------------------------------------
-- Step 3: Replace Q9 entity question with the new cascade definition.
-- ---------------------------------------------------------------------
UPDATE questionnaire
SET phases_json = (    SELECT jsonb_agg(
        CASE
            WHEN phase ? 'questions' THEN
                jsonb_set(
                    phase,
                    '{questions}',
                    (
                        SELECT jsonb_agg(
                            CASE
                                WHEN q->>'id' = 'entity'
                                    THEN '{"id": "entity", "title": "Entity", "text": "Select the business entity/program/function that owns the authorization package.", "description": null, "type": "choose-one-cascade", "subphase": "General", "options": null, "dependsOn": "sbu_organization", "optionsByParent": {"AMER": ["AMER - Commercial Engine", "AMER - Engineering", "AMER - Fin/HR/Legal/Coms", "AMER - Functions", "AMER - Military Engine", "AMER - Operations", "AMER - PW Canada", "AMER - PWC"], "APAC": ["APAC - Commercial Engine", "APAC - Engineering", "APAC - Fin/HR/Legal/Coms", "APAC - Functions", "APAC - Military Engine", "APAC - Operations", "APAC - PW Canada", "APAC - PWC"], "Advanced Products & Solutions (APS)": ["EO/IR Solutions", "Jaguar", "Radio Frequency (RF)", "Space, Imaging & Microelectronics (SIM)", "Space, Imaging, and Microelectronics (SIM)"], "Advanced Structures": ["Actuation Systems - Crompton Technologies (Banbury, UK)", "Actuation Systems France (St Ouen, Vernon, Buc )", "Actuation Systems Italy (Microtecnica) (Turin, Italy)", "Actuation Systems UK (Wolverhampton, UK)", "Advanced Laboratory on Embedded Systems srl (ALES)", "Advanced Structures", "Aerostructures - (Everett, Washington)", "Aerostructures - (Foley, AL)", "Aerostructures - (Hamburg, Germany)", "Aerostructures - (Riverside, CA)", "Aerostructures - (San Marcos, Texas)", "Aerostructures - Dutch Thermoplastics (Almere, NL)", "Aerostructures - Foley MRO (Foley, AL)", "Aerostructures - France MRO (Toulouse, France)", "Aerostructures - France OE (Toulouse, France)", "Aerostructures - Mexicali (Mexicali, Mexico)", "Aerostructures - Prestwick (Prestwick, Scotland)", "Aerostructures - Rohr Inc (Chula Vista, CA)", "Aerostructures - Singapore (Singapore)", "Aerostructures - Tianjin MRO (Tianjin, China)", "Aerostructures - Tianjin OE (Tianjin, China)", "Aerostructures - Turkey (Istanbul, Turkey)", "Aerostructures Luxembourg (LUXMEX)", "Carbon Operations Wheels and Brakes", "Customer Service - USA (Monroe, NC)", "Engineered Polymer Products - EPP (Jacksonville, FL)", "Goodrich Aerospace Poland", "Hoist and Winch - France (St. Ouen, France)", "Landing Gear - Canada (Oakville, Ontario)", "Landing Gear - Menasco (Everett Facility (Boeing)) (Menasco Washington)", "Landing Gear - Poland (Krosno/Rzeszow,Poland)", "Landing Gear - US Operations (independence OH)", "PS - Ratier Figeac (Figeac, France)", "Wheels and Brakes - Australia (Sydney, Australia)", "Wheels and Brakes - Domestic (Troy, OH)", "Wheels and Brakes - Hong Kong (Fanling, Hong Kong)", "Wheels and Brakes - UK (Hatfield,UK)"], "Advanced Technology (AT)": ["Advanced Architectures", "Advanced Effectors & Space", "Advanced Integrated Surface Sensors", "Air Dominance (AD)", "Airborne Spectrum Dominance"], "Air & Space Defense Systems (ASDS)": ["Mission Solutions & Payloads (MSP)", "RGNext", "Space Intelligence, Surveillance and Reconnaissance (SISR)", "Strategic Sensors & Precision Strike (SSPS)", "Strike Initiatives (SI)"], "Avionics": ["AVIC Leihua RC Avionics Co (ALRAC)", "Avionics", "Avionics (Excluding IMS) Cedar Rapids", "Beijing, CN", "Bellevue, WA", "Blagnac, FR", "Bothell, WA", "Burnsville, MN", "CA Enterprise Private Ltd (Hyderabad, India)", "CA Enterprises Private Ltd (Bangalore, India)", "Calexico, CA", "Cedar Rapids, Elbit Vision Systems LLC, JV", "College Park", "Collins Aerospace Canada (Montreal)", "Collins India Private Ltd (Gurgaon, India)", "Decorah, IA", "Federal Way, WA", "Goodrich Hoist and Winch- Anaheim (prev. Brea)", "Huntsville, AL", "IMS", "IMS Singapore", "IMS UK", "Kidde Aerospace (Wilson, NC)", "Kidde Aerospace and Defence Australia (Australia)", "Kidde Deugra (ratingen,Germany)", "Kidde Graviner (Colnbrook, UK)", "Kidde LHotellier (Antony, France)", "Mexicali", "Middle East Sales Office", "Midwest, OK", "RC AUS", "RC CAN", "RC CETCA Avionics Co (RCCAC) Chengdu", "RC Germany", "RC UK", "Rosemount Munich (Germany)", "Sao Jose dos Campos, BR", "Sensor Systems - Minnesota (Burnsville, MN)", "Shanghai", "Singapore, SG", "Tampa, FL", "Thiais, FR", "Wilsonville, OR"], "Central": ["Central", "Charlotte", "Communications", "Customer and Account Management", "Digital Technology Cyber", "Digital Technology Data", "Digital Technology Engineering", "Digital Technology Infra", "Digital Technology International", "Digital Technology Strategy & Operations", "Engineering and Technology", "Enterprise Operations", "Finance", "Human Resources", "Legal, Contracts, and Compliance (LCC)", "Strategic Development"], "Connected Aviation Solutions": ["Connected Aviation Solutions", "Flight Aware", "Los Angeles, CA", "MIAMI - Executive Aircraft Seating", "Manchester, UK", "RC Brazil", "RC France", "RC Singapore"], "Corporate Strategy & Development": ["*No Known Entity - Corporate Strategy & Development"], "EMEA": ["EMEA - Commercial Engine", "EMEA - Engineering", "EMEA - Fin/HR/Legal/Coms", "EMEA - Functions", "EMEA - Military Engine", "EMEA - Operations", "EMEA - PW Canada", "EMEA - PWC"], "Enterprise Services": ["Customer Service and Operational Excellence", "Enterprise Application Services (EAS)", "Enterprise Business Services", "Enterprise Communications", "Enterprise Cybersecurity Services (ECS)", "Enterprise Data Services (EDX)", "Enterprise Finance", "Enterprise Human Resources", "Enterprise Infrastructure Services (EIS)", "Enterprise Realty Services", "Enterprise Services Transformation and Strategy", "Process and Systems Transformation"], "Finance": ["Accounting", "Controller", "Financial Planning & Analysis", "Internal Audit", "Investor Relations", "Pension", "RTX Ventures", "Tax", "Treasury"], "Functions and International (F&I)": ["Australia", "Digital Services", "Digital Technology", "Engineering Services", "Factory and Operations", "Labs", "RUK"], "Global Communications": ["*No Known Entity - Global Communications"], "Global Government Relations": ["*No Known Entity - Global Government Relations"], "Human Resources": ["Diversity, Equity & Inclusion", "Employee & Labor Relations", "Executive Development & Succession", "Global Talent Development", "HR Strategy & Transformation", "Total Rewards"], "Interiors": ["Altis", "BE Engineering Services India Pvt Ltd", "Consolidated Philippines", "Customer Services - Dubai (Dubai, UAE)", "De-Icing & Specialty Systems (Uniontown, OH)", "Fischer F and E Gmbh (Landshut)", "GEC- Motor Drive Systems Center (MDSC) (Hemel Hempstead,UK)", "Interiors", "Interiors - Cargo Systems (Jamestown,ND)", "Interiors - India (Bangalore, India)", "Interiors - Lighting Systems (Phoenix,AZ)", "Interiors - Lighting Systems - Germany (Lippstadt, Germany)", "Interiors - Specialty Seating (Colorado Springs, CO)", "Interiors Cabin Systems (Wichita, Peshtigo & Jeffersonville)", "Interiors Evacuation Systems (Phoenix ,AZ)", "Kilkeel Seating New Equipment", "Lavatory Systems Everett - Ecosystems/Structures & Integration - FSI", "Lenexa", "Lighting - Bohemia", "Lighting - Harness", "Lighting - New Berlin", "Lighting - Winnipeg", "Mirabel (Canada)", "Nieuwegein", "Nogales - Mexico", "Oxygen & PSU Systems - Lubeck", "Page Airsigna (Lippstadt,Germany)", "Paris, FR", "Refrigeration - Shanghai", "Teklam, Cornoa, CA", "WASP", "Winslow Marine Products (Lake Suzy, FL)", "Winston Salem DataCenter", "Winston Sales Seating Group"], "Land & Air Defense Systems (LADS)": ["Global Patriot", "Lower Tier Air & Missile Defense (LTAMDS)", "Precision Fire & Maneuvers (PF&M)", "Product Support", "Short & Medium Ground Based Air Defense (SMGBAD)"], "Legal, Contracts and Compliance": ["Antitrust", "Contract Vehicle Center", "Contracts", "Global Ethics & Compliance", "Global Trade", "IP Counsel", "Litigation", "Other", "RTX Flight"], "Mission Systems": ["ATS Anaheim, CA", "ATS Japan", "ATS TAIWAN", "Aberdeen", "Atlantic  Inertial Systems - U.K. (Plymouth, U.K.)", "Atlantic Internal Systems - Connecticut (Cheshire, CT)", "Avionics Domestic, Medford, NY", "Binghamton, NY", "Bloomington, IA", "Brazonics, Hampton, NH", "Burgess Hill, GB", "Carlsbad, CA", "Cedar Rapids Data Link Solutions, LLC (JV)", "Cedar Rapids, IA", "Cheshire, CT", "Columbia", "Columbia, MD", "Coralville, IA", "Criel, FR", "Fuel & Utility - Vermont (Vergennes, VT)", "Heidelberg, DE", "Helicopter Seating", "Houston, TX", "ISR - CT (Danbury, CT)", "ISR - Irvine (Irvine, CA)", "ISR - MA (WestFord, MA)", "ISR - Malvern UK (Malvern, UK)", "ISR - NJ (Princeton, NJ)", "ISR - OR (Hood River, OR)", "IT - SAP ERP (Cedar Rapids, IA)", "Intertrade, Cedar Rapids, IA", "J.A. Reinhardt, Mountainhome, PA", "Largo, FL", "MACROLINK", "Machined Products", "Mission Systems", "Mission Systems Domestic", "Orlando, FL", "Ottawa, CA (Canada)", "Propulsion System (Fairfield, CA)", "Refrigeration Products - Anaheim", "Richardson, TX", "Salt Lake City, UT", "Silicon Sensing Products (UK) Limited", "Simmonds Precision Products (Vergennes, VT)", "Sterling, VA", "Warner Robins, GA", "Westford, MA", "Winnersh", "Woven, Simpsonville, SC"], "Naval Power (NP)": ["Advanced Common Products (ACP)", "Naval Air Missiles (NAM)", "Naval Airborne Systems (NAS)", "Naval Integrated Solutions (NIS)", "Shipboard Missiles (SM)"], "Operations & Supply Chain": ["Advanced Operations", "Business Resilience & Crisis Management", "ERP Business Transformation", "Environmental Health & Safety", "Global Security Services", "Industry 4.0, CORE and Quality", "Strategy and Transformation", "Supply Chain"], "Power Controls": ["Actuation Systems - Rockford (Rockford, IL)", "Aero Engine Controls (Widnes, UK)", "Aero Nozzles - IA (West Des Moines, IA)", "CS - Engine Control Systems - Marston Green UK (Marston Green,UK)", "CS - Engine Control Systems - Neuss, Germany (Neuss, Germany)", "CS - FAST (Singapore)", "CS - Goodrich TAECO Aeronautical Systems Co. (Xiamen,China)", "CS - Miramar Repair (Miramar, FL)", "CS - Phoenix Repair (Phoenix, AZ)", "CS - Shannon (Shannon,Ireland)", "Dijon Repair (Dijon,France)", "GEC (Phoneix,AZ)", "HS Germany (Nordlingen,Germany)", "HS Kalisz (Kalisz, Poland)", "HS Maastricht (Maastricht, Netherlands)", "HS Marston (Wolverhampton,UK)", "HS Nauka (Moscow, Russia)", "HS Wroclaw (Wroclaw Poland)", "HS_SLS_Pomona & Long Beach", "Nord Micro (Frankfurt, Germany)", "Power Controls", "Power Transmission (Rome, NY)", "Walbar (Peabody MA)", "Windsor Locks, CT", "Xian (JV) China"], "Technology & Global Engineering": ["Aerospace Technology", "BBN", "Defense Technology", "Global Engineering", "Product Cybersecurity", "Research Center", "Secure Processing"]}, "justificationRequired": false, "review": false}'::jsonb
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
)::json
WHERE id = 1;

-- ---------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------

-- Q9 should be choose-one-cascade with 25 SBU keys
SELECT
    q->>'id'        AS question_id,
    q->>'type'      AS question_type,
    q->>'dependsOn' AS depends_on,
    (
        SELECT count(*) FROM jsonb_object_keys(q->'optionsByParent')
    ) AS sbu_key_count,
    (
        SELECT sum(jsonb_array_length(value))::int
        FROM jsonb_each(q->'optionsByParent')
    ) AS total_entity_count
FROM questionnaire,
     jsonb_array_elements(phases_json) AS phase,
     jsonb_array_elements(phase->'questions') AS q
WHERE id = 1 AND q->>'id' = 'entity';

-- Q8 should now have ASDS (not ADS) and "Legal, Contracts..." (with comma)
SELECT q->'optionsByParent'->'Raytheon' AS raytheon_sbus
FROM questionnaire,
     jsonb_array_elements(phases_json) AS phase,
     jsonb_array_elements(phase->'questions') AS q
WHERE id = 1 AND q->>'id' = 'sbu_organization';

SELECT q->'optionsByParent' ? 'Legal, Contracts and Compliance' AS has_new_name,
       q->'optionsByParent' ? 'Legal/Contracts and Compliance'  AS has_old_name
FROM questionnaire,
     jsonb_array_elements(phases_json) AS phase,
     jsonb_array_elements(phase->'questions') AS q
WHERE id = 1 AND q->>'id' = 'sbu_organization';

COMMIT;
