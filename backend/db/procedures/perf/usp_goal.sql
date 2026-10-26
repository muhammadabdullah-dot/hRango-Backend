-- Performance -> Goals (My Performance: Goal Name, Due Date, Completed). Employee-owned: every procedure
-- filters on auth.fn_visible_employees with the code the endpoint required. @tab 'my' / 'team' / 'all'.
-- Progress and status are settled by the service (actual / target, 100% = completed); this keeps the
-- check-in history, stamps completed_at and publishes performance.goal_completed. A goal that counted in a
-- finalised appraisal is locked.

CREATE OR ALTER PROCEDURE [perf].[usp_goal_list]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @tab                NVARCHAR(20) = N'all',
    @employee_id        BIGINT = NULL,
    @status             NVARCHAR(30) = NULL,
    @appraisal_cycle_id BIGINT = NULL,
    @overdue            BIT = NULL,
    @due_from           DATE = NULL,
    @due_to             DATE = NULL,
    @search             NVARCHAR(200) = NULL,
    @page               INT = 1,
    @page_size          INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT g.id INTO #ids
    FROM [perf].[fn_goal_rows](@company_id) g
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = g.employee_id
    WHERE (@tab = N'all' OR g.employee_id IN (SELECT employee_id FROM [perf].[fn_tab_employees](@actor_user_id, @tab)))
      AND (@employee_id IS NULL OR g.employee_id = @employee_id)
      AND (@status IS NULL OR g.status = @status)
      AND (@appraisal_cycle_id IS NULL OR g.appraisal_cycle_id = @appraisal_cycle_id)
      AND (@overdue IS NULL OR g.is_overdue = @overdue)
      AND (@due_from IS NULL OR g.due_date >= @due_from)
      AND (@due_to IS NULL OR g.due_date <= @due_to)
      AND (@pattern IS NULL OR g.title LIKE @pattern OR g.employee_name LIKE @pattern OR g.employee_code LIKE @pattern)
    OPTION (RECOMPILE, MAXRECURSION 100);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT g.*
    FROM #ids i
    JOIN [perf].[fn_goal_rows](@company_id) g ON g.id = i.id
    ORDER BY CASE WHEN g.status IN (N'completed', N'cancelled') THEN 1 ELSE 0 END, g.due_date, g.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Result set 1: the goal. Result set 2: its check-ins, newest first.
CREATE OR ALTER PROCEDURE [perf].[usp_goal_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [perf].[goal] g
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = g.employee_id
                   WHERE g.id = @id AND g.company_id = @company_id)
        THROW 50404, N'Goal not found', 1;
    SELECT g.* FROM [perf].[fn_goal_rows](@company_id) g WHERE g.id = @id;
    SELECT c.id, c.progress, c.actual_value, c.status, c.comments, c.created_at, c.created_by AS created_by_user_id,
           COALESCE(CONCAT(e.first_name, N' ', e.last_name), u.display_name) AS created_by_name
    FROM [perf].[goal_check_in] c
    LEFT JOIN [auth].[user_account] u ON u.id = c.created_by
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE c.goal_id = @id
    ORDER BY c.id DESC;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_goal_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @id                 BIGINT = NULL,
    @employee_id        BIGINT,
    @appraisal_cycle_id BIGINT = NULL,
    @kpi_id             BIGINT = NULL,
    @title              NVARCHAR(200),
    @description        NVARCHAR(MAX) = NULL,
    @start_date         DATE = NULL,
    @due_date           DATE,
    @weight             DECIMAL(5,2),
    @target_value       DECIMAL(18,2) = NULL,
    @actual_value       DECIMAL(18,2) = NULL,
    @progress           DECIMAL(5,2),
    @status             NVARCHAR(30),
    @comments           NVARCHAR(MAX) = NULL,
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Goal name is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @appraisal_cycle_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] WHERE id = @appraisal_cycle_id
                                                      AND company_id = @company_id AND status <> N'closed')
        THROW 50400, N'appraisalCycleId|Choose an appraisal cycle that is not closed.', 1;
    IF @kpi_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [perf].[kpi] WHERE id = @kpi_id AND company_id = @company_id)
        THROW 50400, N'kpiId|KPI not found.', 1;

    DECLARE @old_status NVARCHAR(30), @old_progress DECIMAL(5,2), @old_actual DECIMAL(18,2);
    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8), @old_emp BIGINT, @locked BIT;
        SELECT @rv = g.row_version, @old_emp = g.employee_id, @locked = g.is_locked, @old_status = g.status,
               @old_progress = g.progress, @old_actual = g.actual_value
        FROM [perf].[fn_goal_rows](@company_id) g
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = g.employee_id
        WHERE g.id = @id;
        IF @rv IS NULL
            THROW 50404, N'Goal not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this goal. Reload it and try again', 1;
        IF @old_emp <> @employee_id
            THROW 50400, N'employeeId|A goal cannot move to another employee.', 1;
        IF @locked = 1
            THROW 50409, N'id|GOAL_LOCKED|This goal counted in a finalised appraisal and can no longer change.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [perf].[goal] (company_id, employee_id, appraisal_cycle_id, kpi_id, title, description, start_date, due_date,
                                  weight, target_value, actual_value, progress, status, completed_at, set_by_user_id, created_by)
            VALUES (@company_id, @employee_id, @appraisal_cycle_id, @kpi_id, @title, @description, @start_date, @due_date,
                    @weight, @target_value, @actual_value, @progress, @status,
                    CASE WHEN @status = N'completed' THEN @now END, @actor_user_id, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'perf.goal', @id, N'title', @title, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [perf].[goal]
            SET appraisal_cycle_id = @appraisal_cycle_id, kpi_id = @kpi_id, title = @title, description = @description,
                start_date = @start_date, due_date = @due_date, weight = @weight, target_value = @target_value,
                actual_value = @actual_value, progress = @progress, status = @status,
                completed_at = CASE WHEN @status <> N'completed' THEN NULL ELSE ISNULL(completed_at, @now) END,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this goal. Reload it and try again', 1;
        END

        -- Progress that moved (or a first update with progress) goes into the goal's history.
        IF (@old_status IS NULL AND (@progress > 0 OR @status <> N'not_started'))
           OR @old_progress <> @progress OR @old_status <> @status OR ISNULL(@old_actual, -1) <> ISNULL(@actual_value, -1)
            INSERT [perf].[goal_check_in] (goal_id, progress, actual_value, status, comments, created_by)
            VALUES (@id, @progress, @actual_value, @status, @comments, @actor_user_id);

        IF @status = N'completed' AND ISNULL(@old_status, N'') <> N'completed'
        BEGIN
            DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS goalId, CONVERT(NVARCHAR(20), @employee_id) AS employeeId,
                                                     @title AS title, @due_date AS dueDate
                                              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'performance.goal_completed',
                 @entity_type = N'perf.goal', @entity_id = @id, @payload = @payload;
        END
    COMMIT;

    EXEC [perf].[usp_goal_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_goal_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @locked BIT, @title NVARCHAR(200);
    SELECT @rv = g.row_version, @locked = g.is_locked, @title = g.title
    FROM [perf].[fn_goal_rows](@company_id) g
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = g.employee_id
    WHERE g.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Goal not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this goal. Reload it and try again', 1;
    IF @locked = 1
        THROW 50409, N'id|GOAL_LOCKED|This goal counted in a finalised appraisal and can no longer change.', 1;
    BEGIN TRAN;
        DELETE [perf].[goal_check_in] WHERE goal_id = @id;
        DELETE [perf].[goal] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.goal', @id, N'title', @title, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
