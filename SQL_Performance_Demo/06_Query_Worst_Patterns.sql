/*
================================================================================
Demo 6: Query Worst Patterns
Topics: Anti-patterns that kill performance
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables for anti-pattern demonstrations
-- ============================================================================

IF OBJECT_ID('dbo.OrdersForPatterns', 'U') IS NOT NULL
    DROP TABLE dbo.OrdersForPatterns;
GO

IF OBJECT_ID('dbo.CustomersForPatterns', 'U') IS NOT NULL
    DROP TABLE dbo.CustomersForPatterns;
GO

CREATE TABLE dbo.CustomersForPatterns (
    CustomerID INT NOT NULL PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(100) NOT NULL,
    City VARCHAR(50) NOT NULL,
    State VARCHAR(2) NOT NULL,
    ZipCode VARCHAR(10) NOT NULL
);
GO

CREATE TABLE dbo.OrdersForPatterns (
    OrderID INT NOT NULL PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    ShipDate DATETIME NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    ProductName VARCHAR(100) NOT NULL
);
GO

-- Insert sample data
INSERT INTO dbo.CustomersForPatterns (CustomerID, CustomerName, LastName, Email, City, State, ZipCode)
SELECT 
    number,
    'Customer' + CAST(number AS VARCHAR(10)),
    'Smith' + CAST(number % 100 AS VARCHAR(10)),
    'customer' + CAST(number AS VARCHAR(10)) + '@example.com',
    CASE (number % 10)
        WHEN 0 THEN 'New York'
        WHEN 1 THEN 'Los Angeles'
        WHEN 2 THEN 'Chicago'
        WHEN 3 THEN 'Houston'
        WHEN 4 THEN 'Phoenix'
        WHEN 5 THEN 'Philadelphia'
        WHEN 6 THEN 'San Antonio'
        WHEN 7 THEN 'San Diego'
        WHEN 8 THEN 'Dallas'
        ELSE 'San Jose'
    END,
    'CA',
    RIGHT('00000' + CAST(number AS VARCHAR), 5)
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 5000;
GO

INSERT INTO dbo.OrdersForPatterns (OrderID, CustomerID, OrderDate, ShipDate, Amount, Status, ProductName)
SELECT 
    number,
    (number % 5000) + 1,
    DATEADD(DAY, -(number % 1095), GETDATE()),
    DATEADD(DAY, -(number % 1095) + (number % 5), GETDATE()),
    (number % 1000) + 50.00,
    CASE (number % 10) 
        WHEN 0 THEN 'Cancelled'
        WHEN 1 THEN 'Pending'
        ELSE 'Completed'
    END,
    'Product ' + CAST((number % 500) + 1 AS VARCHAR(10))
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 50000;
GO

-- Create indexes
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON dbo.OrdersForPatterns(OrderDate);
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON dbo.OrdersForPatterns(CustomerID);
CREATE NONCLUSTERED INDEX IX_Customers_LastName ON dbo.CustomersForPatterns(LastName);
GO

-- ============================================================================
-- ANTI-PATTERN 1: Functions on Columns in WHERE Clause
-- ============================================================================

PRINT '========== ANTI-PATTERN 1: Functions on Columns ==========';
GO

-- BAD: YEAR() function prevents index usage
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT OrderID, CustomerID, OrderDate, Amount
FROM dbo.OrdersForPatterns
WHERE YEAR(OrderDate) = 2025;
-- Result: Index Scan (entire index scanned)
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- GOOD: Sargable predicate
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT OrderID, CustomerID, OrderDate, Amount
FROM dbo.OrdersForPatterns
WHERE OrderDate >= '2025-01-01' AND OrderDate < '2026-01-01';
-- Result: Index Seek (efficient range scan)
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Other common function anti-patterns:

-- BAD: UPPER/LOWER on string columns
SELECT * FROM dbo.CustomersForPatterns
WHERE UPPER(LastName) = 'SMITH0';
-- Index cannot be used
GO

-- GOOD: Use case-insensitive collation or match case
SELECT * FROM dbo.CustomersForPatterns
WHERE LastName = 'Smith0';
GO

-- BAD: SUBSTRING, LEFT, RIGHT
SELECT * FROM dbo.CustomersForPatterns
WHERE LEFT(ZipCode, 3) = '123';
-- Index scan
GO

-- GOOD: Use LIKE with trailing wildcard
SELECT * FROM dbo.CustomersForPatterns
WHERE ZipCode LIKE '123%';
-- Index seek possible
GO

-- BAD: ISNULL/COALESCE on indexed column
SELECT * FROM dbo.OrdersForPatterns
WHERE ISNULL(ShipDate, '1900-01-01') > '2025-01-01';
-- Index scan
GO

-- GOOD: Handle NULL explicitly
SELECT * FROM dbo.OrdersForPatterns
WHERE ShipDate > '2025-01-01' OR ShipDate IS NULL;
-- Index can be used
GO

-- ============================================================================
-- ANTI-PATTERN 2: Leading Wildcards in LIKE
-- ============================================================================

PRINT '========== ANTI-PATTERN 2: Leading Wildcards ==========';
GO

SET STATISTICS IO ON;

-- BAD: Leading wildcard
SELECT * FROM dbo.CustomersForPatterns
WHERE CustomerName LIKE '%Customer100%';
-- Table/Index scan required
GO

-- BAD: Leading wildcard at start
SELECT * FROM dbo.CustomersForPatterns
WHERE LastName LIKE '%Smith';
-- Table/Index scan
GO

-- GOOD: Trailing wildcard only
SELECT * FROM dbo.CustomersForPatterns
WHERE LastName LIKE 'Smith%';
-- Index seek possible
GO

SET STATISTICS IO OFF;
GO

-- Alternative: Full-text search for contains queries
-- CREATE FULLTEXT INDEX for better performance on contains searches

-- ============================================================================
-- ANTI-PATTERN 3: OR with Different Columns
-- ============================================================================

PRINT '========== ANTI-PATTERN 3: OR Across Columns ==========';
GO

SET STATISTICS IO ON;

-- BAD: OR across different columns
SELECT * FROM dbo.OrdersForPatterns
WHERE CustomerID = 100 OR Status = 'Pending';
-- Cannot efficiently use indexes on both columns
GO

-- GOOD: UNION ALL (if appropriate)
SELECT * FROM dbo.OrdersForPatterns WHERE CustomerID = 100
UNION ALL
SELECT * FROM dbo.OrdersForPatterns WHERE Status = 'Pending' AND CustomerID <> 100;
-- Each part can use appropriate index
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- ANTI-PATTERN 4: RBAR (Row-By-Agonizing-Row) with Cursors
-- ============================================================================

PRINT '========== ANTI-PATTERN 4: RBAR with Cursors ==========';
GO

-- BAD: Cursor processing
SET STATISTICS TIME ON;

DECLARE @CustomerID INT;
DECLARE @TotalAmount DECIMAL(10, 2);

CREATE TABLE #CustomerTotals (
    CustomerID INT,
    TotalAmount DECIMAL(10, 2)
);

DECLARE customer_cursor CURSOR FOR
SELECT DISTINCT CustomerID FROM dbo.OrdersForPatterns;

OPEN customer_cursor;
FETCH NEXT FROM customer_cursor INTO @CustomerID;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @TotalAmount = SUM(Amount)
    FROM dbo.OrdersForPatterns
    WHERE CustomerID = @CustomerID;
    
    INSERT INTO #CustomerTotals (CustomerID, TotalAmount)
    VALUES (@CustomerID, @TotalAmount);
    
    FETCH NEXT FROM customer_cursor INTO @CustomerID;
END

CLOSE customer_cursor;
DEALLOCATE customer_cursor;

SELECT * FROM #CustomerTotals;
DROP TABLE #CustomerTotals;
GO

SET STATISTICS TIME OFF;
GO

-- GOOD: Set-based operation
SET STATISTICS TIME ON;

SELECT 
    CustomerID,
    SUM(Amount) AS TotalAmount
FROM dbo.OrdersForPatterns
GROUP BY CustomerID;
-- Much faster!
GO

SET STATISTICS TIME OFF;
GO

-- ============================================================================
-- ANTI-PATTERN 5: SELECT *
-- ============================================================================

PRINT '========== ANTI-PATTERN 5: SELECT * ==========';
GO

SET STATISTICS IO ON;

-- BAD: SELECT * retrieves unnecessary columns
SELECT * FROM dbo.OrdersForPatterns
WHERE CustomerID = 100;
-- Larger I/O, prevents covering indexes
GO

-- GOOD: Select only needed columns
SELECT OrderID, OrderDate, Amount
FROM dbo.OrdersForPatterns
WHERE CustomerID = 100;
-- Less I/O, can use covering index
GO

SET STATISTICS IO OFF;
GO

-- Create covering index to demonstrate
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Covering
ON dbo.OrdersForPatterns(CustomerID)
INCLUDE (OrderID, OrderDate, Amount);
GO

SET STATISTICS IO ON;

-- Now this query is fully covered
SELECT OrderID, OrderDate, Amount
FROM dbo.OrdersForPatterns
WHERE CustomerID = 100;
-- Index seek only, no key lookup!
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- ANTI-PATTERN 6: NOT IN with NULLs
-- ============================================================================

PRINT '========== ANTI-PATTERN 6: NOT IN with NULLs ==========';
GO

-- Add some NULL ShipDates
UPDATE TOP (100) dbo.OrdersForPatterns
SET ShipDate = NULL;
GO

-- BAD: NOT IN with potential NULLs
SET STATISTICS IO ON;

SELECT CustomerID, CustomerName
FROM dbo.CustomersForPatterns
WHERE CustomerID NOT IN (
    SELECT CustomerID FROM dbo.OrdersForPatterns WHERE ShipDate IS NULL
);
-- If subquery returns any NULL, entire result is empty!
GO

-- GOOD: NOT EXISTS
SELECT CustomerID, CustomerName
FROM dbo.CustomersForPatterns C
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.OrdersForPatterns O 
    WHERE O.CustomerID = C.CustomerID 
      AND O.ShipDate IS NULL
);
-- Handles NULLs correctly
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- ANTI-PATTERN 7: Correlated Subqueries in SELECT
-- ============================================================================

PRINT '========== ANTI-PATTERN 7: Correlated Subqueries ==========';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- BAD: Scalar subquery in SELECT (runs for each row)
SELECT 
    C.CustomerID,
    C.CustomerName,
    (SELECT COUNT(*) 
     FROM dbo.OrdersForPatterns O 
     WHERE O.CustomerID = C.CustomerID) AS OrderCount,
    (SELECT SUM(Amount) 
     FROM dbo.OrdersForPatterns O 
     WHERE O.CustomerID = C.CustomerID) AS TotalAmount
FROM dbo.CustomersForPatterns C;
-- Subqueries execute once per customer row
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- GOOD: JOIN with aggregation
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    C.CustomerID,
    C.CustomerName,
    COUNT(O.OrderID) AS OrderCount,
    SUM(O.Amount) AS TotalAmount
FROM dbo.CustomersForPatterns C
LEFT JOIN dbo.OrdersForPatterns O ON C.CustomerID = O.CustomerID
GROUP BY C.CustomerID, C.CustomerName;
-- Single pass, much more efficient
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- ANTI-PATTERN 8: Multiple COUNT DISTINCT
-- ============================================================================

PRINT '========== ANTI-PATTERN 8: Multiple COUNT DISTINCT ==========';
GO

-- BAD: Multiple COUNT DISTINCT in same query
SELECT 
    CustomerID,
    COUNT(DISTINCT ProductName) AS DistinctProducts,
    COUNT(DISTINCT CAST(OrderDate AS DATE)) AS DistinctOrderDates
FROM dbo.OrdersForPatterns
GROUP BY CustomerID;
-- Can be slow with large datasets
GO

-- BETTER: Separate aggregations with CROSS APPLY or subqueries
SELECT 
    CustomerID,
    Products.DistinctCount AS DistinctProducts,
    OrderDates.DistinctCount AS DistinctOrderDates
FROM dbo.OrdersForPatterns O
CROSS APPLY (
    SELECT COUNT(DISTINCT ProductName) AS DistinctCount
    FROM dbo.OrdersForPatterns
    WHERE CustomerID = O.CustomerID
) Products
CROSS APPLY (
    SELECT COUNT(DISTINCT CAST(OrderDate AS DATE)) AS DistinctCount
    FROM dbo.OrdersForPatterns
    WHERE CustomerID = O.CustomerID
) OrderDates
GROUP BY CustomerID, Products.DistinctCount, OrderDates.DistinctCount;
GO

-- ============================================================================
-- ANTI-PATTERN 9: Implicit Conversions (covered in Demo 5)
-- ============================================================================

-- See Demo 5 for detailed examples

-- ============================================================================
-- ANTI-PATTERN 10: Using Hints Unnecessarily
-- ============================================================================

PRINT '========== ANTI-PATTERN 10: Overusing Hints ==========';
GO

-- BAD: Forcing index when optimizer knows better
SELECT OrderID, CustomerID, Amount
FROM dbo.OrdersForPatterns WITH (INDEX(IX_Orders_OrderDate))
WHERE CustomerID = 100;
-- Forcing wrong index
GO

-- GOOD: Let optimizer choose
SELECT OrderID, CustomerID, Amount
FROM dbo.OrdersForPatterns
WHERE CustomerID = 100;
-- Optimizer uses IX_Orders_CustomerID
GO

-- BAD: NOLOCK everywhere (dirty reads)
SELECT * FROM dbo.OrdersForPatterns WITH (NOLOCK)
WHERE Status = 'Completed';
-- Can return inconsistent data
GO

-- GOOD: Use appropriate isolation level
-- Or use READ COMMITTED SNAPSHOT ISOLATION at database level
SELECT * FROM dbo.OrdersForPatterns
WHERE Status = 'Completed';
GO

-- ============================================================================
-- ANTI-PATTERN 11: Unnecessary DISTINCT
-- ============================================================================

PRINT '========== ANTI-PATTERN 11: Unnecessary DISTINCT ==========';
GO

SET STATISTICS IO ON;

-- BAD: DISTINCT when not needed (already unique by PK)
SELECT DISTINCT OrderID, Amount
FROM dbo.OrdersForPatterns
WHERE CustomerID = 100;
-- Adds sort/distinct operation unnecessarily
GO

-- GOOD: Remove DISTINCT when guaranteed unique
SELECT OrderID, Amount
FROM dbo.OrdersForPatterns
WHERE CustomerID = 100;
-- No extra sorting
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- ANTI-PATTERN 12: Updating in Loops
-- ============================================================================

PRINT '========== ANTI-PATTERN 12: Row-by-Row Updates ==========';
GO

-- BAD: Update in loop
DECLARE @OrderID INT;
DECLARE update_cursor CURSOR FOR
SELECT OrderID FROM dbo.OrdersForPatterns WHERE Status = 'Pending';

OPEN update_cursor;
FETCH NEXT FROM update_cursor INTO @OrderID;

WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE dbo.OrdersForPatterns
    SET Status = 'Processing'
    WHERE OrderID = @OrderID;
    
    FETCH NEXT FROM update_cursor INTO @OrderID;
END

CLOSE update_cursor;
DEALLOCATE update_cursor;
-- Many individual updates, heavy transaction log
GO

-- GOOD: Set-based update
UPDATE dbo.OrdersForPatterns
SET Status = 'Processing'
WHERE Status = 'Pending';
-- Single operation, minimal logging (in simple recovery mode)
GO

-- ============================================================================
-- Summary Table of Anti-Patterns
-- ============================================================================

CREATE TABLE #AntiPatterns (
    AntiPattern VARCHAR(100),
    Problem VARCHAR(200),
    Solution VARCHAR(200)
);

INSERT INTO #AntiPatterns VALUES
('Functions in WHERE', 'Prevents index usage, scans entire table', 'Rewrite as sargable predicates'),
('Leading wildcards', 'Cannot use index for string searches', 'Use trailing wildcards or full-text search'),
('OR across columns', 'Cannot efficiently use multiple indexes', 'Use UNION ALL if appropriate'),
('RBAR/Cursors', 'Row-by-row processing is slow', 'Use set-based operations'),
('SELECT *', 'Retrieves unnecessary columns, prevents covering indexes', 'Select only needed columns'),
('NOT IN with NULLs', 'Returns incorrect results with NULLs', 'Use NOT EXISTS instead'),
('Correlated subqueries', 'Execute once per row', 'Use JOINs or window functions'),
('Forcing wrong hints', 'Prevents optimizer from choosing best plan', 'Remove hints, let optimizer work'),
('NOLOCK everywhere', 'Dirty reads, inconsistent data', 'Use appropriate isolation level'),
('Unnecessary DISTINCT', 'Adds sorting overhead', 'Remove if data already unique'),
('Row-by-row updates', 'Heavy logging, many transactions', 'Use set-based UPDATE'),
('Multiple COUNT DISTINCT', 'Can be slow with large data', 'Consider separate queries or window functions');

SELECT * FROM #AntiPatterns;
DROP TABLE #AntiPatterns;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP TABLE dbo.OrdersForPatterns;
-- DROP TABLE dbo.CustomersForPatterns;
-- GO
