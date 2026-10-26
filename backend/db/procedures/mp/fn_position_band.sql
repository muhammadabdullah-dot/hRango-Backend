-- A position's salary band on a day: the latest range in force on that day, or, when every range
-- starts later, the first one.
CREATE OR ALTER FUNCTION [mp].[fn_position_band] (@position_id BIGINT, @on DATE)
RETURNS TABLE
AS RETURN
SELECT TOP (1) r.min_salary, r.max_salary, r.effective_date
FROM [mp].[position_salary_range] r
WHERE r.position_id = @position_id
ORDER BY CASE WHEN r.effective_date <= @on THEN 0 ELSE 1 END,
         CASE WHEN r.effective_date <= @on THEN r.effective_date END DESC,
         r.effective_date;
