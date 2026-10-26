-- Performance: shared functions. One file so they are created in dependency order.

-- The "My" and "Team" tabs: the actor's own employee (@tab 'my') or their direct and indirect reports
-- (@tab 'team'). Lists combine it with auth.fn_visible_employees: the tab narrows, the permission reaches.
CREATE OR ALTER FUNCTION [perf].[fn_tab_employees] (@actor_user_id BIGINT, @tab NVARCHAR(20))
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT u.employee_id AS id FROM [auth].[user_account] u WHERE u.id = @actor_user_id AND u.employee_id IS NOT NULL
),
team AS (
    SELECT e.id FROM [hr].[employee] e JOIN me ON e.line_manager_id = me.id
    UNION ALL
    SELECT e.id FROM [hr].[employee] e JOIN team t ON e.line_manager_id = t.id
)
SELECT id AS employee_id FROM me WHERE @tab = N'my'
UNION ALL
SELECT id FROM team WHERE @tab = N'team';
GO

-- The label of the scale level nearest a score (ties go to the higher level).
CREATE OR ALTER FUNCTION [perf].[fn_scale_label] (@rating_scale_id BIGINT, @score DECIMAL(9,4))
RETURNS NVARCHAR(100)
AS
BEGIN
    IF @score IS NULL RETURN NULL;
    RETURN (SELECT TOP 1 l.label FROM [perf].[rating_scale_level] l WHERE l.rating_scale_id = @rating_scale_id
            ORDER BY ABS(l.score - @score), l.score DESC);
END
GO

-- Goal achievement of an appraisal (0-100): the person's goals that count in its cycle, weighted.
-- A goal counts when it names the cycle, or names none and falls due inside the cycle's period.
CREATE OR ALTER FUNCTION [perf].[fn_goal_achievement] (@appraisal_id BIGINT)
RETURNS DECIMAL(9,4)
AS
BEGIN
    RETURN (
        SELECT SUM(g.weight * g.progress) / NULLIF(SUM(g.weight), 0)
        FROM [perf].[appraisal] a
        JOIN [perf].[appraisal_cycle] c ON c.id = a.appraisal_cycle_id
        JOIN [perf].[goal] g ON g.employee_id = a.employee_id AND g.company_id = a.company_id
        WHERE a.id = @appraisal_id AND g.status <> N'cancelled'
          AND (g.appraisal_cycle_id = c.id OR (g.appraisal_cycle_id IS NULL AND g.due_date BETWEEN c.start_date AND c.end_date)));
END
GO

CREATE OR ALTER FUNCTION [perf].[fn_rating_scale_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT s.id, s.name, s.is_default, s.is_active,
       (SELECT MIN(l.score) FROM [perf].[rating_scale_level] l WHERE l.rating_scale_id = s.id) AS min_score,
       (SELECT MAX(l.score) FROM [perf].[rating_scale_level] l WHERE l.rating_scale_id = s.id) AS max_score,
       (SELECT l.score, l.label, l.description FROM [perf].[rating_scale_level] l
        WHERE l.rating_scale_id = s.id ORDER BY l.score FOR JSON PATH) AS levels,
       (SELECT COUNT(*) FROM [perf].[appraisal_form] f WHERE f.rating_scale_id = s.id) AS in_use,
       s.created_at, s.updated_at, s.row_version
FROM [perf].[rating_scale] s
WHERE s.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [perf].[fn_appraisal_form_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT f.id, f.name, f.description, f.rating_scale_id, s.name AS rating_scale_name, f.goals_weight, f.has_self_review,
       f.is_active,
       (SELECT c.id, c.kpi_id AS kpiId, k.name AS kpiName, c.name, c.description, c.weight, c.sort_order AS sortOrder
        FROM [perf].[appraisal_criterion] c
        LEFT JOIN [perf].[kpi] k ON k.id = c.kpi_id
        WHERE c.appraisal_form_id = f.id ORDER BY c.sort_order, c.id FOR JSON PATH) AS criteria,
       (SELECT COUNT(*) FROM [perf].[appraisal_cycle] y WHERE y.appraisal_form_id = f.id) AS in_use,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] y WHERE y.appraisal_form_id = f.id
                              AND y.status <> N'draft') THEN 1 ELSE 0 END AS BIT) AS is_locked,
       f.created_at, f.updated_at, f.row_version
