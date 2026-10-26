-- Time tracking: manual entries (start and stop, or a duration) and a start / stop timer.
-- "Time Tracking" must be on. Members log their own time on tasks assigned to them (BRD "Only
-- assigned users can log time"); team leaders and above on any task they can see. Managers and
-- above may correct or delete anyone's entries.

CREATE OR ALTER PROCEDURE [pm].[usp_time_entry_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT = NULL,
    @id            BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL
        SET @task_id = (SELECT task_id FROM [pm].[time_entry] WHERE id = @id);
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id)
        THROW 50404, N'Task not found', 1;

    SELECT te.id, te.task_id, te.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, te.start_at, te.end_at,
           ISNULL(te.minutes, DATEDIFF(MINUTE, te.start_at, SYSDATETIME())) AS minutes,
           CAST(CASE WHEN te.end_at IS NULL THEN 1 ELSE 0 END AS BIT) AS is_running, te.notes, te.row_version
    FROM [pm].[time_entry] te JOIN [hr].[employee] e ON e.id = te.employee_id
    WHERE te.task_id = @task_id AND (@id IS NULL OR te.id = @id)
    ORDER BY e.first_name, e.last_name, te.start_at DESC, te.id DESC;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_time_entry_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @task_id       BIGINT = NULL,
    @employee_id   BIGINT = NULL,
    @start_at      DATETIME2(0),
    @end_at        DATETIME2(0) = NULL,
    @minutes       INT = NULL,
    @notes         NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @owner BIGINT, @rv BINARY(8), @running BIT = 0;
    IF @id IS NOT NULL
        SELECT @task_id = task_id, @owner = employee_id, @rv = row_version,
               @running = CASE WHEN end_at IS NULL THEN 1 ELSE 0 END
        FROM [pm].[time_entry] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Time entry not found', 1;
    IF @rank < 1
        THROW 50403, N'Only workspace members can log time.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @ws AND feature_code = N'time_tracking')
        THROW 50409, N'features|FEATURE_OFF|Time tracking is switched off for this workspace.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'time_tracked' AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change tracked time (column permission).', 1;

    SET @employee_id = COALESCE(@owner, @employee_id, @me);
    IF @employee_id <> @me AND @rank < 3
        THROW 50403, N'Only managers and above can log or change time for someone else.', 1;
    IF @id IS NULL AND @rank < 2 AND NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @task_id AND employee_id = @employee_id)
        THROW 50403, N'Only the task''s assignees can log time on it.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] WHERE workspace_id = @ws AND employee_id = @employee_id)
        THROW 50400, N'employeeId|Time is logged for workspace members.', 1;
    IF @running = 1
        THROW 50409, N'Stop the timer before editing this entry.', 1;

    SET @notes = NULLIF(LTRIM(RTRIM(@notes)), N'');
    IF LEN(@notes) > 165
        THROW 50400, N'notes|Notes must be within 165 characters.', 1;
    IF @start_at IS NULL
        THROW 50400, N'startAt|Pick the day and start time.', 1;
    IF @end_at IS NULL AND @minutes IS NOT NULL
        SET @end_at = DATEADD(MINUTE, @minutes, @start_at);
    IF @end_at IS NULL
        THROW 50400, N'endAt|Enter the stop time or the time spent.', 1;
    IF @end_at <= @start_at
        THROW 50400, N'endAt|Stop time must be after the start time.', 1;
    SET @minutes = DATEDIFF(MINUTE, @start_at, @end_at);
    IF @minutes > 24 * 60
        THROW 50400, N'endAt|One entry can be at most 24 hours.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pm].[time_entry] (task_id, employee_id, start_at, end_at, minutes, notes, created_by)
            VALUES (@task_id, @employee_id, @start_at, @end_at, @minutes, @notes, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [pm].[time_entry] SET start_at = @start_at, end_at = @end_at, minutes = @minutes, notes = @notes,
                                         updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this time entry. Reload it and try again', 1;
        END
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task_id, N'time_entry', CONVERT(NVARCHAR(30), @minutes), N'time', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_time_entry_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_time_entry_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @task_id BIGINT, @owner BIGINT;
    SELECT @task_id = task_id, @owner = employee_id FROM [pm].[time_entry] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Time entry not found', 1;
    IF @rank < 3 AND NOT (@rank >= 1 AND @owner = @me)
        THROW 50403, N'You can delete only your own time entries.', 1;

    DELETE [pm].[time_entry] WHERE id = @id;
END
GO

-- Start Timer: one running timer per person.
CREATE OR ALTER PROCEDURE [pm].[usp_time_entry_timer_start]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 1
        THROW 50403, N'Only workspace members can log time.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @ws AND feature_code = N'time_tracking')
        THROW 50409, N'features|FEATURE_OFF|Time tracking is switched off for this workspace.', 1;
    IF @rank < 2 AND NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @task_id AND employee_id = @me)
        THROW 50403, N'Only the task''s assignees can log time on it.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[time_entry] WHERE employee_id = @me AND end_at IS NULL)
        THROW 50409, N'taskId|TIMER_RUNNING|Your timer is already running on a task. Stop it first.', 1;

    INSERT [pm].[time_entry] (task_id, employee_id, start_at, created_by) VALUES (@task_id, @me, SYSDATETIME(), @actor_user_id);
    DECLARE @id BIGINT = SCOPE_IDENTITY();
    EXEC [pm].[usp_time_entry_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Stop Timer: records the caller's running timer as an entry of at least one minute.
CREATE OR ALTER PROCEDURE [pm].[usp_time_entry_timer_stop]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @notes         NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @id BIGINT, @task_id BIGINT;
    SELECT @id = te.id, @task_id = te.task_id
    FROM [pm].[time_entry] te JOIN [pm].[task] t ON t.id = te.task_id
    WHERE te.employee_id = @me AND te.end_at IS NULL AND t.company_id = @company_id;
    IF @id IS NULL
        THROW 50404, N'No timer is running', 1;
    SET @notes = NULLIF(LTRIM(RTRIM(@notes)), N'');
    IF LEN(@notes) > 165
        THROW 50400, N'notes|Notes must be within 165 characters.', 1;

    -- Time entries are local wall-clock time (manual entries are typed that way); stamps stay UTC.
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @local DATETIME2(0) = SYSDATETIME();
    BEGIN TRAN;
        UPDATE [pm].[time_entry]
        SET end_at = CASE WHEN DATEDIFF(MINUTE, start_at, @local) < 1 THEN DATEADD(MINUTE, 1, start_at) ELSE @local END,
            minutes = CASE WHEN DATEDIFF(MINUTE, start_at, @local) < 1 THEN 1 ELSE DATEDIFF(MINUTE, start_at, @local) END,
            notes = ISNULL(@notes, notes), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pm.task', @task_id, N'time_entry', CONVERT(NVARCHAR(30), minutes), N'time', @actor_user_id, @now
        FROM [pm].[time_entry] WHERE id = @id;
    COMMIT;

    EXEC [pm].[usp_time_entry_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
