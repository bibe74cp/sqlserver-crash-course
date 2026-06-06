/*
================================================================================
Demo 8: Table-Valued Functions
Topics: Inline TVF vs Multi-Statement TVF, Performance Comparison
================================================================================
*/

USE PerformanceDemo;
GO

-- ============================================================================
-- Setup: Create tables for TVF demonstrations
-- ============================================================================

IF OBJECT_ID('dbo.ProductsForTVF', 'U') IS NOT NULL
    DROP TABLE dbo.ProductsForTVF;
GO

IF OBJECT_ID('dbo.SalesForTVF', 'U') IS NOT NULL
    DROP TABLE dbo.SalesForTVF;
GO

CREATE TABLE dbo.ProductsForTVF (
    ProductID INT NOT NULL PRIMARY KEY,
    ProductName VARCHAR(100) NOT NULL,
    CategoryID INT NOT NULL,
    UnitPrice DECIMAL(10, 2) NOT NULL,
    IsActive BIT NOT NULL
);
GO

CREATE TABLE dbo.SalesForTVF (
    SaleID INT NOT NULL PRIMARY KEY,
    ProductID INT NOT NULL,
    SaleDate DATE NOT NULL,
    Quantity INT NOT NULL,
    TotalAmount DECIMAL(10, 2) NOT NULL,
    Region VARCHAR(50) NOT NULL
);
GO

-- Insert sample products
INSERT INTO dbo.ProductsForTVF (ProductID, ProductName, CategoryID, UnitPrice, IsActive)
SELECT 
    number,
    'Product ' + CAST(number AS VARCHAR(10)),
    (number % 20) + 1,
    (number % 500) + 9.99,
    CASE WHEN number % 10 = 0 THEN 0 ELSE 1 END
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 2000;
GO

-- Insert sample sales
INSERT INTO dbo.SalesForTVF (SaleID, ProductID, SaleDate, Quantity, TotalAmount, Region)
SELECT 
    number,
    (number % 2000) + 1,
    DATEADD(DAY, -(number % 730), GETDATE()),
    (number % 50) + 1,
    ((number % 50) + 1) * ((number % 500) + 9.99),
    CASE (number % 4)
        WHEN 0 THEN 'North'
        WHEN 1 THEN 'South'
        WHEN 2 THEN 'East'
        ELSE 'West'
    END
FROM master.dbo.spt_values
WHERE type = 'P' AND number BETWEEN 1 AND 100000;
GO

-- Create indexes
CREATE NONCLUSTERED INDEX IX_Sales_ProductID ON dbo.SalesForTVF(ProductID) INCLUDE (Quantity, TotalAmount);
CREATE NONCLUSTERED INDEX IX_Sales_SaleDate ON dbo.SalesForTVF(SaleDate) INCLUDE (ProductID, TotalAmount);
CREATE NONCLUSTERED INDEX IX_Products_CategoryID ON dbo.ProductsForTVF(CategoryID) INCLUDE (ProductName, UnitPrice);
GO

-- ============================================================================
-- 1. INLINE TABLE-VALUED FUNCTION (iTVF) - BEST PRACTICE
-- ============================================================================

PRINT '========== INLINE TABLE-VALUED FUNCTION (iTVF) ==========';
GO

-- Create inline TVF
CREATE OR ALTER FUNCTION dbo.GetProductSales_Inline(@ProductID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        S.SaleID,
        S.SaleDate,
        S.Quantity,
        S.TotalAmount,
        S.Region
    FROM dbo.SalesForTVF S
    WHERE S.ProductID = @ProductID
);
GO

-- Test inline TVF
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM dbo.GetProductSales_Inline(100);
-- Check execution plan: Optimizer can see through the function
-- Uses index efficiently
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Use in JOIN (optimizer integrates seamlessly)
SELECT 
    P.ProductName,
    S.SaleDate,
    S.Quantity,
    S.TotalAmount
FROM dbo.ProductsForTVF P
CROSS APPLY dbo.GetProductSales_Inline(P.ProductID) S
WHERE P.CategoryID = 5;
-- Efficient execution plan
GO

-- ============================================================================
-- 2. MULTI-STATEMENT TABLE-VALUED FUNCTION (mTVF) - AVOID IF POSSIBLE
-- ============================================================================

PRINT '========== MULTI-STATEMENT TABLE-VALUED FUNCTION (mTVF) ==========';
GO

