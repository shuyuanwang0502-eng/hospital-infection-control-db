-- 03_queries.sql
-- Query 1-10 are the queries from part 3 of the assignment.
-- Query 11-13 are extra ones I added (questions an infection control
-- team would probably ask).

-- Query 1
-- For each infection case, the number of involved patients, contributing
-- doctors and tests performed. Each table is counted separately first,
-- joining all three at once would multiply the rows (patients x doctors x tests).
-- Uses: CTEs, LEFT JOIN, COALESCE
WITH p AS (SELECT case_id, COUNT(*) AS n FROM case_patient GROUP BY case_id),
     d AS (SELECT case_id, COUNT(DISTINCT doctor_id) AS n FROM works_on GROUP BY case_id),
     t AS (SELECT case_id, COUNT(*) AS n FROM tests GROUP BY case_id)
SELECT ic.case_id,
       COALESCE(p.n, 0) AS num_patients,
       COALESCE(d.n, 0) AS num_doctors,
       COALESCE(t.n, 0) AS num_tests
FROM infection_case ic
LEFT JOIN p ON p.case_id = ic.case_id
LEFT JOIN d ON d.case_id = ic.case_id
LEFT JOIN t ON t.case_id = ic.case_id
ORDER BY ic.case_id;


-- Query 2
-- All wards with more than 2 infection cases.
-- Uses: GROUP BY, HAVING
SELECT ward, COUNT(*) AS infection_case_count
FROM infection_case
GROUP BY ward
HAVING COUNT(*) > 2
ORDER BY infection_case_count DESC, ward;


-- Query 3
-- Patients involved in at least 3 cases detected between April and June 2024
-- who were source_status = 'active' in at least one of them.
-- Uses: COUNT(*) FILTER, date range
SELECT p.id, p.fname, p.lname,
       COUNT(DISTINCT cp.case_id) AS cases_q2_2024
FROM people p
JOIN case_patient   cp ON cp.patient_id = p.id
JOIN infection_case ic ON ic.case_id    = cp.case_id
WHERE ic.detection_time >= DATE '2024-04-01'
  AND ic.detection_time <  DATE '2024-07-01'
GROUP BY p.id, p.fname, p.lname
HAVING COUNT(DISTINCT cp.case_id) >= 3
   AND COUNT(*) FILTER (WHERE cp.source_status = 'active') >= 1
ORDER BY cases_q2_2024 DESC, p.lname, p.fname;


-- Query 4
-- Names of all doctors who worked together with the doctor who
-- contributed to the most cases. Two doctors both have 5 cases, so RANK()
-- is used to keep both of them instead of picking one with LIMIT 1.
-- Uses: CTEs, RANK(), self join
WITH counts AS (
    SELECT doctor_id, COUNT(DISTINCT case_id) AS n_cases,
           RANK() OVER (ORDER BY COUNT(DISTINCT case_id) DESC) AS rnk
    FROM works_on
    GROUP BY doctor_id
),
top_doctors AS (SELECT doctor_id FROM counts WHERE rnk = 1),
coworkers AS (
    SELECT DISTINCT w2.doctor_id
    FROM works_on w1
    JOIN works_on w2 ON w2.case_id = w1.case_id
    WHERE w1.doctor_id IN (SELECT doctor_id FROM top_doctors)
      AND w2.doctor_id NOT IN (SELECT doctor_id FROM top_doctors)
)
SELECT p.fname, p.lname
FROM coworkers c
JOIN people p ON p.id = c.doctor_id
ORDER BY p.lname, p.fname;


-- Query 5
-- Doctors performing "bad", i.e. case_counter within the 10th percentile.
-- Uses: percentile_disc, view
WITH p10 AS (
    SELECT percentile_disc(0.1) WITHIN GROUP (ORDER BY case_counter) AS v
    FROM doctor_case_counter
)
SELECT p.fname, p.lname, dcc.case_counter
FROM doctor_case_counter dcc
JOIN p10 ON dcc.case_counter <= p10.v
JOIN people p ON p.id = dcc.doctor_id
ORDER BY p.lname, p.fname;


-- Query 6
-- All active cases with case id, infection type, ward, detection time
-- and the full name of the lead doctor.
-- Uses: JOIN, string concatenation
SELECT ic.case_id, ic.infection_type, ic.ward, ic.detection_time,
       p.fname || ' ' || p.lname AS lead_doctor
FROM infection_case ic
JOIN people p ON p.id = ic.lead_doctor_id
WHERE ic.status = 'active'
ORDER BY ic.detection_time, ic.case_id;


