/*
================================================================================
Demo 9: Parameter Sniffing
Topics: Detection, impact, and various solutions
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables for parameter sniffing demonstration
-- ============================================================================

IF OBJECT_ID('dbo.OrdersForSniffing', 'U') IS NOT NULL
    DROP TABLE dbo.OrdersForSniffing;
GO

CREATE TABLE dbo.OrdersForSniffing (
    OrderID INT NOT NULL PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    Region VARCHAR(50) NOT NULL
);
GO

-- Insert data with SKEWED distribution
-- Most orders are 'Completed' (45,000)
-- Few orders are 'Pending' (1,000)
-- Very few are 'Cancelled' (100)

-- Completed orders (45,000)
WITH Numbers
AS (
    SELECT ROW_NUMBER() OVER (ORDER BY v1.value, v2.value) AS number
    FROM GENERATE_SERIES(1, 150) v1
    CROSS APPLY GENERATE_SERIES(1, 300) v2
)
INSERT INTO dbo.OrdersForSniffing (OrderID, CustomerID, OrderDate, Amount, Status, Region)
SELECT 
    number,
    (number % 5000) + 1,
    DATEADD(DAY, -(number % 730), GETDATE()),
    (number % 1000) + 100.00,
    'Completed',
    CASE (number % 4)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END
FROM Numbers;
GO

-- Pending orders (1,000)
INSERT INTO dbo.OrdersForSniffing (OrderID, CustomerID, OrderDate, Amount, Status, Region)
SELECT 
    50000 + value,
    (value % 5000) + 1,
    DATEADD(DAY, -(value % 30), GETDATE()),
    (value % 500) + 50.00,
    'Pending',
    CASE (value % 4)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END
FROM GENERATE_SERIES(1, 1000);
GO

-- Cancelled orders (100)
INSERT INTO dbo.OrdersForSniffing (OrderID, CustomerID, OrderDate, Amount, Status, Region)
SELECT 
    60000 + value,
    (value % 5000) + 1,
    DATEADD(DAY, -(value % 365), GETDATE()),
    (value % 200) + 25.00,
    'Cancelled',
    CASE (value % 4)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END
FROM GENERATE_SERIES(1, 100);
GO

-- Create indexes
CREATE NONCLUSTERED INDEX IX_Orders_Status 
    ON dbo.OrdersForSniffing(Status) 
    INCLUDE (OrderDate, Amount);

CREATE NONCLUSTERED INDEX IX_Orders_Region 
    ON dbo.OrdersForSniffing(Region) 
    INCLUDE (OrderDate, Amount);
GO

-- Update statistics
UPDATE STATISTICS dbo.OrdersForSniffing WITH FULLSCAN;
GO

-- Verify data distribution
SELECT Status, COUNT(*) AS OrderCount
FROM dbo.OrdersForSniffing
GROUP BY Status
ORDER BY OrderCount DESC;
GO

-- ============================================================================
-- 1. DEMONSTRATE PARAMETER SNIFFING PROBLEM
-- ============================================================================

PRINT '========== PARAMETER SNIFFING DEMONSTRATION ==========';
GO

-- Create stored procedure without any hints
CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status;
END
GO

-- Scenario 1: First execution with 'Cancelled' (100 rows)
PRINT '=== First execution: Cancelled (100 rows) ===';
DBCC FREEPROCCACHE;  -- Clear plan cache
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

EXEC dbo.GetOrdersByStatus @Status = 'Cancelled';
-- Plan optimized for small dataset (Index Seek + Key Lookup likely)
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Scenario 2: Second execution with 'Completed' (45,000 rows) - USES SAME PLAN
PRINT '=== Second execution: Completed (45,000 rows) - SAME PLAN ===';

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

EXEC dbo.GetOrdersByStatus @Status = 'Completed';
-- Uses cached plan from 'Cancelled', which is inefficient for 45,000 rows!
-- Index Seek + 45,000 Key Lookups = SLOW
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Now reverse the order to see opposite problem
PRINT '=== Reverse scenario: Start with Completed ===';
DBCC FREEPROCCACHE;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

EXEC dbo.GetOrdersByStatus @Status = 'Completed';
-- Plan optimized for large dataset (Index Scan likely)
GO

PRINT '=== Now execute with Cancelled - SAME PLAN ===';
EXEC dbo.GetOrdersByStatus @Status = 'Cancelled';
-- Uses plan optimized for 45,000 rows on 100 rows = suboptimal
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 2. SOLUTION 1: OPTIMIZE FOR Hint
-- ============================================================================

PRINT '========== SOLUTION 1: OPTIMIZE FOR ==========';
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_OptimizeFor
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status
    OPTION (OPTIMIZE FOR (@Status = 'Completed'));  -- Optimize for most common value
END
GO

DBCC FREEPROCCACHE;
GO

SET STATISTICS IO ON;

-- Always uses plan optimized for 'Completed' regardless of actual parameter
EXEC dbo.GetOrdersByStatus_OptimizeFor @Status = 'Completed';  -- Good
EXEC dbo.GetOrdersByStatus_OptimizeFor @Status = 'Cancelled';  -- Acceptable trade-off
EXEC dbo.GetOrdersByStatus_OptimizeFor @Status = 'Pending';    -- Acceptable

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 3. SOLUTION 2: OPTIMIZE FOR UNKNOWN
-- ============================================================================

PRINT '========== SOLUTION 2: OPTIMIZE FOR UNKNOWN ==========';
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_OptimizeForUnknown
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status
    OPTION (OPTIMIZE FOR UNKNOWN);  -- Use average density
END
GO

DBCC FREEPROCCACHE;
GO

SET STATISTICS IO ON;

-- Creates "generic" plan based on statistics
EXEC dbo.GetOrdersByStatus_OptimizeForUnknown @Status = 'Completed';
EXEC dbo.GetOrdersByStatus_OptimizeForUnknown @Status = 'Cancelled';
EXEC dbo.GetOrdersByStatus_OptimizeForUnknown @Status = 'Pending';
-- Same plan for all, compromise performance

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 4. SOLUTION 3: RECOMPILE (Procedure Level)
-- ============================================================================

PRINT '========== SOLUTION 3: RECOMPILE (Procedure) ==========';
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_Recompile
    @Status VARCHAR(20)
WITH RECOMPILE  -- Recompile every execution
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status;
END
GO

SET STATISTICS IO ON;

-- Each execution gets fresh plan optimized for actual parameter
EXEC dbo.GetOrdersByStatus_Recompile @Status = 'Cancelled';   -- Optimal plan for 100 rows
EXEC dbo.GetOrdersByStatus_Recompile @Status = 'Completed';   -- Optimal plan for 45,000 rows
-- Cost: Compilation overhead every time

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 5. SOLUTION 4: RECOMPILE (Query Level)
-- ============================================================================

PRINT '========== SOLUTION 4: RECOMPILE (Query) ==========';
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_QueryRecompile
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Only this query recompiles, not entire procedure
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status
    OPTION (RECOMPILE);
    
    -- Other queries in procedure could use cached plans
END
GO

SET STATISTICS IO ON;

EXEC dbo.GetOrdersByStatus_QueryRecompile @Status = 'Cancelled';
EXEC dbo.GetOrdersByStatus_QueryRecompile @Status = 'Completed';

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 6. SOLUTION 5: Local Variable Copy
-- ============================================================================

PRINT '========== SOLUTION 5: Local Variable ==========';
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_LocalVar
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StatusLocal VARCHAR(20) = @Status;
    
    -- Local variable prevents parameter sniffing
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @StatusLocal;
    -- Uses average density from statistics (like OPTIMIZE FOR UNKNOWN)
END
GO

DBCC FREEPROCCACHE;
GO

SET STATISTICS IO ON;

EXEC dbo.GetOrdersByStatus_LocalVar @Status = 'Cancelled';
EXEC dbo.GetOrdersByStatus_LocalVar @Status = 'Completed';
-- Generic plan, predictable performance

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 7. SOLUTION 6: Dynamic SQL
-- ============================================================================

PRINT '========== SOLUTION 6: Dynamic SQL ==========';
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_DynamicSQL
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT OrderID, CustomerID, OrderDate, Amount, Status
        FROM dbo.OrdersForSniffing
        WHERE Status = @Status';
    
    -- Each execution gets parameter sniffing
    EXEC sp_executesql @SQL, N'@Status VARCHAR(20)', @Status = @Status;
END
GO

SET STATISTICS IO ON;

EXEC dbo.GetOrdersByStatus_DynamicSQL @Status = 'Cancelled';   -- Optimal plan
EXEC dbo.GetOrdersByStatus_DynamicSQL @Status = 'Completed';   -- Optimal plan
-- Each gets fresh plan, but creates plan cache bloat

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 8. SOLUTION 7: Multiple Procedures (Branch Logic)
-- ============================================================================

PRINT '========== SOLUTION 7: Branch Logic ==========';
GO

-- Create separate procedures for different scenarios
CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_SmallSet
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status
    OPTION (RECOMPILE);  -- Always optimal for small sets
END
GO

CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_LargeSet
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status;
    -- Cached plan for large sets
END
GO

-- Wrapper procedure with branch logic
CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_Branching
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Route based on expected result size
    IF @Status IN ('Cancelled', 'Pending')
    BEGIN
        EXEC dbo.GetOrdersByStatus_SmallSet @Status = @Status;
    END
    ELSE
    BEGIN
        EXEC dbo.GetOrdersByStatus_LargeSet @Status = @Status;
    END
END
GO

EXEC dbo.GetOrdersByStatus_Branching @Status = 'Cancelled';   -- Uses SmallSet procedure
EXEC dbo.GetOrdersByStatus_Branching @Status = 'Completed';   -- Uses LargeSet procedure
GO

-- ============================================================================
-- 9. SQL SERVER 2022: Parameter Sensitive Plan (PSP) Optimization
-- ============================================================================

PRINT '========== SQL SERVER 2022: Parameter Sensitive Plans ==========';
GO

-- Check if PSP is enabled (SQL Server 2022+, compatibility level 160)
SELECT name, compatibility_level
FROM sys.databases
WHERE database_id = DB_ID();
GO

-- Enable PSP for database (SQL Server 2022+)
-- ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
GO

-- Create procedure without hints (let PSP handle it)
CREATE OR ALTER PROCEDURE dbo.GetOrdersByStatus_PSP
    @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT OrderID, CustomerID, OrderDate, Amount, Status
    FROM dbo.OrdersForSniffing
    WHERE Status = @Status;
    -- SQL Server 2022 can automatically detect parameter sensitivity
    -- and create multiple plans for different parameter ranges
END
GO

-- SQL Server 2022 will detect the parameter sensitivity and create
-- multiple plans automatically (if enabled and supported)

-- ============================================================================
-- 10. DETECTION: Finding Parameter Sniffing Issues
-- ============================================================================

PRINT '========== DETECTING PARAMETER SNIFFING ==========';
GO

-- Check for plan variation with same procedure
SELECT 
    qs.execution_count,
    qs.min_elapsed_time / 1000.0 AS min_elapsed_ms,
    qs.max_elapsed_time / 1000.0 AS max_elapsed_ms,
    qs.last_elapsed_time / 1000.0 AS last_elapsed_ms,
    qs.total_logical_reads,
    qs.last_logical_reads,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.text LIKE '%OrdersForSniffing%'
  AND qt.text NOT LIKE '%sys.dm_exec%'
ORDER BY qs.max_elapsed_time - qs.min_elapsed_time DESC;
GO

-- Check cached plans
SELECT 
    cp.objtype,
    cp.cacheobjtype,
    cp.usecounts,
    cp.size_in_bytes,
    OBJECT_NAME(st.objectid) AS ProcedureName,
    st.text
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE st.text LIKE '%GetOrdersByStatus%'
  AND st.text NOT LIKE '%sys.dm_exec%';
GO

-- ============================================================================
-- 11. PERFORMANCE COMPARISON SUMMARY
-- ============================================================================

PRINT '========== PERFORMANCE COMPARISON ==========';
GO

-- Clear plan cache for fair comparison
DBCC FREEPROCCACHE;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '--- No Optimization (Parameter Sniffing) ---';
EXEC dbo.GetOrdersByStatus @Status = 'Completed';
EXEC dbo.GetOrdersByStatus @Status = 'Cancelled';  -- Suffers from sniffing

PRINT '--- OPTIMIZE FOR ---';
EXEC dbo.GetOrdersByStatus_OptimizeFor @Status = 'Completed';
EXEC dbo.GetOrdersByStatus_OptimizeFor @Status = 'Cancelled';

PRINT '--- OPTIMIZE FOR UNKNOWN ---';
EXEC dbo.GetOrdersByStatus_OptimizeForUnknown @Status = 'Completed';
EXEC dbo.GetOrdersByStatus_OptimizeForUnknown @Status = 'Cancelled';

PRINT '--- RECOMPILE ---';
EXEC dbo.GetOrdersByStatus_Recompile @Status = 'Completed';
EXEC dbo.GetOrdersByStatus_Recompile @Status = 'Cancelled';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 12. DECISION MATRIX
-- ============================================================================

CREATE TABLE #ParameterSniffingSolutions (
    Solution VARCHAR(50),
    CPUOverhead VARCHAR(20),
    PlanCacheImpact VARCHAR(30),
    Performance VARCHAR(30),
    WhenToUse VARCHAR(200)
);

INSERT INTO #ParameterSniffingSolutions VALUES
('OPTIMIZE FOR value', 'Low', 'One plan', 'Good for dominant value', 'When one parameter value is used 90%+ of time'),
('OPTIMIZE FOR UNKNOWN', 'Low', 'One plan', 'Compromised', 'Evenly distributed parameter values'),
('RECOMPILE (proc)', 'High', 'No caching', 'Optimal each time', 'Infrequently called, high parameter sensitivity'),
('RECOMPILE (query)', 'Medium', 'Partial caching', 'Optimal for query', 'Only one query in proc is parameter-sensitive'),
('Local variable', 'Low', 'One plan', 'Compromised', 'Simple solution, acceptable compromise'),
('Dynamic SQL', 'Medium', 'Many plans', 'Optimal but bloat', 'Complex scenarios, careful with injection'),
('Branch logic', 'Low', 'Multiple plans', 'Optimal by branch', 'Clear delineation between scenarios'),
('PSP (SQL 2022+)', 'Low', 'Multiple plans', 'Automatic optimal', 'SQL Server 2022+, compatibility level 160+');

SELECT * FROM #ParameterSniffingSolutions;
DROP TABLE #ParameterSniffingSolutions;
GO

-- ============================================================================
-- 13. BEST PRACTICES
-- ============================================================================

PRINT '========== BEST PRACTICES ==========';
GO

/*
1. Monitor for parameter sniffing issues:
   - Large variance in execution times
   - Different logical reads for same procedure
   - User complaints about intermittent slowness

2. Choose solution based on scenario:
   - OPTIMIZE FOR: One dominant value (90%+)
   - OPTIMIZE FOR UNKNOWN: Even distribution
   - RECOMPILE: High sensitivity, low frequency
   - PSP: SQL Server 2022+ with compatibility level 160

3. Avoid premature optimization:
   - Test with realistic data distributions
   - Measure before and after
   - Monitor plan cache size

4. Keep statistics updated:
   - Regular UPDATE STATISTICS
   - AUTO_UPDATE_STATISTICS enabled
   - Consider AUTO_CREATE_STATISTICS

5. Document decisions:
   - Why specific hint was chosen
   - Expected data distribution
   - Review periodically
*/

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
/*
DROP PROCEDURE dbo.GetOrdersByStatus;
DROP PROCEDURE dbo.GetOrdersByStatus_OptimizeFor;
DROP PROCEDURE dbo.GetOrdersByStatus_OptimizeForUnknown;
DROP PROCEDURE dbo.GetOrdersByStatus_Recompile;
DROP PROCEDURE dbo.GetOrdersByStatus_QueryRecompile;
DROP PROCEDURE dbo.GetOrdersByStatus_LocalVar;
DROP PROCEDURE dbo.GetOrdersByStatus_DynamicSQL;
DROP PROCEDURE dbo.GetOrdersByStatus_SmallSet;
DROP PROCEDURE dbo.GetOrdersByStatus_LargeSet;
DROP PROCEDURE dbo.GetOrdersByStatus_Branching;
DROP PROCEDURE dbo.GetOrdersByStatus_PSP;
DROP TABLE dbo.OrdersForSniffing;
GO
*/
