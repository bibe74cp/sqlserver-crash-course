/*
================================================================================
Demo 10: Parameter Sensitive Plan (PSP) Optimization
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables for parameter sniffing demonstration
-- ============================================================================

IF OBJECT_ID('dbo.UsersForSniffing', 'U') IS NOT NULL
    DROP TABLE dbo.UsersForSniffing;
GO

CREATE TABLE dbo.UsersForSniffing (
    ID INT,
    FirstName NVARCHAR(100),
    LastName NVARCHAR(100),
    City NVARCHAR(100),
    HotelName NVARCHAR(100),
    CheckInDate DATE
);
GO

-- Insert data with SKEWED distribution
-- Most users visit Agra (898,999)
-- Less users visit Udaipur (100,000)
-- Few users visit Jaipur (1,000)
-- Very few visit New Delhi (1)
WITH Numbers AS (
    SELECT TOP (1000000) 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowID
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.UsersForSniffing(ID, FirstName, LastName, City, HotelName, CheckInDate)
SELECT 
    RowID,
    'Rahul',
    CASE WHEN RowID % 2 = 1 THEN 'Sharma' ELSE 'Pandey' END,
    CASE 
        WHEN RowID % 10 = 1 THEN 'Udaipur'
        WHEN RowID % 1000 = 5 THEN 'Jaipur'
        WHEN RowID % 1000000 = 3 THEN 'New Delhi'
        ELSE 'Agra'
    END,
    CASE WHEN RowID % 2 = 1 THEN 'Oberoi' ELSE 'Taj' END,
    DATEADD(DAY, -1 * (RowID % 100), CAST(GETDATE() AS DATE))

FROM Numbers;
GO

CREATE INDEX IX_City ON dbo.UsersForSniffing(City);
GO

SELECT City AS TravelDestination, COUNT(*) AS NoOfVisitors
FROM dbo.UsersForSniffing 
GROUP BY City
ORDER BY NoOfVisitors;
GO

CREATE OR ALTER PROCEDURE dbo.UserDestination (
    @City NVARCHAR(100)
)
AS
BEGIN

    SELECT TOP 1000 * FROM dbo.UsersForSniffing WHERE City = @City
    ORDER BY ID;
    -- SQL Server 2022 can automatically detect parameter sensitivity
    -- and create multiple plans for different parameter ranges

END;
GO

DBCC FREEPROCCACHE
GO

SET STATISTICS IO, TIME ON
GO

ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 130  -- SQL 2016
GO

EXEC dbo.UserDestination 'New Delhi';  -- 1 Row(s)
EXEC dbo.UserDestination 'Jaipur';   -- 1000 Row(s)
EXEC dbo.UserDestination 'Udaipur'; -- 100000 Row(s)
EXEC dbo.UserDestination 'Agra'; -- 898999 Row(s)
GO

DBCC FREEPROCCACHE
GO

EXEC dbo.UserDestination 'Agra'; -- 898999 Row(s)
EXEC dbo.UserDestination 'New Delhi';  -- 1 Row(s)
EXEC dbo.UserDestination 'Jaipur';   -- 1000 Row(s)
EXEC dbo.UserDestination 'Udaipur'; -- 100000 Row(s)
GO

DBCC FREEPROCCACHE
GO

ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160  -- SQL 2022
--ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 170  -- SQL 2025
GO

-- Check if PSP is enabled (SQL Server 2022+, compatibility level 160+)
SELECT name, compatibility_level
FROM sys.databases
WHERE database_id = DB_ID();
GO

SELECT
    name,
    value,
    value_for_secondary
FROM sys.database_scoped_configurations
WHERE name = 'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION';
GO

-- Enable PSP for database (SQL Server 2022+)
-- ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
GO

-- SQL Server 2022 will detect the parameter sensitivity and create
-- multiple plans automatically (if enabled and supported)

EXEC dbo.UserDestination 'New Delhi';  -- 1 Row(s)
EXEC dbo.UserDestination 'Jaipur';   -- 1000 Row(s)
EXEC dbo.UserDestination 'Udaipur'; -- 100000 Row(s)
EXEC dbo.UserDestination 'Agra'; -- 898999 Row(s)
GO
