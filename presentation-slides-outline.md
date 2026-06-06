# SQL Server Performance Optimization - Slide Deck Outline

## Slide 1: Title Slide
**Title:** SQL Server Performance Optimization  
**Subtitle:** Indexes, Execution Plans, and Query Optimization  
**Content:**
- Presenter Name
- Date
- Company/Organization Logo

---

## Slide 2: Agenda
**Title:** Today's Topics  
**Content:**
1. Index Structures and Maintenance
2. Reading and Optimizing Execution Plans
3. Advanced Index Techniques
4. Query Processing Order
5. Implicit Conversions
6. Query Anti-Patterns to Avoid
7. Query Best Practices
8. Table-Valued Functions
9. Parameter Sniffing Solutions

---

## Slide 3: Section 1 - Index Structures
**Title:** Index Storage Structures  
**Content:**
- **Heap Tables**: No clustered index, unordered storage
  - Fast inserts, slow reads
  - Best for: staging tables, small lookup tables
- **B+-Tree**: SQL Server's index implementation
  - All data in leaf nodes
  - 3-4 levels for millions of rows
  - Efficient range scans via linked leaf nodes

---

## Slide 4: B+-Tree Structure Diagram
**Title:** How B+-Tree Indexes Work  
**Content:**
- Visual diagram showing:
  - Root node
  - Intermediate nodes (keys and pointers only)
  - Leaf nodes (all data, linked)
- Key advantages:
  - Balanced structure
  - Sequential access at leaf level
  - Better cache utilization

---

## Slide 5: Index Fragmentation
**Title:** Understanding Index Fragmentation  
**Content:**
- **Logical Fragmentation**: Pages not physically sequential
  - Measured: avg_fragmentation_in_percent
  - Causes: INSERTs, UPDATEs, DELETEs
  - Impact: More physical I/O for scans
- **Page Density**: avg_page_space_used_in_percent
  - Low density = wasted space
  - High density = good utilization

---

## Slide 6: Rebuild vs. Reorganize
**Title:** Index Maintenance Strategies  
**Content:**

| Fragmentation Level | Action | Operation |
|---------------------|--------|-----------|
| < 10% | Do Nothing | N/A |
| 10-30% | Reorganize | Online, minimal locks |
| > 30% | Rebuild | Complete defragmentation |

**Key Differences:**
- Rebuild: Drops/recreates, updates statistics
- Reorganize: Compacts pages, minimal space

---

## Slide 7: Demo 1
**Title:** DEMO: Index Fragmentation  
**Content:**
- Check fragmentation levels
- Create fragmentation through random inserts
- Compare Rebuild vs. Reorganize
- Show performance improvement
- DMV: sys.dm_db_index_physical_stats

---

## Slide 8: Section 2 - Execution Plans
**Title:** Reading Execution Plans  
**Content:**
- **Direction**: Right to left, top to bottom
- **Thick arrows**: More rows flowing
- **Color coding**:
  - Black/Blue: Normal operation
  - Yellow triangle: Warnings
- **Relative cost**: Resource consumption percentages
- **Key**: Focus on highest cost operators

---

## Slide 9: Key Execution Plan Operators
**Title:** Common Operators to Recognize  
**Content:**
- **Scans** (Read everything):
  - Table Scan, Clustered Index Scan, Index Scan
- **Seeks** (Targeted read - GOOD):
  - Index Seek, Clustered Index Seek
- **Joins**:
  - Nested Loop (small datasets)
  - Hash Match (large unsorted)
  - Merge Join (large sorted)
- **Key Lookup**: Additional data retrieval (often problematic)

---

## Slide 10: Execution Plan Warnings
**Title:** Interpreting Plan Warnings  
**Content:**
- **Yellow exclamation marks** indicate:
  - Implicit type conversions
  - Missing statistics
  - Excessive memory grants
  - Spills to tempdb
- **Missing Index hints** (green text):
  - Take with caution
  - Evaluate cost vs. benefit
  - May suggest too many indexes

---

## Slide 11: Optimization Strategies
**Title:** How to Optimize Based on Plans  
**Content:**
1. **Eliminate Scans** → Add appropriate indexes
2. **Reduce Key Lookups** → Covering indexes
3. **Avoid Sorts** → Index matches ORDER BY
4. **Fix Conversions** → Match data types
5. **Update Statistics** → Accurate estimates
6. **Rewrite Logic** → Sometimes better than indexes

---

## Slide 12: Demo 2
**Title:** DEMO: Execution Plans  
**Content:**
- Compare Scan vs. Seek performance
- Show Key Lookup overhead
- Demonstrate different JOIN operators
- Fix a slow query using execution plan
- Before/After metrics (IO, time)

