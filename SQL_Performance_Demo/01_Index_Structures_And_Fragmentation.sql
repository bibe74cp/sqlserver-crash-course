/*
================================================================================
Demo 1: Index Structures and Fragmentation
Topics: Heap, B+-Tree, Fragmentation, Rebuild vs. Reorganize
================================================================================
*/

USE master;
GO

-- Create demo database if it doesn't exist
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'PerformanceDemo')
BEGIN
    CREATE DATABASE PerformanceDemo;
END
GO

USE PerformanceDemo;
GO

-- ============================================================================
-- 1. HEAP TABLE (No Clustered Index)
-- ============================================================================

-- Drop if exists
IF OBJECT_ID('dbo.OrdersHeap', 'U') IS NOT NULL
    DROP TABLE dbo.OrdersHeap;
GO

-- Create heap table
CREATE TABLE dbo.OrdersHeap (
    OrderID INT NOT NULL,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Status VARCHAR(20) NOT NULL
);
GO

-- Insert sample data (10,000 rows)
DECLARE @i INT = 1;
WHILE @i <= 10000
BEGIN
    INSERT INTO dbo.OrdersHeap (OrderID, CustomerID, OrderDate, Amount, Status)
    VALUES (
        @i,
        (@i % 1000) + 1,
        DATEADD(DAY, -(@i % 365), GETDATE()),
        (@i % 1000) + 50.00,
        CASE (@i % 10) 
            WHEN 0 THEN 'Cancelled'
            WHEN 1 THEN 'Pending'
            ELSE 'Completed'
        END
    );
    SET @i = @i + 1;
END
GO

-- Query heap table (requires Table Scan)
SET STATISTICS IO ON;
SELECT * FROM dbo.OrdersHeap WHERE OrderID = 5000;
SET STATISTICS IO OFF;
GO

-- View heap structure
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    index_id,
    index_type_desc,
    page_count,
    record_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.OrdersHeap'), NULL, NULL, 'DETAILED');
GO

-- ============================================================================
-- 2. B+-TREE CLUSTERED INDEX
-- ============================================================================

-- Drop if exists
IF OBJECT_ID('dbo.OrdersClustered', 'U') IS NOT NULL
    DROP TABLE dbo.OrdersClustered;
GO

-- Create table with clustered index
CREATE TABLE dbo.OrdersClustered (
    OrderID INT NOT NULL PRIMARY KEY CLUSTERED,  -- Creates B+-Tree
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Status VARCHAR(20) NOT NULL
);
GO

-- Insert same data
DECLARE @i INT = 1;
WHILE @i <= 10000
BEGIN
    INSERT INTO dbo.OrdersClustered (OrderID, CustomerID, OrderDate, Amount, Status)
    VALUES (
        @i,
        (@i % 1000) + 1,
        DATEADD(DAY, -(@i % 365), GETDATE()),
        (@i % 1000) + 50.00,
        CASE (@i % 10) 
            WHEN 0 THEN 'Cancelled'
            WHEN 1 THEN 'Pending'
            ELSE 'Completed'
        END
    );
    SET @i = @i + 1;
END
GO

-- Query with clustered index (Index Seek)
SET STATISTICS IO ON;
SELECT * FROM dbo.OrdersClustered WHERE OrderID = 5000;
SET STATISTICS IO OFF;
GO

-- View B+-Tree structure
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    index_id,
    index_type_desc,
    index_depth,  -- B+-Tree depth
    index_level,
    page_count,
    record_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.OrdersClustered'), NULL, NULL, 'DETAILED');
GO

-- ============================================================================
-- 3. INDEX FRAGMENTATION DEMONSTRATION
-- ============================================================================

-- Drop if exists
IF OBJECT_ID('dbo.FragmentationDemo', 'U') IS NOT NULL
    DROP TABLE dbo.FragmentationDemo;
GO

