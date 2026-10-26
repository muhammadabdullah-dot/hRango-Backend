-- E-budgets of a company as E-Budgeting and Budget Approvals show them. branch_id is the plan's station,
-- used with department_id for scope.
CREATE OR ALTER FUNCTION [mp].[fn_budget_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT b.id, b.title, b.budget_duration_id, d.name AS budget_duration_name,
       b.manpower_plan_id, p.title AS plan_title,
       b.job_title_id, jt.name AS job_title_name, b.department_id, dp.name AS department_name,
       p.branch_id, b.amount, b.total_positions, b.start_date, b.end_date, b.status,
       b.decided_by_user_id, db.name AS decided_by_name, b.decided_at, b.remarks,
       (SELECT COUNT(*) FROM [mp].[open_position] o WHERE o.e_budget_id = b.id) AS open_position_count,
       b.created_at, cb.name AS created_by_name, b.updated_at, b.row_version
FROM [mp].[e_budget] b
JOIN [mp].[budget_duration] d ON d.id = b.budget_duration_id
LEFT JOIN [mp].[manpower_plan] p ON p.id = b.manpower_plan_id
LEFT JOIN [org].[job_title] jt ON jt.id = b.job_title_id
LEFT JOIN [org].[department] dp ON dp.id = b.department_id
OUTER APPLY [mp].[fn_actor_name](b.created_by) cb
OUTER APPLY [mp].[fn_actor_name](b.decided_by_user_id) db
WHERE b.company_id = @company_id;
