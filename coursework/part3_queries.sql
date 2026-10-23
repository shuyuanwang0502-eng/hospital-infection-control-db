------Bonus Project part3------
-- Query 1
-- For each infection case, retrieve the number of involved patients, the number of
-- contributing doctors, and the number of tests performed.
SELECT
    ic.case_id,
    COUNT(DISTINCT cp.patient_id) AS num_patients,
    COUNT(DISTINCT wo.doctor_id) AS num_doctors,
    COUNT(DISTINCT t."timestamp") AS num_tests
FROM infection_case ic
         LEFT JOIN case_patient cp ON ic.case_id = cp.case_id
         LEFT JOIN works_on wo ON ic.case_id = wo.case_id
         LEFT JOIN tests t ON ic.case_id = t.case_id
GROUP BY ic.case_id;

-- Query 2
-- Select all wards where the number of infection cases is greater than 2.
SELECT
    ic.ward,
    COUNT(*) AS infection_case_count
FROM infection_case AS ic
GROUP BY ic.ward
HAVING COUNT(*) > 2
ORDER BY infection_case_count DESC, ic.ward;

-- Query 3
-- Find patients who were involved in at least 3 infection cases between April 2024 and
-- June 2024, and who were marked as source_status = ’active’ in at least one of those cases.
SELECT p.id, p.fname, p.lname
FROM people p
         JOIN case_patient cp
              ON p.id = cp.patient_id
         JOIN infection_case ic
              ON cp.case_id = ic.case_id
WHERE ic.detection_date BETWEEN '2024-04-01' AND '2024-06-30'
GROUP BY p.id, p.fname, p.lname
HAVING COUNT(DISTINCT ic.case_id) >= 3
   AND SUM(CASE WHEN cp.source_status = 'active' THEN 1 ELSE 0 END) >= 1;

-- Query 4
-- Select the names of all doctors who worked together with the doctor
-- who contributed to the most cases.
WITH top_doctor AS (
    SELECT wo.doctor_id
    FROM works_on AS wo
    GROUP BY wo.doctor_id
    ORDER BY COUNT(DISTINCT wo.case_id) DESC, wo.doctor_id
    LIMIT 1
),
     top_cases AS (
         SELECT DISTINCT wo.case_id
         FROM works_on AS wo
         WHERE wo.doctor_id = (SELECT doctor_id FROM top_doctor)
     ),
     coworkers AS (
         SELECT DISTINCT wo.doctor_id
         FROM works_on AS wo
                  JOIN top_cases tc ON tc.case_id = wo.case_id
         WHERE wo.doctor_id != (SELECT doctor_id FROM top_doctor)
     )
SELECT
    p.fname,
    p.lname
FROM coworkers c
         JOIN doctors d ON d.doctor_id = c.doctor_id
         JOIN people p ON p.id = d.doctor_id
ORDER BY p.lname, p.fname;

-- Query 5
--  Select the names of doctors who are performing “bad”, i.e., their case_counter is within
--  the 10th percentile of all doctors’ case_counter. (Hint: use percentile_disc.)
WITH doctor_case_counts AS (
    SELECT
        d.doctor_id,
        COUNT(DISTINCT wo.case_id) AS case_count
    FROM doctors d
             LEFT JOIN works_on wo
                       ON wo.doctor_id = d.doctor_id
    GROUP BY d.doctor_id
),
     tenth_percentile AS (
         SELECT
                     percentile_disc(0.1) WITHIN GROUP (ORDER BY case_count) AS p10
         FROM doctor_case_counts
     )
SELECT
    p.fname,
    p.lname
FROM doctor_case_counts dcc
         JOIN tenth_percentile tp
              ON dcc.case_count <= tp.p10
         JOIN people p
              ON p.id = dcc.doctor_id
ORDER BY p.lname, p.fname;

-- Query 6
-- List all active infection cases, including: case id, infection type, ward,
-- detection time, and the lead doctor’s full name.
SELECT
    ic.case_id,
    ic.infection_type,
    ic.ward,
    ic.detection_date,
    (p.fname || ' ' || p.lname) AS lead_doctor_full_name
FROM infection_case AS ic
         JOIN doctors AS d
              ON d.doctor_id = ic.lead_doctor_id
         JOIN people AS p
              ON p.id = d.doctor_id
WHERE ic.status = 'active'
ORDER BY ic.detection_date ASC, ic.case_id;

-- Query 7
-- For each infection type, retrieve the number of cases, and how many of them are active.
SELECT
    infection_type,
    COUNT(case_id) AS total_cases,
    (SELECT COUNT(*)
     FROM infection_case ic2
     WHERE ic2.infection_type = ic.infection_type
       AND ic2.status = 'active') AS active_cases
FROM infection_case ic
GROUP BY infection_type;

-- Query 8
-- Select the top 3 infection cases with the highest number of collected samples.
SELECT
    es.case_id,
    COUNT(*) AS collected_samples
FROM evidence_samples AS es
GROUP BY es.case_id
ORDER BY collected_samples DESC, es.case_id
LIMIT 3;

-- Query 9
-- Find patients who are currently marked as source_status = ’active’ in more than 2 cases.
SELECT p.fname, p.lname
FROM people p, case_patient cp
WHERE p.id = cp.patient_id
  AND cp.source_status = 'active'
GROUP BY p.id, p.fname, p.lname
HAVING COUNT(DISTINCT cp.case_id) > 2;

-- Query 10
-- For each doctor who has conducted more than 8 tests, retrieve the total number
-- of tests they conducted and the timestamp of their most recent test (if any).
WITH test_stats AS (
    SELECT
        t.doctor_id,
        COUNT(*) AS total_tests_conducted,
        MAX(t."timestamp") AS most_recent_test_time
    FROM tests t
    GROUP BY t.doctor_id
)
SELECT
    d.doctor_id,
    (p.fname || ' ' || p.lname) AS doctor_full_name,
    ts.total_tests_conducted,
    ts.most_recent_test_time
FROM test_stats ts
         JOIN doctors d
              ON d.doctor_id = ts.doctor_id
         JOIN people p
              ON p.id = d.doctor_id
WHERE ts.total_tests_conducted > 8
ORDER BY ts.total_tests_conducted DESC, doctor_full_name;