-- Telling people about work: a task assigned to them, a comment that mentions them, a comment on their
-- task or a reply to theirs, extension requests and decisions. Called inside the caller's transaction;
-- no result set. The person who did it is never notified about their own action. Every link opens the
-- task panel: /project-management/workspaces/{workspaceId}?task={taskId}.

-- projects.task_assigned: one event for the task with the people newly assigned, and a notification
-- to each of them. @employee_ids: JSON array of the employees just added as assignees.
CREATE OR ALTER PROCEDURE [pm].[usp_task_announce_assigned]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT,
    @employee_ids  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @people SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) FROM OPENJSON(ISNULL(@employee_ids, N'[]'))
    WHERE TRY_CONVERT(BIGINT, [value]) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @people)
        RETURN;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @code NVARCHAR(30), @name NVARCHAR(200), @ws BIGINT, @payload NVARCHAR(MAX);
    SELECT @code = t.code, @name = t.name, @ws = t.workspace_id,
           @payload = (SELECT CONVERT(NVARCHAR(30), t.id) AS taskId, t.code, t.name, CONVERT(NVARCHAR(30), t.workspace_id) AS workspaceId,
                              w.name AS workspaceName, CONVERT(NVARCHAR(10), t.due_date, 23) AS dueDate, t.priority,
                              (SELECT CONVERT(NVARCHAR(30), p.employee_id) AS employeeId FROM @people p FOR JSON PATH) AS assigned,
                              CONVERT(NVARCHAR(30), @actor_user_id) AS assignedBy
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM [pm].[task] t JOIN [pm].[workspace] w ON w.id = t.workspace_id
    WHERE t.id = @task_id AND t.company_id = @company_id;
    IF @payload IS NULL
        RETURN;

    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'projects.task_assigned',
         @entity_type = N'pm.task', @entity_id = @task_id, @payload = @payload;

    DECLARE @title NVARCHAR(200) = LEFT(CONCAT(N'Task assigned to you: ', @code, N' ', @name), 200);
    DECLARE @link NVARCHAR(500) = CONCAT(N'/project-management/workspaces/', @ws, N'?task=', @task_id);
    DECLARE @emp BIGINT = (SELECT MIN(employee_id) FROM @people WHERE employee_id <> ISNULL(@me, -1));
    WHILE @emp IS NOT NULL
    BEGIN
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
             @title = @title, @notification_type = N'task', @link = @link, @entity_type = N'pm.task', @entity_id = @task_id;
        SET @emp = (SELECT MIN(employee_id) FROM @people WHERE employee_id > @emp AND employee_id <> ISNULL(@me, -1));
    END
END
GO

-- projects.comment_mention: one event for the comment with the people newly mentioned, and a
-- notification to each of them. @employee_ids: JSON array of the employees just mentioned.
CREATE OR ALTER PROCEDURE [pm].[usp_task_announce_mention]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @comment_id    BIGINT,
    @employee_ids  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @people SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) FROM OPENJSON(ISNULL(@employee_ids, N'[]'))
    WHERE TRY_CONVERT(BIGINT, [value]) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @people)
        RETURN;

    DECLARE @task_id BIGINT, @ws BIGINT, @code NVARCHAR(30), @author NVARCHAR(400), @author_id BIGINT,
            @body NVARCHAR(MAX), @payload NVARCHAR(MAX);
    SELECT @task_id = t.id, @ws = t.workspace_id, @code = t.code, @author_id = c.author_id,
           @author = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), @body = LEFT(c.body, 300),
           @payload = (SELECT CONVERT(NVARCHAR(30), c.id) AS commentId, CONVERT(NVARCHAR(30), t.id) AS taskId, t.code AS taskCode,
                              t.name AS taskName, CONVERT(NVARCHAR(30), t.workspace_id) AS workspaceId,
                              CONVERT(NVARCHAR(30), c.author_id) AS authorId, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS authorName,
                              LEFT(c.body, 300) AS excerpt,
                              (SELECT CONVERT(NVARCHAR(30), p.employee_id) AS employeeId FROM @people p FOR JSON PATH) AS mentioned
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM [pm].[task_comment] c
    JOIN [pm].[task] t ON t.id = c.task_id AND t.company_id = @company_id
    LEFT JOIN [hr].[employee] e ON e.id = c.author_id
    WHERE c.id = @comment_id;
    IF @payload IS NULL
        RETURN;

    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'projects.comment_mention',
         @entity_type = N'pm.task_comment', @entity_id = @comment_id, @payload = @payload;

    DECLARE @title NVARCHAR(200) = LEFT(CONCAT(ISNULL(@author, N'Someone'), N' mentioned you on ', @code), 200);
    DECLARE @link NVARCHAR(500) = CONCAT(N'/project-management/workspaces/', @ws, N'?task=', @task_id);
    DECLARE @emp BIGINT = (SELECT MIN(employee_id) FROM @people WHERE employee_id <> ISNULL(@author_id, -1));
    WHILE @emp IS NOT NULL
    BEGIN
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
             @title = @title, @body = @body, @notification_type = N'mention', @link = @link,
             @entity_type = N'pm.task_comment', @entity_id = @comment_id;
        SET @emp = (SELECT MIN(employee_id) FROM @people WHERE employee_id > @emp AND employee_id <> ISNULL(@author_id, -1));
    END
END
GO

-- projects.comment_added: a new comment or reply on a task. The task's assignees are told (type
-- projects.comment); for a reply, so is the author of the comment replied to (projects.comment_reply).
-- Nobody hears twice: people the comment mentions were told by usp_task_announce_mention, and an
-- assignee whose comment got a reply hears about it as an assignee. The author is never told.
CREATE OR ALTER PROCEDURE [pm].[usp_task_announce_comment]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @comment_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task_id BIGINT, @ws BIGINT, @code NVARCHAR(30), @task_name NVARCHAR(200), @author_id BIGINT,
            @author NVARCHAR(400), @body NVARCHAR(MAX), @parent_id BIGINT, @parent_author BIGINT;
    SELECT @task_id = t.id, @ws = t.workspace_id, @code = t.code, @task_name = t.name, @author_id = c.author_id,
           @author = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), @body = LEFT(c.body, 300),
           @parent_id = c.parent_id, @parent_author = p.author_id
    FROM [pm].[task_comment] c
    JOIN [pm].[task] t ON t.id = c.task_id AND t.company_id = @company_id
    LEFT JOIN [hr].[employee] e ON e.id = c.author_id
    LEFT JOIN [pm].[task_comment] p ON p.id = c.parent_id
    WHERE c.id = @comment_id;
    IF @task_id IS NULL
        RETURN;

    DECLARE @told TABLE (employee_id BIGINT PRIMARY KEY, kind NVARCHAR(30));
    INSERT @told SELECT a.employee_id, N'projects.comment' FROM [pm].[task_assignee] a WHERE a.task_id = @task_id;
    INSERT @told SELECT @parent_author, N'projects.comment_reply'
    WHERE @parent_author IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @told WHERE employee_id = @parent_author);
    DELETE @told
    WHERE employee_id = ISNULL(@author_id, -1)
       OR employee_id IN (SELECT m.employee_id FROM [pm].[comment_mention] m WHERE m.comment_id = @comment_id AND m.employee_id IS NOT NULL);

    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), @comment_id) AS commentId, CONVERT(NVARCHAR(30), @parent_id) AS parentId,
               CONVERT(NVARCHAR(30), @task_id) AS taskId, @code AS taskCode, @task_name AS taskName,
               CONVERT(NVARCHAR(30), @ws) AS workspaceId, CONVERT(NVARCHAR(30), @author_id) AS authorId,
               @author AS authorName, @body AS excerpt,
               (SELECT CONVERT(NVARCHAR(30), x.employee_id) AS employeeId, x.kind FROM @told x FOR JSON PATH) AS notified
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'projects.comment_added',
         @entity_type = N'pm.task_comment', @entity_id = @comment_id, @payload = @payload;

    DECLARE @link NVARCHAR(500) = CONCAT(N'/project-management/workspaces/', @ws, N'?task=', @task_id);
    DECLARE @title NVARCHAR(200), @kind NVARCHAR(30), @emp BIGINT = (SELECT MIN(employee_id) FROM @told);
    WHILE @emp IS NOT NULL
    BEGIN
        SET @kind = (SELECT kind FROM @told WHERE employee_id = @emp);
        SET @title = LEFT(CONCAT(ISNULL(@author, N'Someone'),
                                 CASE @kind WHEN N'projects.comment_reply' THEN N' replied to your comment on ' ELSE N' commented on ' END,
                                 @code, N' ', @task_name), 200);
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
             @title = @title, @body = @body, @notification_type = @kind, @link = @link,
             @entity_type = N'pm.task_comment', @entity_id = @comment_id;
        SET @emp = (SELECT MIN(employee_id) FROM @told WHERE employee_id > @emp);
    END
