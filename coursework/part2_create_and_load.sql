-- ============================================================
-- Bonus Project Part 2 — Final SQL (PostgreSQL)
-- ============================================================

---------- Base entity: PEOPLE ----------
CREATE TABLE people (
                        id         INT PRIMARY KEY,
                        fname      TEXT NOT NULL,
                        lname      TEXT NOT NULL,
                        phone_num  TEXT,
                        zip        TEXT,
                        street     TEXT,
                        city       TEXT
);

---------- Specialization-->Subtype: patients ----------
CREATE TABLE patients (
                          patient_id      INT PRIMARY KEY,
                          admission_date  DATE,
                          discharge_date  DATE,
                          bday            DATE,
                          ward            TEXT,
                          CONSTRAINT fk_patients_people
                              FOREIGN KEY (patient_id) REFERENCES people(id)
                                  ON UPDATE CASCADE ON DELETE CASCADE,
                          CONSTRAINT chk_patient_dates
                              CHECK (discharge_date IS NULL OR admission_date IS NULL OR discharge_date >= admission_date)
);

---------- Specialization-->Subtype: doctors ----------
CREATE TABLE doctors (
                         doctor_id       INT PRIMARY KEY,
                         dpt             TEXT,
                         rank            TEXT,
                         CONSTRAINT fk_doctors_people
                             FOREIGN KEY (doctor_id) REFERENCES people(id)
                                 ON UPDATE CASCADE ON DELETE CASCADE
);

---------- INFECTION CASE ----------
CREATE TABLE infection_case (
                                case_id         INT PRIMARY KEY,
                                infection_type  TEXT NOT NULL,
                                status          TEXT,
                                ward            TEXT,
                                detection_date  DATE,
                                lead_doctor_id  INT NOT NULL,   -- "exactly one lead doctor" -> NOT NULL
                                CONSTRAINT fk_case_lead_doctor
                                    FOREIGN KEY (lead_doctor_id) REFERENCES doctors(doctor_id)
                                        ON UPDATE CASCADE ON DELETE RESTRICT
);

---------- WORKS_ON ----------
CREATE TABLE works_on (
                          case_id    INT NOT NULL,
                          doctor_id  INT NOT NULL,
                          start_date DATE NOT NULL,
                          end_date   DATE,
                          PRIMARY KEY (case_id, doctor_id, start_date),
                          CONSTRAINT fk_workson_case
                              FOREIGN KEY (case_id) REFERENCES infection_case(case_id)
                                  ON UPDATE CASCADE ON DELETE CASCADE,
                          CONSTRAINT fk_workson_doctor
                              FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
                                  ON UPDATE CASCADE ON DELETE CASCADE,
                          CONSTRAINT chk_workson_dates
                              CHECK (end_date IS NULL OR end_date >= start_date)
);

---------- CASE_PATIENT ----------
CREATE TABLE case_patient (
                              case_id       INT NOT NULL,
                              patient_id    INT NOT NULL,
                              source_status TEXT NOT NULL,
                              PRIMARY KEY (case_id, patient_id),
                              CONSTRAINT fk_casepatient_case
                                  FOREIGN KEY (case_id) REFERENCES infection_case(case_id)
                                      ON UPDATE CASCADE ON DELETE CASCADE,
                              CONSTRAINT fk_casepatient_patient
                                  FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
                                      ON UPDATE CASCADE ON DELETE CASCADE,
                              CONSTRAINT chk_source_status
                                  CHECK (source_status IN ('active', 'cleared'))
);

