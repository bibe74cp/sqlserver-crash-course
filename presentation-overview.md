# SQL Server Performance Optimization - Presentation Overview

## 1. Indexes: Storage Structures and Maintenance

### Heap Tables
- **Definition**: A table without a clustered index
- **Storage**: Data pages are not ordered in any particular sequence
- **Access**: SQL Server uses IAM (Index Allocation Map) pages to track extents
- **Performance Characteristics**:
  - Insertions are fast (no need to maintain order)
  - Reads require table scans unless nonclustered indexes exist
  - Forwarding pointers created when rows expand beyond page capacity
  - Best for: staging tables, very small lookup tables

### B-Tree (Binary Tree)
- **Structure**: Each node has at most 2 children
- **Usage**: Traditional balanced tree structure
- **Limitation**: Not optimal for disk-based storage due to high depth
- **Key Point**: SQL Server doesn't use pure B-Trees

### B+-Tree (B-Plus Tree)
- **Structure**: SQL Server's actual implementation for indexes
- **Characteristics**:
  - All data stored in leaf nodes
  - Internal nodes contain only keys and pointers
  - Leaf nodes are linked (doubly-linked list)
  - Typical depth: 3-4 levels even for millions of rows
- **Advantages**:
  - Efficient range scans (traverse leaf level only)
  - All leaf nodes at same depth (balanced)
  - Better cache utilization
  - Sequential access via leaf-level links

### Index Fragmentation
- **Logical Fragmentation**: Pages in the index are not physically sequential
  - Measured by avg_fragmentation_in_percent
  - Causes: INSERTs, UPDATEs, DELETEs
  - Impact: More physical I/O for range scans
- **Extent Fragmentation**: Pages scattered across different extents
- **Page Density**: avg_page_space_used_in_percent
  - Low density = wasted space
  - High density = good space utilization

### Rebuild vs. Reorganize
| Operation | Rebuild | Reorganize |
|-----------|---------|------------|
| **Mechanism** | Drops and recreates index | Compacts existing pages |
| **Fragmentation Removal** | Complete | Partial |
| **Space Required** | Additional tempdb space | Minimal |
| **Locking** | Can be ONLINE (Enterprise) | Always online, minimal locks |
| **Statistics** | Automatically updated | Not updated |
| **Transaction Log** | Fully logged (or minimally in Simple/Bulk) | Fully logged |
| **When to Use** | Fragmentation > 30% | Fragmentation 10-30% |

**Best Practice Decision Matrix**:
- < 10% fragmentation: Do nothing
- 10-30% fragmentation: REORGANIZE
- > 30% fragmentation: REBUILD

---

## 2. Execution Plans: Reading, Interpreting, and Optimizing

### How to Read Execution Plans
- **Direction**: Right to left, top to bottom
- **Relative Cost**: Percentages indicate resource consumption
- **Thick arrows**: More rows flowing through
- **Operators**: Each icon represents an operation
- **Color coding**:
  - No warnings: Black/Blue
  - Warnings: Yellow triangle (missing index, type conversion)

### Key Operators to Recognize
- **Scans**:
  - Table Scan: Reads entire heap
  - Clustered Index Scan: Reads entire clustered index
  - Index Scan: Reads entire nonclustered index
- **Seeks**:
  - Index Seek: Uses index to find specific rows (optimal)
  - Key Lookup: Retrieve additional columns from clustered index
- **Joins**:
  - Nested Loop: Good for small datasets or when one side is small
  - Hash Match: Good for large unsorted datasets
  - Merge Join: Efficient for large sorted datasets
- **Sorts**: Expensive operation, indicates missing index or bad ORDER BY
- **Spools**: Table Spool/Index Spool = temporary workspace (can be expensive)

### Interpretation Tips
- **Missing Index Hints**: Green text in execution plan
  - Take with a grain of salt
  - May suggest too many indexes
  - Evaluate impact vs. maintenance cost
- **Warnings**: Yellow exclamation marks
  - Implicit conversions
  - Missing statistics
  - Excessive memory grants
- **Actual vs. Estimated Rows**: Large discrepancies indicate stale statistics
- **Parallelism**: Multiple threads (good for long queries, bad for short OLTP)

