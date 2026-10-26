-- Plan years of a company as the Plan Years list shows them. Status follows today's date. The election
-- and missing-information counts cover the employees the user reaches through Employee Elections
-- (benefits.elections.view), so a user who cannot see elections sees zeros.
CREATE OR ALTER FUNCTION [ben].[fn_plan_year_rows] (@company_id BIGINT, @actor_user_id BIGINT)
RETURNS TABLE
AS RETURN
WITH v AS (
    SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'benefits.elections.view')
)
SELECT y.id, y.name, y.start_date, y.end_date,
       CASE WHEN CAST(SYSUTCDATETIME() AS DATE) < y.start_date THEN N'upcoming'
            WHEN CAST(SYSUTCDATETIME() AS DATE) > y.end_date THEN N'ended' ELSE N'active' END AS status,
       y.new_hire_start, y.waiting_period_days, y.election_period, y.election_unit,
       (SELECT STRING_AGG(CAST(pp.benefit_plan_id AS NVARCHAR(20)), N',') FROM [ben].[plan_year_plan] pp
        WHERE pp.plan_year_id = y.id) AS plan_ids,
       (SELECT COUNT(*) FROM [ben].[plan_year_plan] pp WHERE pp.plan_year_id = y.id) AS plan_count,
       (SELECT COUNT(*) FROM [ben].[enrollment_window] w WHERE w.plan_year_id = y.id) AS window_count,
       (SELECT COUNT(*) FROM [ben].[election] e JOIN v ON v.employee_id = e.employee_id
        WHERE e.plan_year_id = y.id AND e.status = N'pending') AS pending,
       (SELECT COUNT(*) FROM [ben].[election] e JOIN v ON v.employee_id = e.employee_id
        WHERE e.plan_year_id = y.id AND e.status = N'approved') AS approved,
       (SELECT COUNT(*) FROM [ben].[election] e JOIN v ON v.employee_id = e.employee_id
        WHERE e.plan_year_id = y.id AND e.status = N'incomplete') AS incomplete,
       (SELECT COUNT(*) FROM [hr].[employee] em JOIN v ON v.employee_id = em.id
        WHERE em.status <> N'left' AND (em.date_of_birth IS NULL OR em.marital_status IS NULL)) AS missing_information,
       y.created_at, cb.name AS created_by_name, y.updated_at, y.row_version
FROM [ben].[plan_year] y
OUTER APPLY [ben].[fn_actor_name](y.created_by) cb
WHERE y.company_id = @company_id;
