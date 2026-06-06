/*
================================================================================
Demo 4: Query Operator Order
Topics: Logical query processing order and its implications
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables
-- ============================================================================

IF OBJECT_ID('dbo.Employees', 'U') IS NOT NULL
    DROP TABLE dbo.Employees;
GO

IF OBJECT_ID('dbo.Departments', 'U') IS NOT NULL
    DROP TABLE dbo.Departments;
GO

IF OBJECT_ID('dbo.Sales', 'U') IS NOT NULL
    DROP TABLE dbo.Sales;
GO

-- Create Departments table
CREATE TABLE dbo.Departments (
    DepartmentID INT NOT NULL PRIMARY KEY,
    DepartmentName VARCHAR(50) NOT NULL,
    Location VARCHAR(50) NOT NULL
);
GO

INSERT INTO dbo.Departments (DepartmentID, DepartmentName, Location)
VALUES 
    (1, 'Sales', 'New York'),
    (2, 'IT', 'San Francisco'),
    (3, 'HR', 'Chicago'),
    (4, 'Marketing', 'Los Angeles'),
    (5, 'Finance', 'Boston');
GO

-- Create Employees table
CREATE TABLE dbo.Employees (
    EmployeeID INT NOT NULL PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    DepartmentID INT NOT NULL,
    Salary DECIMAL(10, 2) NOT NULL,
    HireDate DATE NOT NULL,
    ManagerID INT NULL
);
GO

INSERT INTO dbo.Employees (EmployeeID, FirstName, LastName, DepartmentID, Salary, HireDate, ManagerID)
SELECT 
    number,
    'FirstName' + CAST(number AS VARCHAR(10)),
    'LastName' + CAST(number AS VARCHAR(10)),
    (number % 5) + 1,
    30000 + (number * 100),
    DATEADD(DAY, -(number % 3650), GETDATE()),
    CASE WHEN number % 10 = 0 THEN NULL ELSE (number % 100) + 1 END
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 1000;
GO

-- Create Sales table
CREATE TABLE dbo.Sales (
    SaleID INT NOT NULL PRIMARY KEY,
    EmployeeID INT NOT NULL,
    SaleDate DATE NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Region VARCHAR(50) NOT NULL
);
GO

INSERT INTO dbo.Sales (SaleID, EmployeeID, SaleDate, Amount, Region)
SELECT 
    number,
    (number % 1000) + 1,
    DATEADD(DAY, -(number % 730), GETDATE()),
    (number % 5000) + 100.00,
    CASE (number % 4)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 10000;
GO

-- ============================================================================
-- Logical Query Processing Order:
-- 1. FROM (including JOINs)
-- 2. WHERE
-- 3. GROUP BY
-- 4. HAVING
-- 5. SELECT
-- 6. DISTINCT
-- 7. ORDER BY
-- 8. TOP / OFFSET-FETCH
-- ============================================================================

-- ============================================================================
-- 1. FROM → WHERE → SELECT: Column Aliases
-- ============================================================================

-- WRONG: Cannot use SELECT alias in WHERE (alias doesn't exist yet)
/*
SELECT 
    FirstName,
    LastName,
    Salary * 12 AS AnnualSalary
FROM dbo.Employees
WHERE AnnualSalary > 500000;  -- ERROR: Invalid column name 'AnnualSalary'
*/

-- CORRECT: Repeat expression or use subquery/CTE
SELECT 
    FirstName,
    LastName,
    Salary * 12 AS AnnualSalary
FROM dbo.Employees
WHERE Salary * 12 > 500000;  -- Expression repeated
GO

-- BETTER: Use CTE to avoid repeating logic
WITH EmployeeWithAnnual AS (
    SELECT 
        FirstName,
        LastName,
        Salary * 12 AS AnnualSalary
    FROM dbo.Employees
)
SELECT *
FROM EmployeeWithAnnual
WHERE AnnualSalary > 500000;
GO

-- ============================================================================
-- 2. WHERE → GROUP BY → HAVING: Filter Order
-- ============================================================================

-- LESS EFFICIENT: Filter after aggregation with HAVING
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount,
    AVG(Salary) AS AvgSalary
FROM dbo.Employees
GROUP BY DepartmentID
HAVING DepartmentID IN (1, 2, 3);  -- Filtering after grouping all departments
GO

-- MORE EFFICIENT: Filter before aggregation with WHERE
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount,
    AVG(Salary) AS AvgSalary
FROM dbo.Employees
WHERE DepartmentID IN (1, 2, 3)  -- Reduce dataset early
GROUP BY DepartmentID;
GO

-- HAVING is for aggregate conditions
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount,
    AVG(Salary) AS AvgSalary
FROM dbo.Employees
WHERE HireDate >= '2020-01-01'  -- Filter rows before grouping
GROUP BY DepartmentID
HAVING COUNT(*) > 50;  -- Filter groups after aggregation
GO

-- ============================================================================
-- 3. SELECT → ORDER BY: Can Use Aliases
-- ============================================================================

-- ORDER BY can reference SELECT aliases (ORDER BY processes after SELECT)
SELECT 
    FirstName + ' ' + LastName AS FullName,
    Salary,
    DepartmentID
FROM dbo.Employees
ORDER BY FullName;  -- Valid: FullName defined in SELECT
GO

-- ORDER BY can use column positions (not recommended, but valid)
SELECT 
    FirstName,
    LastName,
    Salary
FROM dbo.Employees
ORDER BY 3 DESC;  -- Orders by 3rd column (Salary)
GO

-- ORDER BY can use columns not in SELECT
SELECT 
    FirstName,
    LastName
FROM dbo.Employees
ORDER BY Salary DESC;  -- Valid: Salary doesn't need to be in SELECT
GO

