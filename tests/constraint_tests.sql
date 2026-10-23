-- constraint tests
-- Every test below tries to insert/update/delete data that breaks one of the
-- rules from the requirements, and checks that postgres rejects it.
-- Everything runs in one transaction that gets rolled back at the end,
-- so the data is not changed.

\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE test_results (rule TEXT, passed BOOLEAN);

CREATE OR REPLACE FUNCTION pg_temp.expect_reject(rule TEXT, stmt TEXT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE stmt;
    EXCEPTION WHEN integrity_constraint_violation OR check_violation
                   OR not_null_violation OR foreign_key_violation OR unique_violation THEN
        INSERT INTO test_results VALUES (rule, TRUE);
        RETURN;
    END;
    INSERT INTO test_results VALUES (rule, FALSE);
END $$;

-- 30000 is a doctor, the patients come after the doctors in people.csv
SELECT pg_temp.expect_reject('A case must have exactly one lead doctor (NOT NULL)',
  $q$INSERT INTO infection_case VALUES (99001,'MRSA','2024-07-01 10:00','active','ICU',NULL)$q$);

SELECT pg_temp.expect_reject('Lead doctor must be a doctor, not a patient',
  $q$INSERT INTO infection_case VALUES (99002,'MRSA','2024-07-01 10:00','active','ICU',
       (SELECT MIN(patient_id) FROM patients))$q$);

SELECT pg_temp.expect_reject('Case status is only active/resolved',
  $q$INSERT INTO infection_case VALUES (99003,'MRSA','2024-07-01 10:00','closed','ICU',30000)$q$);

SELECT pg_temp.expect_reject('source_status is only active/cleared',
  $q$INSERT INTO case_patient VALUES (22001,(SELECT MIN(patient_id) FROM patients),'unknown')$q$);

SELECT pg_temp.expect_reject('A test can only target a patient involved in that case',
  $q$INSERT INTO tests
     SELECT TIMESTAMP '2024-07-01 09:00', 22001, 30000, p.patient_id
     FROM patients p
     WHERE NOT EXISTS (SELECT 1 FROM case_patient cp WHERE cp.case_id = 22001 AND cp.patient_id = p.patient_id)
     LIMIT 1$q$);

SELECT pg_temp.expect_reject('A sample can only be linked to patients of the same case',
  $q$INSERT INTO sample_patient
     SELECT es.case_id, es.storage_id, p.patient_id
     FROM evidence_samples es, patients p
     WHERE NOT EXISTS (SELECT 1 FROM case_patient cp WHERE cp.case_id = es.case_id AND cp.patient_id = p.patient_id)
     LIMIT 1$q$);

SELECT pg_temp.expect_reject('Storage ID is unique within a case',
  $q$INSERT INTO evidence_samples
     SELECT case_id, storage_id, 'duplicate', 'unclassified', doctor_id FROM evidence_samples LIMIT 1$q$);

SELECT pg_temp.expect_reject('Every sample is collected by exactly one doctor (NOT NULL)',
  $q$INSERT INTO evidence_samples VALUES (22001, 999, 'no collector', 'unclassified', NULL)$q$);

SELECT pg_temp.expect_reject('A work period cannot end before it starts',
  $q$INSERT INTO works_on VALUES (22001, 30000, '2024-06-10', '2024-06-01')$q$);

SELECT pg_temp.expect_reject('Discharge cannot be before admission',
  $q$UPDATE patients SET discharge_date = admission_date - 1
     WHERE patient_id = (SELECT MIN(patient_id) FROM patients WHERE admission_date IS NOT NULL)$q$);

SELECT pg_temp.expect_reject('Doctor rank is Assistant/Senior/Chief',
  $q$UPDATE doctors SET rank = 'Intern' WHERE doctor_id = 30000$q$);

SELECT pg_temp.expect_reject('Cannot delete a doctor who still leads a case',
  $q$DELETE FROM doctors WHERE doctor_id = (SELECT lead_doctor_id FROM infection_case LIMIT 1)$q$);

-- results
SELECT CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result, rule FROM test_results;

DO $$
DECLARE n_fail INT;
BEGIN
    SELECT COUNT(*) INTO n_fail FROM test_results WHERE NOT passed;
    IF n_fail > 0 THEN
        RAISE EXCEPTION '% constraint test(s) failed', n_fail;
    END IF;
    RAISE NOTICE 'All % constraint tests passed', (SELECT COUNT(*) FROM test_results);
END $$;

ROLLBACK;
