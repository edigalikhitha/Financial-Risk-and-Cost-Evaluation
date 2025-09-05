use health;
select * from encounters;
select * from organizations;
select * from patients;
select * from payers;
select * from procedures;

-- Cleanup: Set NULL costs to 0 using CTEs
WITH CostFix AS (
    SELECT *
    FROM encounters
    WHERE BASE_ENCOUNTER_COST IS NULL 
       OR TOTAL_CLAIM_COST IS NULL 
       OR PAYER_COVERAGE IS NULL
)
UPDATE e
SET 
    BASE_ENCOUNTER_COST = ISNULL(c.BASE_ENCOUNTER_COST, 0),
    TOTAL_CLAIM_COST = ISNULL(c.TOTAL_CLAIM_COST, 0),
    PAYER_COVERAGE = ISNULL(c.PAYER_COVERAGE, 0)
FROM encounters e
JOIN CostFix c ON e.Id = c.Id;

-- Remove rows with missing ReasonCode
WITH InvalidReasons AS (
    SELECT Id FROM encounters WHERE ReasonCode IS NULL
)
DELETE FROM encounters
WHERE Id IN (SELECT Id FROM InvalidReasons);

-- Clean procedures with missing or empty codes
WITH InvalidProcedures AS (
    SELECT * FROM procedures WHERE Code IS NULL OR LTRIM(RTRIM(Code)) = ''
)
DELETE FROM procedures
WHERE EXISTS (SELECT 1 FROM InvalidProcedures i WHERE i.Encounter = procedures.Encounter);

-- Fill NULL base costs in procedures
WITH MissingBaseCost AS (
    SELECT * FROM procedures WHERE Base_Cost IS NULL
)
UPDATE procedures
SET Base_Cost = 0
FROM procedures p
JOIN MissingBaseCost m ON p.Encounter = m.Encounter;

-- Clean missing payer names
WITH UnknownPayers AS (
    SELECT * FROM payers WHERE Name IS NULL
)
UPDATE payers
SET Name = 'Unknown'
FROM payers p
JOIN UnknownPayers u ON p.Id = u.Id;

-- Clean missing organization names
WITH UnknownOrgs AS (
    SELECT * FROM organizations WHERE Name IS NULL
)
UPDATE organizations
SET Name = 'Unknown Organization'
FROM organizations o
JOIN UnknownOrgs u ON o.Id = u.Id;
1.
WITH FinancialRisk AS (
    SELECT 
        ReasonCode,
        SUM(ISNULL(Total_Claim_Cost, 0) - ISNULL(Payer_Coverage, 0)) AS Total_Uncovered_Cost
    FROM encounters
    GROUP BY ReasonCode
)
SELECT TOP 100 *
FROM FinancialRisk
ORDER BY Total_Uncovered_Cost DESC;

2. 
WITH HighCostEncounters AS (
    SELECT 
        Patient,
        YEAR(Start) AS EncounterYear,
        COUNT(*) AS EncounterCount,
        SUM(Total_Claim_Cost) AS TotalCost
    FROM encounters
    WHERE Total_Claim_Cost > 10000
    GROUP BY Patient, YEAR(Start)
)
SELECT 
    p.Id, p.First, p.Last, h.EncounterYear, h.EncounterCount, h.TotalCost
FROM HighCostEncounters h
JOIN patients p ON p.Id = h.Patient
WHERE h.EncounterCount > 3;
3.

WITH TopReasonCodes AS (
    SELECT TOP 3 ReasonCode, COUNT(*) AS Frequency
    FROM encounters
    GROUP BY ReasonCode
    ORDER BY COUNT(*) DESC
)
SELECT 
    rc.ReasonCode, e.Total_Claim_Cost,
    p.Gender, p.Race, p.Ethnicity, p.State
FROM encounters e
JOIN TopReasonCodes rc ON e.ReasonCode = rc.ReasonCode
JOIN patients p ON e.Patient = p.Id;

4.
WITH ProcedurePayerGap AS (
    SELECT 
        pr.Code AS ProcedureCode,
        pr.Description AS ProcedureName,
        e.Payer,
        AVG(ISNULL(e.Total_Claim_Cost, 0)) AS AvgTotalCost,
        AVG(ISNULL(e.Payer_Coverage, 0)) AS AvgPayerCoverage,
        AVG(ISNULL(e.Total_Claim_Cost, 0) - ISNULL(e.Payer_Coverage, 0)) AS AvgGap
    FROM procedures pr
    JOIN encounters e ON pr.Encounter = e.Id
    GROUP BY pr.Code, pr.Description, e.Payer
)
SELECT *
FROM ProcedurePayerGap
ORDER BY AvgGap DESC;

5.
WITH MultiProcedurePatients AS (
    SELECT 
        pr.Patient,
        e.ReasonCode,
        COUNT(DISTINCT pr.Encounter) AS EncounterCount
    FROM procedures pr
    JOIN encounters e ON pr.Encounter = e.Id
    GROUP BY pr.Patient, e.ReasonCode
    HAVING COUNT(DISTINCT pr.Encounter) > 1
)
SELECT 
    m.Patient, p.First, p.Last, m.ReasonCode, m.EncounterCount
FROM MultiProcedurePatients m
JOIN patients p ON m.Patient = p.Id;

6.
WITH EncounterDurations AS (
    SELECT 
        e.Organization,
        e.EncounterClass,
        DATEDIFF(HOUR, e.Start, e.Stop) AS DurationHours
    FROM encounters e
)
SELECT 
    o.Name AS OrganizationName,
    ed.EncounterClass,
    AVG(ed.DurationHours) AS AvgDuration,
    COUNT(CASE WHEN ed.DurationHours > 24 THEN 1 END) AS EncountersOver24Hrs
FROM EncounterDurations ed
JOIN organizations o ON ed.Organization = o.Id
GROUP BY o.Name, ed.EncounterClass;