### Optimization Strategies
1. **Eliminate Scans**: Add appropriate indexes for seeks
2. **Reduce Key Lookups**: Use covering indexes or included columns
3. **Avoid Sorts**: Create indexes that match ORDER BY
4. **Fix Implicit Conversions**: Match data types in JOINs and WHEREs
5. **Update Statistics**: Keep statistics current for accurate estimates
6. **Partition Large Tables**: For very large datasets
7. **Rewrite Queries**: Sometimes logic changes outperform index additions

---

## 3. Indexes: Types and Advanced Techniques

### Clustered Index
- **Definition**: Determines physical order of data in table
- **Limit**: One per table
- **Structure**: Leaf level contains actual data rows
- **Key Selection Criteria**:
  - Narrow (few bytes = smaller index)
  - Unique (or SQL Server adds uniqueifier)
  - Static (unchanging values avoid page splits)
  - Ever-increasing (like IDENTITY) for minimal fragmentation
- **Typical Choice**: Primary key (if appropriate)
- **Impact**: All nonclustered indexes reference clustered key

### Nonclustered Index
- **Definition**: Separate structure from data table
- **Limit**: Up to 999 per table (not recommended!)
- **Structure**: 
  - Leaf level contains index key + bookmark
  - Bookmark = clustered key (or RID for heaps)
- **Use Cases**: Support frequent queries with selective WHERE/JOIN conditions
- **Downside**: Every nonclustered index adds overhead to INSERT/UPDATE/DELETE

### Covering Index
- **Definition**: Index contains all columns needed for a query
- **Benefit**: Query satisfied entirely from index (no bookmark lookup)
- **How to Achieve**:
  - Option 1: Include all columns in index key (order matters!)
  - Option 2: Use INCLUDE clause for non-key columns
- **Detection**: "Index Seek" with no "Key Lookup" in execution plan

### INCLUDE Clause
```sql
CREATE NONCLUSTERED INDEX IX_Example
ON Table (KeyColumn1, KeyColumn2)
INCLUDE (Column3, Column4, Column5);
```
- **Purpose**: Add non-key columns at leaf level only
- **Benefits**:
  - Columns in INCLUDE don't affect sort order
  - Reduces index size (not in intermediate levels)
  - Creates covering index without oversized keys
- **Best Practice**: 
  - Key columns: Used in WHERE, JOIN, GROUP BY, ORDER BY
  - INCLUDE columns: Only in SELECT list

### Filtered Indexes
```sql
CREATE NONCLUSTERED INDEX IX_ActiveOrders
ON Orders (OrderDate, CustomerID)
WHERE Status = 'Active';
```
- **Definition**: Index on subset of rows
- **Benefits**:
  - Smaller index size
  - Reduced maintenance overhead
  - Better selectivity
- **Use Cases**:
  - Sparse columns (e.g., EndDate IS NULL for active records)
  - Partitioned data (e.g., current year only)
  - Status-based filtering
- **Limitation**: Optimizer must match filter condition exactly

---

## 4. Queries: Order of Operators

### Logical Query Processing Order
Understanding the logical order helps write correct queries:

```
1. FROM (including JOINs)
2. WHERE
3. GROUP BY
4. HAVING
5. SELECT
6. DISTINCT
7. ORDER BY
8. TOP / OFFSET-FETCH
```

### Key Implications

**1. FROM → WHERE → GROUP BY**
- You can't use column aliases from SELECT in WHERE
```sql
-- WRONG
SELECT Price * Quantity AS Total
FROM Orders
WHERE Total > 1000;  -- Error: Total doesn't exist yet

-- CORRECT
SELECT Price * Quantity AS Total
FROM Orders
WHERE Price * Quantity > 1000;
```

**2. WHERE → HAVING**
- WHERE filters before aggregation (more efficient)
- HAVING filters after aggregation
```sql
-- Better: Filter early with WHERE
SELECT CustomerID, COUNT(*) AS OrderCount
FROM Orders
WHERE OrderDate >= '2024-01-01'
GROUP BY CustomerID
HAVING COUNT(*) > 5;
```