---------- TESTS ----------
CREATE TABLE tests (
                       "timestamp" TIMESTAMP NOT NULL,
                       case_id     INT NOT NULL,
                       doctor_id   INT NOT NULL,
                       patient_id  INT NOT NULL,
                       PRIMARY KEY ("timestamp", case_id, doctor_id, patient_id),
                       CONSTRAINT fk_tests_case
                           FOREIGN KEY (case_id) REFERENCES infection_case(case_id)
                               ON UPDATE CASCADE ON DELETE CASCADE,
                       CONSTRAINT fk_tests_doctor
                           FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
                       CONSTRAINT fk_tests_patient
                           FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
                               ON UPDATE CASCADE ON DELETE RESTRICT,
    -- ensure the tested patient is in the same case
                       CONSTRAINT fk_tests_casepatient
                           FOREIGN KEY (case_id, patient_id) REFERENCES case_patient(case_id, patient_id)
                               ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------- EVIDENCE SAMPLES ----------
-- Storage_ID is unique only within a case => PK is composed by (case_id, storage_id)
-- Exactly one doctor collected the sample => doctor_id is a single FK here.
CREATE TABLE evidence_samples (
                                  case_id            INT NOT NULL,
                                  storage_id         INT NOT NULL,
                                  description        TEXT,
                                  classification_tag TEXT,
                                  doctor_id          INT NOT NULL,
                                  PRIMARY KEY (case_id, storage_id),
                                  CONSTRAINT fk_sample_case
                                      FOREIGN KEY (case_id) REFERENCES infection_case(case_id)
                                          ON UPDATE CASCADE ON DELETE CASCADE,
                                  CONSTRAINT fk_sample_doctor
                                      FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
                                          ON UPDATE CASCADE ON DELETE RESTRICT
);

---------- SAMPLE_PATIENT (Sample associated with several patients) ----------
-- Must ensure: patient is involved in the SAME case.
CREATE TABLE sample_patient (
                                case_id    INT NOT NULL,
                                storage_id INT NOT NULL,
                                patient_id INT NOT NULL,
                                PRIMARY KEY (case_id, storage_id, patient_id),
                                CONSTRAINT fk_sp_sample
                                    FOREIGN KEY (case_id, storage_id)
                                        REFERENCES evidence_samples(case_id, storage_id)
                                        ON UPDATE CASCADE ON DELETE CASCADE,
                                CONSTRAINT fk_sp_patient
                                    FOREIGN KEY (patient_id)
                                        REFERENCES patients(patient_id)
                                        ON UPDATE CASCADE ON DELETE CASCADE,
                                CONSTRAINT fk_sp_same_case
                                    FOREIGN KEY (case_id, patient_id)
                                        REFERENCES case_patient(case_id, patient_id)
                                        ON UPDATE CASCADE ON DELETE CASCADE
);

---Create the staging tables and import the data provided---
CREATE TABLE stg_people (
                            id INT,
                            first_name TEXT,
                            last_name TEXT,
                            phone_number TEXT,
                            street TEXT,
                            city TEXT,
                            zip TEXT,
                            role INT,
                            department TEXT,
                            rank TEXT,
                            date_of_birth DATE,
                            ward TEXT,
                            admission_date DATE,
                            discharge_date DATE
);

CREATE TABLE stg_cases (
                           id INT,
                           infection_type TEXT,
                           detection_datetime TIMESTAMP,
                           status TEXT,
                           ward TEXT,
                           lead_doctor_id INT
);

CREATE TABLE stg_works_on (
                              doctor_id INT,
                              case_id INT,
                              start_date DATE,
                              end_date DATE
);

CREATE TABLE stg_tests (
                           case_id INT,
                           doctor_id INT,
                           patient_id INT,
                           ts TIMESTAMP
);

CREATE TABLE stg_samples (
                             case_id INT,
                             storage_id INT,
                             description TEXT,
                             tag TEXT,
                             collected_by_doctor_id INT
);

CREATE TABLE stg_involves (
                              case_id INT,
                              patient_id INT,
                              source_status TEXT
);

CREATE TABLE stg_sample_patient (
                                    case_id INT,
                                    storage_id INT,
                                    patient_id INT
);

---Insert data from staging tables into real schemas by the correct order---
---insert the data into people table---
INSERT INTO people (id, fname, lname, phone_num, zip, street, city)
SELECT id, first_name, last_name, phone_number, zip, street, city
FROM stg_people;

---check if data insertion is successful---
SELECT COUNT(*) FROM people;

---We know from the data provided in the people file that doctors and patients are split be role numbers, doctor is 1 whereas patient is 2---
---insert the data into doctors table---
---Doctors: role = 1
INSERT INTO doctors (doctor_id, dpt, rank)
SELECT id, department, rank
FROM stg_people
WHERE role = 1;

---check if data insertion is successful---
SELECT COUNT(*) FROM doctors;

---insert the data into patients table---
---Patients: role = 2
INSERT INTO patients (patient_id, admission_date, discharge_date, bday, ward)
SELECT id, admission_date, discharge_date, date_of_birth, ward
FROM stg_people
WHERE role = 2;

---check if data insertion is successful---
SELECT COUNT(*) FROM patients;

---insert the data into infection_case table---
INSERT INTO infection_case (case_id, infection_type, status, ward, detection_date, lead_doctor_id)
SELECT id, infection_type, status, ward, detection_datetime::date, lead_doctor_id
FROM stg_cases;

---check if data insertion is successful---
SELECT COUNT(*) FROM infection_case;

---insert the data into works_on table---
INSERT INTO works_on (case_id, doctor_id, start_date, end_date)
SELECT case_id, doctor_id, start_date, end_date
FROM stg_works_on;

---check if data insertion is successful---
SELECT COUNT(*) FROM works_on;

---insert the data into case_patient table---
INSERT INTO case_patient (case_id, patient_id, source_status)
SELECT case_id, patient_id, source_status
FROM stg_involves;

---check if data insertion is successful---
SELECT COUNT(*) FROM case_patient;

---insert the data into evidence_samples table---
INSERT INTO evidence_samples (case_id, storage_id, description, classification_tag, doctor_id)
SELECT case_id, storage_id, description, tag, collected_by_doctor_id
FROM stg_samples;

---check if data insertion is successful---
SELECT COUNT(*) FROM evidence_samples;

---insert the data into sample_patient table---
INSERT INTO sample_patient (case_id, storage_id, patient_id)
SELECT case_id, storage_id, patient_id
FROM stg_sample_patient;

---check if data insertion is successful---
SELECT COUNT(*) FROM sample_patient;

---insert the data into tests table---
INSERT INTO tests ("timestamp", case_id, doctor_id, patient_id)
SELECT ts, case_id, doctor_id, patient_id
FROM stg_tests;

---check if data insertion is successful---
SELECT COUNT(*) FROM tests;

---check if there's any samples linked to patients that are not in the same case---
SELECT * FROM sample_patient sp
LEFT JOIN case_patient cp ON cp.case_id = sp.case_id AND cp.patient_id = sp.patient_id
WHERE cp.case_id IS NULL;

---check if there's any negative work periods
SELECT *
FROM works_on
WHERE end_date IS NOT NULL AND end_date < start_date;






