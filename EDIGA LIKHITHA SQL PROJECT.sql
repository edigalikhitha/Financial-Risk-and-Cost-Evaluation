use health;
select * from encounters;
select * from organizations;
select * from patients;
select * from payers;
select * from procedures;

-- Remove encounters with missing or invalid dates

DELETE FROM encounters
WHERE
  Start IS NULL
  AND Stop IS NULL;

  -- Handle any encounters with missing costs or payer coverage

  UPDATE encounters
SET
  Base_Encounter_Cost = 0
WHERE
  Base_Encounter_Cost IS NULL;

  UPDATE encounters
SET
  Total_Claim_Cost = 0
WHERE
  Total_Claim_Cost IS NULL;

UPDATE encounters
SET
  Payer_Coverage = 0
WHERE
  Payer_Coverage IS NULL;

  -- Clean any invalid ReasonCodes (if applicable)

  DELETE FROM encounters
WHERE
  ReasonCode IS NULL;

  -- Remove rows where the procedure code is invalid or missing

  DELETE FROM procedures
WHERE
  Code IS NULL
  OR Code = '';

  -- Clean the Base_Cost if it's missing

  UPDATE procedures
SET
  Base_Cost = 0
WHERE
  Base_Cost IS NULL;

  -- Ensure there are no rows with missing payer information

  UPDATE payers
SET
  Name = 'Unknown'
WHERE
  Name IS NULL;

  -- Clean missing organization details

  UPDATE organizations
SET Name = 'Unknown Organization'
WHERE Name IS NULL;


-- Main Project--

-- 1. Evaluating Financial Risk by Encounter Outcome --

SELECT
  p.Code AS ReasonCode,
  SUM(e.Total_Claim_Cost - e.Payer_Coverage) AS Uncovered_Cost,
  COUNT(*) AS Encounter_Count
FROM
  procedures p
  JOIN encounters e ON p.Encounter = e.Id
GROUP BY
  p.Code
ORDER BY
  Uncovered_Cost DESC
OFFSET
  0 ROWS
FETCH NEXT
  1000 ROWS ONLY;

  -- 2. Identifying Patients with Frequent High-Cost Encounters --

  SELECT
  Patient,
  COUNT(*) AS High_Cost_Encounters,
  SUM(Total_Claim_Cost) AS Total_Encounter_Cost
FROM
  encounters
WHERE
  Total_Claim_Cost > 10000 -- Threshold for high-cost encounters
GROUP BY
  Patient
HAVING
  COUNT(*) > 3;

  --3. Identifying Risk Factors Based on Demographics and Encounter Reasons --
  SELECT
  p.Gender, -- Gender from patients table
  p.Race, -- Race from patients table
  p.Ethnicity, -- Ethnicity from patients table
  e.ReasonCode, -- ReasonCode from encounters table
  pr.Description AS Procedure_Name, -- Procedure details from procedures table
  pay.NAME AS Payer_Name, -- Payer details from payers table
  COUNT(*) AS Encounter_Count, -- Count of encounters per procedure and payer group
  ROUND(SUM(e.Total_Claim_Cost), 2) AS Total_Cost, -- Sum of Total Claim Cost for each group
  ROUND(SUM(e.Total_Claim_Cost) / COUNT(*), 2) AS Avg_Cost_Per_Encounter, -- Average cost per encounter for each procedure group
  COUNT(DISTINCT e.PATIENT) AS Distinct_Patient_Count, -- Count of distinct patients for each group
  ROUND(
    SUM(e.Total_Claim_Cost) / COUNT(DISTINCT e.PATIENT),
    2
  ) AS Avg_Cost_Per_Patient -- Average cost per patient per procedure
FROM
  encounters e -- Encounters table
  JOIN patients p -- Patients table
  ON e.PATIENT = p.Id -- Join encounters with patients by Patient_ID
  LEFT JOIN procedures pr -- Procedures table
  ON e.CODE = pr.CODE -- Join encounters with procedures using the correct procedure CODE
  LEFT JOIN payers pay -- Payers table
  ON e.PAYER = pay.ID -- Join encounters with payers using the correct payer ID field
WHERE
  e.ReasonCode IS NOT NULL -- Ensure ReasonCode is not null
  AND e.Total_Claim_Cost >= 0 -- Ensure total claim cost is valid
  AND e.Total_Claim_Cost < 1000000 -- Filter out encounters with excessively high costs
GROUP BY
  p.Gender,
  p.Race,
  p.Ethnicity,
  e.ReasonCode,
  pr.Description,
  pay.NAME -- Group by demographics, reason code, procedure, and payer name
HAVING
  COUNT(*) < 10000 -- Filter by encounter count in the HAVING clause to remove anomalies
ORDER BY
  Total_Cost DESC;
-- Sort by Total Cost in descending order to highlight high-cost procedures

-- 4. Assessing Payer Contributions for Different Procedure Types

SELECT
  p.Code,
  SUM(e.Total_Claim_Cost) AS Total_Cost,
  SUM(e.Payer_Coverage) AS Total_Payer_Coverage,
  SUM(e.Total_Claim_Cost - e.Payer_Coverage) AS Uncovered_Cost
FROM
  procedures p
  JOIN encounters e ON p.Encounter = e.Id
GROUP BY
  p.Code
ORDER BY
  SUM(e.Total_Claim_Cost - e.Payer_Coverage) DESC;

  -- 5.Identifying Patients with Multiple Procedures Across Encounters
SELECT
    e.ID AS PATIENTID, -- Assuming you have a PatientID in your encounters table
    p.CODE AS PROCEDURE_CODE,
    p.DESCRIPTION AS PROCEDURE_DESC,
    YEAR(e.START) AS encounter_year,
    MONTH(e.START) AS encounter_month,
    SUM(e.BASE_ENCOUNTER_COST) AS total_cost,
    COUNT(e.ID) AS encounter_count,
    SUM(e.CODE) AS total_procedures -- Assuming you have a PROCEDURES column in encounters
FROM
    encounters e
    left JOIN procedures p ON e.CODE = p.CODE
	where p.CODE IS NOT NULL
GROUP BY
    e.ID,  -- Grouping by PatientID to identify patients
    p.CODE,
    p.DESCRIPTION,
    YEAR(e.START),
    MONTH(e.START)
HAVING
	SUM(e.CODE) > 1  --Filter for patients with multiple procedures
ORDER BY
    encounter_year,
    encounter_month,
    total_cost DESC
OFFSET
    999 ROWS
FETCH NEXT
   2000 ROWS ONLY;

-- 6. Analyzing Patient Encounter Duration for Different Classes

SELECT e.EncounterClass, o.Name AS Organization, AVG(DATEDIFF(HOUR, e.Start, e.Stop)) AS Avg_Duration
FROM encounters e
JOIN organizations o ON e.Organization = o.Id
GROUP BY e.EncounterClass, o.Name
ORDER BY Avg_Duration DESC;


