use master;
go

drop database if exists PSPDemo;
go

create database PSPDemo;
go

alter database PSPDemo
set query_store = on
    (
        operation_mode = read_write
      , query_capture_mode = all
      , interval_length_minutes = 1
    );
go

use PSPDemo;
go

create table dbo.Orders
(
    OrderID bigint not null
  , CustomerID int not null
  , OrderDate date not null
  , TotalAmount decimal(12, 2) not null
  , OrderStatus char(1) not null
  , Notes char(100) not null
  , constraint PK_Orders
        primary key clustered (OrderID)
);
go

with E1 (N)
as (select 1
    from
    (
        values
            (0)
          , (0)
          , (0)
          , (0)
          , (0)
          , (0)
          , (0)
          , (0)
          , (0)
          , (0)
    ) as d (N) )
   , E2 (N)
as (select 1
    from E1           as a
        cross join E1 as b)
   , E4 (N)
as (select 1
    from E2           as a
        cross join E2 as b)
   , E6 (N)
as (select 1
    from E4           as a
        cross join E2 as b)
   , Numbers
as (select top (1000000)
           row_number() over (order by (select null)) as n
    from E6)
insert dbo.Orders
(
    OrderID
  , CustomerID
  , OrderDate
  , TotalAmount
  , OrderStatus
  , Notes
)
select n
     , case
           when n <= 400000 then
               1
           else
               2 + convert(int, (n - 400001) / 100)
       end
     , dateadd(day, -convert(int, n % 1095), convert(date, '2025-01-01'))
     , convert(decimal(12, 2), 10.00 + (n % 50000) / 100.0)
     , case n % 4
           when 0 then
               'N'
           when 1 then
               'P'
           when 2 then
               'S'
           else
               'C'
       end
     , replicate(char(65 + n % 26), 100)
from Numbers;
go

create index IX_Orders_CustomerID on dbo.Orders (CustomerID);
go

update statistics dbo.Orders
with fullscan;
go

create or alter procedure dbo.usp_GetCustomerOrders @CustomerID int
as
begin
    set nocount on;

    select OrderID
         , OrderDate
         , TotalAmount
         , OrderStatus
         , Notes
    from dbo.Orders
    where CustomerID = @CustomerID;
end;
GO

select CustomerID
     , count_big(*) as OrderCount
from dbo.Orders
where CustomerID in ( 1, 2, 3000 )
group by CustomerID
order by CustomerID;

ALTER DATABASE PSPDemo SET COMPATIBILITY_LEVEL = 170;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO, TIME ON;
GO
EXEC dbo.usp_GetCustomerOrders @CustomerID = 2; -- compiles for 100 rows
EXEC dbo.usp_GetCustomerOrders @CustomerID = 1; -- reuses that plan for 400,000
GO
SET STATISTICS IO, TIME OFF;

ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO, TIME ON;
GO
EXEC dbo.usp_GetCustomerOrders @CustomerID = 1; -- compiles for 400,000 rows
EXEC dbo.usp_GetCustomerOrders @CustomerID = 2; -- reuses the large-value plan
GO
SET STATISTICS IO, TIME OFF;
GO

ALTER DATABASE PSPDemo SET COMPATIBILITY_LEVEL = 160;
GO
ALTER DATABASE SCOPED CONFIGURATION
SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO, TIME ON;
GO
EXEC dbo.usp_GetCustomerOrders @CustomerID = 2;
EXEC dbo.usp_GetCustomerOrders @CustomerID = 1;
EXEC dbo.usp_GetCustomerOrders @CustomerID = 3000;
EXEC dbo.usp_GetCustomerOrders @CustomerID = 1;
GO
SET STATISTICS IO, TIME OFF;
GO

EXEC sys.sp_query_store_flush_db;
GO

SELECT
    qsp.plan_type,
    qsp.plan_type_desc,
    qsp.plan_id,
    qsp.query_id,
    qsqv.parent_query_id,
    qsqv.query_variant_query_id,
    qsqv.dispatcher_plan_id,
    qsq.count_compiles,
    SUM(ISNULL(qsrs.count_executions, 0)) AS executions,
    MAX(qsrs.last_execution_time) AS last_execution_time,
    CONVERT(xml, qsp.query_plan) AS query_plan
FROM sys.query_store_plan AS qsp
JOIN sys.query_store_query AS qsq
    ON qsq.query_id = qsp.query_id
LEFT JOIN sys.query_store_query_variant AS qsqv
    ON qsqv.query_variant_query_id = qsp.query_id
LEFT JOIN sys.query_store_runtime_stats AS qsrs
    ON qsrs.plan_id = qsp.plan_id
WHERE --qsp.plan_type IN (1, 2)
  --AND
  (
      qsq.object_id = OBJECT_ID(N'dbo.usp_GetCustomerOrders')
      OR qsqv.parent_query_id IN
      (
          SELECT query_id
          FROM sys.query_store_query
          WHERE object_id = OBJECT_ID(N'dbo.usp_GetCustomerOrders')
      )
  )
GROUP BY
    qsp.plan_type,
    qsp.plan_type_desc,
    qsp.plan_id,
    qsp.query_id,
    qsqv.parent_query_id,
    qsqv.query_variant_query_id,
    qsqv.dispatcher_plan_id,
    qsq.count_compiles,
    qsp.query_plan
ORDER BY qsp.plan_type_desc, qsp.plan_id;

SELECT name, compatibility_level
FROM sys.databases
WHERE name = DB_NAME();

SELECT compatibility_level
FROM sys.databases
WHERE database_id = DB_ID();

SELECT name, value, value_for_secondary
FROM sys.database_scoped_configurations
WHERE name IN
(
    'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION',
    'PARAMETER_SNIFFING'
);

SELECT map_key, map_value
FROM sys.dm_xe_map_values
WHERE name = N'psp_skipped_reason_enum'
ORDER BY map_key;
