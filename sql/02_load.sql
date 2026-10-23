-- 02_load.sql: load the csv files into the tables
-- run from the repo root:  psql -d <db> -f sql/02_load.sql
--
-- The csv files don't match the tables 1:1 (people.csv has doctors and
-- patients together, the column `role` says which one). So:
--   1. copy every csv into a temp staging table
--   2. insert into the real tables (in FK order)
--   3. some checks at the end

BEGIN;

-- 1. staging tables (same columns as the csv files)
CREATE TEMP TABLE stg_people (
    id INT, first_name TEXT, last_name TEXT, phone_number TEXT,
    street TEXT, city TEXT, zip TEXT, role INT,
    department TEXT, rank TEXT, date_of_birth DATE, ward TEXT,
    admission_date DATE, discharge_date DATE
) ON COMMIT DROP;
CREATE TEMP TABLE stg_cases (
    id INT, infection_type TEXT, detection_datetime TIMESTAMP,
    status TEXT, ward TEXT, lead_doctor_id INT
) ON COMMIT DROP;
CREATE TEMP TABLE stg_works_on (doctor_id INT, case_id INT, start_date DATE, end_date DATE) ON COMMIT DROP;
CREATE TEMP TABLE stg_tests (case_id INT, doctor_id INT, patient_id INT, ts TIMESTAMP) ON COMMIT DROP;
CREATE TEMP TABLE stg_samples (case_id INT, storage_id INT, description TEXT, tag TEXT, collected_by_doctor_id INT) ON COMMIT DROP;
CREATE TEMP TABLE stg_involves (case_id INT, patient_id INT, source_status TEXT) ON COMMIT DROP;
CREATE TEMP TABLE stg_sample_patient (case_id INT, storage_id INT, patient_id INT) ON COMMIT DROP;

\copy stg_people         FROM 'data/people.csv'         WITH (FORMAT csv, HEADER true)
\copy stg_cases          FROM 'data/cases.csv'          WITH (FORMAT csv, HEADER true)
\copy stg_works_on       FROM 'data/works_on.csv'       WITH (FORMAT csv, HEADER true)
\copy stg_tests          FROM 'data/tests.csv'          WITH (FORMAT csv, HEADER true)
\copy stg_samples        FROM 'data/samples.csv'        WITH (FORMAT csv, HEADER true)
\copy stg_involves       FROM 'data/involves.csv'       WITH (FORMAT csv, HEADER true)
\copy stg_sample_patient FROM 'data/sample_patient.csv' WITH (FORMAT csv, HEADER true)

-- 2. insert into the real tables
INSERT INTO people (id, fname, lname, phone_num, street, city, zip)
SELECT id, first_name, last_name, phone_number, street, city, zip
FROM stg_people;

-- role 1 = doctor, role 2 = patient
INSERT INTO doctors (doctor_id, dpt, rank)
SELECT id, department, rank FROM stg_people WHERE role = 1;

INSERT INTO patients (patient_id, bday, ward, admission_date, discharge_date)
SELECT id, date_of_birth, ward, admission_date, discharge_date FROM stg_people WHERE role = 2;

INSERT INTO infection_case (case_id, infection_type, detection_time, status, ward, lead_doctor_id)
SELECT id, infection_type, detection_datetime, status, ward, lead_doctor_id FROM stg_cases;

INSERT INTO works_on (case_id, doctor_id, start_date, end_date)
SELECT case_id, doctor_id, start_date, end_date FROM stg_works_on;

INSERT INTO case_patient (case_id, patient_id, source_status)
SELECT case_id, patient_id, source_status FROM stg_involves;

INSERT INTO evidence_samples (case_id, storage_id, description, classification_tag, doctor_id)
SELECT case_id, storage_id, description, tag, collected_by_doctor_id FROM stg_samples;

INSERT INTO sample_patient (case_id, storage_id, patient_id)
SELECT case_id, storage_id, patient_id FROM stg_sample_patient;

INSERT INTO tests ("timestamp", case_id, doctor_id, patient_id)
SELECT ts, case_id, doctor_id, patient_id FROM stg_tests;

-- 3. checks
-- rows per table
SELECT 'people' AS table_name, COUNT(*) AS rows FROM people
UNION ALL SELECT 'doctors',          COUNT(*) FROM doctors
UNION ALL SELECT 'patients',         COUNT(*) FROM patients
UNION ALL SELECT 'infection_case',   COUNT(*) FROM infection_case
UNION ALL SELECT 'works_on',         COUNT(*) FROM works_on
UNION ALL SELECT 'case_patient',     COUNT(*) FROM case_patient
UNION ALL SELECT 'evidence_samples', COUNT(*) FROM evidence_samples
UNION ALL SELECT 'sample_patient',   COUNT(*) FROM sample_patient
UNION ALL SELECT 'tests',            COUNT(*) FROM tests;

-- every person should be exactly one of doctor / patient (expected: 0)
SELECT COUNT(*) AS persons_violating_specialization
FROM people p
WHERE (p.id IN (SELECT doctor_id FROM doctors))::int
    + (p.id IN (SELECT patient_id FROM patients))::int <> 1;

COMMIT;
