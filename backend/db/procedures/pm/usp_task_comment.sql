-- Task comments: threads (replies), @mentions of people and tasks, assigning a comment, Mark as
-- Resolve, reactions. Workspace members comment on tasks they can see; authors edit their own
-- (BRD "may edit or delete only their own comments"); team leaders and above assign comments.

CREATE OR ALTER PROCEDURE [pm].[usp_task_comment_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT = NULL,
    @id            BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL
        SET @task_id = (SELECT task_id FROM [pm].[task_comment] WHERE id = @id);
    DECLARE @me BIGINT;
    SELECT @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id)
        THROW 50404, N'Task not found', 1;

    SELECT c.id, c.task_id, c.parent_id, c.author_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS author_name, c.body,
           c.assigned_to_id, NULLIF(CONCAT(t.first_name, N' ', t.last_name), N' ') AS assigned_to_name,
           c.assigned_by_id, NULLIF(CONCAT(b.first_name, N' ', b.last_name), N' ') AS assigned_by_name,
           CAST(CASE WHEN c.resolved_at IS NULL THEN 0 ELSE 1 END AS BIT) AS is_resolved,
           c.resolved_by_id, NULLIF(CONCAT(r.first_name, N' ', r.last_name), N' ') AS resolved_by_name, c.resolved_at,
           c.edited_at, c.created_at,
           (SELECT COUNT(*) FROM [pm].[task_comment] x WHERE x.parent_id = c.id) AS reply_count,
           (SELECT x.employee_id, x.reaction FROM [pm].[comment_reaction] x WHERE x.comment_id = c.id FOR JSON PATH) AS reactions_json,
           (SELECT m.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name, m.mentioned_task_id AS task_id, mt.code AS task_code,
                   mt.name AS task_name
            FROM [pm].[comment_mention] m
            LEFT JOIN [hr].[employee] e ON e.id = m.employee_id
            LEFT JOIN [pm].[task] mt ON mt.id = m.mentioned_task_id
            WHERE m.comment_id = c.id FOR JSON PATH) AS mentions_json,
           c.row_version
    FROM [pm].[task_comment] c
    JOIN [hr].[employee] a ON a.id = c.author_id
    LEFT JOIN [hr].[employee] t ON t.id = c.assigned_to_id
    LEFT JOIN [hr].[employee] b ON b.id = c.assigned_by_id
    LEFT JOIN [hr].[employee] r ON r.id = c.resolved_by_id
    WHERE c.task_id = @task_id AND (@id IS NULL OR c.id = @id)
    ORDER BY c.created_at, c.id;
END
GO

