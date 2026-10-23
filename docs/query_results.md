# Query results

Output of every query in sql/03_queries.sql (made with scripts/export_results.py).

## Query 1

For each infection case, the number of involved patients, contributing doctors and tests performed. Each table is counted separately first, joining all three at once would multiply the rows (patients x doctors x tests).

Uses: CTEs, LEFT JOIN, COALESCE

```sql
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
```

| case_id | num_patients | num_doctors | num_tests |
|---|---|---|---|
| 22001 | 7 | 8 | 16 |
| 22002 | 7 | 5 | 12 |
| 22003 | 14 | 4 | 17 |
| 22004 | 14 | 6 | 16 |
| 22005 | 5 | 6 | 15 |
| 22006 | 14 | 3 | 16 |
| 22007 | 15 | 5 | 16 |
| 22008 | 5 | 8 | 10 |
| 22009 | 11 | 7 | 11 |
| 22010 | 12 | 3 | 10 |
| 22011 | 12 | 5 | 18 |
| 22012 | 13 | 5 | 12 |
| 22013 | 11 | 5 | 20 |
| 22014 | 9 | 8 | 12 |
| 22015 | 13 | 6 | 16 |

(20 rows, first 15 shown)

## Query 2

All wards with more than 2 infection cases.

Uses: GROUP BY, HAVING

```sql
SELECT ward, COUNT(*) AS infection_case_count
FROM infection_case
GROUP BY ward
HAVING COUNT(*) > 2
ORDER BY infection_case_count DESC, ward;
```

| ward | infection_case_count |
|---|---|
| Surgery | 5 |
| Emergency | 4 |
| Pediatrics | 4 |
| ICU | 3 |
| Oncology | 3 |

(5 rows)

## Query 3

Patients involved in at least 3 cases detected between April and June 2024 who were source_status = 'active' in at least one of them.

Uses: COUNT(*) FILTER, date range

```sql
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
```

| id | fname | lname | cases_q2_2024 |
|---|---|---|---|
| 30199 | Sara | Fischer | 5 |
| 30099 | David | Hartmann | 4 |
| 30097 | Carla | Klein | 4 |
| 30133 | Lea | Koch | 4 |
| 30192 | Paul | Meyer | 4 |
| 30165 | Anna | Zimmermann | 4 |
| 30107 | Carla | Bauer | 3 |
| 30140 | Max | Becker | 3 |
| 30143 | Paul | Becker | 3 |
| 30149 | David | Hale | 3 |
| 30172 | Aisha | Hoffmann | 3 |
| 30124 | Jonas | Klein | 3 |
| 30145 | Julia | Koch | 3 |
| 30176 | Mira | Meyer | 3 |
| 30197 | Nora | Meyer | 3 |

(18 rows, first 15 shown)

## Query 4

Names of all doctors who worked together with the doctor who contributed to the most cases. Two doctors both have 5 cases, so RANK() is used to keep both of them instead of picking one with LIMIT 1.

Uses: CTEs, RANK(), self join

```sql
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
```

| fname | lname |
|---|---|
| Tobias | Becker |
| Julia | Brandt |
| Victor | Brandt |
| David | Fischer |
| Julia | Fischer |
| David | Hale |
| Max | Hale |
| David | Hartmann |
| Carla | Hoffmann |
| Carla | Hoffmann |
| Mira | Hoffmann |
| Sara | Hoffmann |
| Mira | Khan |
| Aisha | Koch |
| Anna | Meyer |

(32 rows, first 15 shown)

## Query 5

Doctors performing "bad", i.e. case_counter within the 10th percentile.

Uses: percentile_disc, view

```sql
WITH p10 AS (
    SELECT percentile_disc(0.1) WITHIN GROUP (ORDER BY case_counter) AS v
    FROM doctor_case_counter
)
SELECT p.fname, p.lname, dcc.case_counter
FROM doctor_case_counter dcc
JOIN p10 ON dcc.case_counter <= p10.v
JOIN people p ON p.id = dcc.doctor_id
ORDER BY p.lname, p.fname;
```

| fname | lname | case_counter |
|---|---|---|
| Anna | Becker | 0 |
| Emilia | Becker | 0 |
| Lukas | Hale | 0 |
| Jonas | Hartmann | 0 |
| Nora | Hartmann | 0 |
| Lea | Khan | 0 |
| Marco | Klein | 0 |
| Julia | Koch | 0 |
| Max | Koch | 0 |
| Nora | Koch | 0 |
| Sara | Koch | 0 |
| Felix | Lopez | 0 |
| David | Meyer | 0 |
| Tobias | Meyer | 0 |
| Carla | Novak | 0 |

(23 rows, first 15 shown)

## Query 6

All active cases with case id, infection type, ward, detection time and the full name of the lead doctor.

