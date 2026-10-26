-- Open positions of a company as the Open Positions list shows them, with who approved the budget.
CREATE OR ALTER FUNCTION [mp].[fn_open_position_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT o.id, o.title, o.e_budget_id, b.title AS budget_title, b.manpower_plan_id, pl.title AS plan_title,
       o.manpower_plan_line_id, o.position_id, ps.code AS position_code,
       o.job_title_id, jt.name AS job_title_name, o.department_id, dp.name AS department_name,
       o.branch_id, br.name AS branch_name, o.approved_positions, o.total_positions, o.end_date,
       o.jd_file_id, f.name AS jd_file_name, o.status,
       b.decided_at AS approved_at, ab.name AS approved_by_name,
       o.created_at, o.updated_at, o.row_version
FROM [mp].[open_position] o
JOIN [mp].[e_budget] b ON b.id = o.e_budget_id
LEFT JOIN [mp].[manpower_plan] pl ON pl.id = b.manpower_plan_id
LEFT JOIN [mp].[position] ps ON ps.id = o.position_id
LEFT JOIN [org].[job_title] jt ON jt.id = o.job_title_id
LEFT JOIN [org].[department] dp ON dp.id = o.department_id
LEFT JOIN [org].[branch] br ON br.id = o.branch_id
LEFT JOIN [core].[stored_file] f ON f.id = o.jd_file_id
OUTER APPLY [mp].[fn_actor_name](b.decided_by_user_id) ab
WHERE o.company_id = @company_id;
