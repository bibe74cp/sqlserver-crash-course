/*
================================================================================
Demo 7: Query Best Patterns
Topics: Optimized query patterns and techniques
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables for best pattern demonstrations
-- ============================================================================

IF OBJECT_ID('dbo.OrdersBestPractice', 'U') IS NOT NULL
    DROP TABLE dbo.OrdersBestPractice;
GO

IF OBJECT_ID('dbo.CustomersBestPractice', 'U') IS NOT NULL
    DROP TABLE dbo.CustomersBestPractice;
GO

IF OBJECT_ID('dbo.OrderDetailsBestPractice', 'U') IS NOT NULL
    DROP TABLE dbo.OrderDetailsBestPractice;
GO

CREATE TABLE dbo.CustomersBestPractice (
    CustomerID INT NOT NULL PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    Region VARCHAR(50) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    SignupDate DATE NOT NULL
);
GO

CREATE TABLE dbo.OrdersBestPractice (
    OrderID INT NOT NULL PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL,
    Status VARCHAR(20) NOT NULL
);
GO

CREATE TABLE dbo.OrderDetailsBestPractice (
    OrderDetailID INT NOT NULL PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10, 2) NOT NULL
);
GO

-- Insert sample data
INSERT INTO dbo.CustomersBestPractice (CustomerID, CustomerName, Region, Status, SignupDate)
SELECT 
    number,
    'Customer ' + CAST(number AS VARCHAR(10)),
    CASE (number % 5)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        WHEN 3 THEN 'West'
        ELSE 'Central'
    END,
    CASE WHEN number % 10 = 0 THEN 'Inactive' ELSE 'Active' END,
    DATEADD(DAY, -(number % 1095), GETDATE())
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 5000;
GO

INSERT INTO dbo.OrdersBestPractice (OrderID, CustomerID, OrderDate, Amount, Status)
SELECT 
    number,
    (number % 5000) + 1,
    DATEADD(DAY, -(number % 730), GETDATE()),
    (number % 1000) + 100.00,
    CASE (number % 10) 
        WHEN 0 THEN 'Cancelled'
        WHEN 1 THEN 'Pending'
        ELSE 'Completed'
    END
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 50000;
GO

INSERT INTO dbo.OrderDetailsBestPractice (OrderDetailID, OrderID, ProductID, Quantity, UnitPrice)
SELECT 
    number,
    (number % 50000) + 1,
    (number % 1000) + 1,
    (number % 10) + 1,
    (number % 100) + 9.99
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 100000;
GO

-- Create indexes
CREATE NONCLUSTERED INDEX IX_Customers_Status_Region 
    ON dbo.CustomersBestPractice(Status, Region) 
    INCLUDE (CustomerName);

CREATE NONCLUSTERED INDEX IX_Orders_CustomerID_Date 
    ON dbo.OrdersBestPractice(CustomerID, OrderDate) 
    INCLUDE (Amount, Status);

CREATE NONCLUSTERED INDEX IX_Orders_Date_Status 
    ON dbo.OrdersBestPractice(OrderDate, Status);

CREATE NONCLUSTERED INDEX IX_OrderDetails_OrderID 
    ON dbo.OrderDetailsBestPractice(OrderID) 
    INCLUDE (Quantity, UnitPrice);
GO

-- ============================================================================
-- BEST PATTERN 1: Filter Early and Often
-- ============================================================================

PRINT '========== BEST PATTERN 1: Filter Early ==========';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- GOOD: Filter before joining
SELECT 
    C.CustomerName,
    O.OrderDate,
    O.Amount
FROM dbo.CustomersBestPractice C
INNER JOIN dbo.OrdersBestPractice O ON C.CustomerID = O.CustomerID
WHERE C.Status = 'Active'
  AND O.OrderDate >= '2025-01-01'
  AND O.Status = 'Completed';
-- Filters applied early, reduces join size
GO

-- EVEN BETTER: Filter in subquery/CTE when very selective
WITH ActiveCustomers AS (
    SELECT CustomerID, CustomerName, Region
    FROM dbo.CustomersBestPractice
    WHERE Status = 'Active' AND Region = 'North'  -- Very selective filter
),
RecentOrders AS (
    SELECT CustomerID, OrderDate, Amount
    FROM dbo.OrdersBestPractice
    WHERE OrderDate >= '2025-01-01' AND Status = 'Completed'
)
SELECT 
    AC.CustomerName,
    RO.OrderDate,
    RO.Amount
FROM ActiveCustomers AC
INNER JOIN RecentOrders RO ON AC.CustomerID = RO.CustomerID;
-- Each dataset reduced before join
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- BEST PATTERN 2: Use EXISTS Instead of IN for Subqueries
-- ============================================================================

PRINT '========== BEST PATTERN 2: EXISTS vs IN ==========';
GO

SET STATISTICS IO ON;

-- GOOD: IN (acceptable for small lists)
SELECT CustomerID, CustomerName
FROM dbo.CustomersBestPractice
WHERE CustomerID IN (SELECT CustomerID FROM dbo.OrdersBestPractice WHERE Amount > 5000);
GO

-- BETTER: EXISTS (stops at first match)
SELECT CustomerID, CustomerName
FROM dbo.CustomersBestPractice C
WHERE EXISTS (
    SELECT 1 FROM dbo.OrdersBestPractice O 
    WHERE O.CustomerID = C.CustomerID 
      AND O.Amount > 5000
);
-- More efficient, especially with indexes
GO

-- BEST: JOIN with DISTINCT (if you need other columns from Orders)
SELECT DISTINCT 
    C.CustomerID,
    C.CustomerName,
    C.Region
FROM dbo.CustomersBestPractice C
INNER JOIN dbo.OrdersBestPractice O ON C.CustomerID = O.CustomerID
WHERE O.Amount > 5000;
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- BEST PATTERN 3: Common Table Expressions (CTEs) for Readability
-- ============================================================================

PRINT '========== BEST PATTERN 3: CTEs ==========';
GO

-- GOOD: Using CTEs for complex logic
WITH CustomerMetrics AS (
    SELECT 
        CustomerID,
        CustomerName,
        Region,
        SignupDate
    FROM dbo.CustomersBestPractice
    WHERE Status = 'Active'
),
OrderSummary AS (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(Amount) AS TotalAmount,
        MAX(OrderDate) AS LastOrderDate
    FROM dbo.OrdersBestPractice
    WHERE Status = 'Completed'
    GROUP BY CustomerID
),
HighValueCustomers AS (
    SELECT 
        OS.CustomerID,
        OS.OrderCount,
        OS.TotalAmount
    FROM OrderSummary OS
    WHERE OS.TotalAmount > 10000 AND OS.OrderCount > 5
)
SELECT 
    CM.CustomerName,
    CM.Region,
    HVC.OrderCount,
    HVC.TotalAmount,
    DATEDIFF(DAY, CM.SignupDate, GETDATE()) AS DaysSinceSignup
FROM CustomerMetrics CM
INNER JOIN HighValueCustomers HVC ON CM.CustomerID = HVC.CustomerID
ORDER BY HVC.TotalAmount DESC;
-- Readable, maintainable, easy to debug
GO

-- ============================================================================
-- BEST PATTERN 4: Window Functions Instead of Self-Joins
-- ============================================================================

PRINT '========== BEST PATTERN 4: Window Functions ==========';
GO

SET STATISTICS IO ON;

-- OLD WAY: Self-join for running totals (slow)
SELECT 
    O1.OrderID,
    O1.OrderDate,
    O1.Amount,
    (SELECT SUM(O2.Amount) 
     FROM dbo.OrdersBestPractice O2 
     WHERE O2.CustomerID = O1.CustomerID 
       AND O2.OrderDate <= O1.OrderDate) AS RunningTotal
FROM dbo.OrdersBestPractice O1
WHERE O1.CustomerID = 100
ORDER BY O1.OrderDate;
GO

-- BETTER: Window function
SELECT 
    OrderID,
    OrderDate,
    Amount,
    SUM(Amount) OVER (
        PARTITION BY CustomerID 
        ORDER BY OrderDate 
        ROWS UNBOUNDED PRECEDING
    ) AS RunningTotal
FROM dbo.OrdersBestPractice
WHERE CustomerID = 100
ORDER BY OrderDate;
-- Single pass, much more efficient
GO

SET STATISTICS IO OFF;
GO

-- More window function examples
SELECT 
    CustomerID,
    OrderID,
    OrderDate,
    Amount,
    -- Running total
    SUM(Amount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RunningTotal,
    -- Row number
    ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC) AS RowNum,
    -- Rank
    DENSE_RANK() OVER (PARTITION BY CustomerID ORDER BY Amount DESC) AS AmountRank,
    -- Moving average (last 3 orders)
    AVG(Amount) OVER (
        PARTITION BY CustomerID 
        ORDER BY OrderDate 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAvg3,
    -- Difference from previous
    Amount - LAG(Amount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS AmountChange
FROM dbo.OrdersBestPractice
WHERE CustomerID IN (100, 101, 102)
ORDER BY CustomerID, OrderDate;
GO

-- ============================================================================
-- BEST PATTERN 5: CROSS APPLY for Top N Per Group
-- ============================================================================

PRINT '========== BEST PATTERN 5: CROSS APPLY ==========';
GO

SET STATISTICS IO ON;

-- Get top 3 orders per customer
SELECT 
    C.CustomerID,
    C.CustomerName,
    TopOrders.OrderDate,
    TopOrders.Amount
FROM dbo.CustomersBestPractice C
CROSS APPLY (
    SELECT TOP 3 OrderDate, Amount
    FROM dbo.OrdersBestPractice O
    WHERE O.CustomerID = C.CustomerID
    ORDER BY Amount DESC
) TopOrders
WHERE C.Region = 'North'
ORDER BY C.CustomerID, TopOrders.Amount DESC;
-- Efficient for top N per group scenarios
GO

SET STATISTICS IO OFF;
GO

-- OUTER APPLY (like LEFT JOIN but with logic)
SELECT 
    C.CustomerID,
    C.CustomerName,
    LatestOrder.OrderDate,
    LatestOrder.Amount
FROM dbo.CustomersBestPractice C
OUTER APPLY (
    SELECT TOP 1 OrderDate, Amount
    FROM dbo.OrdersBestPractice O
    WHERE O.CustomerID = C.CustomerID
    ORDER BY OrderDate DESC
) LatestOrder
WHERE C.Status = 'Active';
-- Returns all customers, with latest order if exists
GO

-- ============================================================================
-- BEST PATTERN 6: Batch Processing for Large Updates
-- ============================================================================

PRINT '========== BEST PATTERN 6: Batch Updates ==========';
GO

-- GOOD: Batch updates to prevent log growth
DECLARE @BatchSize INT = 5000;
DECLARE @RowsAffected INT = @BatchSize;

WHILE @RowsAffected = @BatchSize
BEGIN
    UPDATE TOP (@BatchSize) dbo.OrdersBestPractice
    SET Status = 'Archived'
    WHERE Status = 'Completed' 
      AND OrderDate < '2023-01-01';
    
    SET @RowsAffected = @@ROWCOUNT;
    
    -- Optional: Add delay to reduce impact on other queries
    IF @RowsAffected = @BatchSize
        WAITFOR DELAY '00:00:01';
END
GO

-- Reset for other demos
UPDATE dbo.OrdersBestPractice
SET Status = 'Completed'
WHERE Status = 'Archived';
GO

-- ============================================================================
-- BEST PATTERN 7: Index-Friendly JOINs
-- ============================================================================

PRINT '========== BEST PATTERN 7: Optimal JOINs ==========';
GO

SET STATISTICS IO ON;

-- GOOD: JOIN on indexed columns
SELECT 
    C.CustomerName,
    O.OrderDate,
    O.Amount
FROM dbo.CustomersBestPractice C
INNER JOIN dbo.OrdersBestPractice O ON C.CustomerID = O.CustomerID
WHERE C.Region = 'North';
-- Uses indexes efficiently
GO

-- Multi-table join with proper filters
SELECT 
    C.CustomerName,
    O.OrderDate,
    SUM(OD.Quantity * OD.UnitPrice) AS OrderTotal
FROM dbo.CustomersBestPractice C
INNER JOIN dbo.OrdersBestPractice O ON C.CustomerID = O.CustomerID
INNER JOIN dbo.OrderDetailsBestPractice OD ON O.OrderID = OD.OrderID
WHERE C.Status = 'Active'
  AND O.OrderDate >= '2025-01-01'
GROUP BY C.CustomerName, O.OrderDate
HAVING SUM(OD.Quantity * OD.UnitPrice) > 500
ORDER BY OrderTotal DESC;
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- BEST PATTERN 8: Avoid Scalar UDFs, Use Inline TVFs
-- ============================================================================

PRINT '========== BEST PATTERN 8: Inline Functions ==========';
GO

-- Create inline table-valued function
CREATE OR ALTER FUNCTION dbo.GetCustomerOrders_Inline(@CustomerID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderDate, Amount, Status
    FROM dbo.OrdersBestPractice
    WHERE CustomerID = @CustomerID
);
GO

-- Use inline TVF (optimizer can see through it)
SELECT 
    C.CustomerName,
    O.OrderDate,
    O.Amount
FROM dbo.CustomersBestPractice C
CROSS APPLY dbo.GetCustomerOrders_Inline(C.CustomerID) O
WHERE C.Region = 'South';
-- Efficiently integrated into query plan
GO

-- ============================================================================
-- BEST PATTERN 9: Appropriate Use of Temp Tables vs Table Variables vs CTEs
-- ============================================================================

PRINT '========== BEST PATTERN 9: Temp Tables, Table Variables, CTEs ==========';
GO

-- CTE: For readability, not reused multiple times, small to medium datasets
WITH RecentOrders AS (
    SELECT CustomerID, SUM(Amount) AS TotalAmount
    FROM dbo.OrdersBestPractice
    WHERE OrderDate >= '2025-01-01'
    GROUP BY CustomerID
)
SELECT C.CustomerName, RO.TotalAmount
FROM dbo.CustomersBestPractice C
INNER JOIN RecentOrders RO ON C.CustomerID = RO.CustomerID;
GO

-- Temp Table: Large datasets, need indexes, reused multiple times
CREATE TABLE #CustomerSummary (
    CustomerID INT NOT NULL PRIMARY KEY,
    TotalOrders INT NOT NULL,
    TotalAmount DECIMAL(10, 2) NOT NULL
);

INSERT INTO #CustomerSummary (CustomerID, TotalOrders, TotalAmount)
SELECT 
    CustomerID,
    COUNT(*) AS TotalOrders,
    SUM(Amount) AS TotalAmount
FROM dbo.OrdersBestPractice
GROUP BY CustomerID;

-- Create index on temp table
CREATE NONCLUSTERED INDEX IX_Temp_TotalAmount ON #CustomerSummary(TotalAmount);

-- Use temp table multiple times
SELECT * FROM #CustomerSummary WHERE TotalAmount > 10000;
SELECT AVG(TotalAmount) FROM #CustomerSummary;

DROP TABLE #CustomerSummary;
GO

-- Table Variable: Small datasets (<1000 rows), no indexes needed
DECLARE @TopCustomers TABLE (
    CustomerID INT,
    CustomerName VARCHAR(100),
    TotalAmount DECIMAL(10, 2)
);

INSERT INTO @TopCustomers (CustomerID, CustomerName, TotalAmount)
SELECT TOP 100
    C.CustomerID,
    C.CustomerName,
    SUM(O.Amount) AS TotalAmount
FROM dbo.CustomersBestPractice C
INNER JOIN dbo.OrdersBestPractice O ON C.CustomerID = O.CustomerID
GROUP BY C.CustomerID, C.CustomerName
ORDER BY SUM(O.Amount) DESC;

SELECT * FROM @TopCustomers;
GO

-- ============================================================================
-- BEST PATTERN 10: Covering Indexes with INCLUDE
-- ============================================================================

-- Already demonstrated in index creation above
-- IX_Customers_Status_Region includes CustomerName
-- IX_Orders_CustomerID_Date includes Amount, Status

SET STATISTICS IO ON;

-- Query fully covered by index
SELECT CustomerID, OrderDate, Amount, Status
FROM dbo.OrdersBestPractice
WHERE CustomerID = 100 AND OrderDate >= '2025-01-01';
-- Index seek only, no key lookup!
GO

SET STATISTICS IO OFF;
GO

-- ============================================================================
-- BEST PATTERN 11: Proper Data Types
-- ============================================================================

PRINT '========== BEST PATTERN 11: Appropriate Data Types ==========';
GO

-- GOOD: Use appropriate sizes
CREATE TABLE #BestPracticeTypes (
    ID INT NOT NULL,                    -- Not BIGINT if not needed
    Code CHAR(5) NOT NULL,              -- Fixed length for fixed data
    Name VARCHAR(100) NOT NULL,         -- Variable length for variable data
    IsActive BIT NOT NULL,              -- BIT for true/false
    Price DECIMAL(10,2) NOT NULL,       -- DECIMAL for money (not FLOAT)
    Quantity SMALLINT NOT NULL,         -- SMALLINT if range allows
    EventDate DATE NOT NULL,            -- DATE if time not needed
    CreatedDateTime DATETIME2(0) NOT NULL  -- DATETIME2, precision as needed
);
GO

DROP TABLE #BestPracticeTypes;
GO

-- ============================================================================
-- BEST PATTERN 12: Parameterized Queries (Prevent SQL Injection)
-- ============================================================================

PRINT '========== BEST PATTERN 12: Parameterized Queries ==========';
GO

-- GOOD: Using sp_executesql with parameters
DECLARE @CustomerID INT = 100;
DECLARE @SQL NVARCHAR(MAX);

SET @SQL = N'
    SELECT CustomerID, CustomerName, Region
    FROM dbo.CustomersBestPractice
    WHERE CustomerID = @CustomerID';

EXEC sp_executesql @SQL, N'@CustomerID INT', @CustomerID = @CustomerID;
-- Safe from SQL injection, plan can be reused
GO

-- ============================================================================
-- Best Practices Summary Table
-- ============================================================================

CREATE TABLE #BestPractices (
    Pattern VARCHAR(100),
    Benefit VARCHAR(200),
    WhenToUse VARCHAR(200)
);

INSERT INTO #BestPractices VALUES
('Filter early', 'Reduces dataset size before expensive operations', 'All queries with WHERE clauses'),
('EXISTS vs IN', 'Stops at first match, better with NULLs', 'Existence checks, large subqueries'),
('CTEs', 'Improves readability and maintainability', 'Complex queries, recursive operations'),
('Window functions', 'Single pass vs multiple self-joins', 'Running totals, rankings, analytics'),
('CROSS/OUTER APPLY', 'Efficient top N per group', 'Correlated logic, table-valued functions'),
('Batch updates', 'Prevents log growth, allows other queries', 'Large data modifications'),
('Index-friendly JOINs', 'Leverages indexes for efficiency', 'JOIN on indexed FK columns'),
('Inline TVFs', 'Optimizer can see through and optimize', 'Reusable parameterized logic'),
('Temp tables', 'Can add indexes, accurate statistics', 'Large intermediate results, reused multiple times'),
('Covering indexes', 'Eliminates key lookups', 'Frequently queried column combinations'),
('Appropriate types', 'Reduces storage, improves performance', 'All table designs'),
('Parameterized queries', 'Security, plan reuse', 'All dynamic SQL');

SELECT * FROM #BestPractices ORDER BY Pattern;
DROP TABLE #BestPractices;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
-- DROP FUNCTION dbo.GetCustomerOrders_Inline;
-- DROP TABLE dbo.OrderDetailsBestPractice;
-- DROP TABLE dbo.OrdersBestPractice;
-- DROP TABLE dbo.CustomersBestPractice;
-- GO