-- Adds a comment or reply (@id NULL) or edits the caller's own comment.
-- @mentions: [{"employee_id"} or {"task_id"}].
CREATE OR ALTER PROCEDURE [pm].[usp_task_comment_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @id             BIGINT = NULL,
    @task_id        BIGINT = NULL,
    @parent_id      BIGINT = NULL,
    @body           NVARCHAR(MAX),
    @assigned_to_id BIGINT = NULL,
    @mentions       NVARCHAR(MAX) = NULL,
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @author BIGINT, @rv BINARY(8);
    IF @id IS NOT NULL
        SELECT @task_id = task_id, @author = author_id, @rv = row_version FROM [pm].[task_comment] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 1
        THROW 50403, N'Only workspace members can comment.', 1;

    SET @body = LTRIM(RTRIM(@body));
    IF @body IS NULL OR @body = N''
        THROW 50400, N'body|Write a comment first.', 1;
    IF LEN(@body) > 2000
        THROW 50400, N'body|A comment must be within 2000 characters.', 1;

    DECLARE @mn TABLE (employee_id BIGINT, task_id BIGINT);
    INSERT @mn SELECT DISTINCT j.employee_id, j.task_id
    FROM OPENJSON(ISNULL(@mentions, N'[]')) WITH (employee_id BIGINT '$.employee_id', task_id BIGINT '$.task_id') j
    WHERE j.employee_id IS NOT NULL OR j.task_id IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @mn m WHERE m.employee_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = m.employee_id AND e.company_id = @company_id))
        THROW 50400, N'mentions|A mentioned person was not found.', 1;
    IF EXISTS (SELECT 1 FROM @mn m WHERE m.task_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) a WHERE a.task_id = m.task_id))
        THROW 50400, N'mentions|A mentioned task was not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        IF @parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[task_comment] WHERE id = @parent_id AND task_id = @task_id)
            THROW 50400, N'parentId|The comment you reply to was not found.', 1;
        IF @assigned_to_id IS NOT NULL AND @rank < 2
            THROW 50403, N'Only team leaders and above can assign comments.', 1;
        IF @assigned_to_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] WHERE workspace_id = @ws AND employee_id = @assigned_to_id)
            THROW 50400, N'assignedToId|Comments are assigned to workspace members.', 1;

        BEGIN TRAN;
            INSERT [pm].[task_comment] (task_id, author_id, body, parent_id, assigned_to_id, assigned_by_id, created_by)
            VALUES (@task_id, @me, @body, @parent_id, @assigned_to_id, CASE WHEN @assigned_to_id IS NOT NULL THEN @me END, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [pm].[comment_mention] (comment_id, employee_id, mentioned_task_id, created_by)
            SELECT @id, employee_id, task_id, @actor_user_id FROM @mn;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @task_id, N'comment', LEFT(@body, 200), N'comment', @actor_user_id, @now);

            DECLARE @mentioned NVARCHAR(MAX) = (SELECT CONCAT(N'[', STRING_AGG(CONVERT(NVARCHAR(MAX), employee_id), N','), N']')
                                                FROM @mn WHERE employee_id IS NOT NULL);
            EXEC [pm].[usp_task_announce_mention] @company_id = @company_id, @actor_user_id = @actor_user_id,
                 @comment_id = @id, @employee_ids = @mentioned;
        COMMIT;
    END
    ELSE
    BEGIN
        IF @author <> @me
            THROW 50403, N'You can edit only your own comments.', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;
        -- Only people the edit newly mentions are told.
        DECLARE @newly NVARCHAR(MAX) = (
            SELECT CONCAT(N'[', STRING_AGG(CONVERT(NVARCHAR(MAX), m.employee_id), N','), N']') FROM @mn m
            WHERE m.employee_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM [pm].[comment_mention] x WHERE x.comment_id = @id AND x.employee_id = m.employee_id));
        BEGIN TRAN;
            UPDATE [pm].[task_comment] SET body = @body, edited_at = @now, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;
            DELETE [pm].[comment_mention] WHERE comment_id = @id;
            INSERT [pm].[comment_mention] (comment_id, employee_id, mentioned_task_id, created_by)
            SELECT @id, employee_id, task_id, @actor_user_id FROM @mn;

            EXEC [pm].[usp_task_announce_mention] @company_id = @company_id, @actor_user_id = @actor_user_id,
                 @comment_id = @id, @employee_ids = @newly;
        COMMIT;
    END

    EXEC [pm].[usp_task_comment_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Assigns a comment to a workspace member, or takes the assignment off (@assigned_to_id NULL).
CREATE OR ALTER PROCEDURE [pm].[usp_task_comment_assign]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @id             BIGINT,
    @assigned_to_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @task_id BIGINT = (SELECT task_id FROM [pm].[task_comment] WHERE id = @id);
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Comment not found', 1;
    IF @rank < 2
        THROW 50403, N'Only team leaders and above can assign comments.', 1;
    IF @assigned_to_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] WHERE workspace_id = @ws AND employee_id = @assigned_to_id)
        THROW 50400, N'assignedToId|Comments are assigned to workspace members.', 1;

    UPDATE [pm].[task_comment]
    SET assigned_to_id = @assigned_to_id, assigned_by_id = CASE WHEN @assigned_to_id IS NULL THEN NULL ELSE @me END,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @id;

    EXEC [pm].[usp_task_comment_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Mark as Resolve (or reopen): the author, the person it is assigned to, or team leaders and above.
CREATE OR ALTER PROCEDURE [pm].[usp_task_comment_resolve]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @is_resolved   BIT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @task_id BIGINT, @author BIGINT, @assignee BIGINT;
    SELECT @task_id = task_id, @author = author_id, @assignee = assigned_to_id FROM [pm].[task_comment] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Comment not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND (@me = @author OR @me = @assignee))
        THROW 50403, N'Only the author, the assignee or a team leader can resolve this comment.', 1;

    UPDATE [pm].[task_comment]
    SET resolved_at = CASE WHEN @is_resolved = 1 THEN ISNULL(resolved_at, SYSUTCDATETIME()) END,
        resolved_by_id = CASE WHEN @is_resolved = 1 THEN ISNULL(resolved_by_id, @me) END,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @id;

    EXEC [pm].[usp_task_comment_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Like or emoji on a comment, one per person; @reaction NULL takes it off.
CREATE OR ALTER PROCEDURE [pm].[usp_task_comment_react]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @reaction      NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task_id BIGINT = (SELECT task_id FROM [pm].[task_comment] WHERE id = @id);
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Comment not found', 1;
    IF @rank < 1
        THROW 50403, N'Only workspace members can react to comments.', 1;

    BEGIN TRAN;
        DELETE [pm].[comment_reaction] WHERE comment_id = @id AND employee_id = @me;
        IF NULLIF(@reaction, N'') IS NOT NULL
            INSERT [pm].[comment_reaction] (comment_id, employee_id, reaction, created_by) VALUES (@id, @me, @reaction, @actor_user_id);
    COMMIT;

    EXEC [pm].[usp_task_comment_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Deletes a comment and its replies: the author, or managers and above.
CREATE OR ALTER PROCEDURE [pm].[usp_task_comment_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task_id BIGINT, @author BIGINT, @rv BINARY(8);
    SELECT @task_id = task_id, @author = author_id, @rv = row_version FROM [pm].[task_comment] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Comment not found', 1;
    IF @rank < 3 AND NOT (@rank >= 1 AND @me = @author)
        THROW 50403, N'You can delete only your own comments.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    WITH tree AS (
        SELECT id FROM [pm].[task_comment] WHERE id = @id
        UNION ALL
        SELECT c.id FROM [pm].[task_comment] c JOIN tree ON c.parent_id = tree.id
    )
    INSERT @ids SELECT id FROM tree OPTION (MAXRECURSION 100);

    BEGIN TRAN;
        DELETE r FROM [pm].[comment_reaction] r JOIN @ids x ON x.id = r.comment_id;
        DELETE m FROM [pm].[comment_mention] m JOIN @ids x ON x.id = m.comment_id;
        DELETE c FROM [pm].[task_comment] c JOIN @ids x ON x.id = c.id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task_id, N'comment', N'comment_delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
