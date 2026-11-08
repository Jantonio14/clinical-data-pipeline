-- 01_staging.sql — Step 2 of the pipeline: raw TEXT -> clean, typed tables.
-- ------------------------------------------------------------------------
-- WHY THIS LAYER EXISTS
-- raw.* holds everything as TEXT. Here we:
--   * cast columns to real types (DATE, TIMESTAMPTZ, NUMERIC) so date math
--     and SUM() work correctly
--   * keep only the columns we actually use (smaller, easier to read)
--   * add indexes on join keys so queries stay fast
--
-- Run (from the project root):
--   docker exec -i clinical-db psql -U clinical -d clinical -f /sql/01_staging.sql
--
-- If a statement fails with "column does not exist", your Synthea version
-- named it differently. Check the real names with:
--   docker exec -it clinical-db psql -U clinical -d clinical -c '\d raw.procedures'
-- Fixing that yourself is a good exercise — it's exactly what happens when
-- a vendor changes an export format in a real hospital feed.
-- ------------------------------------------------------------------------

-- One transaction: either every table rebuilds, or nothing changes.
BEGIN;

-- DROP ... CASCADE + recreate makes this script re-runnable (idempotent).
DROP SCHEMA IF EXISTS clinical CASCADE;
CREATE SCHEMA clinical;

-- ---------- patients: one row per synthetic person ----------
CREATE TABLE clinical.patients AS
SELECT
    id                              AS patient_id,
    birthdate::date                 AS birth_date,
    NULLIF(deathdate, '')::date     AS death_date,   -- NULL = still living
    gender,
    race,
    ethnicity,
    marital,
    city,
    state,
    county,
    zip
FROM raw.patients;

ALTER TABLE clinical.patients ADD PRIMARY KEY (patient_id);

-- ---------- encounters: every visit (ER, inpatient, wellness, ...) ----------
-- encounterclass is the key field for analysts: inpatient vs emergency vs
-- ambulatory drives most utilization metrics (readmissions, ER use, etc.).
CREATE TABLE clinical.encounters AS
SELECT
    id                                   AS encounter_id,
    patient                              AS patient_id,
    "start"::timestamptz                 AS start_ts,
    NULLIF("stop", '')::timestamptz      AS stop_ts,
    encounterclass                       AS encounter_class,
    code                                 AS encounter_code,   -- SNOMED code
    description,
    base_encounter_cost::numeric         AS base_cost,
    total_claim_cost::numeric            AS total_claim_cost,
    reasoncode                           AS reason_code,
    reasondescription                    AS reason_description
FROM raw.encounters;

ALTER TABLE clinical.encounters ADD PRIMARY KEY (encounter_id);
CREATE INDEX ON clinical.encounters (patient_id);
CREATE INDEX ON clinical.encounters (encounter_class, start_ts);

-- ---------- conditions: diagnoses (diabetes, hypertension, ...) ----------
-- stop_date IS NULL means the condition is still active.
CREATE TABLE clinical.conditions AS
SELECT
    patient                         AS patient_id,
    encounter                       AS encounter_id,
    "start"::date                   AS start_date,
    NULLIF("stop", '')::date        AS stop_date,
    code                            AS condition_code,   -- SNOMED code
    description
FROM raw.conditions;

CREATE INDEX ON clinical.conditions (patient_id);
CREATE INDEX ON clinical.conditions (condition_code);

-- ---------- observations: labs + vitals (A1c, BMI, blood pressure, ...) ----------
-- `value` is mixed: some rows are numbers ("7.2"), some are text
-- ("Never smoker"). We keep the original AND a numeric version that is only
-- filled when the text really looks like a number — a defensive cast that
-- can't crash the load.
CREATE TABLE clinical.observations AS
SELECT
    patient                         AS patient_id,
    encounter                       AS encounter_id,
    "date"::timestamptz             AS observed_ts,
    category,
    code                            AS loinc_code,       -- LOINC = lab/vital code system
    description,
    value                           AS value_text,
    CASE WHEN value ~ '^-?[0-9]+(\.[0-9]+)?$'
         THEN value::numeric END    AS value_numeric,
    units
FROM raw.observations;

CREATE INDEX ON clinical.observations (patient_id);
CREATE INDEX ON clinical.observations (loinc_code, observed_ts);

-- ---------- medications ----------
CREATE TABLE clinical.medications AS
SELECT
    patient                         AS patient_id,
    encounter                       AS encounter_id,
    "start"::timestamptz            AS start_ts,
    NULLIF("stop", '')::timestamptz AS stop_ts,
    code                            AS rxnorm_code,      -- RxNorm = drug code system
    description,
    totalcost::numeric              AS total_cost,
    reasoncode                      AS reason_code,
    reasondescription               AS reason_description
FROM raw.medications;

CREATE INDEX ON clinical.medications (patient_id);

-- ---------- procedures ----------
-- Recent Synthea versions use START/STOP here; very old ones used DATE.
CREATE TABLE clinical.procedures AS
SELECT
    patient                         AS patient_id,
    encounter                       AS encounter_id,
    "start"::timestamptz            AS start_ts,
    code                            AS procedure_code,   -- SNOMED code
    description,
    base_cost::numeric              AS base_cost
FROM raw.procedures;

CREATE INDEX ON clinical.procedures (patient_id);

COMMIT;

-- ANALYZE refreshes the planner's statistics so it picks good query plans
-- on freshly loaded tables.
ANALYZE;

-- Quick sanity check: row counts per table.
SELECT 'patients' AS tbl, COUNT(*) FROM clinical.patients
UNION ALL SELECT 'encounters',   COUNT(*) FROM clinical.encounters
UNION ALL SELECT 'conditions',   COUNT(*) FROM clinical.conditions
UNION ALL SELECT 'observations', COUNT(*) FROM clinical.observations
UNION ALL SELECT 'medications',  COUNT(*) FROM clinical.medications
UNION ALL SELECT 'procedures',   COUNT(*) FROM clinical.procedures;