Uses: JOIN, string concatenation

```sql
SELECT ic.case_id, ic.infection_type, ic.ward, ic.detection_time,
       p.fname || ' ' || p.lname AS lead_doctor
FROM infection_case ic
JOIN people p ON p.id = ic.lead_doctor_id
WHERE ic.status = 'active'
ORDER BY ic.detection_time, ic.case_id;
```

| case_id | infection_type | ward | detection_time | lead_doctor |
|---|---|---|---|---|
| 22019 | COVID-19 | Surgery | 2024-03-23 11:15:00 | Laura Wolf |
| 22016 | C. difficile | Surgery | 2024-04-07 21:42:00 | David Lopez |
| 22009 | MRSA | Emergency | 2024-04-20 15:44:00 | Mira Fischer |
| 22012 | Norovirus | Oncology | 2024-04-22 03:03:00 | Max Koch |
| 22006 | C. difficile | Oncology | 2024-04-28 00:26:00 | Paul Hoffmann |
| 22004 | RSV | Pediatrics | 2024-05-20 03:18:00 | Sara Fischer |
| 22002 | VRE | Surgery | 2024-05-21 13:10:00 | Sara Hoffmann |
| 22017 | MRSA | Oncology | 2024-05-21 17:32:00 | Mira Fischer |
| 22010 | C. difficile | ICU | 2024-06-01 00:57:00 | Jonas Meyer |
| 22014 | MRSA | Emergency | 2024-06-03 16:36:00 | David Becker |

(10 rows)

## Query 7

For each infection type, the number of cases and how many are active.

Uses: COUNT(*) FILTER

```sql
SELECT infection_type,
       COUNT(*)                                   AS total_cases,
       COUNT(*) FILTER (WHERE status = 'active')  AS active_cases
FROM infection_case
GROUP BY infection_type
ORDER BY total_cases DESC, infection_type;
```

| infection_type | total_cases | active_cases |
|---|---|---|
| COVID-19 | 6 | 1 |
| C. difficile | 5 | 3 |
| MRSA | 4 | 3 |
| Norovirus | 3 | 1 |
| RSV | 1 | 1 |
| VRE | 1 | 1 |

(6 rows)

## Query 8

Top 3 cases with the most collected samples. WITH TIES keeps cases that are tied with 3rd place, the outer ORDER BY just sorts ties by case id.

Uses: FETCH FIRST ... WITH TIES

```sql
SELECT *
FROM (
    SELECT case_id, COUNT(*) AS collected_samples
    FROM evidence_samples
    GROUP BY case_id
    ORDER BY collected_samples DESC
    FETCH FIRST 3 ROWS WITH TIES
) top3
ORDER BY collected_samples DESC, case_id;
```

| case_id | collected_samples |
|---|---|
| 22015 | 5 |
| 22006 | 4 |
| 22013 | 4 |

(3 rows)

## Query 9

Patients who are source_status = 'active' in more than 2 cases.

Uses: WHERE, GROUP BY, HAVING

```sql
SELECT p.id, p.fname, p.lname, COUNT(*) AS active_source_in_cases
FROM people p
JOIN case_patient cp ON cp.patient_id = p.id
WHERE cp.source_status = 'active'
GROUP BY p.id, p.fname, p.lname
HAVING COUNT(*) > 2
ORDER BY active_source_in_cases DESC, p.lname, p.fname;
```

| id | fname | lname | active_source_in_cases |
|---|---|---|---|
| 30107 | Carla | Bauer | 3 |
| 30140 | Max | Becker | 3 |
| 30199 | Sara | Fischer | 3 |
| 30099 | David | Hartmann | 3 |
| 30192 | Paul | Meyer | 3 |
| 30141 | Victor | Richter | 3 |

(6 rows)

## Query 10

Doctors with more than 8 tests, their number of tests and the most recent one.

Uses: COUNT, MAX, HAVING

```sql
SELECT t.doctor_id,
       p.fname || ' ' || p.lname AS doctor,
       COUNT(*)                  AS total_tests,
       MAX(t."timestamp")        AS most_recent_test
FROM tests t
JOIN people p ON p.id = t.doctor_id
GROUP BY t.doctor_id, p.fname, p.lname
HAVING COUNT(*) > 8
ORDER BY total_tests DESC, doctor;
```

| doctor_id | doctor | total_tests | most_recent_test |
|---|---|---|---|
| 30073 | Tobias Novak | 20 | 2024-06-18 23:53:00 |
| 30025 | Elena Novak | 14 | 2024-05-23 05:20:00 |
| 30040 | Nora Brandt | 14 | 2024-05-30 17:51:00 |
| 30071 | Sara Klein | 13 | 2024-06-13 04:35:00 |
| 30056 | Tobias Schmidt | 12 | 2024-06-09 05:49:00 |
| 30065 | Max Hartmann | 11 | 2024-05-25 03:07:00 |
| 30063 | Lukas Schmidt | 10 | 2024-06-10 15:55:00 |
| 30068 | Anna Novak | 9 | 2024-06-09 17:51:00 |

