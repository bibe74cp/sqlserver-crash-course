/*
================================================================================
Demo 3: Index Types
Topics: Clustered, Nonclustered, Covering, INCLUDE clause, Filtered Indexes
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create base table
-- ============================================================================

IF OBJECT_ID('dbo.Products', 'U') IS NOT NULL
    DROP TABLE dbo.Products;
GO

CREATE TABLE dbo.Products (
    ProductID INT NOT NULL,
    ProductName VARCHAR(100) NOT NULL,
    CategoryID INT NOT NULL,
    Price DECIMAL(10, 2) NOT NULL,
    StockQuantity INT NOT NULL,
    IsActive BIT NOT NULL,
    CreatedDate DATETIME NOT NULL,
    LastModifiedDate DATETIME NULL,
    SupplierID INT NOT NULL,
    Description VARCHAR(500) NULL
);
GO

-- Insert sample data (20,000 products)
INSERT INTO dbo.Products (ProductID, ProductName, CategoryID, Price, StockQuantity, IsActive, CreatedDate, LastModifiedDate, SupplierID, Description)
SELECT 
    value AS ProductID,
    'Product ' + CAST(value AS VARCHAR(10)) AS ProductName,
    (value % 50) + 1 AS CategoryID,
    (value % 1000) + 9.99 AS Price,
    (value % 500) AS StockQuantity,
    CASE WHEN value % 10 = 0 THEN 0 ELSE 1 END AS IsActive,  -- 10% inactive
    DATEADD(DAY, -(value % 365), GETDATE()) AS CreatedDate,
    CASE WHEN value % 5 = 0 THEN DATEADD(DAY, -10, GETDATE()) ELSE NULL END AS LastModifiedDate,
    (value % 100) + 1 AS SupplierID,
    'Description for product ' + CAST(value AS VARCHAR(10)) AS Description
FROM GENERATE_SERIES(1, 20000);
GO

-- ============================================================================
-- 1. CLUSTERED INDEX
-- ============================================================================

-- Add clustered index (determines physical order)
ALTER TABLE dbo.Products
ADD CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductID);
GO

-- Query benefits from clustered index
SET STATISTICS IO ON;

SELECT * FROM dbo.Products WHERE ProductID = 10000;
-- Result: Clustered Index Seek (very efficient)

SELECT * FROM dbo.Products WHERE ProductID BETWEEN 5000 AND 5100;
-- Result: Clustered Index Seek with range scan

SET STATISTICS IO OFF;
GO

-- View clustered index details
SELECT 
    i.name AS IndexName,
    i.type_desc,
    i.is_unique,
    i.is_primary_key,
    COL_NAME(ic.object_id, ic.column_id) AS ColumnName,
    ic.key_ordinal
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE i.object_id = OBJECT_ID('dbo.Products')
  AND i.type_desc = 'CLUSTERED';
GO

-- ============================================================================
-- 2. NONCLUSTERED INDEX (Basic)
-- ============================================================================

-- Create nonclustered index on frequently queried column
CREATE NONCLUSTERED INDEX IX_Products_CategoryID
ON dbo.Products(CategoryID);
GO

DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
GO


SET STATISTICS IO ON;

-- Query uses nonclustered index
SELECT ProductID, CategoryID, ProductName
FROM dbo.Products 
WHERE CategoryID = 25;
-- Result: Index Seek on IX_Products_CategoryID
-- Note: Key Lookup not needed because ProductID is in clustered key

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 3. COVERING INDEX (Without INCLUDE)
-- ============================================================================

-- Create covering index by including all needed columns in key
CREATE NONCLUSTERED INDEX IX_Products_Category_Price_Name
ON dbo.Products(CategoryID, Price, ProductName);
GO

DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
GO

SET STATISTICS IO ON;

-- Query fully covered by index (no Key Lookup)
SELECT CategoryID, Price, ProductName
FROM dbo.Products
--WHERE CategoryID = 25 AND Price < 100;
WHERE CategoryID BETWEEN 25 AND 30 AND Price < 100;
-- Result: Index Seek only, no Key Lookup!

SET STATISTICS IO OFF;
GO

-- Problem with this approach: Key is wide (includes ProductName)
SELECT 
    i.name AS IndexName,
    SUM(ps.used_page_count) * 8 AS IndexSizeKB
FROM sys.indexes i
INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID('dbo.Products')
  AND i.name = 'IX_Products_Category_Price_Name'
GROUP BY i.name;
GO

-- ============================================================================
-- 4. COVERING INDEX WITH INCLUDE CLAUSE (Best Practice)
-- ============================================================================

-- Create optimized covering index
CREATE NONCLUSTERED INDEX IX_Products_Category_Price_INCLUDE
ON dbo.Products(CategoryID, Price)
INCLUDE (ProductName, StockQuantity);
GO

DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
GO

SET STATISTICS IO ON;

-- Query fully covered, smaller index
SELECT CategoryID, Price, ProductName, StockQuantity
FROM dbo.Products
WHERE CategoryID = 25 AND Price < 100;
-- Result: Index Seek only, no Key Lookup, but index is smaller!

SET STATISTICS IO OFF;
GO

-- Compare index sizes
SELECT 
    i.name AS IndexName,
    i.type_desc,
    SUM(ps.used_page_count) * 8 AS IndexSizeKB,
    SUM(ps.row_count) AS [RowCount]
FROM sys.indexes i
INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID('dbo.Products')
  AND i.name IN ('IX_Products_Category_Price_Name', 'IX_Products_Category_Price_INCLUDE')
GROUP BY i.name, i.type_desc;
GO

-- View index columns
SELECT 
    i.name AS IndexName,
    COL_NAME(ic.object_id, ic.column_id) AS ColumnName,
    ic.is_included_column,
    ic.key_ordinal
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE i.object_id = OBJECT_ID('dbo.Products')
  AND i.name IN ('IX_Products_Category_Price_Name', 'IX_Products_Category_Price_INCLUDE')
ORDER BY i.NAME, ic.key_ordinal, ic.is_included_column;
GO

-- ============================================================================
-- 5. FILTERED INDEX
-- ============================================================================

-- Scenario: Most queries only search active products
-- Create filtered index for active products only

CREATE NONCLUSTERED INDEX IX_Products_Active_Category
ON dbo.Products(CategoryID, Price)
INCLUDE (ProductName, StockQuantity)
WHERE IsActive = 1;  -- Filter condition
GO

SET STATISTICS IO ON;

-- Query on active products (uses filtered index)
SELECT TOP (10) CategoryID, Price, ProductName, StockQuantity
FROM dbo.Products
WHERE CategoryID = 25 AND IsActive = 1
ORDER BY CategoryID, Price;
-- Result: Uses IX_Products_Active_Category (smaller, more selective)

-- Query on inactive products (cannot use filtered index)
SELECT TOP (10) CategoryID, Price, ProductName, StockQuantity
FROM dbo.Products
WHERE CategoryID = 25 AND IsActive = 0
ORDER BY CategoryID, Price;
-- Result: Uses different index or scan

SET STATISTICS IO OFF;
GO

-- Compare filtered vs non-filtered index size
SELECT 
    i.name AS IndexName,
    i.has_filter,
    i.filter_definition,
    SUM(ps.used_page_count) * 8 AS IndexSizeKB,
    SUM(ps.row_count) AS [RowCount]
FROM sys.indexes i
INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.object_id = OBJECT_ID('dbo.Products')
  AND i.name IN ('IX_Products_Category_Price_INCLUDE', 'IX_Products_Active_Category')
GROUP BY i.name, i.has_filter, i.filter_definition;
GO

-- ============================================================================
-- 6. FILTERED INDEX - Additional Scenarios
-- ============================================================================

-- Filtered index for sparse column (LastModifiedDate is NULL for 80% of rows)
CREATE NONCLUSTERED INDEX IX_Products_RecentlyModified
ON dbo.Products(LastModifiedDate, ProductID)
WHERE LastModifiedDate IS NOT NULL;
GO

-- Query recent changes
SELECT TOP (10) ProductID, ProductName, LastModifiedDate
FROM dbo.Products
WHERE LastModifiedDate > DATEADD(DAY, -30, GETDATE())
ORDER BY LastModifiedDate;
-- Uses filtered index (much smaller than full index)
GO

-- Filtered index for specific category (hot partition)
CREATE NONCLUSTERED INDEX IX_Products_Category1
ON dbo.Products(ProductID, Price)
INCLUDE (ProductName)
WHERE CategoryID = 1;
GO

-- ============================================================================
-- 7. COMPOSITE INDEX - Column Order Matters
-- ============================================================================

-- Create index with different column orders
CREATE NONCLUSTERED INDEX IX_Products_Cat_Supplier
ON dbo.Products(CategoryID, SupplierID);
GO

CREATE NONCLUSTERED INDEX IX_Products_Supplier_Cat
ON dbo.Products(SupplierID, CategoryID);
GO

SET STATISTICS IO ON;

-- Query 1: Benefits from IX_Products_Cat_Supplier
SELECT ProductID, ProductName
FROM dbo.Products
WHERE CategoryID = 25;
-- Uses IX_Products_Cat_Supplier (first column matches)

-- Query 2: Benefits from IX_Products_Supplier_Cat
SELECT ProductID, ProductName
FROM dbo.Products
WHERE SupplierID = 50;
-- Uses IX_Products_Supplier_Cat (first column matches)

-- Query 3: Benefits from either (both columns in WHERE)
SELECT ProductID, ProductName
FROM dbo.Products
WHERE CategoryID = 25 AND SupplierID = 50;
-- Can use either index effectively

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 8. INDEX USAGE STATISTICS
-- ============================================================================

-- View index usage stats
SELECT 
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    s.last_user_seek,
    s.last_user_scan
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID()
  AND OBJECT_NAME(s.object_id) = 'Products'
ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC;
GO

-- ============================================================================
-- 9. MISSING INDEX RECOMMENDATIONS
-- ============================================================================

-- Run a query without a good index
SELECT ProductName, Price, StockQuantity
FROM dbo.Products
WHERE Price > 500 AND Price < 1000
ORDER BY CreatedDate DESC;
-- Check execution plan for missing index suggestion
GO

-- View missing index recommendations
SELECT 
    d.statement AS TableName,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    s.avg_user_impact,
    s.user_seeks,
    s.user_scans
FROM sys.dm_db_missing_index_details d
INNER JOIN sys.dm_db_missing_index_groups g ON d.index_handle = g.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats s ON g.index_group_handle = s.group_handle
WHERE d.database_id = DB_ID()
  AND d.statement LIKE '%Products%';
GO

-- ============================================================================
-- 10. INDEX BEST PRACTICES DEMONSTRATION
-- ============================================================================

-- Good: Narrow clustered index (INT)
-- Bad example would be: GUID, wide composite key

-- Good: Filtered index for subset
-- Already demonstrated above

-- Good: INCLUDE for covering without wide key
-- Already demonstrated above

-- Show all indexes on table
EXEC sp_helpindex 'dbo.Products';
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP TABLE dbo.Products;
-- GO