-- Create multi-statement TVF
CREATE OR ALTER FUNCTION dbo.GetProductSales_MultiStatement(@ProductID INT)
RETURNS @Result TABLE (
    SaleID INT,
    SaleDate DATE,
    Quantity INT,
    TotalAmount DECIMAL(10, 2),
    Region VARCHAR(50)
)
AS
BEGIN
    INSERT INTO @Result (SaleID, SaleDate, Quantity, TotalAmount, Region)
    SELECT 
        SaleID,
        SaleDate,
        Quantity,
        TotalAmount,
        Region
    FROM dbo.SalesForTVF
    WHERE ProductID = @ProductID;
    
    RETURN;
END
GO

-- Test multi-statement TVF
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM dbo.GetProductSales_MultiStatement(100);
-- Check execution plan: Treated as black box
-- Optimizer estimates fixed rows (often 100)
-- No indexes on table variable
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 3. PERFORMANCE COMPARISON: Inline vs Multi-Statement
-- ============================================================================

PRINT '========== PERFORMANCE COMPARISON ==========';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '--- Inline TVF Performance ---';
SELECT 
    P.ProductName,
    COUNT(*) AS SalesCount,
    SUM(S.TotalAmount) AS TotalRevenue
FROM dbo.ProductsForTVF P
CROSS APPLY dbo.GetProductSales_Inline(P.ProductID) S
WHERE P.CategoryID = 5
GROUP BY P.ProductName;
GO

PRINT '--- Multi-Statement TVF Performance ---';
SELECT 
    P.ProductName,
    COUNT(*) AS SalesCount,
    SUM(S.TotalAmount) AS TotalRevenue
FROM dbo.ProductsForTVF P
CROSS APPLY dbo.GetProductSales_MultiStatement(P.ProductID) S
WHERE P.CategoryID = 5
GROUP BY P.ProductName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Compare execution plans side-by-side

-- ============================================================================
-- 4. COMPLEX INLINE TVF EXAMPLE
-- ============================================================================

PRINT '========== COMPLEX INLINE TVF ==========';
GO

-- Inline TVF with multiple tables and aggregation
CREATE OR ALTER FUNCTION dbo.GetCategorySalesSummary_Inline(@CategoryID INT, @StartDate DATE, @EndDate DATE)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        P.ProductID,
        P.ProductName,
        COUNT(S.SaleID) AS TotalSales,
        SUM(S.Quantity) AS TotalQuantity,
        SUM(S.TotalAmount) AS TotalRevenue,
        AVG(S.TotalAmount) AS AvgSaleAmount,
        MIN(S.SaleDate) AS FirstSale,
        MAX(S.SaleDate) AS LastSale
    FROM dbo.ProductsForTVF P
    LEFT JOIN dbo.SalesForTVF S ON P.ProductID = S.ProductID
        AND S.SaleDate BETWEEN @StartDate AND @EndDate
    WHERE P.CategoryID = @CategoryID
    GROUP BY P.ProductID, P.ProductName
);
GO

-- Use complex inline TVF
SELECT * 
FROM dbo.GetCategorySalesSummary_Inline(5, '2024-01-01', '2025-12-31')
ORDER BY TotalRevenue DESC;
-- Optimizer can still see through and optimize
GO

-- ============================================================================
-- 5. WHEN MULTI-STATEMENT TVF MIGHT BE NEEDED
-- ============================================================================

PRINT '========== MULTI-STATEMENT TVF USE CASE ==========';
GO

-- When procedural logic is absolutely required
CREATE OR ALTER FUNCTION dbo.GetProductSalesWithCalculations(@ProductID INT)
RETURNS @Result TABLE (
    SaleID INT,
    SaleDate DATE,
    Quantity INT,
    TotalAmount DECIMAL(10, 2),
    Commission DECIMAL(10, 2),
    DiscountAmount DECIMAL(10, 2),
    NetAmount DECIMAL(10, 2)
)
AS
BEGIN
    -- Insert base data
    INSERT INTO @Result (SaleID, SaleDate, Quantity, TotalAmount, Commission, DiscountAmount, NetAmount)
    SELECT 
        SaleID,
        SaleDate,
        Quantity,
        TotalAmount,
        0, 0, 0
    FROM dbo.SalesForTVF
    WHERE ProductID = @ProductID;
    
    -- Complex procedural calculations
    UPDATE @Result
    SET Commission = TotalAmount * 0.05
    WHERE Quantity > 10;
    
    UPDATE @Result
    SET Commission = TotalAmount * 0.10
    WHERE Quantity > 50;
    
    UPDATE @Result
    SET DiscountAmount = TotalAmount * 0.15
    WHERE SaleDate < DATEADD(YEAR, -1, GETDATE());
    
    UPDATE @Result
    SET NetAmount = TotalAmount - Commission - DiscountAmount;
    
    RETURN;
