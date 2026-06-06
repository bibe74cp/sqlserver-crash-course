# SQL Server Performance Demo Project

This project contains comprehensive SQL demonstrations for a SQL Server performance optimization presentation.

## Project Structure

All SQL files create and use the `PerformanceDemo` database. Run them in order or independently as needed.

### Demo Files

1. **01_Index_Structures_And_Fragmentation.sql**
   - Heap tables vs. clustered indexes
   - B+-Tree structure visualization
   - Index fragmentation demonstration
   - Rebuild vs. Reorganize comparison
   - Automated maintenance script

2. **02_Execution_Plans.sql**
   - Table Scan vs. Index Seek
   - Key Lookups and their impact
   - JOIN operators (Nested Loop, Hash Match, Merge Join)
   - Sort operators and optimization
   - Missing index hints
   - Parallelism demonstration
   - Actual vs. Estimated rows
   - Warning detection (implicit conversions)

3. **03_Index_Types.sql**
   - Clustered index implementation
   - Nonclustered indexes
   - Covering indexes with INCLUDE clause
   - Filtered indexes for sparse data
   - Composite index column order
   - Index usage statistics
   - Missing index recommendations

4. **04_Query_Operator_Order.sql**
   - Logical query processing order (FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY)
   - Column alias usage limitations
   - WHERE vs. HAVING filter placement
   - TOP and OFFSET-FETCH
   - DISTINCT vs. GROUP BY
   - Common mistakes and solutions

5. **05_Implicit_Conversions.sql**
   - VARCHAR vs. NVARCHAR conversions
   - Numeric type mismatches
   - INT vs. BIGINT in JOINs
   - Date/Time function issues
   - Detection using execution plans
   - DMV queries for finding conversions
   - Collation conflicts
   - Performance impact measurement

6. **06_Query_Worst_Patterns.sql**
   - Functions on columns in WHERE clause
   - Leading wildcards in LIKE
   - OR conditions across columns
   - RBAR (Row-By-Agonizing-Row) with cursors
   - SELECT * anti-pattern
   - NOT IN with NULLs
   - Correlated subqueries in SELECT
   - Unnecessary DISTINCT
   - Row-by-row updates

7. **07_Query_Best_Patterns.sql**
   - Filter early and often
   - EXISTS vs. IN vs. JOIN
   - Common Table Expressions (CTEs)
   - Window functions instead of self-joins
   - CROSS APPLY for top N per group
   - Batch processing for large updates
   - Index-friendly JOINs
   - Temp tables vs. table variables vs. CTEs
   - Covering indexes
   - Proper data types
   - Parameterized queries

8. **08_Table_Valued_Functions.sql**
   - Inline Table-Valued Functions (iTVF) - BEST PRACTICE
   - Multi-Statement Table-Valued Functions (mTVF) - AVOID
   - Performance comparison
   - Scalar UDF anti-pattern
   - Alternatives to mTVFs
   - Migration from mTVF to iTVF

9. **09_Parameter_Sniffing.sql**
   - Parameter sniffing demonstration
   - Solution 1: OPTIMIZE FOR hint
   - Solution 2: OPTIMIZE FOR UNKNOWN
   - Solution 3: RECOMPILE (procedure level)
   - Solution 4: RECOMPILE (query level)
   - Solution 5: Local variable copy
   - Solution 6: Dynamic SQL
   - Solution 7: Branch logic
   - SQL Server 2022: Parameter Sensitive Plans (PSP)
   - Detection using DMVs
   - Decision matrix for choosing solutions

## Getting Started

### Prerequisites
- SQL Server 2016 or later (2022+ for PSP features)
- SQL Server Management Studio (SSMS) 18.0 or later
- Permissions to create database, tables, and procedures

### Installation

1. Open SQL Server Management Studio
2. Connect to your SQL Server instance
3. Open any demo file(s) you want to run
4. Execute the script (F5)

**Note**: The first script (01) creates the `PerformanceDemo` database. Other scripts use this database.