(8 rows)

## Query 11: Response time

How fast does testing start after an outbreak is detected? Hours from detection to the first test, compared within each ward.

Uses: interval arithmetic, AVG() OVER, RANK() OVER

```sql
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
```

| case_id | ward | infection_type | hours_to_first_test | ward_avg_hours | rank_in_ward |
|---|---|---|---|---|---|
| 22014 | Emergency | MRSA | 7.4 | 28.6 | 1 |
| 22009 | Emergency | MRSA | 16.5 | 28.6 | 2 |
| 22020 | Emergency | Norovirus | 26.3 | 28.6 | 3 |
| 22018 | Emergency | MRSA | 64.1 | 28.6 | 4 |
| 22011 | ICU | Norovirus | 1.4 | 56.2 | 1 |
| 22005 | ICU | C. difficile | 24.3 | 56.2 | 2 |
| 22010 | ICU | C. difficile | 143.0 | 56.2 | 3 |
| 22001 | Internal Medicine | COVID-19 | 65.4 | 65.4 | 1 |
| 22006 | Oncology | C. difficile | 13.0 | 20.1 | 1 |
| 22017 | Oncology | MRSA | 18.5 | 20.1 | 2 |
| 22012 | Oncology | Norovirus | 28.8 | 20.1 | 3 |
| 22004 | Pediatrics | RSV | 5.5 | 9.6 | 1 |
| 22015 | Pediatrics | COVID-19 | 7.3 | 9.6 | 2 |
| 22007 | Pediatrics | COVID-19 | 12.7 | 9.6 | 3 |
| 22008 | Pediatrics | COVID-19 | 12.8 | 9.6 | 4 |

(20 rows, first 15 shown)

## Query 12: Cases that share patients

Pairs of cases with 4 or more patients in common. A shared patient could be a link between two outbreaks.

Uses: self join, STRING_AGG

```sql
SELECT a.case_id AS case_a, b.case_id AS case_b,
       COUNT(*)  AS shared_patients,
       STRING_AGG(a.patient_id::text, ', ' ORDER BY a.patient_id) AS patient_ids
FROM case_patient a
JOIN case_patient b ON b.patient_id = a.patient_id AND b.case_id > a.case_id
GROUP BY a.case_id, b.case_id
HAVING COUNT(*) >= 4
ORDER BY shared_patients DESC, case_a, case_b;
```

| case_a | case_b | shared_patients | patient_ids |
|---|---|---|---|
| 22004 | 22020 | 5 | 30091, 30131, 30161, 30185, 30189 |
| 22003 | 22013 | 4 | 30122, 30162, 30188, 30198 |
| 22011 | 22018 | 4 | 30087, 30107, 30109, 30144 |

(3 rows)

## Query 13: Doctor workload

Tests per doctor, ranked inside the department, and the share of the department's tests. LEFT JOIN so doctors without tests show up with 0.

Uses: LEFT JOIN, DENSE_RANK(), SUM() OVER

```sql
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
```

| department | doctor | rank | tests | rank_in_dept | pct_of_dept |
|---|---|---|---|---|---|
| Emergency | Tobias Schmidt | Chief | 12 | 1 | 27.9 |
| Emergency | Aisha Koch | Assistant | 8 | 2 | 18.6 |
| Emergency | Julia Fischer | Senior | 8 | 2 | 18.6 |
| Emergency | Tobias Wagner | Chief | 7 | 3 | 16.3 |
| Emergency | Paul Khan | Assistant | 3 | 4 | 7.0 |
| Emergency | Sara Novak | Chief | 3 | 4 | 7.0 |
| Emergency | David Hale | Senior | 2 | 5 | 4.7 |
| Emergency | Jonas Reuter | Assistant | 0 | 6 | 0.0 |
| Emergency | Lukas Hale | Chief | 0 | 6 | 0.0 |
| Emergency | Mira Wolf | Senior | 0 | 6 | 0.0 |
| Infectious Diseases | Tobias Novak | Assistant | 20 | 1 | 40.0 |
| Infectious Diseases | Felix Reuter | Chief | 8 | 2 | 16.0 |
| Infectious Diseases | David Zimmermann | Assistant | 7 | 3 | 14.0 |
| Infectious Diseases | Jonas Meyer | Assistant | 5 | 4 | 10.0 |
| Infectious Diseases | Sara Schmidt | Chief | 5 | 4 | 10.0 |

(80 rows, first 15 shown)