**3. SELECT → ORDER BY**
- ORDER BY can use SELECT aliases
- ORDER BY is last operation (except TOP/OFFSET)
```sql
SELECT FirstName + ' ' + LastName AS FullName
FROM Employees
ORDER BY FullName;  -- Valid: FullName exists after SELECT
```

**4. Execution Order vs. Optimization**
- Logical order ≠ physical execution order
- Query optimizer reorders operations for efficiency
- Execution plan shows optimized physical order

---

## 5. Queries: Implicit Conversions

### What Are Implicit Conversions?
- SQL Server automatically converts data types when they don't match
- Can prevent index usage and cause performance degradation
- Often indicated by CONVERT_IMPLICIT in execution plan

### Common Scenarios

**Scenario 1: Column vs. Literal**
```sql
-- Column is VARCHAR, parameter is NVARCHAR
-- Implicit conversion on column = index not used
SELECT * FROM Users WHERE Username = N'john';  -- BAD

-- Solution: Match the data type
SELECT * FROM Users WHERE Username = 'john';   -- GOOD
```

**Scenario 2: Numeric Precision**
```sql
-- Column is INT, comparing with DECIMAL
SELECT * FROM Products WHERE ProductID = 1.0;  -- Implicit conversion

-- Better
SELECT * FROM Products WHERE ProductID = 1;
```

**Scenario 3: JOIN on Mismatched Types**
```sql
-- Table1.ID is INT, Table2.ID is BIGINT
SELECT * 
FROM Table1 T1
JOIN Table2 T2 ON T1.ID = T2.ID;  -- Conversion on T1.ID
```

### Detection
- **Execution Plan**: Look for yellow warning icon
- **CONVERT_IMPLICIT** or **CONVERT** operator
- **Warnings tab**: "Type conversion may affect seekability"

### Solutions
1. **Match Data Types**: Ensure columns and parameters use same type
2. **Explicit Conversion**: Move conversion to parameter side
```sql
-- If must convert, do it on the non-indexed side
WHERE ColumnName = CAST(@Parameter AS VARCHAR(50))
```
3. **Fix Schema**: Align data types across related tables
4. **Use Proper Literal Prefix**:
   - NVARCHAR: N'text'
   - VARCHAR: 'text'
   - No prefix for numbers

### Performance Impact
- Index seeks become scans
- CPU overhead for conversion
- Inaccurate cardinality estimates
- Can cause query timeouts in large tables

---

## 6. Queries: Worst Patterns

### Pattern 1: Functions on Columns in WHERE
```sql
-- BAD: Function prevents index usage
SELECT * FROM Orders
WHERE YEAR(OrderDate) = 2024;

-- GOOD: Sargable predicate
SELECT * FROM Orders
WHERE OrderDate >= '2024-01-01' 
  AND OrderDate < '2025-01-01';
```

**Why It's Bad**:
- SQL Server must evaluate function for every row
- Index on OrderDate becomes useless
- Results in table/index scan instead of seek

**Common Offenders**:
- `YEAR()`, `MONTH()`, `DAY()` on date columns
- `UPPER()`, `LOWER()` on string columns
- `SUBSTRING()`, `LEFT()`, `RIGHT()`
- `ISNULL()`, `COALESCE()`

### Pattern 2: Leading Wildcards
```sql
-- BAD: Leading wildcard
SELECT * FROM Customers
WHERE LastName LIKE '%Smith%';

-- BETTER (if pattern allows)
SELECT * FROM Customers
WHERE LastName LIKE 'Smith%';  -- Can use index
```

### Pattern 3: OR Conditions Across Columns
```sql
-- BAD: OR can prevent index usage
SELECT * FROM Products
WHERE ProductName = 'Widget' 
   OR CategoryID = 5;

-- BETTER: Use UNION ALL (if appropriate)
SELECT * FROM Products WHERE ProductName = 'Widget'
UNION ALL
SELECT * FROM Products WHERE CategoryID = 5 AND ProductName <> 'Widget';
```

