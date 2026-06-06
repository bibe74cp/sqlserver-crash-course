/*
================================================================================
Demo 2: Execution Plans
Topics: Reading plans, interpreting operators, optimization strategies
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables for execution plan demos
-- ============================================================================

IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL
    DROP TABLE dbo.Customers;
GO

IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL
    DROP TABLE dbo.Orders;
GO

-- Create Customers table
CREATE TABLE dbo.Customers (
    CustomerID INT NOT NULL PRIMARY KEY CLUSTERED,
    CustomerName VARCHAR(100) NOT NULL,
    Region VARCHAR(50) NOT NULL,
    Status VARCHAR(20) NOT NULL
);
GO

-- Create Orders table
CREATE TABLE dbo.Orders (
    OrderID INT NOT NULL PRIMARY KEY CLUSTERED,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Status VARCHAR(20) NOT NULL
);
GO

-- Insert sample customers (1,000 customers)
INSERT INTO dbo.Customers (CustomerID, CustomerName, Region, Status)
SELECT 
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    'Customer ' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VARCHAR(10)),
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 5)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        WHEN 3 THEN 'West'
        ELSE 'Central'
    END,
    CASE (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 10)
        WHEN 0 THEN 'Inactive'
        ELSE 'Active'
    END
FROM master.dbo.spt_values
WHERE type = 'P' AND number < 1000;
GO

-- Insert sample orders (50,000 orders)
DECLARE @i INT = 1;
WHILE @i <= 50000
BEGIN
    INSERT INTO dbo.Orders (OrderID, CustomerID, OrderDate, Amount, Status)
    VALUES (
        @i,
        (@i % 1000) + 1,
        DATEADD(DAY, -(@i % 730), GETDATE()),  -- Last 2 years
        (@i % 500) + 25.00,
        CASE (@i % 20) 
            WHEN 0 THEN 'Cancelled'
            WHEN 1 THEN 'Pending'
            ELSE 'Completed'
        END
    );
    SET @i = @i + 1;
END
GO

-- ============================================================================
-- 1. TABLE SCAN vs INDEX SEEK
-- ============================================================================

-- Enable actual execution plan (Ctrl+M in SSMS)
-- Or use: SET SHOWPLAN_XML ON;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- TABLE SCAN: No WHERE clause
SELECT * FROM dbo.Orders;
-- Look for: Clustered Index Scan operator
GO

-- INDEX SEEK: Specific value
SELECT * FROM dbo.Orders WHERE OrderID = 25000;
-- Look for: Clustered Index Seek operator
GO

-- SCAN: Range that returns many rows
SELECT * FROM dbo.Orders WHERE OrderID BETWEEN 1 AND 40000;
-- Look for: Clustered Index Scan (optimizer chose scan over seek)
GO

-- SEEK: Range with few rows
SELECT * FROM dbo.Orders WHERE OrderID BETWEEN 1 AND 100;
-- Look for: Clustered Index Seek
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- ============================================================================
-- 2. KEY LOOKUP (RID Lookup for heaps)
-- ============================================================================

-- Create nonclustered index (not covering)
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID 
ON dbo.Orders(CustomerID);
GO

SET STATISTICS IO ON;

-- Query uses nonclustered index but needs additional columns
-- Result: Index Seek + Key Lookup
SELECT OrderID, CustomerID, OrderDate, Amount
FROM dbo.Orders
WHERE CustomerID = 500;
-- Look for: Index Seek on IX_Orders_CustomerID + Key Lookup + Nested Loop Join
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 3. JOIN OPERATORS
-- ============================================================================

SET STATISTICS IO ON;

-- NESTED LOOP JOIN: Small outer, seeks on inner
SELECT C.CustomerName, O.OrderDate, O.Amount
FROM dbo.Customers C
INNER JOIN dbo.Orders O ON C.CustomerID = O.CustomerID
WHERE C.CustomerID IN (1, 2, 3);  -- Very few customers
-- Look for: Nested Loops operator
GO

-- HASH MATCH JOIN: Large datasets without good indexes
SELECT C.CustomerName, O.OrderDate, O.Amount
FROM dbo.Customers C
INNER JOIN dbo.Orders O ON C.Region = O.Status;  -- No index on join columns
-- Look for: Hash Match operator
GO

-- Create index to enable MERGE JOIN
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Sorted 
ON dbo.Orders(CustomerID, OrderDate);
GO

-- MERGE JOIN: Both inputs sorted
SELECT C.CustomerID, C.CustomerName, O.OrderDate, O.Amount
FROM dbo.Customers C
INNER JOIN dbo.Orders O ON C.CustomerID = O.CustomerID
ORDER BY C.CustomerID;
-- Look for: Merge Join operator (both inputs sorted)
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 4. SORT OPERATOR (Expensive)
-- ============================================================================

SET STATISTICS IO ON;

-- Query requires sort (no supporting index)
SELECT * 
FROM dbo.Orders
WHERE Status = 'Completed'
ORDER BY OrderDate DESC;
-- Look for: Sort operator (expensive!)
GO

-- Create index to eliminate sort
CREATE NONCLUSTERED INDEX IX_Orders_Status_OrderDate 
ON dbo.Orders(Status, OrderDate DESC);
GO

-- Same query, no sort needed
SELECT OrderID, CustomerID, OrderDate, Amount, Status
FROM dbo.Orders
WHERE Status = 'Completed'
ORDER BY OrderDate DESC;
-- Look for: Index Seek, no Sort operator
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 5. MISSING INDEX HINT
-- ============================================================================

-- Query that could benefit from an index
SELECT OrderDate, Amount
FROM dbo.Orders
WHERE Status = 'Pending' AND OrderDate > '2025-01-01';
-- Look for: Green text in execution plan suggesting missing index
GO

-- The missing index hint might suggest something like:
-- CREATE NONCLUSTERED INDEX IX_Suggested
-- ON dbo.Orders(Status, OrderDate)
-- INCLUDE (Amount);

-- ============================================================================
-- 6. PARALLELISM
-- ============================================================================

-- Large query that uses parallelism
SELECT 
    CustomerID,
    COUNT(*) AS OrderCount,
    SUM(Amount) AS TotalAmount,
    AVG(Amount) AS AvgAmount
FROM dbo.Orders
GROUP BY CustomerID;
-- Look for: Parallelism operators (arrows splitting into multiple streams)
GO

-- Disable parallelism for comparison
SELECT 
    CustomerID,
    COUNT(*) AS OrderCount,
    SUM(Amount) AS TotalAmount,
    AVG(Amount) AS AvgAmount
FROM dbo.Orders
GROUP BY CustomerID
OPTION (MAXDOP 1);
-- Compare execution time and plan
GO

-- ============================================================================
-- 7. ACTUAL vs ESTIMATED ROWS (Statistics issue)
-- ============================================================================

-- Insert skewed data
INSERT INTO dbo.Orders (OrderID, CustomerID, OrderDate, Amount, Status)
SELECT 
    50000 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    1,  -- All orders for customer 1
    DATEADD(DAY, -number, GETDATE()),
    100.00,
    'VIPOrder'
FROM master.dbo.spt_values
WHERE type = 'P' AND number < 5000;
GO

-- Query without updated statistics
SELECT * FROM dbo.Orders WHERE CustomerID = 1;
-- Compare Actual vs Estimated rows in execution plan
-- Large difference indicates stale statistics
GO

-- Update statistics
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
GO

-- Query again
SELECT * FROM dbo.Orders WHERE CustomerID = 1;
-- Actual and Estimated should now be closer
GO

-- ============================================================================
-- 8. SPOOL OPERATORS (Table Spool, Index Spool)
-- ============================================================================

-- Query that might use a spool
SELECT DISTINCT C.Region, O.Status
FROM dbo.Customers C
CROSS JOIN dbo.Orders O
WHERE C.Status = 'Active';
-- Look for: Table Spool or Index Spool operators
GO

-- ============================================================================
-- 9. WARNINGS IN EXECUTION PLAN
-- ============================================================================

-- Create table with VARCHAR column
IF OBJECT_ID('dbo.ProductCodes', 'U') IS NOT NULL
    DROP TABLE dbo.ProductCodes;
GO

CREATE TABLE dbo.ProductCodes (
    ProductID INT NOT NULL PRIMARY KEY,
    ProductCode VARCHAR(20) NOT NULL
);
GO

CREATE NONCLUSTERED INDEX IX_ProductCodes_Code 
ON dbo.ProductCodes(ProductCode);
GO

INSERT INTO dbo.ProductCodes (ProductID, ProductCode)
SELECT number, 'PROD' + RIGHT('00000' + CAST(number AS VARCHAR), 5)
FROM master.dbo.spt_values
WHERE type = 'P' AND number < 10000;
GO

-- Query with implicit conversion (NVARCHAR literal on VARCHAR column)
SET STATISTICS IO ON;

SELECT * FROM dbo.ProductCodes 
WHERE ProductCode = N'PROD00100';  -- N prefix causes implicit conversion
-- Look for: Yellow warning icon indicating type conversion
GO

-- Corrected query (no implicit conversion)
SELECT * FROM dbo.ProductCodes 
WHERE ProductCode = 'PROD00100';  -- No N prefix
-- No warning, index can be used efficiently
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 10. QUERY OPTIMIZATION COMPARISON
-- ============================================================================

PRINT '========== BEFORE OPTIMIZATION ==========';
-- Bad query: Function in WHERE, SELECT *
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * 
FROM dbo.Orders
WHERE YEAR(OrderDate) = 2025;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT '========== AFTER OPTIMIZATION ==========';
-- Good query: Sargable predicate, specific columns
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT OrderID, CustomerID, OrderDate, Amount, Status
FROM dbo.Orders
WHERE OrderDate >= '2025-01-01' AND OrderDate < '2026-01-01';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP TABLE dbo.Customers;
-- DROP TABLE dbo.Orders;
-- DROP TABLE dbo.ProductCodes;
-- GO
