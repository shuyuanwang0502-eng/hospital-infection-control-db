-- Hospital Infection Control DB
-- 01_schema.sql: tables, constraints, indexes (PostgreSQL 13+)
--
-- Mapping of the EER diagram (docs/eer_diagram.drawio):
--   - people is specialized into patients and doctors (total + disjoint).
--     Each subtype table uses the person id as PK and FK.
--   - tests and evidence_samples are weak entities of infection_case.
--   - "exactly one lead doctor" -> NOT NULL foreign key.
--   - tests and sample_patient have a composite FK to case_patient, so a
--     patient can only be tested / linked to a sample if he is in that case.
--   - the derived attribute case_counter is a view (doctor_case_counter).

-- drop old objects so the script can be run again
DROP VIEW  IF EXISTS doctor_case_counter;
DROP TABLE IF EXISTS sample_patient, evidence_samples, tests, case_patient,
                     works_on, infection_case, doctors, patients, people CASCADE;


-- people (supertype)
CREATE TABLE people (
    id         INT  PRIMARY KEY,
    fname      TEXT NOT NULL,
    lname      TEXT NOT NULL,
    phone_num  TEXT,
    street     TEXT,           -- address = street, city, zip
    city       TEXT,
    zip        TEXT
);

-- patients (subtype)
CREATE TABLE patients (
    patient_id      INT PRIMARY KEY
                    REFERENCES people(id) ON UPDATE CASCADE ON DELETE CASCADE,
    bday            DATE,
    ward            TEXT,
    admission_date  DATE,
    discharge_date  DATE,      -- optional
    CONSTRAINT chk_patient_dates
        CHECK (discharge_date IS NULL OR admission_date IS NULL
               OR discharge_date >= admission_date)
);

-- doctors (subtype)
CREATE TABLE doctors (
    doctor_id  INT PRIMARY KEY
               REFERENCES people(id) ON UPDATE CASCADE ON DELETE CASCADE,
    dpt        TEXT,
    rank       TEXT,
    CONSTRAINT chk_doctor_rank CHECK (rank IN ('Assistant', 'Senior', 'Chief'))
);

-- infection_case
CREATE TABLE infection_case (
    case_id         INT  PRIMARY KEY,
    infection_type  TEXT NOT NULL,
    detection_time  TIMESTAMP NOT NULL,     -- date + time of detection
    status          TEXT NOT NULL,
    ward            TEXT NOT NULL,
    lead_doctor_id  INT  NOT NULL           -- exactly one lead doctor
                    REFERENCES doctors(doctor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_case_status CHECK (status IN ('active', 'resolved'))
);

-- works_on: doctors contributing to a case (M:N)
-- start_date is in the PK because a doctor can work on the same case
-- in two different periods.
CREATE TABLE works_on (
    case_id     INT  NOT NULL REFERENCES infection_case(case_id) ON UPDATE CASCADE ON DELETE CASCADE,
    doctor_id   INT  NOT NULL REFERENCES doctors(doctor_id)      ON UPDATE CASCADE ON DELETE CASCADE,
    start_date  DATE NOT NULL,
    end_date    DATE,                       -- NULL = still working on it
    PRIMARY KEY (case_id, doctor_id, start_date),
    CONSTRAINT chk_workson_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

-- case_patient: patients involved in a case (M:N) + source_status
CREATE TABLE case_patient (
    case_id        INT  NOT NULL REFERENCES infection_case(case_id) ON UPDATE CASCADE ON DELETE CASCADE,
    patient_id     INT  NOT NULL REFERENCES patients(patient_id)    ON UPDATE CASCADE ON DELETE CASCADE,
    source_status  TEXT NOT NULL,
    PRIMARY KEY (case_id, patient_id),
    CONSTRAINT chk_source_status CHECK (source_status IN ('active', 'cleared'))
);

-- tests (weak entity)
CREATE TABLE tests (
    "timestamp"  TIMESTAMP NOT NULL,
    case_id      INT NOT NULL REFERENCES infection_case(case_id) ON UPDATE CASCADE ON DELETE CASCADE,
    doctor_id    INT NOT NULL REFERENCES doctors(doctor_id)      ON UPDATE CASCADE ON DELETE RESTRICT,
    patient_id   INT NOT NULL REFERENCES patients(patient_id)    ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY ("timestamp", case_id, doctor_id, patient_id),
    -- tested patient has to be involved in this case
    CONSTRAINT fk_tests_case_patient FOREIGN KEY (case_id, patient_id)
        REFERENCES case_patient(case_id, patient_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- evidence_samples (weak entity, storage_id is only unique inside a case)
CREATE TABLE evidence_samples (
    case_id             INT  NOT NULL REFERENCES infection_case(case_id) ON UPDATE CASCADE ON DELETE CASCADE,
    storage_id          INT  NOT NULL,
    description         TEXT,
    classification_tag  TEXT,
    doctor_id           INT  NOT NULL       -- collected by exactly one doctor
                        REFERENCES doctors(doctor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (case_id, storage_id)
);

-- sample_patient: a sample can belong to several patients of the same case
CREATE TABLE sample_patient (
    case_id     INT NOT NULL,
    storage_id  INT NOT NULL,
    patient_id  INT NOT NULL REFERENCES patients(patient_id) ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (case_id, storage_id, patient_id),
    CONSTRAINT fk_sp_sample FOREIGN KEY (case_id, storage_id)
        REFERENCES evidence_samples(case_id, storage_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_sp_same_case FOREIGN KEY (case_id, patient_id)
        REFERENCES case_patient(case_id, patient_id) ON UPDATE CASCADE ON DELETE CASCADE
);


-- indexes for FK columns that are used in joins
-- (postgres does not create these automatically)
CREATE INDEX idx_case_lead_doctor   ON infection_case (lead_doctor_id);
CREATE INDEX idx_workson_doctor     ON works_on (doctor_id);
CREATE INDEX idx_casepatient_pat    ON case_patient (patient_id);
CREATE INDEX idx_tests_case         ON tests (case_id);
CREATE INDEX idx_tests_doctor       ON tests (doctor_id);
CREATE INDEX idx_samples_doctor     ON evidence_samples (doctor_id);


-- derived attribute: number of cases a doctor worked on
CREATE VIEW doctor_case_counter AS
SELECT d.doctor_id,
       COUNT(DISTINCT wo.case_id) AS case_counter
FROM doctors d
LEFT JOIN works_on wo ON wo.doctor_id = d.doctor_id
GROUP BY d.doctor_id;
