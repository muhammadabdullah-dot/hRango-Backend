-- The leave year a date falls in. The leave year follows the company's fiscal year
-- (org.company.fiscal_year_start_month, January when not set); fiscal_year is the year it starts in.
CREATE OR ALTER FUNCTION [lv].[fn_leave_year] (@company_id BIGINT, @date DATE)
RETURNS TABLE
AS RETURN
SELECT CAST(y.fiscal_year AS SMALLINT) AS fiscal_year,
       DATEFROMPARTS(y.fiscal_year, y.start_month, 1) AS year_start,
       DATEADD(day, -1, DATEADD(year, 1, DATEFROMPARTS(y.fiscal_year, y.start_month, 1))) AS year_end
FROM (
    SELECT m.start_month, YEAR(@date) - CASE WHEN MONTH(@date) < m.start_month THEN 1 ELSE 0 END AS fiscal_year
    FROM (SELECT ISNULL((SELECT CASE WHEN c.fiscal_year_start_month BETWEEN 1 AND 12 THEN c.fiscal_year_start_month END
                         FROM [org].[company] c WHERE c.id = @company_id), 1) AS start_month) m
) y;
GO

-- One employee's balance of one leave type (or of every type when @leave_type_id is NULL) in the
-- leave year that contains @as_of. Types with tenure 'employment' count the whole employment.
--   entitled  credits: opening, allotment, earned, carry_forward, adjustment, overtime
--   used      debits net of restorations: availed, encashed, penalty, restored
--   pending   leave requests submitted and not yet decided (req.request status 'pending')
--   available entitled - used - pending
-- The requests engine calls it for the balance check; lv.usp_request_apply_leave uses it again
-- on final approval.
CREATE OR ALTER FUNCTION [lv].[fn_leave_balance] (@company_id BIGINT, @employee_id BIGINT, @leave_type_id BIGINT, @as_of DATE)
RETURNS TABLE
AS RETURN
SELECT t.id AS leave_type_id,
       CAST(ISNULL(l.entitled, 0) AS DECIMAL(6,2)) AS entitled,
       CAST(ISNULL(l.used, 0) AS DECIMAL(6,2)) AS used,
       CAST(ISNULL(p.pending, 0) AS DECIMAL(6,2)) AS pending,
       CAST(ISNULL(l.entitled, 0) - ISNULL(l.used, 0) - ISNULL(p.pending, 0) AS DECIMAL(6,2)) AS available
FROM [lv].[leave_type] t
JOIN [hr].[employee] e ON e.id = @employee_id AND e.company_id = @company_id
CROSS APPLY [lv].[fn_leave_year](@company_id, ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE))) y
OUTER APPLY (
    SELECT SUM(CASE WHEN g.reason IN (N'availed', N'encashed', N'penalty', N'restored') THEN 0 ELSE g.days END) AS entitled,
           -SUM(CASE WHEN g.reason IN (N'availed', N'encashed', N'penalty', N'restored') THEN g.days ELSE 0 END) AS used
    FROM [lv].[leave_ledger] g
    WHERE g.employee_id = @employee_id AND g.leave_type_id = t.id
      AND (t.tenure = N'employment' OR g.fiscal_year = y.fiscal_year)
) l
OUTER APPLY (
    SELECT SUM(ISNULL(rl.days, r.days)) AS pending
    FROM [req].[request] r
    JOIN [req].[req_leave] rl ON rl.request_id = r.id
    WHERE r.company_id = @company_id AND r.employee_id = @employee_id AND rl.leave_type_id = t.id
      AND r.status = N'pending' AND r.is_deleted = 0
      AND (t.tenure = N'employment' OR r.from_date BETWEEN y.year_start AND y.year_end)
) p
WHERE t.company_id = @company_id AND (@leave_type_id IS NULL OR t.id = @leave_type_id);
