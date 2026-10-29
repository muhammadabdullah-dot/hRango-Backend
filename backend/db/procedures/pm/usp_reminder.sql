-- Reminders on a task, list or workspace ("Remind Me", BRD "Reminders"). usp_reminder_deliver_due (run
-- by a scheduler) sends them to the inbox. A member sets reminders for themselves; team leaders and above
-- may give one to another member (delegate). A task reminder cannot fall after the task's due date.

CREATE OR ALTER PROCEDURE [pm].[usp_reminder_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @entity_type   NVARCHAR(50) = NULL,
    @entity_id     BIGINT = NULL,
    @include_done  BIT = 0,
    @id            BIGINT = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    SELECT COUNT(*) AS total
    FROM [pm].[reminder] r
    JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = r.workspace_id
    WHERE (r.owner_id = @me OR r.assignee_id = @me)
      AND (@id IS NULL OR r.id = @id)
      AND (@entity_type IS NULL OR (r.entity_type = @entity_type AND (@entity_id IS NULL OR r.entity_id = @entity_id)))
      AND (@include_done = 1 OR r.notified_at IS NULL)
    OPTION (RECOMPILE);

    SELECT r.id, r.workspace_id, r.entity_type, r.entity_id,
           CASE r.entity_type WHEN N'task' THEN t.name WHEN N'task_list' THEN l.name ELSE w.name END AS entity_name,
           r.name, r.owner_id, NULLIF(CONCAT(o.first_name, N' ', o.last_name), N' ') AS owner_name,
           r.assignee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS assignee_name,
           r.remind_at, r.notify_before_minutes, r.reminder_kind, r.notified_at, r.created_at, r.row_version
    FROM [pm].[reminder] r
    JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = r.workspace_id
    JOIN [pm].[workspace] w ON w.id = r.workspace_id
    JOIN [hr].[employee] o ON o.id = r.owner_id
    LEFT JOIN [hr].[employee] e ON e.id = r.assignee_id
    LEFT JOIN [pm].[task] t ON r.entity_type = N'task' AND t.id = r.entity_id
    LEFT JOIN [pm].[task_list] l ON r.entity_type = N'task_list' AND l.id = r.entity_id
    WHERE (r.owner_id = @me OR r.assignee_id = @me)
      AND (@id IS NULL OR r.id = @id)
      AND (@entity_type IS NULL OR (r.entity_type = @entity_type AND (@entity_id IS NULL OR r.entity_id = @entity_id)))
      AND (@include_done = 1 OR r.notified_at IS NULL)
    ORDER BY r.remind_at, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_reminder_save]
    @company_id            BIGINT,
    @actor_user_id         BIGINT,
    @id                    BIGINT = NULL,
    @entity_type           NVARCHAR(50) = NULL,
    @entity_id             BIGINT = NULL,
    @name                  NVARCHAR(200) = NULL,
    @remind_at             DATETIME2(0),
    @assignee_id           BIGINT = NULL,
    @notify_before_minutes INT = NULL,
    @reminder_kind         NVARCHAR(30) = NULL,
    @row_version           BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @owner BIGINT;
    IF @id IS NOT NULL
    BEGIN
        SELECT @entity_type = entity_type, @entity_id = entity_id, @owner = owner_id FROM [pm].[reminder] WHERE id = @id;
        IF @owner IS NULL OR @owner <> ISNULL(@me, 0)
            THROW 50404, N'Reminder not found', 1;
    END

    DECLARE @ws BIGINT, @rank INT, @entity_name NVARCHAR(200), @due DATE;
    IF @entity_type = N'task'
        SELECT @ws = a.workspace_id, @rank = a.role_rank, @entity_name = t.name, @due = t.due_date
        FROM [pm].[fn_task_access](@company_id, @actor_user_id) a JOIN [pm].[task] t ON t.id = a.task_id WHERE a.task_id = @entity_id;
    ELSE IF @entity_type = N'task_list'
        SELECT @ws = a.workspace_id, @rank = a.role_rank, @entity_name = l.name
        FROM [pm].[task_list] l JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = l.workspace_id WHERE l.id = @entity_id;
    ELSE IF @entity_type = N'workspace'
        SELECT @ws = a.workspace_id, @rank = a.role_rank, @entity_name = w.name
        FROM [pm].[workspace] w JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = w.id WHERE w.id = @entity_id;
    ELSE
        THROW 50400, N'entityType|Reminders are set on a task, list or workspace.', 1;
    IF @ws IS NULL
        THROW 50404, N'Item not found', 1;
    IF @rank < 1
        THROW 50403, N'Only workspace members can set reminders here.', 1;

    SET @name = ISNULL(NULLIF(LTRIM(RTRIM(@name)), N''), @entity_name);
    IF @remind_at IS NULL
        THROW 50400, N'remindAt|Pick a date and time.', 1;
    IF @due IS NOT NULL AND CAST(@remind_at AS DATE) > @due
        THROW 50400, N'remindAt|A reminder cannot be set after the task''s due date.', 1;
    IF @notify_before_minutes IS NOT NULL AND (@notify_before_minutes < 0 OR @notify_before_minutes > 60 * 24 * 30)
        THROW 50400, N'notifyBeforeMinutes|Notify between 0 minutes and 30 days before.', 1;
    IF @reminder_kind IS NOT NULL AND @reminder_kind NOT IN (N'soft', N'hard')
        THROW 50400, N'reminderKind|Choose a soft or hard reminder.', 1;
    IF @assignee_id IS NOT NULL AND @assignee_id <> @me
    BEGIN
        IF @rank < 2
            THROW 50403, N'Only team leaders and above can give reminders to others.', 1;
        IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] WHERE workspace_id = @ws AND employee_id = @assignee_id)
            THROW 50400, N'assigneeId|Reminders go to workspace members.', 1;
    END

    IF @id IS NULL
    BEGIN
        INSERT [pm].[reminder] (workspace_id, entity_type, entity_id, name, owner_id, assignee_id, remind_at, notify_before_minutes,
                                reminder_kind, created_by)
        VALUES (@ws, @entity_type, @entity_id, @name, @me, ISNULL(@assignee_id, @me), @remind_at, @notify_before_minutes,
                @reminder_kind, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [pm].[reminder]
        SET name = @name, remind_at = @remind_at, assignee_id = ISNULL(@assignee_id, @me), notify_before_minutes = @notify_before_minutes,
            reminder_kind = @reminder_kind, notified_at = NULL, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this reminder. Reload it and try again', 1;
    END

    EXEC [pm].[usp_reminder_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id, @include_done = 1;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_reminder_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF NOT EXISTS (SELECT 1 FROM [pm].[reminder] r JOIN [pm].[workspace] w ON w.id = r.workspace_id
                   WHERE r.id = @id AND w.company_id = @company_id AND r.owner_id = @me)
        THROW 50404, N'Reminder not found', 1;

    DELETE [pm].[reminder] WHERE id = @id;
END
GO

-- Sends the reminders that are due: remind_at minus notify_before_minutes has passed and nothing was sent
-- yet. Each goes to the reminder's assignee (the owner when nobody else was given it) as an inbox
-- notification of type projects.reminder, with the item's type and id and a link into the app; then
-- notified_at is set. remind_at is the company's wall-clock time (as entered), so "now" is each company's
-- local time (att.fn_company_now) unless @now is given (tests, catch-up runs). @company_id: one company,
-- or every company when NULL. Returns one row: delivered (count).
CREATE OR ALTER PROCEDURE [pm].[usp_reminder_deliver_due]
    @company_id BIGINT = NULL,
    @now        DATETIME2(0) = NULL,
    @batch_size INT = 500
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @due TABLE (id BIGINT PRIMARY KEY, company_id BIGINT, workspace_id BIGINT, entity_type NVARCHAR(50), entity_id BIGINT,
                        name NVARCHAR(200), employee_id BIGINT, remind_at DATETIME2(0), row_version BINARY(8));
    INSERT @due
    SELECT TOP (@batch_size) r.id, w.company_id, r.workspace_id, r.entity_type, r.entity_id, r.name,
           ISNULL(r.assignee_id, r.owner_id), r.remind_at, r.row_version
    FROM [pm].[reminder] r
    JOIN [pm].[workspace] w ON w.id = r.workspace_id
    WHERE r.notified_at IS NULL
      AND (@company_id IS NULL OR w.company_id = @company_id)
      AND DATEADD(MINUTE, -ISNULL(r.notify_before_minutes, 0), r.remind_at) <= ISNULL(@now, [att].[fn_company_now](w.company_id))
    ORDER BY r.remind_at, r.id;

    DECLARE @delivered INT = 0, @id BIGINT = (SELECT MIN(id) FROM @due);
    DECLARE @company BIGINT, @ws BIGINT, @etype NVARCHAR(50), @eid BIGINT, @name NVARCHAR(200), @emp BIGINT, @at DATETIME2(0),
            @rv BINARY(8), @title NVARCHAR(200), @body NVARCHAR(MAX), @link NVARCHAR(500), @ntype NVARCHAR(50);
    WHILE @id IS NOT NULL
    BEGIN
        SELECT @company = company_id, @ws = workspace_id, @etype = entity_type, @eid = entity_id, @name = name, @emp = employee_id,
               @at = remind_at, @rv = row_version
        FROM @due WHERE id = @id;
        -- The inbox speaks of a task, list, workspace (or doc) and links to where it opens.
        SET @ntype = CASE @etype WHEN N'task_list' THEN N'list' ELSE @etype END;
        SET @link = CASE @etype
            WHEN N'task' THEN CONCAT(N'/project-management/workspaces/', @ws, N'?task=', @eid)
            WHEN N'task_list' THEN CONCAT(N'/project-management/workspaces/', @ws, N'?list=', @eid)
            ELSE CONCAT(N'/project-management/workspaces/', @ws) END;
        SET @title = LEFT(CONCAT(N'Reminder: ', @name), 200);
        SET @body = CONCAT(CASE @etype WHEN N'task' THEN N'Task' WHEN N'task_list' THEN N'List' ELSE N'Workspace' END,
                           N' reminder for ', CONVERT(NVARCHAR(16), @at, 120), N'.');

        BEGIN TRAN;
            -- Claimed first, so a run that overlaps another does not send it twice.
            UPDATE [pm].[reminder] SET notified_at = SYSUTCDATETIME() WHERE id = @id AND notified_at IS NULL AND row_version = @rv;
            IF @@ROWCOUNT = 1
            BEGIN
                EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company, @employee_id = @emp, @title = @title,
                     @body = @body, @notification_type = N'projects.reminder', @link = @link, @entity_type = @ntype, @entity_id = @eid;
                SET @delivered += 1;
            END
        COMMIT;

        SET @id = (SELECT MIN(id) FROM @due WHERE id > @id);
    END

    SELECT @delivered AS delivered;
END
