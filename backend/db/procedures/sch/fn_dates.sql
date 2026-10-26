-- Every date from @from to @to (at most 10,000 days), with its weekday: 1 = Monday ... 7 = Sunday,
-- whatever SET DATEFIRST says. Nothing when @to is before @from.
CREATE OR ALTER FUNCTION [sch].[fn_dates] (@from DATE, @to DATE)
RETURNS TABLE
AS RETURN
WITH t10 AS (SELECT n FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) v (n)),
t AS (SELECT a.n + b.n * 10 + c.n * 100 + d.n * 1000 AS n FROM t10 a CROSS JOIN t10 b CROSS JOIN t10 c CROSS JOIN t10 d)
SELECT DATEADD(DAY, t.n, @from) AS d,
       DATEDIFF(DAY, CAST('19000101' AS DATE), DATEADD(DAY, t.n, @from)) % 7 + 1 AS weekday
FROM t
WHERE t.n <= DATEDIFF(DAY, @from, @to);
GO

-- The dates a repeat pattern picks between @from and @to, as Create Scheduling and Create New Rest
-- Day draw it: @weekdays is "1,2,3" (1 = Monday; blank = every day); @repeat_every_weeks 0 = no
-- repeat (every week in the range), n = a cycle of n weeks counted from the Monday of @from's week,
-- of which the first @step weeks are on. Every 3 weeks with step 2 = two weeks on, one week off.
CREATE OR ALTER FUNCTION [sch].[fn_pattern_dates] (@from DATE, @to DATE, @weekdays NVARCHAR(30),
                                                  @repeat_every_weeks INT, @step INT)
RETURNS TABLE
AS RETURN
SELECT d.d, d.weekday
FROM [sch].[fn_dates](@from, @to) d
WHERE (NULLIF(LTRIM(RTRIM(@weekdays)), N'') IS NULL
       OR d.weekday IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@weekdays, N',')))
  AND (ISNULL(@repeat_every_weeks, 0) = 0
       OR (DATEDIFF(DAY, DATEADD(DAY, -(DATEDIFF(DAY, CAST('19000101' AS DATE), @from) % 7), @from), d.d) / 7)
            % @repeat_every_weeks < ISNULL(@step, 1));