## Usage

### Running Individual Demos

Each file is self-contained with:
- Database creation (if needed)
- Table creation
- Sample data insertion
- Multiple demonstration queries with explanations
- Cleanup scripts (commented out at the end)

### Viewing Execution Plans

Most demos benefit from viewing execution plans:
1. Enable "Include Actual Execution Plan" (Ctrl+M) before running queries
2. Or click the "Include Actual Execution Plan" button in SSMS toolbar
3. After query execution, click the "Execution Plan" tab to view

### Interpreting Results

Look for:
- **STATISTICS IO**: Logical reads, physical reads, read-ahead reads
- **STATISTICS TIME**: CPU time vs. elapsed time
- **Execution Plans**: Operator types, row counts, costs, warnings
- **Performance differences**: Before/after optimization comparisons

## Key Concepts Covered

### Indexes
- When to use clustered vs. nonclustered
- Covering indexes with INCLUDE clause
- Filtered indexes for sparse data
- Fragmentation monitoring and maintenance

### Query Optimization
- Sargable vs. non-sargable predicates
- Set-based operations vs. RBAR
- Proper JOIN techniques
- Window functions for analytics

### Common Issues
- Implicit type conversions
- Parameter sniffing
- Missing statistics
- Inefficient T-SQL patterns

### Best Practices
- Filter early in query execution
- Use appropriate index types
- Avoid scalar UDFs (use inline TVFs)
- Keep statistics updated
- Choose proper data types

## Performance Tips

1. **Always test with realistic data volumes**
   - Small datasets may not show performance differences
   - Consider data distribution (skewed vs. uniform)

2. **Clear plan cache between tests** (use cautiously!)
   ```sql
   DBCC FREEPROCCACHE;
   DBCC DROPCLEANBUFFERS; -- Only in dev/test!
   ```

3. **Monitor resource usage**
   - SET STATISTICS IO ON
   - SET STATISTICS TIME ON
   - Review execution plans

4. **Update statistics regularly**
   ```sql
   UPDATE STATISTICS TableName WITH FULLSCAN;
   ```

## Troubleshooting

### Script fails with "Database already exists"
The first script creates the database. If it exists:
```sql
USE master;
DROP DATABASE PerformanceDemo;
```
Then re-run the script.

### Sample data takes too long to insert
Some scripts insert large datasets (50K-100K rows). This is intentional to demonstrate performance differences. Be patient or reduce the row counts in the INSERT statements.

### Execution plan shows different operators than expected
- Ensure indexes are created (check index creation scripts)
- Update statistics: `UPDATE STATISTICS TableName WITH FULLSCAN;`
- Check SQL Server version (some features require newer versions)
- Data distribution affects optimizer choices

## Cleanup

To remove all demo objects:

```sql
USE master;
GO

-- Drop all procedures and functions (run each demo's cleanup section first)
-- Then drop the database
DROP DATABASE PerformanceDemo;
GO
```

Or run the commented CLEANUP sections at the end of each file.

## Contributing

This is a demonstration project for presentations. Suggestions for improvements:
- Additional demo scenarios
- Performance comparisons
- Real-world examples
- SQL Server version-specific features

## Additional Resources

- [Microsoft SQL Server Documentation](https://docs.microsoft.com/en-us/sql/sql-server/)
- [Execution Plan Basics](https://docs.microsoft.com/en-us/sql/relational-databases/performance/execution-plans)
- [Index Design Guide](https://docs.microsoft.com/en-us/sql/relational-databases/sql-server-index-design-guide)
- [Query Tuning Guide](https://docs.microsoft.com/en-us/sql/relational-databases/performance/query-processing-architecture-guide)

## License

Free to use for educational and presentation purposes.

## Author

Created for SQL Server performance optimization training and presentations.

---

**Note**: Run these scripts in a development or test environment. Some scripts deliberately create performance issues to demonstrate problems and solutions. Do not run in production without understanding the impact.