### Pattern 4: RBAR (Row-By-Agonizing-Row)
```sql
-- BAD: Cursor processing
DECLARE @CustomerID INT;
DECLARE cur CURSOR FOR SELECT CustomerID FROM Customers;
OPEN cur;
FETCH NEXT FROM cur INTO @CustomerID;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Process one row at a time
    UPDATE Orders SET Status = 'Processed' 
    WHERE CustomerID = @CustomerID;
    FETCH NEXT FROM cur INTO @CustomerID;
END
CLOSE cur;
DEALLOCATE cur;

-- GOOD: Set-based operation
UPDATE Orders
SET Status = 'Processed'
FROM Orders O
INNER JOIN Customers C ON O.CustomerID = C.CustomerID;
```

**Why RBAR is Bad**:
- Network round trips (in client code)
- Repeated query compilations
- Individual row locks
- Loses SQL Server's set-based optimization

### Pattern 5: SELECT *
```sql
-- BAD: Retrieves unnecessary data
SELECT * FROM LargeTable WHERE ID = 123;

-- GOOD: Select only needed columns
SELECT ID, Name, Status FROM LargeTable WHERE ID = 123;
```

**Impact**:
- Prevents covering indexes
- Increases I/O and network traffic
- Memory grants larger than needed
- Breaks applications when schema changes

### Pattern 6: NOT IN with NULLs
```sql
-- DANGEROUS: Returns unexpected results with NULLs
SELECT * FROM Customers
WHERE CustomerID NOT IN (SELECT CustomerID FROM Orders);

-- BETTER: Use NOT EXISTS
SELECT * FROM Customers C
WHERE NOT EXISTS (
    SELECT 1 FROM Orders O WHERE O.CustomerID = C.CustomerID
);
```

---

## 7. Queries: Best Patterns

### Pattern 1: Filter Early and Often
```sql
-- GOOD: Filter in WHERE before JOIN
SELECT C.CustomerName, O.OrderDate
FROM Customers C
INNER JOIN Orders O ON C.CustomerID = O.CustomerID
WHERE O.OrderDate >= '2024-01-01'
  AND C.Status = 'Active';

-- EVEN BETTER: Filter in subquery if very selective
SELECT C.CustomerName, O.OrderDate
FROM Customers C
INNER JOIN (
    SELECT CustomerID, OrderDate 
    FROM Orders 
    WHERE OrderDate >= '2024-01-01'
) O ON C.CustomerID = O.CustomerID
WHERE C.Status = 'Active';
```

**Principle**: Reduce dataset size as early as possible

### Pattern 2: JOIN with WHERE (Not WHERE with Subquery)
```sql
-- LESS OPTIMAL: Correlated subquery
SELECT CustomerName
FROM Customers
WHERE CustomerID IN (
    SELECT CustomerID 
    FROM Orders 
    WHERE OrderDate >= '2024-01-01'
);

-- BETTER: JOIN (usually more efficient)
SELECT DISTINCT C.CustomerName
FROM Customers C
INNER JOIN Orders O ON C.CustomerID = O.CustomerID
WHERE O.OrderDate >= '2024-01-01';

-- BEST: EXISTS (no DISTINCT needed, stops after first match)
SELECT C.CustomerName
FROM Customers C
WHERE EXISTS (
    SELECT 1 FROM Orders O 
    WHERE O.CustomerID = C.CustomerID 
      AND O.OrderDate >= '2024-01-01'
);
```

### Pattern 3: Common Table Expressions (CTEs)
```sql
-- GOOD: Improves readability and maintenance
WITH ActiveCustomers AS (
    SELECT CustomerID, CustomerName, Region
    FROM Customers
    WHERE Status = 'Active'
),
RecentOrders AS (
    SELECT CustomerID, OrderDate, Amount
    FROM Orders
    WHERE OrderDate >= DATEADD(MONTH, -3, GETDATE())
)
SELECT 
    AC.CustomerName,
    AC.Region,
    COUNT(RO.OrderDate) AS OrderCount,
    SUM(RO.Amount) AS TotalAmount
FROM ActiveCustomers AC
LEFT JOIN RecentOrders RO ON AC.CustomerID = RO.CustomerID
GROUP BY AC.CustomerName, AC.Region;
```