-- Create table for fragmentation demo
CREATE TABLE dbo.FragmentationDemo (
    ID INT NOT NULL PRIMARY KEY CLUSTERED,
    DataColumn CHAR(2000) NOT NULL
);
GO

-- Insert sequential data (no fragmentation initially)
INSERT INTO dbo.FragmentationDemo (ID, DataColumn)
SELECT 
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) * 2,  -- Even numbers only
    REPLICATE('A', 2000)
FROM master.dbo.spt_values
WHERE type = 'P' AND number < 5000;
GO

-- Check initial fragmentation (should be low)
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent,
    ips.page_count,
    ips.fragment_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.FragmentationDemo'), NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0;
GO

-- Cause fragmentation by inserting in the middle (odd numbers)
INSERT INTO dbo.FragmentationDemo (ID, DataColumn)
SELECT 
    (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) * 2) - 1,  -- Odd numbers
    REPLICATE('B', 2000)
FROM master.dbo.spt_values
WHERE type = 'P' AND number < 5000;
GO

-- Check fragmentation after inserts (should be high)
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent,
    ips.page_count,
    ips.fragment_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.FragmentationDemo'), NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0;
GO

-- ============================================================================
-- 4. REBUILD vs. REORGANIZE
-- ============================================================================

-- REORGANIZE (online operation, minimal locking)
ALTER INDEX PK__Fragment__3214EC271234ABCD ON dbo.FragmentationDemo REORGANIZE;
GO

-- Or use system-generated name
ALTER INDEX ALL ON dbo.FragmentationDemo REORGANIZE;
GO

-- Check fragmentation after REORGANIZE
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.FragmentationDemo'), NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0;
GO

-- Re-fragment the index
UPDATE dbo.FragmentationDemo 
SET DataColumn = REPLICATE('C', 2000)
WHERE ID % 3 = 0;
GO

-- REBUILD (offline by default, or online with Enterprise Edition)
ALTER INDEX ALL ON dbo.FragmentationDemo REBUILD;
GO

-- REBUILD with options (Enterprise Edition)
-- ALTER INDEX ALL ON dbo.FragmentationDemo REBUILD WITH (ONLINE = ON);
GO

-- Check fragmentation after REBUILD (should be near 0%)
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.FragmentationDemo'), NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0;
GO

-- ============================================================================
-- 5. MAINTENANCE SCRIPT: Automated Rebuild/Reorganize Decision
-- ============================================================================

DECLARE @TableName NVARCHAR(256);
DECLARE @IndexName NVARCHAR(256);
DECLARE @Fragmentation FLOAT;
DECLARE @SQL NVARCHAR(MAX);

DECLARE index_cursor CURSOR FOR
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
  AND ips.page_count > 100
  AND i.name IS NOT NULL;

OPEN index_cursor;

FETCH NEXT FROM index_cursor INTO @TableName, @IndexName, @Fragmentation;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @Fragmentation >= 30
    BEGIN
        -- REBUILD for high fragmentation
        SET @SQL = N'ALTER INDEX ' + QUOTENAME(@IndexName) + N' ON ' + QUOTENAME(@TableName) + N' REBUILD;';
        PRINT 'Rebuilding: ' + @SQL;
        -- EXEC sp_executesql @SQL;  -- Uncomment to execute
    END
    ELSE IF @Fragmentation >= 10
    BEGIN
        -- REORGANIZE for moderate fragmentation
        SET @SQL = N'ALTER INDEX ' + QUOTENAME(@IndexName) + N' ON ' + QUOTENAME(@TableName) + N' REORGANIZE;';
        PRINT 'Reorganizing: ' + @SQL;
        -- EXEC sp_executesql @SQL;  -- Uncomment to execute
    END

    FETCH NEXT FROM index_cursor INTO @TableName, @IndexName, @Fragmentation;
END

CLOSE index_cursor;
DEALLOCATE index_cursor;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP TABLE dbo.OrdersHeap;
-- DROP TABLE dbo.OrdersClustered;
-- DROP TABLE dbo.FragmentationDemo;
-- GO