END
GO

SELECT * FROM dbo.GetProductSalesWithCalculations(100);
-- Use only when procedural logic cannot be expressed in single query
GO

-- ============================================================================
-- 6. ALTERNATIVES TO MULTI-STATEMENT TVF
-- ============================================================================

PRINT '========== ALTERNATIVES TO mTVF ==========';
GO

-- Alternative 1: Inline TVF with CASE expressions
CREATE OR ALTER FUNCTION dbo.GetProductSalesWithCalculations_Inline(@ProductID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        SaleID,
        SaleDate,
        Quantity,
        TotalAmount,
        -- Commission based on quantity
        CASE 
            WHEN Quantity > 50 THEN TotalAmount * 0.10
            WHEN Quantity > 10 THEN TotalAmount * 0.05
            ELSE 0
        END AS Commission,
        -- Discount for old sales
        CASE 
            WHEN SaleDate < DATEADD(YEAR, -1, GETDATE()) THEN TotalAmount * 0.15
            ELSE 0
        END AS DiscountAmount,
        -- Net amount calculation
        TotalAmount - 
        CASE 
            WHEN Quantity > 50 THEN TotalAmount * 0.10
            WHEN Quantity > 10 THEN TotalAmount * 0.05
            ELSE 0
        END -
        CASE 
            WHEN SaleDate < DATEADD(YEAR, -1, GETDATE()) THEN TotalAmount * 0.15
            ELSE 0
        END AS NetAmount
    FROM dbo.SalesForTVF
    WHERE ProductID = @ProductID
);
GO

-- Compare performance
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM dbo.GetProductSalesWithCalculations_Inline(100);
-- Likely faster than multi-statement version
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- Alternative 2: Stored Procedure
CREATE OR ALTER PROCEDURE dbo.GetProductSalesWithCalculations_SP
    @ProductID INT
AS
BEGIN
    SELECT 
        SaleID,
        SaleDate,
        Quantity,
        TotalAmount,
        CASE 
            WHEN Quantity > 50 THEN TotalAmount * 0.10
            WHEN Quantity > 10 THEN TotalAmount * 0.05
            ELSE 0
        END AS Commission,
        CASE 
            WHEN SaleDate < DATEADD(YEAR, -1, GETDATE()) THEN TotalAmount * 0.15
            ELSE 0
        END AS DiscountAmount
    FROM dbo.SalesForTVF
    WHERE ProductID = @ProductID;
END
GO

EXEC dbo.GetProductSalesWithCalculations_SP @ProductID = 100;
-- More flexible, can have multiple result sets
GO

-- ============================================================================
-- 7. SCALAR UDF vs INLINE TVF (AVOID SCALAR UDFS!)
-- ============================================================================

PRINT '========== SCALAR UDF (ANTI-PATTERN) ==========';
GO

-- BAD: Scalar UDF
CREATE OR ALTER FUNCTION dbo.GetProductTotalSales_Scalar(@ProductID INT)
RETURNS DECIMAL(10, 2)
AS
BEGIN
    DECLARE @Total DECIMAL(10, 2);
    
    SELECT @Total = SUM(TotalAmount)
    FROM dbo.SalesForTVF
    WHERE ProductID = @ProductID;
    
    RETURN ISNULL(@Total, 0);
END
GO

-- Using scalar UDF (SLOW!)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    ProductID,
    ProductName,
    dbo.GetProductTotalSales_Scalar(ProductID) AS TotalSales
FROM dbo.ProductsForTVF
WHERE CategoryID = 5;
-- Executed once per row, no parallelism, slow!
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- GOOD: Inline TVF alternative
CREATE OR ALTER FUNCTION dbo.GetProductTotalSales_Inline(@ProductID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT ISNULL(SUM(TotalAmount), 0) AS TotalSales
    FROM dbo.SalesForTVF
    WHERE ProductID = @ProductID
);
GO

-- Using inline TVF (FASTER)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    P.ProductID,
    P.ProductName,
    TS.TotalSales
FROM dbo.ProductsForTVF P
CROSS APPLY dbo.GetProductTotalSales_Inline(P.ProductID) TS
WHERE P.CategoryID = 5;
-- Optimized by query processor
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- BEST: Direct JOIN (when possible)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    P.ProductID,
    P.ProductName,
    ISNULL(SUM(S.TotalAmount), 0) AS TotalSales