**Benefits**:
- Readable, maintainable code
- Recursive queries support
- Can reference multiple times in query
- Easier debugging

**Note**: CTEs are not materialized by default (re-evaluated each reference)

### Pattern 4: Window Functions Instead of Self-Joins
```sql
-- LESS OPTIMAL: Self-join for running totals
SELECT O1.OrderDate, O1.Amount,
    (SELECT SUM(Amount) 
     FROM Orders O2 
     WHERE O2.OrderDate <= O1.OrderDate) AS RunningTotal
FROM Orders O1;

-- BETTER: Window function
SELECT OrderDate, Amount,
    SUM(Amount) OVER (ORDER BY OrderDate 
                      ROWS UNBOUNDED PRECEDING) AS RunningTotal
FROM Orders;
```

### Pattern 5: Batch Updates
```sql
-- GOOD: Batch processing for large updates
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) Orders
    SET Status = 'Archived'
    WHERE OrderDate < '2020-01-01'
      AND Status = 'Completed';
    
    IF @@ROWCOUNT < 5000 BREAK;
    
    WAITFOR DELAY '00:00:01';  -- Prevent log growth
END
```

**Benefits**:
- Prevents log file explosion
- Allows other queries to run
- Easier to restart if interrupted

### Pattern 6: Appropriate JOIN Types
- **INNER JOIN**: Only matching rows
- **LEFT JOIN**: All from left, matching from right
- **CROSS APPLY**: Like INNER JOIN but allows correlated logic
- **OUTER APPLY**: Like LEFT JOIN but allows correlated logic

```sql
-- APPLY for table-valued functions or complex logic
SELECT C.CustomerName, LatestOrders.OrderDate
FROM Customers C
CROSS APPLY (
    SELECT TOP 3 OrderDate, Amount
    FROM Orders O
    WHERE O.CustomerID = C.CustomerID
    ORDER BY OrderDate DESC
) LatestOrders;
```

---

## 8. Queries: Table-Valued Functions

### Inline Table-Valued Functions (iTVF)
```sql
CREATE FUNCTION dbo.GetCustomerOrders(@CustomerID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderDate, Amount
    FROM Orders
    WHERE CustomerID = @CustomerID
);

-- Usage
SELECT * FROM dbo.GetCustomerOrders(123);
```

**Characteristics**:
- **Performance**: Excellent (acts like a view with parameters)
- **Query Optimizer**: Can see through and optimize
- **Execution Plan**: Integrated with calling query
- **Best Practice**: Strongly preferred over multi-statement TVFs

### Multi-Statement Table-Valued Functions (mTVF)
```sql
CREATE FUNCTION dbo.GetCustomerSummary(@CustomerID INT)
RETURNS @Result TABLE (
    OrderID INT,
    OrderDate DATE,
    Amount DECIMAL(10,2)
)
AS
BEGIN
    INSERT INTO @Result
    SELECT OrderID, OrderDate, Amount
    FROM Orders
    WHERE CustomerID = @CustomerID;
    
    -- Additional processing
    UPDATE @Result SET Amount = Amount * 1.1;
    
    RETURN;
END
```

**Characteristics**:
- **Performance**: Poor (often)
- **Query Optimizer**: Treats as black box (estimates 1 row!)
- **Execution Plan**: Separate, then materialized
- **Use Cases**: Complex procedural logic that can't be expressed in single query

### Comparison: iTVF vs. mTVF

| Aspect | Inline TVF | Multi-Statement TVF |
|--------|-----------|-------------------|
| **Performance** | Excellent | Often poor |
| **Optimization** | Fully optimized with query | Treated as black box |
| **Cardinality** | Accurate estimates | Fixed estimate (100 rows) |
| **Parallelism** | Yes | No |
| **Indexes** | Uses table indexes | No indexes on table variable |
| **Statistics** | Yes | No |
| **When to Use** | Almost always | Only when procedural logic required |

### Best Practices
1. **Prefer Inline TVFs**: Whenever possible
2. **Avoid Scalar UDFs**: Use inline TVFs or computed columns instead
3. **CROSS APPLY for Row-Level**: Use with inline TVFs for row-by-row logic
4. **Test Performance**: Always compare TVF vs. direct query
5. **Consider Views**: For parameterless logic, views may be better

