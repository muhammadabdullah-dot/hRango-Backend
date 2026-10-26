-- Move To (another list or workspace), Convert to Subtask (@parent_task_id), Convert to Task
-- (@parent_task_id NULL), and reordering (@sort_order). The task's subtasks move with it.
-- Team leaders and above, in both workspaces. Moving to another workspace maps the status to the
-- first status of the same group there and drops what belongs to the old workspace: tags, custom
-- field values, dependencies, and assignees who are not members of the new one.
CREATE OR ALTER PROCEDURE [pm].[usp_task_move]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @id             BIGINT,
    @workspace_id   BIGINT = NULL,
    @task_list_id   BIGINT = NULL,
    @parent_task_id BIGINT = NULL,
    @sort_order     INT = NULL,
    @row_version    BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @src_ws BIGINT, @rank INT;
    SELECT @src_ws = workspace_id, @rank = role_rank FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @src_ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 2
        THROW 50403, N'Only team leaders and above can move tasks.', 1;
    IF (SELECT row_version FROM [pm].[task] WHERE id = @id) <> @row_version
        THROW 50409, N'Someone else changed this task. Reload it and try again', 1;

    IF @parent_task_id IS NOT NULL
    BEGIN
        SET @workspace_id = NULL;
        SELECT @workspace_id = t.workspace_id, @task_list_id = t.task_list_id
        FROM [pm].[task] t JOIN [pm].[fn_task_access](@company_id, @actor_user_id) a ON a.task_id = t.id
        WHERE t.id = @parent_task_id;
        IF @workspace_id IS NULL
            THROW 50400, N'parentTaskId|Parent task not found.', 1;
    END
    SET @workspace_id = ISNULL(@workspace_id, @src_ws);

    DECLARE @dst_rank INT;
    SELECT @dst_rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @dst_rank IS NULL
        THROW 50400, N'workspaceId|Workspace not found.', 1;
    IF @dst_rank < 2
        THROW 50403, N'Only team leaders and above can move tasks into that workspace.', 1;
    IF @task_list_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[task_list] WHERE id = @task_list_id AND workspace_id = @workspace_id)
        THROW 50400, N'taskListId|List not found in that workspace.', 1;

    -- The subtree that moves.
    CREATE TABLE #tree (task_id BIGINT PRIMARY KEY);
    WITH tree AS (
        SELECT id FROM [pm].[task] WHERE id = @id
        UNION ALL
        SELECT c.id FROM [pm].[task] c JOIN tree ON c.parent_task_id = tree.id
    )
    INSERT #tree SELECT id FROM tree OPTION (MAXRECURSION 100);
    IF @parent_task_id IN (SELECT task_id FROM #tree)
        THROW 50400, N'parentTaskId|A task cannot sit under itself or one of its own subtasks.', 1;

    DECLARE @old_list BIGINT, @old_parent BIGINT;
    SELECT @old_list = task_list_id, @old_parent = parent_task_id FROM [pm].[task] WHERE id = @id;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        IF @workspace_id <> @src_ws
        BEGIN
            UPDATE t SET status_id = ISNULL(
                    (SELECT TOP 1 n.id FROM [pm].[workspace_status] n
                     WHERE n.workspace_id = @workspace_id AND n.status_group = s.status_group ORDER BY n.sort_order, n.id),
                    (SELECT TOP 1 n.id FROM [pm].[workspace_status] n
                     WHERE n.workspace_id = @workspace_id AND n.status_group = N'not_started' ORDER BY n.sort_order, n.id))
            FROM [pm].[task] t JOIN #tree x ON x.task_id = t.id JOIN [pm].[workspace_status] s ON s.id = t.status_id;
            DELETE g FROM [pm].[task_tag] g JOIN #tree x ON x.task_id = g.task_id;
            DELETE v FROM [pm].[task_field_value] v JOIN #tree x ON x.task_id = v.task_id;
            DELETE d FROM [pm].[task_dependency] d
            WHERE (d.task_id IN (SELECT task_id FROM #tree) AND d.other_task_id NOT IN (SELECT task_id FROM #tree))
               OR (d.other_task_id IN (SELECT task_id FROM #tree) AND d.task_id NOT IN (SELECT task_id FROM #tree));
            DELETE a FROM [pm].[task_assignee] a JOIN #tree x ON x.task_id = a.task_id
            WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @workspace_id AND m.employee_id = a.employee_id);
            UPDATE r SET workspace_id = @workspace_id FROM [pm].[reminder] r JOIN #tree x ON x.task_id = r.entity_id AND r.entity_type = N'task';
            UPDATE s SET workspace_id = @workspace_id FROM [pm].[share_link] s JOIN #tree x ON x.task_id = s.entity_id AND s.entity_type = N'task';
        END

        UPDATE t SET workspace_id = @workspace_id, task_list_id = @task_list_id,
                     parent_task_id = CASE WHEN t.id = @id THEN @parent_task_id ELSE t.parent_task_id END,
                     sort_order = CASE WHEN t.id = @id THEN ISNULL(@sort_order, CASE WHEN @workspace_id <> @src_ws
                                       THEN ISNULL((SELECT MAX(sort_order) FROM [pm].[task] WHERE workspace_id = @workspace_id), 0) + 10
                                       ELSE t.sort_order END) ELSE t.sort_order END,
                     updated_at = @now, updated_by = @actor_user_id
        FROM [pm].[task] t JOIN #tree x ON x.task_id = t.id;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pm.task', @id, f.field_name, f.old_value, f.new_value, N'move', @actor_user_id, @now
        FROM (VALUES
            (N'workspace_id', CONVERT(NVARCHAR(30), @src_ws), CONVERT(NVARCHAR(30), @workspace_id)),
            (N'task_list_id', CONVERT(NVARCHAR(30), @old_list), CONVERT(NVARCHAR(30), @task_list_id)),
            (N'parent_task_id', CONVERT(NVARCHAR(30), @old_parent), CONVERT(NVARCHAR(30), @parent_task_id))
        ) f (field_name, old_value, new_value)
        WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Convert to List: makes a list named after the task in the same folder, moves the task's subtasks
-- into it as tasks, and removes the task. Managers and above (they manage lists).
-- Returns the new list's id.
CREATE OR ALTER PROCEDURE [pm].[usp_task_convert_to_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT;
    SELECT @ws = workspace_id, @rank = role_rank FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can convert a task to a list.', 1;

    DECLARE @name NVARCHAR(200), @rv BINARY(8), @list BIGINT, @folder BIGINT, @desc NVARCHAR(MAX), @priority NVARCHAR(30), @parent BIGINT;
    SELECT @name = t.name, @rv = t.row_version, @list = t.task_list_id, @desc = t.description, @priority = t.priority,
           @parent = t.parent_task_id, @folder = l.folder_id
    FROM [pm].[task] t LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id WHERE t.id = @id;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this task. Reload it and try again', 1;
    IF @parent IS NOT NULL
        THROW 50409, N'Convert a subtask to a task before converting it to a list.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[task_list] WHERE workspace_id = @ws AND name = @name)
        THROW 50409, N'name|LIST_DUPLICATE|A list with this task''s name already exists in this workspace.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @new_list BIGINT;
    CREATE TABLE #tree (task_id BIGINT PRIMARY KEY);
    WITH tree AS (
        SELECT id FROM [pm].[task] WHERE parent_task_id = @id
        UNION ALL
        SELECT c.id FROM [pm].[task] c JOIN tree ON c.parent_task_id = tree.id
    )
    INSERT #tree SELECT id FROM tree OPTION (MAXRECURSION 100);

    CREATE TABLE #purge (task_id BIGINT PRIMARY KEY);
    INSERT #purge VALUES (@id);

    BEGIN TRAN;
        INSERT [pm].[task_list] (workspace_id, folder_id, name, privacy, description, priority, sort_order, created_by)
        VALUES (@ws, @folder, @name, N'workspace', LEFT(@desc, 500), @priority,
                ISNULL((SELECT MAX(sort_order) FROM [pm].[task_list] WHERE workspace_id = @ws), 0) + 10, @actor_user_id);
        SET @new_list = SCOPE_IDENTITY();

        UPDATE t SET task_list_id = @new_list, parent_task_id = CASE WHEN t.parent_task_id = @id THEN NULL ELSE t.parent_task_id END,
                     updated_at = @now, updated_by = @actor_user_id
        FROM [pm].[task] t JOIN #tree x ON x.task_id = t.id;

        EXEC [pm].[usp_task_purge];

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @ws, N'task', @name, CONVERT(NVARCHAR(30), @new_list), N'task_to_list', @actor_user_id, @now);
    COMMIT;

    SELECT @new_list AS task_list_id;
END
GO

-- Deletes a task and its subtasks. Managers and above, or the task's creator.
CREATE OR ALTER PROCEDURE [pm].[usp_task_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT;
    SELECT @ws = workspace_id, @rank = role_rank FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    DECLARE @rv BINARY(8), @creator BIGINT, @name NVARCHAR(200), @code NVARCHAR(30);
    SELECT @rv = row_version, @creator = created_by, @name = name, @code = code FROM [pm].[task] WHERE id = @id;
    IF @rank < 3 AND NOT (@rank >= 1 AND @creator = @actor_user_id)
        THROW 50403, N'Only managers and above, or the task''s creator, can delete this task.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this task. Reload it and try again', 1;

    CREATE TABLE #purge (task_id BIGINT PRIMARY KEY);
    WITH tree AS (
        SELECT id FROM [pm].[task] WHERE id = @id
        UNION ALL
        SELECT c.id FROM [pm].[task] c JOIN tree ON c.parent_task_id = tree.id
    )
    INSERT #purge SELECT id FROM tree OPTION (MAXRECURSION 100);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        EXEC [pm].[usp_task_purge];
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @id, N'delete', @actor_user_id, @now);
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @ws, N'task', CONCAT(@code, N' ', @name), N'task_delete', @actor_user_id, @now);
    COMMIT;
END
