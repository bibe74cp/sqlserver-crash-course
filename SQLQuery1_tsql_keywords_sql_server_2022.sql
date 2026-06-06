-- 1: GENERATE_SERIES()

WITH Due AS (SELECT 1 AS id UNION SELECT 2)
SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY O1.id, O2.id) 
FROM Due O1
CROSS JOIN Due O2
CROSS JOIN Due O3
CROSS JOIN Due O4
CROSS JOIN Due O5
CROSS JOIN Due O6
CROSS JOIN Due O7;

SELECT * FROM GENERATE_SERIES(1, 1000);

-- 2: GREATEST(), LEAST()

CREATE TABLE dbo.Orders (
    OrderId INT NOT NULL IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
    OrderDate DATE NOT NULL,
    OrderNumber NVARCHAR(10) NOT NULL,
    RequestedDate DATE NULL,
    ApprovedDate DATE NULL,
    EstimatedShipDate DATE NULL
);
GO

INSERT INTO dbo.Orders
(
    OrderDate,
    OrderNumber,
    RequestedDate,
    ApprovedDate,
    EstimatedShipDate
)
VALUES (GETDATE(), N'O-001', '2026-06-15', '2026-06-15', '2026-06-17'),
    (GETDATE(), N'O-002', '2026-06-15', '2026-06-22', '2026-06-21'),
    (GETDATE(), N'O-003', '2026-06-15', '2026-06-12', '2026-06-30'),
    (GETDATE(), N'O-004', '2026-06-15', '2026-06-22', '2026-06-21');
GO

SELECT
    O.OrderId,
    O.OrderDate,
    O.OrderNumber,
    CASE WHEN O.EstimatedShipDate >= O.ApprovedDate AND O.EstimatedShipDate >= O.RequestedDate THEN O.EstimatedShipDate
      WHEN O.ApprovedDate >= O.RequestedDate THEN O.ApprovedDate
      ELSE O.RequestedDate
    END AS MaxDate
FROM dbo.Orders O;
GO

SELECT
    O.OrderId,
    O.OrderDate,
    O.OrderNumber,
    LEAST(O.EstimatedShipDate, O.ApprovedDate, O.RequestedDate) AS MaxDate
FROM dbo.Orders O;
GO

-- 3: DATE_BUCKET()

WITH EventsDetail
AS (
    SELECT 1 AS EventId, CONVERT(DATETIME, '2026-06-04 22:00:15') AS TimestampEvent
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 05:01:30')
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 10:09:30')
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 10:15:30')
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 10:20:30')
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 10:25:30')
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 10:30:30')
    UNION ALL SELECT 2, CONVERT(DATETIME, '2026-06-05 12:35:30')
)
SELECT
    DATEADD(HOUR, 6, DATE_BUCKET(HOUR, 8, DATEADD(HOUR, -6, ED.TimestampEvent))) AS Slot,
    COUNT(1) AS EventCount

FROM EventsDetail ED
GROUP BY DATEADD(HOUR, 6, DATE_BUCKET(HOUR, 8, DATEADD(HOUR, -6, ED.TimestampEvent)));
GO

-- 4: WINDOW

WITH TableData
AS (
    SELECT 1 AS EmployeeId, 'Production' AS Department, 1000 AS Salary
    UNION ALL SELECT 2, 'Production', 2000
    UNION ALL SELECT 3, 'Production', 2000
    UNION ALL SELECT 4, 'Sales', 3000
)

SELECT
    TD.EmployeeId,
    TD.Department,
    TD.Salary,
    ROW_NUMBER() OVER (PARTITION BY TD.Department ORDER BY TD.Salary DESC) AS rownumber_,
    RANK() OVER (PARTITION BY TD.Department ORDER BY TD.Salary DESC) AS rank_,
    DENSE_RANK() OVER (PARTITION BY TD.Department ORDER BY TD.Salary DESC) AS denserank_,
    ROW_NUMBER() OVER w,
    RANK() OVER w,
    DENSE_RANK() OVER w,
    SUM(TD.Salary) OVER w

FROM TableData TD
WINDOW w AS (PARTITION BY TD.Department ORDER BY TD.Salary DESC)
ORDER BY TD.Department, rownumber_;
