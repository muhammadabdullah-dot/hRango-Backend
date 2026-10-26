-- Enrollment windows of a company: open until their last day (closes_on), then closed. No employees
-- listed means everyone may enrol.
CREATE OR ALTER FUNCTION [ben].[fn_window_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT w.id, w.name, w.kind, w.plan_year_id, y.name AS plan_year_name, w.effective_date, w.closes_on,
       CASE WHEN CAST(SYSUTCDATETIME() AS DATE) <= w.closes_on THEN N'open' ELSE N'closed' END AS status,
       w.description,
       (SELECT STRING_AGG(CAST(wp.benefit_plan_id AS NVARCHAR(20)), N',') FROM [ben].[enrollment_window_plan] wp
        WHERE wp.enrollment_window_id = w.id) AS plan_ids,
       (SELECT STRING_AGG(CAST(we.employee_id AS NVARCHAR(20)), N',') FROM [ben].[enrollment_window_employee] we
        WHERE we.enrollment_window_id = w.id) AS employee_ids,
       (SELECT COUNT(*) FROM [ben].[election] e WHERE e.enrollment_window_id = w.id) AS election_count,
       w.created_at, cb.name AS created_by_name, w.updated_at, w.row_version
FROM [ben].[enrollment_window] w
JOIN [ben].[plan_year] y ON y.id = w.plan_year_id
OUTER APPLY [ben].[fn_actor_name](w.created_by) cb
WHERE w.company_id = @company_id;