---

## Slide 13: Section 3 - Index Types
**Title:** Clustered vs. Nonclustered Indexes  
**Content:**
- **Clustered Index**:
  - Determines physical row order
  - One per table
  - Leaf level = actual data
  - Choose: Narrow, unique, static, increasing
- **Nonclustered Index**:
  - Separate structure from data
  - Up to 999 per table (don't!)
  - Leaf level = key + bookmark
  - Overhead on writes

---

## Slide 14: Covering Indexes
**Title:** Covering Indexes with INCLUDE  
**Content:**
```sql
CREATE NONCLUSTERED INDEX IX_Example
ON Orders (CustomerID, OrderDate)
INCLUDE (Amount, Status);
```
**Benefits:**
- Query satisfied entirely from index
- No bookmark lookup needed
- INCLUDE: Columns only in leaf level
- Key columns: WHERE, JOIN, GROUP BY, ORDER BY
- INCLUDE columns: SELECT list only

---

## Slide 15: Filtered Indexes
**Title:** Indexes on Subsets of Data  
**Content:**
```sql
CREATE NONCLUSTERED INDEX IX_ActiveOrders
ON Orders (OrderDate, CustomerID)
WHERE Status = 'Active';
```
**Use Cases:**
- Sparse columns (e.g., EndDate IS NULL)
- Status-based filtering (Active records)
- Current year data only
- 90% smaller than full index

---

## Slide 16: Demo 3
**Title:** DEMO: Index Types  
**Content:**
- Create covering index
- Show elimination of Key Lookups
- Demonstrate filtered index benefits
- Compare index sizes
- Index usage statistics (DMVs)

---

## Slide 17: Section 4 - Query Processing Order
**Title:** Logical Query Processing Order  
**Content:**
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
**Key Point**: Logical ≠ Physical execution order

---

## Slide 18: Common Mistakes - Processing Order
**Title:** Order-Related Mistakes  
**Content:**
**WRONG:**
```sql
SELECT Price * Quantity AS Total
FROM Orders
WHERE Total > 1000;  -- Error!
```
**CORRECT:**
```sql
SELECT Price * Quantity AS Total
FROM Orders
WHERE Price * Quantity > 1000;
```
**Why?** WHERE executes before SELECT

---

## Slide 19: WHERE vs. HAVING
**Title:** Filter Early with WHERE  
**Content:**
- **WHERE**: Filters before aggregation (EFFICIENT)
- **HAVING**: Filters after aggregation (LESS EFFICIENT)

**Best Practice:**
```sql
SELECT CustomerID, COUNT(*) AS OrderCount
FROM Orders
WHERE OrderDate >= '2024-01-01'  -- Filter early
GROUP BY CustomerID
HAVING COUNT(*) > 5;  -- Filter groups
```

---

## Slide 20: Section 5 - Implicit Conversions
**Title:** The Hidden Performance Killer  
**Content:**
- SQL Server auto-converts mismatched data types
- **Problem**: Prevents index usage
- **Detection**: CONVERT_IMPLICIT in plan, yellow warning

**Example:**
```sql
-- BAD: NVARCHAR literal on VARCHAR column
WHERE Username = N'john'  -- Index scan

-- GOOD: Matching types
WHERE Username = 'john'   -- Index seek
```

---

## Slide 21: Common Conversion Scenarios
**Title:** Where Conversions Hide  
**Content:**
1. **VARCHAR vs NVARCHAR**: N prefix on literals
2. **Numeric precision**: INT vs DECIMAL/FLOAT
3. **JOIN mismatches**: INT vs BIGINT
4. **Date functions**: CONVERT(DATE, column)

**Impact:**
- Index seeks become scans
- CPU overhead
- Inaccurate cardinality
- Query timeouts

---

## Slide 22: Demo 4
**Title:** DEMO: Implicit Conversions  
**Content:**
- Show conversion warning in plan
- Compare performance: with vs without
- Fix JOIN type mismatch
- DMV query to find conversions
- Before/After logical reads

---

## Slide 23: Section 6 - Query Anti-Patterns
**Title:** Worst Patterns That Kill Performance  
**Content:**
1. **Functions on columns** in WHERE
2. **Leading wildcards** in LIKE
3. **OR across columns**
4. **RBAR** (Row-By-Agonizing-Row)
5. **SELECT ***
6. **NOT IN** with NULLs
7. **Correlated subqueries** in SELECT

---

## Slide 24: Anti-Pattern 1 - Functions in WHERE
**Title:** Functions Prevent Index Usage  
**Content:**
**BAD:**
```sql
WHERE YEAR(OrderDate) = 2024
WHERE UPPER(LastName) = 'SMITH'
```
Result: Index Scan

**GOOD (Sargable):**
```sql
WHERE OrderDate >= '2024-01-01' 
  AND OrderDate < '2025-01-01'
WHERE LastName = 'Smith'
```
Result: Index Seek

---

## Slide 25: Anti-Pattern 2 - RBAR
**Title:** Row-By-Agonizing-Row Processing  
**Content:**
**BAD:** Cursors
```sql
DECLARE cur CURSOR FOR SELECT CustomerID FROM Customers;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE Orders SET Status = 'Processed' 
    WHERE CustomerID = @CustomerID;
END
```

**GOOD:** Set-based
```sql
UPDATE Orders SET Status = 'Processed'
FROM Orders O
INNER JOIN Customers C ON O.CustomerID = C.CustomerID;
```

---

## Slide 26: Demo 5
**Title:** DEMO: Anti-Patterns  
**Content:**
- Function in WHERE: Before/After
- RBAR vs Set-based: Performance comparison
- SELECT * vs specific columns
- NOT IN vs NOT EXISTS with NULLs
- Show execution time differences

---

## Slide 27: Section 7 - Best Practices
**Title:** Query Best Patterns  
**Content:**
1. **Filter early and often**
2. **EXISTS vs IN** (EXISTS stops at first match)
3. **CTEs** for readability
4. **Window functions** vs self-joins
5. **CROSS APPLY** for top N per group
6. **Batch updates** for large data
7. **Covering indexes**

---

## Slide 28: Best Practice - CTEs
**Title:** Common Table Expressions  
**Content:**
```sql
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
SELECT AC.CustomerName, COUNT(*) AS OrderCount
FROM ActiveCustomers AC
JOIN RecentOrders RO ON AC.CustomerID = RO.CustomerID
GROUP BY AC.CustomerName;
```
**Benefits:** Readable, maintainable, easier debugging

---

## Slide 29: Best Practice - Window Functions
**Title:** Window Functions vs Self-Joins  
**Content:**
**OLD (Slow):**
```sql
SELECT O1.OrderDate, 
       (SELECT SUM(Amount) FROM Orders O2 
        WHERE O2.OrderDate <= O1.OrderDate) AS RunningTotal
FROM Orders O1;
```

**BETTER (Fast):**
```sql
SELECT OrderDate,
       SUM(Amount) OVER (ORDER BY OrderDate 
                         ROWS UNBOUNDED PRECEDING) AS RunningTotal
FROM Orders;
```

---

## Slide 30: Demo 6
**Title:** DEMO: Best Practices  
**Content:**
- CTE readability example
- Window function performance
- CROSS APPLY for top N per group
- Batch update vs single update
- Covering index elimination of lookups

---

## Slide 31: Section 8 - Table-Valued Functions
**Title:** Inline vs Multi-Statement TVFs  
**Content:**

| Aspect | Inline TVF | Multi-Statement TVF |
|--------|-----------|---------------------|
| Performance | Excellent | Poor |
| Optimization | Fully integrated | Black box |
| Cardinality | Accurate | Fixed (100 rows) |
| Parallelism | Yes | No |
| Statistics | Yes | No |
| **When to Use** | **Almost always** | Only if procedural logic required |

---

## Slide 32: Inline TVF Example
**Title:** The Right Way: Inline TVFs  
**Content:**
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
**Acts like a parameterized view** - optimizer can see through it!

---

## Slide 33: Demo 7
**Title:** DEMO: Table-Valued Functions  
**Content:**
- Create inline TVF
- Create multi-statement TVF
- Performance comparison (same logic)
- Execution plan differences
- Scalar UDF anti-pattern (avoid!)

---

## Slide 34: Section 9 - Parameter Sniffing
**Title:** What is Parameter Sniffing?  
**Content:**
- SQL Server compiles proc with **first parameter values**
- Plan cached and reused for all executions
- **The Good**: Efficient plan reuse
- **The Bad**: Plan optimal for first value, terrible for others

**Example:**
- First call: @Status = 'Pending' (1000 rows) → Index Scan
- Second call: @Status = 'Cancelled' (3 rows) → Uses same Scan!

---

## Slide 35: Detecting Parameter Sniffing
**Title:** How to Identify the Problem  
**Content:**
**Symptoms:**
- Same procedure fast sometimes, slow others
- Performance varies with parameter values
- Same plan for different row counts

**Detection:**
- Execution plan shows same shape for different params
- DMV: sys.dm_exec_query_stats (variance in times)
- Extended Events: parameter_sensitive_plan_optimization

---

## Slide 36: Parameter Sniffing Solutions (1/2)
**Title:** Solutions 1-4  
**Content:**

**1. OPTIMIZE FOR hint**
```sql
OPTION (OPTIMIZE FOR (@Status = 'Pending'))
```
Use when: One value is 90%+ of calls

**2. OPTIMIZE FOR UNKNOWN**
```sql
OPTION (OPTIMIZE FOR UNKNOWN)
```
Use when: Even distribution of values

---

## Slide 37: Parameter Sniffing Solutions (2/2)
**Title:** Solutions 5-7  
**Content:**

**3. RECOMPILE**
```sql
WITH RECOMPILE  -- or OPTION (RECOMPILE)
```
Use when: High sensitivity, low frequency

**4. Local variable copy**
```sql
DECLARE @StatusLocal VARCHAR(20) = @Status;
WHERE Status = @StatusLocal;
```

**5. Dynamic SQL** (fresh plan each time)

**6. Multiple procedures** (branch logic)

**7. SQL 2022: Parameter Sensitive Plans (PSP)** - Automatic!

---

## Slide 38: Parameter Sniffing Decision Matrix
**Title:** Choosing the Right Solution  
**Content:**

| Scenario | Solution |
|----------|----------|
| One value dominates (90%+) | OPTIMIZE FOR value |
| Even distribution | OPTIMIZE FOR UNKNOWN |
| Extreme sensitivity | RECOMPILE |
| Ad-hoc reporting | Dynamic SQL |
| SQL Server 2022+ | Enable PSP |

**SQL 2022 PSP:** Automatically detects and creates multiple plans!

---

## Slide 39: Demo 8
**Title:** DEMO: Parameter Sniffing  
**Content:**
- Show problem: Same plan, different data
- OPTIMIZE FOR solution
- OPTIMIZE FOR UNKNOWN comparison
- RECOMPILE overhead measurement
- Clear cache: DBCC FREEPROCCACHE
- Performance metrics comparison

---

## Slide 40: Key Performance Metrics
**Title:** What to Measure  
**Content:**
**Always monitor:**
- Logical reads (SET STATISTICS IO)
- CPU time vs Elapsed time
- Execution plan warnings
- Index fragmentation %
- Plan cache reuse

**DMVs to know:**
- sys.dm_db_index_physical_stats
- sys.dm_exec_query_stats
- sys.dm_db_index_usage_stats
- sys.dm_exec_cached_plans

---

## Slide 41: Common Interview Questions
**Title:** Test Your Knowledge  
**Content:**
1. When would you use clustered vs nonclustered index?
2. How do you identify a missing index?
3. What's the difference between REBUILD and REORGANIZE?
4. How do implicit conversions affect performance?
5. When would you use a filtered index?
6. What is parameter sniffing and how do you resolve it?
7. What makes a query "sargable"?

---

## Slide 42: Best Practices Summary
**Title:** Key Takeaways  
**Content:**
✅ **Monitor fragmentation** - Rebuild > 30%, Reorganize 10-30%  
✅ **Read execution plans** - Focus on scans, lookups, warnings  
✅ **Use covering indexes** - INCLUDE clause for non-key columns  
✅ **Filter early** - WHERE before joins when possible  
✅ **Avoid functions on columns** - Use sargable predicates  
✅ **Prefer inline TVFs** - Never scalar UDFs  
✅ **Match data types** - Prevent implicit conversions  
✅ **Handle parameter sniffing** - Choose appropriate solution  

---

## Slide 43: Tools and Resources
**Title:** Additional Resources  
**Content:**
**Tools:**
- SQL Server Management Studio (SSMS)
- SQL Server Profiler
- Extended Events
- Database Tuning Advisor
- Query Store (SQL 2016+)

**Documentation:**
- Microsoft SQL Server Docs
- Execution Plan Reference
- Index Design Guide
- Query Performance Tuning Guide

---

## Slide 44: Demo Code Repository
**Title:** Hands-On Practice  
**Content:**
**GitHub/Code Repository:**
- All demo scripts available
- 9 comprehensive SQL files
- Sample database creation
- Performance comparison examples
- README with setup instructions

**Database:** PerformanceDemo  
**Files:** 01-09 covering all topics

---

## Slide 45: Q&A
**Title:** Questions?  
**Content:**
- Open discussion
- Specific scenarios
- Real-world challenges
- Additional examples

**Contact Information:**
- Email
- LinkedIn
- GitHub

---

## Slide 46: Thank You
**Title:** Thank You!  
**Content:**
**Key Message:**
Performance optimization is an ongoing process:
- Monitor continuously
- Test changes
- Update statistics
- Review execution plans
- Stay current with new features

**Remember:** The best optimization is the one that solves YOUR specific problem!

---

**Total Slides: 46**