### Alternatives to Consider
```sql
-- Instead of function, consider:

-- 1. Stored Procedure with OUTPUT
CREATE PROCEDURE GetOrders @CustomerID INT
AS
SELECT * FROM Orders WHERE CustomerID = @CustomerID;

-- 2. Dynamic SQL
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Orders WHERE CustomerID = @CustomerID';
EXEC sp_executesql @SQL, N'@CustomerID INT', @CustomerID = 123;

-- 3. Inline derived table
SELECT C.*, O.*
FROM Customers C
CROSS APPLY (
    SELECT TOP 5 *
    FROM Orders
    WHERE CustomerID = C.CustomerID
    ORDER BY OrderDate DESC
) O;
```

---

## 9. Parameter Sniffing and How to Avoid It

### What is Parameter Sniffing?
- SQL Server compiles a stored procedure using the **first parameter values** it receives
- Execution plan is optimized for those specific values
- Plan is cached and reused for subsequent executions
- **Problem**: Plan optimal for first values may be terrible for others

### The Good Side
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
AS
SELECT * FROM Orders WHERE Status = @Status;

-- First call: @Status = 'Pending' (1000 rows)
-- Plan: Index Scan (appropriate for 1000 rows)

-- Second call: @Status = 'Pending' (still 1000 rows)
-- Uses cached plan: Still good!
```

### The Bad Side
```sql
-- First call: @Status = 'Pending' (1000 rows)
-- Plan: Index Scan (appropriate for many rows)

-- Second call: @Status = 'Cancelled' (3 rows)
-- Uses same Index Scan plan: Inefficient! 
-- Should use Index Seek instead
```

### Detection
1. **Performance Variation**: Same procedure fast sometimes, slow others
2. **Execution Plans**: Different parameter values show same plan shape
3. **Extended Events**: Track `parameter_sensitive_plan_optimization`
4. **DMVs**: Query `sys.dm_exec_query_stats` for plan variation

### Solution 1: OPTIMIZE FOR Hint
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
AS
SELECT * FROM Orders 
WHERE Status = @Status
OPTION (OPTIMIZE FOR (@Status = 'Pending'));
```
- **Use When**: One parameter value is most common
- **Pro**: Ensures plan optimized for specific value
- **Con**: Hardcoded optimization target

### Solution 2: OPTIMIZE FOR UNKNOWN
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
AS
SELECT * FROM Orders 
WHERE Status = @Status
OPTION (OPTIMIZE FOR UNKNOWN);
```
- **Use When**: Parameter values vary widely
- **Pro**: Creates "generic" plan using statistics
- **Con**: May not be optimal for any specific value

### Solution 3: RECOMPILE (Procedure Level)
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
WITH RECOMPILE
AS
SELECT * FROM Orders WHERE Status = @Status;
```
- **Use When**: Parameter sensitivity is extreme
- **Pro**: Always fresh plan
- **Con**: CPU overhead for compilation every time

### Solution 4: RECOMPILE (Query Level)
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
AS
SELECT * FROM Orders 
WHERE Status = @Status
OPTION (RECOMPILE);
```
- **Use When**: Only one query in procedure is sensitive
- **Pro**: Recompiles only problematic query
- **Con**: Still compilation overhead

### Solution 5: Local Variable Copy
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
AS
DECLARE @StatusLocal VARCHAR(20) = @Status;

SELECT * FROM Orders 
WHERE Status = @StatusLocal;
```
- **Use When**: Need to avoid parameter sniffing entirely
- **Pro**: Creates "unknown" plan without hint
- **Con**: Loses parameter sniffing benefits entirely

### Solution 6: Dynamic SQL
```sql
CREATE PROCEDURE GetOrdersByStatus @Status VARCHAR(20)
AS
DECLARE @SQL NVARCHAR(MAX) = N'
    SELECT * FROM Orders 
    WHERE Status = @Status';

EXEC sp_executesql @SQL, 
                   N'@Status VARCHAR(20)', 
                   @Status = @Status;
```
- **Use When**: Need fresh plan each time
- **Pro**: Parameter sniffing for each execution
- **Con**: Plan cache pollution, SQL injection risk if not careful