-- ============================================================================
-- 4. FROM with JOINs: Order of Joins
-- ============================================================================

-- Joins are processed left to right in FROM clause
-- But optimizer can reorder for efficiency

SELECT 
    E.FirstName,
    E.LastName,
    D.DepartmentName,
    S.Amount
FROM dbo.Employees E
INNER JOIN dbo.Departments D ON E.DepartmentID = D.DepartmentID
INNER JOIN dbo.Sales S ON E.EmployeeID = S.EmployeeID
WHERE S.SaleDate >= '2025-01-01';
-- Optimizer may start with Sales (filtered by WHERE) then join to Employees and Departments
GO

-- ============================================================================
-- 5. GROUP BY → SELECT: SELECT can only reference grouped or aggregated columns
-- ============================================================================

-- WRONG: FirstName not in GROUP BY and not aggregated
/*
SELECT 
    DepartmentID,
    FirstName,  -- ERROR: Not in GROUP BY
    COUNT(*) AS EmployeeCount
FROM dbo.Employees
GROUP BY DepartmentID;
*/

-- CORRECT: Only grouped columns and aggregates
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount,
    MIN(FirstName) AS SampleFirstName  -- Aggregate function OK
FROM dbo.Employees
GROUP BY DepartmentID;
GO

-- ============================================================================
-- 6. TOP → ORDER BY: TOP processes after ORDER BY
-- ============================================================================

-- TOP without ORDER BY (non-deterministic)
SELECT TOP 10 *
FROM dbo.Employees;
-- Returns arbitrary 10 rows
GO

-- TOP with ORDER BY (deterministic)
SELECT TOP 10 
    FirstName,
    LastName,
    Salary
FROM dbo.Employees
ORDER BY Salary DESC;
-- Returns top 10 highest paid employees
GO

-- TOP with TIES (includes ties in ORDER BY)
SELECT TOP 10 WITH TIES
    FirstName,
    LastName,
    Salary
FROM dbo.Employees
ORDER BY Salary DESC;
-- Includes additional rows if salary matches 10th value
GO

-- Modern alternative: OFFSET-FETCH
SELECT 
    FirstName,
    LastName,
    Salary
FROM dbo.Employees
ORDER BY Salary DESC
OFFSET 0 ROWS
FETCH NEXT 10 ROWS ONLY;
GO

-- Pagination example
SELECT 
    FirstName,
    LastName,
    Salary
FROM dbo.Employees
ORDER BY Salary DESC
OFFSET 20 ROWS  -- Skip first 20
FETCH NEXT 10 ROWS ONLY;  -- Get next 10 (rows 21-30)
GO

-- ============================================================================
-- 7. DISTINCT: Processes after SELECT
-- ============================================================================

-- DISTINCT on single column
SELECT DISTINCT DepartmentID
FROM dbo.Employees;
GO

-- DISTINCT on multiple columns (distinct combinations)
SELECT DISTINCT DepartmentID, Salary
FROM dbo.Employees
ORDER BY DepartmentID, Salary;
GO

-- Alternative: GROUP BY (sometimes more efficient)
SELECT DepartmentID
FROM dbo.Employees
GROUP BY DepartmentID;
GO

-- ============================================================================
-- 8. Subqueries: Each has its own processing order
-- ============================================================================

-- Scalar subquery in SELECT (executed for each row)
SELECT 
    E.FirstName,
    E.LastName,
    E.Salary,
    (SELECT AVG(Salary) FROM dbo.Employees WHERE DepartmentID = E.DepartmentID) AS DeptAvgSalary
FROM dbo.Employees E;
GO

-- Subquery in WHERE (better: use JOIN)
SELECT 
    FirstName,
    LastName,
    Salary
FROM dbo.Employees
WHERE DepartmentID IN (
    SELECT DepartmentID 
    FROM dbo.Departments 
    WHERE Location = 'New York'
);
GO

-- Better with JOIN
SELECT 
    E.FirstName,
    E.LastName,
    E.Salary
FROM dbo.Employees E
INNER JOIN dbo.Departments D ON E.DepartmentID = D.DepartmentID
WHERE D.Location = 'New York';
GO

-- ============================================================================
-- 9. Common Mistakes Due to Processing Order
-- ============================================================================

-- Mistake 1: Filtering on window function in WHERE
/*
SELECT 
    FirstName,
    LastName,
    Salary,
    ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum
FROM dbo.Employees
WHERE RowNum <= 10;  -- ERROR: Window functions not allowed in WHERE
*/

-- Correct: Use CTE or subquery
WITH RankedEmployees AS (
    SELECT 
        FirstName,
        LastName,
        Salary,
        ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum
    FROM dbo.Employees
)
SELECT *
FROM RankedEmployees
WHERE RowNum <= 10;
GO

-- Mistake 2: Using aggregate without GROUP BY on non-aggregated columns
/*
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount
FROM dbo.Employees;  -- ERROR if not grouped
*/

-- Correct
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount
FROM dbo.Employees
GROUP BY DepartmentID;
GO

-- ============================================================================
-- 10. Execution Order vs. Optimization
-- ============================================================================

-- Logical order is for correctness
-- Physical execution order (in plan) is optimized

SET STATISTICS IO ON;

-- Logical: FROM → WHERE → SELECT → ORDER BY
-- Physical: Optimizer may reorder operations for efficiency
SELECT 
    E.FirstName,
    E.LastName,
    D.DepartmentName
FROM dbo.Employees E
INNER JOIN dbo.Departments D ON E.DepartmentID = D.DepartmentID
WHERE E.Salary > 100000
ORDER BY E.LastName;
-- Check execution plan: May filter (WHERE) before join for efficiency
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP TABLE dbo.Sales;
-- DROP TABLE dbo.Employees;
-- DROP TABLE dbo.Departments;
-- GO
