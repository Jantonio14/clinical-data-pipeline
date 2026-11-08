-- analysis.sql — Step 3: YOUR part.
-- ------------------------------------------------------------------------
-- Each block is a business question an EHR/clinical analyst would actually
-- get. Q1 is fully worked to show the pattern. The rest are yours:
-- hints + a skeleton, no answers. Time-box ~25 min each; if stuck, bring
-- me your attempt and we'll review it.
--
-- Run interactively:
--   docker exec -it clinical-db psql -U clinical -d clinical
-- or connect DBeaver to localhost:5432 (user/pass/db: clinical).
--
-- When a query works, write the ANSWER + one sentence of "so what" in the
-- README. Interviewers care about the insight, not just the SQL.
-- ------------------------------------------------------------------------


-- ========================================================================
-- Q1 (WORKED EXAMPLE): How many patients do we have, by gender,
--    and how many are living vs deceased?
-- ========================================================================
-- Pattern: GROUP BY the dimensions you want to slice by, then aggregate.
-- COUNT(*) FILTER (WHERE ...) is a Postgres shortcut for conditional counts
-- (the portable version is SUM(CASE WHEN ... THEN 1 ELSE 0 END)).
SELECT
    gender,
    COUNT(*)                                        AS total_patients,
    COUNT(*) FILTER (WHERE death_date IS NULL)      AS living,
    COUNT(*) FILTER (WHERE death_date IS NOT NULL)  AS deceased
FROM clinical.patients
GROUP BY gender
ORDER BY gender;


-- ========================================================================
-- Q2: What are the 10 most common ACTIVE conditions?
-- ========================================================================
-- Hints:
--   * "active" = stop_date IS NULL
--   * Count distinct PATIENTS, not rows — one patient can have the same
--     condition recorded more than once. (Classic interview gotcha.)
-- TODO: SELECT description, COUNT(DISTINCT ...) ... FROM clinical.conditions ...


-- ========================================================================
-- Q3: Average encounters per patient, broken down by encounter class.
-- ========================================================================
-- Hints:
--   * Two levels of aggregation: first count per (patient, class),
--     then average those counts per class.
--   * A CTE (WITH per_patient AS (...)) keeps that readable.
-- TODO


-- ========================================================================
-- Q4: 30-day inpatient readmission rate.   <-- the flagship query
-- ========================================================================
-- Context: hospitals are penalized by Medicare for high 30-day readmissions,
-- so this is THE metric to be able to explain in a healthcare interview.
-- Definition for this project: an inpatient stay counts as "readmitted" if
-- the same patient has another inpatient encounter starting within 30 days
-- after the first one ended.
-- Hints:
--   * Filter to encounter_class = 'inpatient' first.
--   * LEAD(start_ts) OVER (PARTITION BY patient_id ORDER BY start_ts)
--     gives you each patient's NEXT inpatient admission on the same row.
--   * Rate = readmitted stays / total stays. Watch integer division:
--     multiply by 100.0, not 100.
-- TODO


-- ========================================================================
-- Q5: Most common condition in each age group (0-17, 18-39, 40-64, 65+).
-- ========================================================================
-- Hints:
--   * Age: EXTRACT(YEAR FROM AGE(COALESCE(death_date, CURRENT_DATE), birth_date))
--   * Bucket with CASE WHEN ... THEN '18-39' ...
--   * "Top 1 per group" = ROW_NUMBER() OVER (PARTITION BY age_group
--     ORDER BY patient_count DESC), then keep rn = 1.
-- TODO


-- ========================================================================
-- Q6: Care gap — diabetic patients with NO HbA1c test in the last 12 months.
-- ========================================================================
-- Context: "care gap" reports are bread-and-butter analyst work (quality
-- measures, population health).
-- Hints:
--   * Diabetics: conditions where description ILIKE '%diabetes%'
--     (and only living patients).
--   * HbA1c LOINC code: '4548-4'
--   * "Has no matching row" = NOT EXISTS (subquery) or LEFT JOIN ... IS NULL.
--     Try both and compare.
-- TODO


-- ========================================================================
-- Q7: Which encounter classes cost the most (total + average claim cost)?
-- ========================================================================
-- Hints: SUM / AVG on total_claim_cost, ROUND(..., 2) for readability.
-- TODO


-- ========================================================================
-- Q8: Data quality checks.   <-- your SDET background shows here
-- ========================================================================
-- Write queries that should return ZERO rows if the data is healthy, e.g.:
--   * encounters where stop_ts < start_ts
--   * patients whose death_date is before birth_date
--   * conditions/encounters pointing to a patient_id that doesn't exist
--     (orphan records)
--   * duplicate encounter IDs
-- These later become automated tests in the pipeline (Phase 2).
-- TODO
