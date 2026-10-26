-- Manpower plans of a company as the list and the form header show them. is_locked: a plan with an
-- approved budget can no longer change.
CREATE OR ALTER FUNCTION [mp].[fn_plan_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.title, p.budget_duration_id, d.name AS budget_duration_name, d.is_current,
       p.division_id, dv.name AS division_name, p.branch_id, br.name AS branch_name,
       p.department_id, dp.name AS department_name, p.sub_department_id, sd.name AS sub_department_name,
       p.employee_group_id, eg.name AS employee_group_name, p.description,
       p.monthly_amount, p.annual_amount, p.status, p.submitted_at,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM [mp].[manpower_plan_line] l WHERE l.manpower_plan_id = p.id AND l.kind = N'new_position')
                 THEN 1 ELSE 0 END AS BIT) AS has_new_positions,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM [mp].[manpower_plan_line] l WHERE l.manpower_plan_id = p.id AND l.kind = N'existing_employee')
                 THEN 1 ELSE 0 END AS BIT) AS has_existing_positions,
       (SELECT COUNT(*) FROM [mp].[e_budget] b WHERE b.manpower_plan_id = p.id) AS budget_count,
       (SELECT COUNT(*) FROM [mp].[e_budget] b WHERE b.manpower_plan_id = p.id AND b.status = N'approved') AS approved_budget_count,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM [mp].[e_budget] b WHERE b.manpower_plan_id = p.id AND b.status = N'approved')
                 THEN 1 ELSE 0 END AS BIT) AS is_locked,
       p.created_at, cb.name AS created_by_name, p.updated_at, ub.name AS updated_by_name, p.row_version
FROM [mp].[manpower_plan] p
JOIN [mp].[budget_duration] d ON d.id = p.budget_duration_id
LEFT JOIN [org].[division] dv ON dv.id = p.division_id
LEFT JOIN [org].[branch] br ON br.id = p.branch_id
LEFT JOIN [org].[department] dp ON dp.id = p.department_id
LEFT JOIN [org].[department] sd ON sd.id = p.sub_department_id
LEFT JOIN [org].[employee_group] eg ON eg.id = p.employee_group_id
OUTER APPLY [mp].[fn_actor_name](p.created_by) cb
OUTER APPLY [mp].[fn_actor_name](p.updated_by) ub
WHERE p.company_id = @company_id;
