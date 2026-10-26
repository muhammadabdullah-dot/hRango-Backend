-- Adds a task or subtask (@id NULL) or edits one (@id and the @row_version last read).
--   Add: team leaders and above; a contributor may add subtasks under a task assigned to them.
--     Only the name is required (BRD "Add Task"); the status defaults to the first Not Started one,
--     a subtask takes its parent's due date unless one is given (BRD "Add Sub-Tasks").
--   Edit: team leaders and above, or the task's creator. Column permissions (can_view, private)
--     stop changes to that column. Organizer features that are off refuse their fields.
--   A due date change moves the subtasks' due dates by the same number of days when "Remap
--   Subtask Due Dates" is on, and the tasks waiting on this one when "Reschedule Dependencies" is on.
-- @assignee_ids, @tag_ids: JSON arrays of ids, used when adding.
CREATE OR ALTER PROCEDURE [pm].[usp_task_save]
    @company_id            BIGINT,
    @actor_user_id         BIGINT,
    @id                    BIGINT = NULL,
    @workspace_id          BIGINT = NULL,
    @task_list_id          BIGINT = NULL,
    @parent_task_id        BIGINT = NULL,
    @name                  NVARCHAR(200),
    @description           NVARCHAR(MAX) = NULL,
    @task_type             NVARCHAR(30) = N'task',
    @status_id             BIGINT = NULL,
    @priority              NVARCHAR(30) = NULL,
    @start_date            DATE = NULL,
    @start_time            TIME(0) = NULL,
    @due_date              DATE = NULL,
    @due_time              TIME(0) = NULL,
    @time_estimate_minutes INT = NULL,
    @rating                INT = NULL,
    @url                   NVARCHAR(2000) = NULL,
    @recurrence            NVARCHAR(MAX) = NULL,
    @assignee_ids          NVARCHAR(MAX) = NULL,
    @tag_ids               NVARCHAR(MAX) = NULL,
    @row_version           BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(@description, N'');
    SET @task_type = ISNULL(@task_type, N'task');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Task name is required.', 1;
    IF LEN(@description) > 5000
        THROW 50400, N'description|Description must be within 5000 characters.', 1;
    IF @task_type NOT IN (N'task', N'milestone')
        THROW 50400, N'taskType|Choose Task or Milestone.', 1;
    IF @priority IS NOT NULL AND @priority NOT IN (N'urgent', N'high', N'normal', N'low')
        THROW 50400, N'priority|Choose Urgent, High, Normal or Low.', 1;
    IF @start_date IS NOT NULL AND @due_date IS NOT NULL AND @due_date < @start_date
        THROW 50400, N'dueDate|Due date cannot be before the start date.', 1;
    IF @time_estimate_minutes < 0
        THROW 50400, N'timeEstimateMinutes|Time estimate cannot be negative.', 1;
    IF @rating IS NOT NULL AND @rating NOT BETWEEN 0 AND 3
        THROW 50400, N'rating|Rating runs from 1 (Fair) to 3 (Excellent).', 1;
    IF @url IS NOT NULL AND @url NOT LIKE N'http://_%' AND @url NOT LIKE N'https://_%'
        THROW 50400, N'url|A link must begin with http:// or https://.', 1;
    IF @recurrence IS NOT NULL AND ISJSON(@recurrence) = 0
        THROW 50400, N'recurrence|Recurrence is not valid.', 1;

    DECLARE @rank INT, @me BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @feat TABLE (feature_code NVARCHAR(50) PRIMARY KEY);

    IF @id IS NULL
    BEGIN
        ---------------------------------------------------------------- add
        DECLARE @parent_assigned BIT = 0;
        IF @parent_task_id IS NOT NULL
        BEGIN
            DECLARE @p_due DATE, @p_due_time TIME(0);
            SET @workspace_id = NULL;
            SELECT @workspace_id = t.workspace_id, @task_list_id = t.task_list_id, @p_due = t.due_date, @p_due_time = t.due_time
            FROM [pm].[task] t JOIN [pm].[fn_task_access](@company_id, @actor_user_id) a ON a.task_id = t.id
            WHERE t.id = @parent_task_id;
            IF @workspace_id IS NULL
                THROW 50400, N'parentTaskId|Parent task not found.', 1;
            IF @due_date IS NULL
                SELECT @due_date = @p_due, @due_time = @p_due_time;
        END
        SELECT @rank = role_rank, @me = employee_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
        IF @rank IS NULL
            THROW 50404, N'Workspace not found', 1;
        IF @parent_task_id IS NOT NULL AND EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @parent_task_id AND employee_id = @me)
            SET @parent_assigned = 1;
        IF @rank < 2 AND NOT (@rank = 1 AND @parent_assigned = 1)
            THROW 50403, N'Only team leaders and above add tasks. Contributors may add subtasks to tasks assigned to them.', 1;
        IF @task_list_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[task_list] WHERE id = @task_list_id AND workspace_id = @workspace_id)
            THROW 50400, N'taskListId|List not found in this workspace.', 1;

        IF @status_id IS NULL
            SELECT TOP 1 @status_id = id FROM [pm].[workspace_status]
            WHERE workspace_id = @workspace_id AND status_group = N'not_started' ORDER BY sort_order, id;
        ELSE IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_status] WHERE id = @status_id AND workspace_id = @workspace_id)
            THROW 50400, N'statusId|Status not found in this workspace.', 1;

        INSERT @feat SELECT feature_code FROM [pm].[workspace_feature] WHERE workspace_id = @workspace_id;
        IF @priority IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'priority')
            THROW 50409, N'priority|FEATURE_OFF|Priority is switched off for this workspace.', 1;
        IF @time_estimate_minutes IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'time_estimate')
            THROW 50409, N'timeEstimateMinutes|FEATURE_OFF|Time estimates are switched off for this workspace.', 1;

        DECLARE @as TABLE (employee_id BIGINT PRIMARY KEY);
        INSERT @as SELECT DISTINCT CAST(value AS BIGINT) FROM OPENJSON(ISNULL(@assignee_ids, N'[]'));
        DECLARE @tg TABLE (tag_id BIGINT PRIMARY KEY);
        INSERT @tg SELECT DISTINCT CAST(value AS BIGINT) FROM OPENJSON(ISNULL(@tag_ids, N'[]'));
        IF EXISTS (SELECT 1 FROM @as a WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @workspace_id AND m.employee_id = a.employee_id))
            THROW 50400, N'assigneeIds|Assignees must be members of the workspace.', 1;
        IF @rank < 2 AND EXISTS (SELECT 1 FROM @as WHERE employee_id <> @me)
            THROW 50403, N'Only team leaders and above assign tasks to others.', 1;
        IF (SELECT COUNT(*) FROM @as) > 1 AND NOT EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'multiple_assignees')
            THROW 50409, N'assigneeIds|FEATURE_OFF|This workspace allows one assignee per task.', 1;
        IF EXISTS (SELECT 1 FROM @tg) AND NOT EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'tags')
            THROW 50409, N'tagIds|FEATURE_OFF|Tags are switched off for this workspace.', 1;
        IF EXISTS (SELECT 1 FROM @tg g WHERE NOT EXISTS (SELECT 1 FROM [pm].[tag] t WHERE t.id = g.tag_id AND t.workspace_id = @workspace_id))
            THROW 50400, N'tagIds|Tag not found in this workspace.', 1;

        DECLARE @group NVARCHAR(30) = (SELECT status_group FROM [pm].[workspace_status] WHERE id = @status_id);

        BEGIN TRAN;
            DECLARE @n BIGINT;
            DECLARE @seq TABLE (n BIGINT);
            UPDATE [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK)
            SET next_number = next_number + 1, updated_at = @now
            OUTPUT DELETED.next_number INTO @seq
            WHERE company_id = @company_id AND prefix = N'PMTASK';
            SET @n = (SELECT n FROM @seq);
            IF @n IS NULL
            BEGIN
                SET @n = 1;
                INSERT [core].[number_sequence] (company_id, prefix, next_number, created_by) VALUES (@company_id, N'PMTASK', 2, @actor_user_id);
            END

            INSERT [pm].[task] (company_id, workspace_id, task_list_id, parent_task_id, code, name, description, task_type, status_id,
                                priority, start_date, start_time, due_date, due_time, time_estimate_minutes, rating, url, recurrence,
                                sort_order, closed_at, created_by)
            VALUES (@company_id, @workspace_id, @task_list_id, @parent_task_id, N'HR' + RIGHT(N'000000000' + CAST(@n AS NVARCHAR(20)), 9),
                    @name, @description, @task_type, @status_id, @priority, @start_date, @start_time, @due_date, @due_time,
                    @time_estimate_minutes, NULLIF(@rating, 0), @url, @recurrence,
                    ISNULL((SELECT MAX(sort_order) FROM [pm].[task] WHERE workspace_id = @workspace_id), 0) + 10,
                    CASE WHEN @group IN (N'done', N'closed') THEN @now END, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [pm].[task_assignee] (task_id, employee_id, created_by) SELECT @id, employee_id, @actor_user_id FROM @as;
            INSERT [pm].[task_tag] (task_id, tag_id, created_by) SELECT @id, tag_id, @actor_user_id FROM @tg;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @id, N'name', @name, N'create', @actor_user_id, @now);

            IF EXISTS (SELECT 1 FROM @as)
            BEGIN
                DECLARE @assigned NVARCHAR(MAX) = (SELECT CONCAT(N'[', STRING_AGG(CONVERT(NVARCHAR(MAX), employee_id), N','), N']') FROM @as);
                EXEC [pm].[usp_task_announce_assigned] @company_id = @company_id, @actor_user_id = @actor_user_id,
                     @task_id = @id, @employee_ids = @assigned;
            END
        COMMIT;
    END
    ELSE
    BEGIN
        ---------------------------------------------------------------- edit
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a task', 1;
        SELECT @workspace_id = workspace_id, @rank = role_rank, @me = employee_id
        FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
        IF @rank IS NULL
            THROW 50404, N'Task not found', 1;

        DECLARE @o_name NVARCHAR(200), @o_desc NVARCHAR(MAX), @o_type NVARCHAR(30), @o_priority NVARCHAR(30),
                @o_start DATE, @o_start_time TIME(0), @o_due DATE, @o_due_time TIME(0), @o_est INT, @o_rating INT,
                @o_url NVARCHAR(2000), @o_rec NVARCHAR(MAX), @o_rv BINARY(8), @creator BIGINT;
        SELECT @o_name = name, @o_desc = description, @o_type = task_type, @o_priority = priority, @o_start = start_date,
               @o_start_time = start_time, @o_due = due_date, @o_due_time = due_time, @o_est = time_estimate_minutes,
               @o_rating = rating, @o_url = url, @o_rec = recurrence, @o_rv = row_version, @creator = created_by
        FROM [pm].[task] WHERE id = @id;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed this task. Reload it and try again', 1;
        IF @rank < 2 AND NOT (@rank >= 1 AND @creator = @actor_user_id)
            THROW 50403, N'Only team leaders and above, or the task''s creator, can edit this task.', 1;

        SET @rating = NULLIF(@rating, 0);
        DECLARE @changed TABLE (column_key NVARCHAR(50), field_name NVARCHAR(100), old_value NVARCHAR(MAX), new_value NVARCHAR(MAX));
        INSERT @changed
        SELECT c.column_key, c.field_name, c.old_value, c.new_value
        FROM (VALUES
            (N'name', N'name', @o_name, @name),
            (NULL, N'description', @o_desc, @description),
            (NULL, N'task_type', @o_type, @task_type),
            (N'priority', N'priority', @o_priority, @priority),
            (N'start_date', N'start_date', CONVERT(NVARCHAR(10), @o_start, 23), CONVERT(NVARCHAR(10), @start_date, 23)),
            (N'start_date', N'start_time', CONVERT(NVARCHAR(8), @o_start_time, 108), CONVERT(NVARCHAR(8), @start_time, 108)),
            (N'due_date', N'due_date', CONVERT(NVARCHAR(10), @o_due, 23), CONVERT(NVARCHAR(10), @due_date, 23)),
            (N'due_date', N'due_time', CONVERT(NVARCHAR(8), @o_due_time, 108), CONVERT(NVARCHAR(8), @due_time, 108)),
            (N'due_date', N'recurrence', @o_rec, @recurrence),
            (N'time_estimate', N'time_estimate_minutes', CONVERT(NVARCHAR(30), @o_est), CONVERT(NVARCHAR(30), @time_estimate_minutes)),
            (N'story_points', N'rating', CONVERT(NVARCHAR(30), @o_rating), CONVERT(NVARCHAR(30), @rating)),
            (NULL, N'url', @o_url, @url)
        ) c (column_key, field_name, old_value, new_value)
        WHERE EXISTS (SELECT c.old_value EXCEPT SELECT c.new_value);

        IF EXISTS (SELECT 1 FROM @changed c JOIN [pm].[fn_column_levels](@workspace_id, @me) l ON l.column_key = c.column_key
                   WHERE l.permission_level IN (N'can_view', N'private'))
            THROW 50403, N'You can view but not change one of these fields (column permission).', 1;

        INSERT @feat SELECT feature_code FROM [pm].[workspace_feature] WHERE workspace_id = @workspace_id;
        IF EXISTS (SELECT 1 FROM @changed WHERE field_name = N'priority') AND @priority IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'priority')
            THROW 50409, N'priority|FEATURE_OFF|Priority is switched off for this workspace.', 1;
        IF EXISTS (SELECT 1 FROM @changed WHERE field_name = N'time_estimate_minutes') AND @time_estimate_minutes IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'time_estimate')
            THROW 50409, N'timeEstimateMinutes|FEATURE_OFF|Time estimates are switched off for this workspace.', 1;

        DECLARE @shift INT = CASE WHEN @o_due IS NOT NULL AND @due_date IS NOT NULL THEN DATEDIFF(DAY, @o_due, @due_date) ELSE 0 END;

        BEGIN TRAN;
            UPDATE [pm].[task]
            SET name = @name, description = @description, task_type = @task_type, priority = @priority,
                start_date = @start_date, start_time = @start_time, due_date = @due_date, due_time = @due_time,
                time_estimate_minutes = @time_estimate_minutes, rating = @rating, url = @url, recurrence = @recurrence,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this task. Reload it and try again', 1;

            IF @shift <> 0 AND EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'remap_subtask_due_dates')
                UPDATE [pm].[task] SET due_date = DATEADD(DAY, @shift, due_date), updated_at = @now, updated_by = @actor_user_id
                WHERE parent_task_id = @id AND due_date IS NOT NULL;
            IF @shift <> 0 AND EXISTS (SELECT 1 FROM @feat WHERE feature_code = N'reschedule_dependencies')
                UPDATE w SET start_date = DATEADD(DAY, @shift, w.start_date), due_date = DATEADD(DAY, @shift, w.due_date),
                             updated_at = @now, updated_by = @actor_user_id
                FROM [pm].[task] w JOIN [pm].[task_dependency] d ON d.task_id = w.id
                WHERE d.other_task_id = @id AND d.kind = N'waiting_on';

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'pm.task', @id, field_name, old_value, new_value, N'update', @actor_user_id, @now FROM @changed;
        COMMIT;
    END

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
