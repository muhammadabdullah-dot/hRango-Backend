-- Telling people about work: a task assigned to them, a comment that mentions them. Called inside the
-- caller's transaction; no result set. The person who did it is never notified about their own action.

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
