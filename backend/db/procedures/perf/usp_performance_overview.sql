-- My Performance overview for one employee (the actor when @employee_id is NULL).
-- Result sets: 1 the person and their goal figures; 2 the next goals due; 3 their appraisals, newest first.
CREATE OR ALTER PROCEDURE [perf].[usp_performance_overview]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @employee_id = ISNULL(@employee_id, (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id));
    IF @employee_id IS NULL
        THROW 50400, N'employeeId|Choose an employee.', 1;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           d.name AS department_name, jt.name AS job_title_name,
           SUM(CASE WHEN g.id IS NOT NULL THEN 1 ELSE 0 END) AS goals_total,
           SUM(CASE WHEN g.status = N'not_started' THEN 1 ELSE 0 END) AS goals_not_started,
           SUM(CASE WHEN g.status = N'in_progress' THEN 1 ELSE 0 END) AS goals_in_progress,
           SUM(CASE WHEN g.status = N'completed' THEN 1 ELSE 0 END) AS goals_completed,
           SUM(CASE WHEN g.status = N'cancelled' THEN 1 ELSE 0 END) AS goals_cancelled,
           SUM(CASE WHEN g.status IN (N'not_started', N'in_progress') AND g.due_date < @today THEN 1 ELSE 0 END) AS goals_overdue,
           CAST(SUM(CASE WHEN g.status <> N'cancelled' THEN g.weight * g.progress ELSE 0 END)
                / NULLIF(SUM(CASE WHEN g.status <> N'cancelled' THEN g.weight ELSE 0 END), 0) AS DECIMAL(5,2)) AS weighted_progress
    FROM [hr].[employee] e
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    LEFT JOIN [perf].[goal] g ON g.employee_id = e.id AND g.company_id = @company_id
    WHERE e.id = @employee_id
    GROUP BY e.id, e.code, e.first_name, e.last_name, d.name, jt.name;

    SELECT TOP 5 g.id, g.title, g.due_date, g.progress, g.status,
           CAST(CASE WHEN g.due_date < @today THEN 1 ELSE 0 END AS BIT) AS is_overdue
    FROM [perf].[goal] g
    WHERE g.employee_id = @employee_id AND g.company_id = @company_id AND g.status IN (N'not_started', N'in_progress')
    ORDER BY g.due_date, g.id;

    SELECT TOP 10 a.id, a.appraisal_cycle_id, a.appraisal_cycle_name, a.period_start, a.period_end, a.status,
           a.self_review_due_date, a.manager_review_due_date, a.final_score, a.final_rating_label, a.outcome, a.finalised_at
    FROM [perf].[fn_appraisal_rows](@company_id) a
    WHERE a.employee_id = @employee_id AND a.status <> N'draft'
    ORDER BY a.period_end DESC, a.id DESC;
END