### Solution 7: Multiple Procedures
```sql
-- Separate procedures for different scenarios
CREATE PROCEDURE GetOrdersByCommonStatus @Status VARCHAR(20)
AS
SELECT * FROM Orders WHERE Status = @Status;

CREATE PROCEDURE GetOrdersByRareStatus @Status VARCHAR(20)
AS
SELECT * FROM Orders 
WHERE Status = @Status
OPTION (RECOMPILE);
```

### SQL Server 2022: Parameter Sensitivity Plans (PSP)
- Automatically detects parameter-sensitive queries
- Generates multiple plans for different parameter ranges
- Chooses appropriate plan at runtime
- Requires compatibility level 160+

```sql
-- Enable for database
ALTER DATABASE SCOPED CONFIGURATION 
SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
```

### Decision Matrix

| Scenario | Recommended Solution |
|----------|---------------------|
| One value dominates (90%+) | OPTIMIZE FOR specific value |
| Values evenly distributed | OPTIMIZE FOR UNKNOWN |
| Extreme sensitivity | RECOMPILE (query or proc) |
| Ad-hoc reporting | Dynamic SQL |
| SQL Server 2022+ | Enable PSP feature |

### Monitoring and Maintenance
- Regularly clear plan cache for testing: `DBCC FREEPROCCACHE`
- Monitor plan cache size: `sys.dm_exec_cached_plans`
- Track recompiles: Extended Events `sql_statement_recompile`
- Review parameter statistics: `sys.dm_exec_query_stats`

---

## Demo Ideas and Sample Code

### Demo 1: Index Fragmentation
```sql
-- Check fragmentation
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id 
                          AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Rebuild vs Reorganize
ALTER INDEX IX_Example ON TableName REBUILD;
ALTER INDEX IX_Example ON TableName REORGANIZE;
```

### Demo 2: Execution Plan Comparison
```sql
-- Enable actual execution plan
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Bad query (scan)
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2024;

-- Good query (seek)
SELECT * FROM Orders 
WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01';
```

### Demo 3: Covering Index
```sql
-- Create covering index
CREATE NONCLUSTERED INDEX IX_Orders_Covering
ON Orders (CustomerID, OrderDate)
INCLUDE (Amount, Status);

-- Query satisfied by index
SELECT OrderDate, Amount, Status
FROM Orders
WHERE CustomerID = 123;
```

### Demo 4: Implicit Conversion
```sql
-- Create test table
CREATE TABLE TestConversion (
    ID INT PRIMARY KEY,
    Code VARCHAR(10)
);

-- Bad: Implicit conversion
SELECT * FROM TestConversion WHERE Code = N'ABC';

-- Good: Matching types
SELECT * FROM TestConversion WHERE Code = 'ABC';
```

### Demo 5: Parameter Sniffing
```sql
CREATE PROCEDURE Demo_ParameterSniffing 
    @Status VARCHAR(20)
AS
SELECT * FROM Orders WHERE Status = @Status;

-- First call (many rows)
EXEC Demo_ParameterSniffing @Status = 'Pending';

-- Second call (few rows, uses same plan)
EXEC Demo_ParameterSniffing @Status = 'Cancelled';

-- Clear cache and reverse order to see difference
DBCC FREEPROCCACHE;
```

---

## Additional Resources for Slides

### Key Performance Metrics to Show
- Before/After query execution times
- Logical reads (from SET STATISTICS IO)
- CPU time vs. elapsed time
- Index size comparisons
- Fragmentation percentages

### Visual Elements to Consider
- B+-Tree diagrams
- Execution plan operator flow
- Index selection decision tree
- Parameter sniffing timeline
- Fragmentation progression charts

### Common Interview Questions
1. When would you use a clustered vs. nonclustered index?
2. How do you identify a missing index?
3. What's the difference between REBUILD and REORGANIZE?
4. How do implicit conversions affect performance?
5. When would you use a filtered index?
6. What is parameter sniffing and how do you resolve it?
7. What makes a query "sargable"?
