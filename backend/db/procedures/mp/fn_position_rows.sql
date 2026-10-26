-- Employee positions of a company as the lists and forms show them: names beside ids and the salary band
-- in force today. Used by mp.usp_position_get / _list.
CREATE OR ALTER FUNCTION [mp].[fn_position_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.code, p.status,
       p.job_title_id, jt.name AS job_title_name,
       p.branch_id, br.name AS branch_name,
       p.employee_group_id, eg.name AS employee_group_name,
       p.division_id, dv.name AS division_name,
       p.department_id, dp.name AS department_name,
       p.sub_department_id, sd.name AS sub_department_name,
       p.cost_center_id, cc.name AS cost_center_name,
       p.grade_id, gr.name AS grade_name,
       p.reports_to_id, rt.code AS reports_to_code, rtj.name AS reports_to_title,
       p.employee_id, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
       band.min_salary, band.max_salary,
       p.created_at, cb.name AS created_by_name, p.updated_at, ub.name AS updated_by_name, p.row_version
FROM [mp].[position] p
JOIN [org].[job_title] jt ON jt.id = p.job_title_id
JOIN [org].[branch] br ON br.id = p.branch_id
JOIN [org].[employee_group] eg ON eg.id = p.employee_group_id
LEFT JOIN [org].[division] dv ON dv.id = p.division_id
LEFT JOIN [org].[department] dp ON dp.id = p.department_id
LEFT JOIN [org].[department] sd ON sd.id = p.sub_department_id
LEFT JOIN [org].[cost_center] cc ON cc.id = p.cost_center_id
LEFT JOIN [org].[grade] gr ON gr.id = p.grade_id
LEFT JOIN [mp].[position] rt ON rt.id = p.reports_to_id
LEFT JOIN [org].[job_title] rtj ON rtj.id = rt.job_title_id
LEFT JOIN [hr].[employee] em ON em.id = p.employee_id
OUTER APPLY [mp].[fn_position_band](p.id, CAST(SYSUTCDATETIME() AS DATE)) band
OUTER APPLY [mp].[fn_actor_name](p.created_by) cb
OUTER APPLY [mp].[fn_actor_name](p.updated_by) ub
WHERE p.company_id = @company_id;
