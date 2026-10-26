-- Elections of a company: one per employee and plan year, with the plans elected.
CREATE OR ALTER FUNCTION [ben].[fn_election_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT e.id, e.employee_id, em.code AS employee_code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
       dp.name AS department_name, jt.name AS job_title_name,
       e.plan_year_id, y.name AS plan_year_name, e.enrollment_window_id, w.name AS enrollment_window_name,
       e.status,
       (SELECT STRING_AGG(CAST(ep.benefit_plan_id AS NVARCHAR(20)), N',') FROM [ben].[election_plan] ep
        WHERE ep.election_id = e.id) AS plan_ids,
       (SELECT STRING_AGG(b.name, N', ') WITHIN GROUP (ORDER BY b.name) FROM [ben].[election_plan] ep
        JOIN [ben].[benefit_plan] b ON b.id = ep.benefit_plan_id WHERE ep.election_id = e.id) AS plan_names,
       e.submitted_at, e.decided_by_user_id, db.name AS decided_by_name, e.decided_at, e.remarks,
       e.created_at, e.updated_at, e.row_version
FROM [ben].[election] e
JOIN [hr].[employee] em ON em.id = e.employee_id
JOIN [ben].[plan_year] y ON y.id = e.plan_year_id
LEFT JOIN [ben].[enrollment_window] w ON w.id = e.enrollment_window_id
LEFT JOIN [org].[department] dp ON dp.id = em.department_id
LEFT JOIN [org].[job_title] jt ON jt.id = em.job_title_id
OUTER APPLY [ben].[fn_actor_name](e.decided_by_user_id) db
WHERE e.company_id = @company_id;
