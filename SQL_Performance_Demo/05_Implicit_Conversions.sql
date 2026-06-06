/*
================================================================================
Demo 5: Implicit Conversions
Topics: Detection, performance impact, and solutions
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables with various data types
-- ============================================================================

IF OBJECT_ID('dbo.Users', 'U') IS NOT NULL
    DROP TABLE dbo.Users;
GO

IF OBJECT_ID('dbo.Transactions', 'U') IS NOT NULL
    DROP TABLE dbo.Transactions;
GO

-- Table with VARCHAR columns
CREATE TABLE dbo.Users (
    UserID INT NOT NULL PRIMARY KEY,
    Username VARCHAR(50) NOT NULL,
    Email VARCHAR(100) NOT NULL,
    PhoneNumber VARCHAR(20) NOT NULL,
    CreatedDate DATETIME NOT NULL
);
GO

CREATE NONCLUSTERED INDEX IX_Users_Username ON dbo.Users(Username);
CREATE NONCLUSTERED INDEX IX_Users_Email ON dbo.Users(Email);
CREATE NONCLUSTERED INDEX IX_Users_PhoneNumber ON dbo.Users(PhoneNumber);
GO

-- Insert sample data
INSERT INTO dbo.Users (UserID, Username, Email, PhoneNumber, CreatedDate)
SELECT 
    number,
    'user' + CAST(number AS VARCHAR(10)),
    'user' + CAST(number AS VARCHAR(10)) + '@example.com',
    '555-' + RIGHT('0000' + CAST(number AS VARCHAR), 4),
    DATEADD(DAY, -(number % 730), GETDATE())
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 10000;
GO

-- Table with INT and BIGINT columns
CREATE TABLE dbo.Transactions (
    TransactionID BIGINT NOT NULL PRIMARY KEY,  -- BIGINT
    UserID INT NOT NULL,  -- INT
    Amount DECIMAL(10, 2) NOT NULL,
    TransactionDate DATETIME NOT NULL
);
GO

CREATE NONCLUSTERED INDEX IX_Transactions_UserID ON dbo.Transactions(UserID);
GO

INSERT INTO dbo.Transactions (TransactionID, UserID, Amount, TransactionDate)
SELECT 
    number,
    (number % 10000) + 1,
    (number % 10000) + 10.50,
    DATEADD(MINUTE, -(number % 525600), GETDATE())
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 50000;
GO

-- ============================================================================
-- 1. VARCHAR vs NVARCHAR Implicit Conversion
-- ============================================================================

-- BAD: NVARCHAR literal on VARCHAR column
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM dbo.Users 
WHERE Username = N'user5000';  -- N prefix = NVARCHAR
-- Check execution plan: Yellow warning icon for implicit conversion
-- Index scan instead of seek due to CONVERT_IMPLICIT on Username column
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- GOOD: Matching VARCHAR literal
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM dbo.Users 
WHERE Username = 'user5000';  -- No N prefix = VARCHAR
-- Index seek, no conversion warning
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- View execution plans side by side to see the difference

-- ============================================================================
-- 2. Numeric Type Conversion
-- ============================================================================

-- Create table with specific numeric types
IF OBJECT_ID('dbo.ProductPrices', 'U') IS NOT NULL
    DROP TABLE dbo.ProductPrices;
GO

CREATE TABLE dbo.ProductPrices (
    ProductID INT NOT NULL PRIMARY KEY,
    Price DECIMAL(10, 2) NOT NULL,
    Quantity SMALLINT NOT NULL
);
GO

CREATE NONCLUSTERED INDEX IX_ProductPrices_Price ON dbo.ProductPrices(Price);
GO

INSERT INTO dbo.ProductPrices (ProductID, Price, Quantity)
SELECT 
    number,
    (number % 1000) + 0.99,
    (number % 100)
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 10000;
GO

-- BAD: Comparing INT column with FLOAT literal
SET STATISTICS IO ON;

SELECT * FROM dbo.ProductPrices
WHERE ProductID = 5000.0;  -- Implicit conversion (minor impact here)
GO

-- GOOD: Matching type
SELECT * FROM dbo.ProductPrices
WHERE ProductID = 5000;
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 3. INT vs BIGINT in JOINs
-- ============================================================================

SET STATISTICS IO ON;

-- JOIN with type mismatch (UserID is INT, TransactionID is BIGINT)
SELECT U.Username, T.Amount, T.TransactionDate
FROM dbo.Users U
INNER JOIN dbo.Transactions T ON U.UserID = T.TransactionID;  -- Wrong join!
-- Check plan: Implicit conversion on U.UserID (INT → BIGINT)
GO

-- Correct JOIN (matching columns)
SELECT U.Username, T.Amount, T.TransactionDate
FROM dbo.Users U
INNER JOIN dbo.Transactions T ON U.UserID = T.UserID;  -- Correct columns
-- No implicit conversion
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 4. Date/Time Conversions
-- ============================================================================

-- BAD: Function on column
SET STATISTICS IO ON;

SELECT * FROM dbo.Users
WHERE CONVERT(DATE, CreatedDate) = '2025-06-01';
-- Index scan: Cannot use index on CreatedDate due to function
GO

-- GOOD: Sargable range
SELECT * FROM dbo.Users
WHERE CreatedDate >= '2025-06-01' 
  AND CreatedDate < '2025-06-02';
-- Index seek possible
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 5. Detecting Implicit Conversions in Execution Plans
-- ============================================================================

-- Enable actual execution plan (Ctrl+M)
-- Run this query and examine the plan

SELECT * FROM dbo.Users WHERE Username = N'user1000';
GO

-- In the execution plan:
-- 1. Look for yellow warning triangle
-- 2. Hover over Index Scan operator
-- 3. Look for "CONVERT_IMPLICIT" in tooltip
-- 4. Warning text: "Type conversion in expression (CONVERT_IMPLICIT(nvarchar(50),[PerformanceDemo].[dbo].[Users].[Username],0)=[@1]) may affect 'CardinalityEstimate' in query plan choice"

-- ============================================================================
-- 6. Using DMVs to Find Conversion Issues
-- ============================================================================

-- Find queries with CONVERT_IMPLICIT in cached plans
SELECT 
    qs.execution_count,
    qs.total_worker_time / qs.execution_count AS avg_cpu_time,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qp.query_plan LIKE '%CONVERT_IMPLICIT%'
  AND qt.text NOT LIKE '%sys.dm_exec_query_stats%'  -- Exclude this query
ORDER BY qs.total_worker_time DESC;
GO

-- ============================================================================
-- 7. Parameter Sniffing with Implicit Conversion
-- ============================================================================

CREATE OR ALTER PROCEDURE dbo.GetUserByUsername
    @Username NVARCHAR(50)  -- NVARCHAR parameter
AS
BEGIN
    SELECT * FROM dbo.Users 
    WHERE Username = @Username;  -- Implicit conversion on column!
END
GO

-- Execute procedure
EXEC dbo.GetUserByUsername @Username = 'user5000';
-- Check plan: CONVERT_IMPLICIT on Username column
GO

-- FIX: Match parameter type to column type
CREATE OR ALTER PROCEDURE dbo.GetUserByUsername_Fixed
    @Username VARCHAR(50)  -- VARCHAR to match table
AS
BEGIN
    SELECT * FROM dbo.Users 
    WHERE Username = @Username;
END
GO

EXEC dbo.GetUserByUsername_Fixed @Username = 'user5000';
-- No conversion needed
GO

-- ============================================================================
-- 8. Explicit Conversion (Move to Non-Indexed Side)
-- ============================================================================

-- If types MUST differ, convert the parameter/literal, not the column

-- BAD: Convert column
SELECT * FROM dbo.Users
WHERE CAST(Username AS NVARCHAR(50)) = N'user5000';
-- Index cannot be used
GO

-- BETTER: Convert parameter (in procedure)
CREATE OR ALTER PROCEDURE dbo.GetUserByUsername_Convert
    @Username NVARCHAR(50)
AS
BEGIN
    DECLARE @UsernameVarchar VARCHAR(50) = CAST(@Username AS VARCHAR(50));
    
    SELECT * FROM dbo.Users 
    WHERE Username = @UsernameVarchar;
END
GO

EXEC dbo.GetUserByUsername_Convert @Username = N'user5000';
-- Conversion happens once on parameter, index can be used
GO

-- ============================================================================
-- 9. Collation Conflicts
-- ============================================================================

-- Create table with different collation
IF OBJECT_ID('dbo.UsersLatinCollation', 'U') IS NOT NULL
    DROP TABLE dbo.UsersLatinCollation;
GO

CREATE TABLE dbo.UsersLatinCollation (
    UserID INT NOT NULL PRIMARY KEY,
    Username VARCHAR(50) COLLATE Latin1_General_CI_AS NOT NULL
);
GO

INSERT INTO dbo.UsersLatinCollation (UserID, Username)
SELECT TOP 1000 UserID, Username FROM dbo.Users;
GO

-- JOIN with collation mismatch
-- (Assuming dbo.Users has different default collation)
SELECT U1.Username, U2.Username
FROM dbo.Users U1
INNER JOIN dbo.UsersLatinCollation U2 ON U1.Username = U2.Username;
-- May see collation conversion in plan
GO

-- FIX: Specify collation explicitly
SELECT U1.Username, U2.Username
FROM dbo.Users U1
INNER JOIN dbo.UsersLatinCollation U2 
    ON U1.Username COLLATE Latin1_General_CI_AS = U2.Username;
GO

-- ============================================================================
-- 10. Best Practices Summary
-- ============================================================================

-- Create a summary table of common conversion scenarios
CREATE TABLE #ConversionImpact (
    Scenario VARCHAR(100),
    Problem VARCHAR(200),
    Solution VARCHAR(200)
);

INSERT INTO #ConversionImpact VALUES
('VARCHAR vs NVARCHAR', 'N prefix on VARCHAR column', 'Remove N prefix or change column to NVARCHAR'),
('INT vs BIGINT JOIN', 'Mismatched numeric types in JOIN', 'Ensure columns have matching types'),
('Function on column', 'CONVERT/CAST on indexed column', 'Move conversion to parameter side'),
('Date filtering', 'CONVERT(DATE, column) in WHERE', 'Use range predicates (>= AND <)'),
('Parameter type mismatch', 'Proc parameter type ≠ column type', 'Match parameter type to column'),
('Collation mismatch', 'Different collations in JOIN', 'Explicit COLLATE clause'),
('Numeric precision', 'DECIMAL vs FLOAT comparison', 'Ensure consistent numeric types');

SELECT * FROM #ConversionImpact;
GO

DROP TABLE #ConversionImpact;
GO

-- ============================================================================
-- 11. Performance Impact Measurement
-- ============================================================================

-- Compare performance with and without conversion

-- Clear buffer cache for accurate measurement (use cautiously in production!)
-- DBCC DROPCLEANBUFFERS;
-- DBCC FREEPROCCACHE;
-- GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== WITH IMPLICIT CONVERSION ===';
SELECT COUNT(*) 
FROM dbo.Users 
WHERE Username = N'user5000';
GO

PRINT '=== WITHOUT IMPLICIT CONVERSION ===';
SELECT COUNT(*) 
FROM dbo.Users 
WHERE Username = 'user5000';
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP PROCEDURE dbo.GetUserByUsername;
-- DROP PROCEDURE dbo.GetUserByUsername_Fixed;
-- DROP PROCEDURE dbo.GetUserByUsername_Convert;
-- DROP TABLE dbo.Users;
-- DROP TABLE dbo.Transactions;
-- DROP TABLE dbo.ProductPrices;
-- DROP TABLE dbo.UsersLatinCollation;
-- GO