FROM dbo.ProductsForTVF P
LEFT JOIN dbo.SalesForTVF S ON P.ProductID = S.ProductID
WHERE P.CategoryID = 5
GROUP BY P.ProductID, P.ProductName;
-- Best performance
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- 8. CHECKING FUNCTION TYPE
-- ============================================================================

-- View all functions in database
SELECT 
    SCHEMA_NAME(schema_id) AS SchemaName,
    name AS FunctionName,
    type_desc AS FunctionType,
    create_date,
    modify_date
FROM sys.objects
WHERE type IN ('TF', 'IF', 'FN')  -- TF=Table-valued, IF=Inline, FN=Scalar
ORDER BY type_desc, name;
GO

-- ============================================================================
-- 9. BEST PRACTICES SUMMARY
-- ============================================================================

CREATE TABLE #TVFBestPractices (
    FunctionType VARCHAR(50),
    Performance VARCHAR(20),
    Optimization VARCHAR(50),
    WhenToUse VARCHAR(200)
);

INSERT INTO #TVFBestPractices VALUES
('Inline TVF', 'Excellent', 'Fully optimized', 'Almost always - default choice for table-valued functions'),
('Multi-Statement TVF', 'Poor', 'Black box (100 rows)', 'Only when complex procedural logic absolutely required'),
('Scalar UDF', 'Very Poor', 'No parallelism', 'AVOID - Use inline TVF or computed columns instead'),
('Stored Procedure', 'Good', 'Can be optimized', 'When you need OUTPUT params or multiple result sets'),
('Direct Query', 'Excellent', 'Best optimization', 'Preferred when logic can be expressed inline');

SELECT * FROM #TVFBestPractices ORDER BY Performance DESC;
DROP TABLE #TVFBestPractices;
GO

-- ============================================================================
-- 10. MIGRATION PATH: Converting mTVF to iTVF
-- ============================================================================

PRINT '========== MIGRATION EXAMPLE: mTVF to iTVF ==========';
GO

-- BEFORE: Multi-statement TVF
CREATE OR ALTER FUNCTION dbo.GetRecentSales_Old(@Days INT)
RETURNS @Result TABLE (
    ProductID INT,
    ProductName VARCHAR(100),
    TotalSales DECIMAL(10, 2)
)
AS
BEGIN
    DECLARE @StartDate DATE = DATEADD(DAY, -@Days, GETDATE());
    
    INSERT INTO @Result (ProductID, ProductName, TotalSales)
    SELECT 
        P.ProductID,
        P.ProductName,
        SUM(S.TotalAmount)
    FROM dbo.ProductsForTVF P
    INNER JOIN dbo.SalesForTVF S ON P.ProductID = S.ProductID
    WHERE S.SaleDate >= @StartDate
    GROUP BY P.ProductID, P.ProductName;
    
    RETURN;
END
GO

-- AFTER: Inline TVF (equivalent functionality)
CREATE OR ALTER FUNCTION dbo.GetRecentSales_New(@Days INT)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        P.ProductID,
        P.ProductName,
        SUM(S.TotalAmount) AS TotalSales
    FROM dbo.ProductsForTVF P
    INNER JOIN dbo.SalesForTVF S ON P.ProductID = S.ProductID
    WHERE S.SaleDate >= DATEADD(DAY, -@Days, GETDATE())
    GROUP BY P.ProductID, P.ProductName
);
GO

-- Compare performance
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '--- Old (Multi-Statement) ---';
SELECT * FROM dbo.GetRecentSales_Old(365) ORDER BY TotalSales DESC;

PRINT '--- New (Inline) ---';
SELECT * FROM dbo.GetRecentSales_New(365) ORDER BY TotalSales DESC;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================================
-- CLEANUP (Optional)
-- ============================================================================
/*
DROP FUNCTION dbo.GetProductSales_Inline;
DROP FUNCTION dbo.GetProductSales_MultiStatement;
DROP FUNCTION dbo.GetCategorySalesSummary_Inline;
DROP FUNCTION dbo.GetProductSalesWithCalculations;
DROP FUNCTION dbo.GetProductSalesWithCalculations_Inline;
DROP FUNCTION dbo.GetProductTotalSales_Scalar;
DROP FUNCTION dbo.GetProductTotalSales_Inline;
DROP FUNCTION dbo.GetRecentSales_Old;
DROP FUNCTION dbo.GetRecentSales_New;
DROP PROCEDURE dbo.GetProductSalesWithCalculations_SP;
DROP TABLE dbo.SalesForTVF;
DROP TABLE dbo.ProductsForTVF;
GO
*/