FROM [perf].[appraisal_form] f
JOIN [perf].[rating_scale] s ON s.id = f.rating_scale_id
WHERE f.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [perf].[fn_kpi_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT k.id, k.name, k.key_result_area, k.description, k.measure_type, k.target_value, k.unit, k.default_weight,
       k.department_id, d.name AS department_name, k.job_title_id, jt.name AS job_title_name, k.is_active,
       (SELECT COUNT(*) FROM [perf].[appraisal_criterion] c WHERE c.kpi_id = k.id)
         + (SELECT COUNT(*) FROM [perf].[goal] g WHERE g.kpi_id = k.id) AS in_use,
       k.created_at, k.updated_at, k.row_version
FROM [perf].[kpi] k
LEFT JOIN [org].[department] d ON d.id = k.department_id
LEFT JOIN [org].[job_title] jt ON jt.id = k.job_title_id
WHERE k.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [perf].[fn_goal_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT g.id, g.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
       e.department_id, d.name AS department_name, g.appraisal_cycle_id, c.name AS appraisal_cycle_name,
       g.kpi_id, k.name AS kpi_name, g.title, g.description, g.start_date, g.due_date, g.weight, g.target_value,
       g.actual_value, g.progress, g.status,
       CAST(CASE WHEN g.status IN (N'not_started', N'in_progress') AND g.due_date < CAST(SYSUTCDATETIME() AS DATE)
                 THEN 1 ELSE 0 END AS BIT) AS is_overdue,
       CAST(CASE WHEN EXISTS (
                SELECT 1 FROM [perf].[appraisal] a
                JOIN [perf].[appraisal_cycle] ac ON ac.id = a.appraisal_cycle_id
                WHERE a.employee_id = g.employee_id AND a.status = N'finalised'
                  AND (ac.id = g.appraisal_cycle_id
                       OR (g.appraisal_cycle_id IS NULL AND g.due_date BETWEEN ac.start_date AND ac.end_date)))
            THEN 1 ELSE 0 END AS BIT) AS is_locked,
       g.completed_at, g.set_by_user_id, g.created_at, g.updated_at, g.row_version
FROM [perf].[goal] g
JOIN [hr].[employee] e ON e.id = g.employee_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
LEFT JOIN [perf].[appraisal_cycle] c ON c.id = g.appraisal_cycle_id
LEFT JOIN [perf].[kpi] k ON k.id = g.kpi_id
WHERE g.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [perf].[fn_appraisal_cycle_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT c.id, c.name, c.appraisal_form_id, f.name AS appraisal_form_name, c.start_date, c.end_date,
       c.self_review_due_date, c.manager_review_due_date, c.status, c.launched_at, c.closed_at,
       ISNULL(n.participants, 0) AS participants, ISNULL(n.self_review, 0) AS self_review,
       ISNULL(n.manager_review, 0) AS manager_review, ISNULL(n.reviewed, 0) AS reviewed,
       ISNULL(n.finalised, 0) AS finalised,
       c.created_at, c.updated_at, c.row_version
FROM [perf].[appraisal_cycle] c
JOIN [perf].[appraisal_form] f ON f.id = c.appraisal_form_id
OUTER APPLY (SELECT COUNT(*) AS participants,
                    SUM(CASE WHEN a.status = N'self_review' THEN 1 ELSE 0 END) AS self_review,
                    SUM(CASE WHEN a.status = N'manager_review' THEN 1 ELSE 0 END) AS manager_review,
                    SUM(CASE WHEN a.status = N'reviewed' THEN 1 ELSE 0 END) AS reviewed,
                    SUM(CASE WHEN a.status = N'finalised' THEN 1 ELSE 0 END) AS finalised
             FROM [perf].[appraisal] a WHERE a.appraisal_cycle_id = c.id) n
WHERE c.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [perf].[fn_appraisal_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT a.id, a.appraisal_cycle_id, c.name AS appraisal_cycle_name, c.status AS cycle_status,
       c.start_date AS period_start, c.end_date AS period_end, c.self_review_due_date, c.manager_review_due_date,
       f.id AS appraisal_form_id, f.name AS appraisal_form_name, f.has_self_review, f.goals_weight, f.rating_scale_id,
       a.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
       e.department_id, d.name AS department_name, jt.name AS job_title_name,
       a.reviewer_employee_id, CASE WHEN r.id IS NOT NULL THEN CONCAT(r.first_name, N' ', r.last_name) END AS reviewer_name,
       a.status, a.goals_score, a.self_score, a.manager_score, a.final_score, a.final_rating_label,
       a.self_comments, a.manager_comments, a.final_comments, a.development_needs, a.outcome,
       a.self_submitted_at, a.manager_submitted_at, a.finalised_at, a.finalised_by_user_id,
       a.letter_file_id, sf.name AS letter_file_name,
       a.created_at, a.updated_at, a.row_version
FROM [perf].[appraisal] a
JOIN [perf].[appraisal_cycle] c ON c.id = a.appraisal_cycle_id
JOIN [perf].[appraisal_form] f ON f.id = c.appraisal_form_id
JOIN [hr].[employee] e ON e.id = a.employee_id
LEFT JOIN [hr].[employee] r ON r.id = a.reviewer_employee_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
LEFT JOIN [core].[stored_file] sf ON sf.id = a.letter_file_id
WHERE a.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [perf].[fn_increment_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.appraisal_id, a.appraisal_cycle_id, c.name AS appraisal_cycle_name, p.employee_id,
       e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name, d.name AS department_name,
       a.final_score, a.final_rating_label, p.change_type, p.change_value, p.effective_date, p.current_salary,
       p.proposed_salary, p.status, p.employee_salary_id, p.decided_at, p.decided_by_user_id, p.remarks,
       p.created_at, p.updated_at, p.row_version
FROM [perf].[increment_proposal] p
JOIN [perf].[appraisal] a ON a.id = p.appraisal_id
JOIN [perf].[appraisal_cycle] c ON c.id = a.appraisal_cycle_id
JOIN [hr].[employee] e ON e.id = p.employee_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
WHERE p.company_id = @company_id;