-- Query 7
-- For each infection type, the number of cases and how many are active.
-- Uses: COUNT(*) FILTER
SELECT infection_type,
       COUNT(*)                                   AS total_cases,
       COUNT(*) FILTER (WHERE status = 'active')  AS active_cases
FROM infection_case
GROUP BY infection_type
ORDER BY total_cases DESC, infection_type;


-- Query 8
-- Top 3 cases with the most collected samples. WITH TIES keeps cases that
-- are tied with 3rd place.
-- Uses: FETCH FIRST ... WITH TIES
SELECT case_id, COUNT(*) AS collected_samples
FROM evidence_samples
GROUP BY case_id
ORDER BY collected_samples DESC
FETCH FIRST 3 ROWS WITH TIES;


-- Query 9
-- Patients who are source_status = 'active' in more than 2 cases.
-- Uses: WHERE, GROUP BY, HAVING
SELECT p.id, p.fname, p.lname, COUNT(*) AS active_source_in_cases
FROM people p
JOIN case_patient cp ON cp.patient_id = p.id
WHERE cp.source_status = 'active'
GROUP BY p.id, p.fname, p.lname
HAVING COUNT(*) > 2
ORDER BY active_source_in_cases DESC, p.lname, p.fname;


-- Query 10
-- Doctors with more than 8 tests, their number of tests and the most recent one.
-- Uses: COUNT, MAX, HAVING
SELECT t.doctor_id,
       p.fname || ' ' || p.lname AS doctor,
       COUNT(*)                  AS total_tests,
       MAX(t."timestamp")        AS most_recent_test
FROM tests t
JOIN people p ON p.id = t.doctor_id
GROUP BY t.doctor_id, p.fname, p.lname
HAVING COUNT(*) > 8
ORDER BY total_tests DESC, doctor;


-- extra queries (not part of the assignment)

-- Query 11: Response time
-- How fast does testing start after an outbreak is detected? Hours from
-- detection to the first test, compared within each ward.
-- Uses: interval arithmetic, AVG() OVER, RANK() OVER
WITH first_test AS (
    SELECT case_id, MIN("timestamp") AS first_test_at
    FROM tests GROUP BY case_id
)
SELECT ic.case_id, ic.ward, ic.infection_type,
       ROUND(EXTRACT(EPOCH FROM ft.first_test_at - ic.detection_time) / 3600, 1) AS hours_to_first_test,
       ROUND(AVG(EXTRACT(EPOCH FROM ft.first_test_at - ic.detection_time) / 3600)
             OVER (PARTITION BY ic.ward), 1)                                    AS ward_avg_hours,
       RANK() OVER (PARTITION BY ic.ward ORDER BY ft.first_test_at - ic.detection_time) AS rank_in_ward
FROM infection_case ic
JOIN first_test ft ON ft.case_id = ic.case_id
ORDER BY ic.ward, rank_in_ward;


-- Query 12: Cases that share patients
-- Pairs of cases with 4 or more patients in common. A shared patient could
-- be a link between two outbreaks.
-- Uses: self join, STRING_AGG
SELECT a.case_id AS case_a, b.case_id AS case_b,
       COUNT(*)  AS shared_patients,
       STRING_AGG(a.patient_id::text, ', ' ORDER BY a.patient_id) AS patient_ids
FROM case_patient a
JOIN case_patient b ON b.patient_id = a.patient_id AND b.case_id > a.case_id
GROUP BY a.case_id, b.case_id
HAVING COUNT(*) >= 4
ORDER BY shared_patients DESC, case_a, case_b;


-- Query 13: Doctor workload
-- Tests per doctor, ranked inside the department, and the share of the
-- department's tests. LEFT JOIN so doctors without tests show up with 0.
-- Uses: LEFT JOIN, DENSE_RANK(), SUM() OVER
SELECT d.dpt AS department,
       p.fname || ' ' || p.lname AS doctor,
       d.rank,
       COUNT(t.case_id) AS tests,
       DENSE_RANK() OVER (PARTITION BY d.dpt ORDER BY COUNT(t.case_id) DESC) AS rank_in_dept,
       ROUND(100.0 * COUNT(t.case_id) / NULLIF(SUM(COUNT(t.case_id)) OVER (PARTITION BY d.dpt), 0), 1) AS pct_of_dept
FROM doctors d
JOIN people p     ON p.id = d.doctor_id
LEFT JOIN tests t ON t.doctor_id = d.doctor_id
GROUP BY d.dpt, d.doctor_id, p.fname, p.lname, d.rank
ORDER BY department, rank_in_dept, doctor;