END
GO

-- projects.extension_requested / projects.extension_decided: a Request Extension and its answer. A new
-- request tells the workspace's managers and above who can open the task (for a task in a private list:
-- workspace admins, HR and managers who are members of the list); a decision tells the person who asked.
-- The notification type is the event type.
CREATE OR ALTER PROCEDURE [pm].[usp_task_announce_extension]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @extension_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task_id BIGINT, @ws BIGINT, @code NVARCHAR(30), @task_name NVARCHAR(200), @list BIGINT, @private_list BIT,
            @due DATE, @status NVARCHAR(30), @requester BIGINT, @requester_name NVARCHAR(400), @decider_name NVARCHAR(400),
            @old_due DATE, @new_due DATE, @reason NVARCHAR(MAX), @remarks NVARCHAR(MAX);
    SELECT @task_id = t.id, @ws = t.workspace_id, @code = t.code, @task_name = t.name, @list = t.task_list_id,
           @private_list = CASE WHEN l.privacy = N'private' THEN 1 ELSE 0 END, @due = t.due_date,
           @status = x.status, @requester = x.requested_by_id,
           @requester_name = NULLIF(CONCAT(r.first_name, N' ', r.last_name), N' '),
           @decider_name = NULLIF(CONCAT(d.first_name, N' ', d.last_name), N' '),
           @old_due = x.old_due_date, @new_due = x.new_due_date, @reason = x.reason, @remarks = x.remarks
    FROM [pm].[task_extension] x
    JOIN [pm].[task] t ON t.id = x.task_id AND t.company_id = @company_id
    LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id
    LEFT JOIN [hr].[employee] r ON r.id = x.requested_by_id
    LEFT JOIN [hr].[employee] d ON d.id = x.decided_by_id
    WHERE x.id = @extension_id;
    IF @task_id IS NULL
        RETURN;

    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    IF @status = N'pending'
        INSERT @people SELECT m.employee_id FROM [pm].[workspace_member] m
        WHERE m.workspace_id = @ws AND m.member_role IN (N'workspace_admin', N'hr', N'manager')
          AND m.employee_id <> ISNULL(@requester, -1)
          AND (@private_list = 0 OR m.member_role IN (N'workspace_admin', N'hr')
               OR EXISTS (SELECT 1 FROM [pm].[task_list_member] lm WHERE lm.task_list_id = @list AND lm.employee_id = m.employee_id));
    ELSE
        INSERT @people SELECT @requester WHERE @requester IS NOT NULL;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DELETE @people WHERE employee_id = ISNULL(@me, -1);

    DECLARE @event NVARCHAR(100) = CASE WHEN @status = N'pending' THEN N'projects.extension_requested'
                                        ELSE N'projects.extension_decided' END;
    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), @extension_id) AS extensionId, CONVERT(NVARCHAR(30), @task_id) AS taskId,
               @code AS taskCode, @task_name AS taskName, CONVERT(NVARCHAR(30), @ws) AS workspaceId, @status AS status,
               CONVERT(NVARCHAR(30), @requester) AS requestedById, CONVERT(NVARCHAR(10), @old_due, 23) AS oldDueDate,
               CONVERT(NVARCHAR(10), @new_due, 23) AS newDueDate, @reason AS reason, @remarks AS remarks,
               (SELECT CONVERT(NVARCHAR(30), p.employee_id) AS employeeId FROM @people p FOR JSON PATH) AS notified
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event,
         @entity_type = N'pm.task_extension', @entity_id = @extension_id, @payload = @payload;

    DECLARE @title NVARCHAR(200) = LEFT(CONCAT(CASE @status WHEN N'pending' THEN N'Extension requested: '
                                                            WHEN N'approved' THEN N'Extension approved: '
                                                            ELSE N'Extension rejected: ' END, @code, N' ', @task_name), 200);
    DECLARE @body NVARCHAR(MAX) = CASE @status
        WHEN N'pending' THEN CONCAT(ISNULL(@requester_name, N'Someone'), N' asks to move the due date from ',
                                    CONVERT(NVARCHAR(10), @old_due, 23), N' to ', CONVERT(NVARCHAR(10), @new_due, 23),
                                    N'. Reason: ', LEFT(@reason, 300))
        WHEN N'approved' THEN CONCAT(ISNULL(@decider_name, N'A manager'), N' approved it. The task is now due on ',
                                     CONVERT(NVARCHAR(10), @new_due, 23), N'.', N' ' + LEFT(@remarks, 300))
        ELSE CONCAT(ISNULL(@decider_name, N'A manager'), N' rejected it. The due date stays ',
                    CONVERT(NVARCHAR(10), @due, 23), N'.', N' ' + LEFT(@remarks, 300)) END;
    DECLARE @link NVARCHAR(500) = CONCAT(N'/project-management/workspaces/', @ws, N'?task=', @task_id);
    DECLARE @emp BIGINT = (SELECT MIN(employee_id) FROM @people);
    WHILE @emp IS NOT NULL
    BEGIN
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
             @title = @title, @body = @body, @notification_type = @event, @link = @link,
             @entity_type = N'pm.task_extension', @entity_id = @extension_id;
        SET @emp = (SELECT MIN(employee_id) FROM @people WHERE employee_id > @emp);
    END
END
