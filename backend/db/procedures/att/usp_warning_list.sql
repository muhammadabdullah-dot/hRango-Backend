-- Warnings raised, for the employees @permission_code reaches.
CREATE OR ALTER PROCEDURE [att].[usp_warning_list]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @permission_code   NVARCHAR(150),
    @employee_id       BIGINT = NULL,
    @warning_policy_id BIGINT = NULL,
    @applies_to        NVARCHAR(30) = NULL,
    @from_date         DATE = NULL,
    @to_date           DATE = NULL,
    @search            NVARCHAR(200) = NULL,
    @page              INT = 1,
    @page_size         INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [att].[warning] w
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = w.employee_id
    JOIN [hr].[employee] e ON e.id = w.employee_id
    JOIN [att].[warning_policy] p ON p.id = w.warning_policy_id
    WHERE w.company_id = @company_id
      AND (@employee_id IS NULL OR w.employee_id = @employee_id)
      AND (@warning_policy_id IS NULL OR w.warning_policy_id = @warning_policy_id)
      AND (@applies_to IS NULL OR p.applies_to = @applies_to)
      AND (@from_date IS NULL OR w.work_date >= @from_date)
      AND (@to_date IS NULL OR w.work_date <= @to_date)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT w.id, w.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           d.name AS department_name, w.warning_policy_id, p.title AS policy_title, p.applies_to, p.period,
           r.clock_event, w.timesheet_day_id, w.work_date, w.minutes, w.occurrence_no, w.penalty_rule_id,
           w.penalty_type, w.penalty_percentage, w.deduction, w.payslip_id, w.created_at
    FROM [att].[warning] w
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = w.employee_id
    JOIN [hr].[employee] e ON e.id = w.employee_id
    JOIN [att].[warning_policy] p ON p.id = w.warning_policy_id
    JOIN [att].[warning_policy_rule] r ON r.id = w.warning_policy_rule_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE w.company_id = @company_id
      AND (@employee_id IS NULL OR w.employee_id = @employee_id)
      AND (@warning_policy_id IS NULL OR w.warning_policy_id = @warning_policy_id)
      AND (@applies_to IS NULL OR p.applies_to = @applies_to)
      AND (@from_date IS NULL OR w.work_date >= @from_date)
      AND (@to_date IS NULL OR w.work_date <= @to_date)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    ORDER BY w.work_date DESC, w.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- The History panel: changes to warning policies and their penalties (core.audit_log), newest first.
CREATE OR ALTER PROCEDURE [att].[usp_warning_history_list]
    @company_id BIGINT,
    @policy_id  BIGINT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [core].[audit_log] a
    WHERE a.company_id = @company_id AND a.entity_type = N'att.warning_policy'
      AND (@policy_id IS NULL OR a.entity_id = @policy_id)
    OPTION (RECOMPILE);

    SELECT a.id, a.performed_at, a.action_name, a.entity_id AS policy_id,
           COALESCE(p.title, (SELECT TOP (1) COALESCE(t.new_value, t.old_value) FROM [core].[audit_log] t
                              WHERE t.entity_type = N'att.warning_policy' AND t.entity_id = a.entity_id
                                AND t.field_name = N'title' ORDER BY t.id DESC)) AS policy_title,
           a.field_name, a.old_value, a.new_value, a.performed_by_user_id,
           COALESCE(u.display_name, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.email) AS performed_by_name
    FROM [core].[audit_log] a
    LEFT JOIN [att].[warning_policy] p ON p.id = a.entity_id
    LEFT JOIN [auth].[user_account] u ON u.id = a.performed_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE a.company_id = @company_id AND a.entity_type = N'att.warning_policy'
      AND (@policy_id IS NULL OR a.entity_id = @policy_id)
    ORDER BY a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
