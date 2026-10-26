-- Dependencies: Waiting On (this task waits on the other), Blocking (the other waits on this one)
-- and Linked. Stored once as "task waits on other". Both tasks are in the same workspace (BRD);
-- loops are refused. Team leaders and above, or the task's creator.
CREATE OR ALTER PROCEDURE [pm].[usp_task_dependency_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT,
    @other_task_id BIGINT,
    @kind          NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND EXISTS (SELECT 1 FROM [pm].[task] WHERE id = @task_id AND created_by = @actor_user_id))
        THROW 50403, N'Only team leaders and above, or the task''s creator, can link tasks.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'dependencies' AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change dependencies (column permission).', 1;
    IF @kind NOT IN (N'waiting_on', N'blocking', N'linked')
        THROW 50400, N'kind|Choose Waiting On, Blocking or Linked.', 1;
    IF @other_task_id = @task_id
        THROW 50400, N'otherTaskId|A task cannot depend on itself.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @other_task_id AND workspace_id = @ws)
        THROW 50400, N'otherTaskId|Linked tasks must be in the same workspace.', 1;

    DECLARE @waiter BIGINT = CASE WHEN @kind = N'blocking' THEN @other_task_id ELSE @task_id END;
    DECLARE @waited BIGINT = CASE WHEN @kind = N'blocking' THEN @task_id ELSE @other_task_id END;
    DECLARE @stored NVARCHAR(30) = CASE WHEN @kind = N'linked' THEN N'linked' ELSE N'waiting_on' END;

    IF EXISTS (SELECT 1 FROM [pm].[task_dependency] WHERE (task_id = @waiter AND other_task_id = @waited) OR (task_id = @waited AND other_task_id = @waiter))
        THROW 50409, N'otherTaskId|DEPENDENCY_DUPLICATE|These tasks are already linked.', 1;
    IF @stored = N'waiting_on'
    BEGIN
        DECLARE @loop BIT = 0;
        WITH chain AS (
            SELECT d.other_task_id AS id FROM [pm].[task_dependency] d WHERE d.task_id = @waited AND d.kind = N'waiting_on'
            UNION ALL
            SELECT d.other_task_id FROM [pm].[task_dependency] d JOIN chain c ON d.task_id = c.id WHERE d.kind = N'waiting_on'
        )
        SELECT @loop = 1 FROM chain WHERE id = @waiter OPTION (MAXRECURSION 100);
        IF @loop = 1
            THROW 50400, N'otherTaskId|This would make the tasks wait on each other.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @other_code NVARCHAR(30) = (SELECT code FROM [pm].[task] WHERE id = @other_task_id);
    BEGIN TRAN;
        INSERT [pm].[task_dependency] (task_id, other_task_id, kind, created_by) VALUES (@waiter, @waited, @stored, @actor_user_id);
        UPDATE [pm].[task] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @task_id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task_id, N'dependency:' + @kind, @other_code, N'link', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @task_id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_task_dependency_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task BIGINT, @other BIGINT;
    SELECT @task = task_id, @other = other_task_id FROM [pm].[task_dependency] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task;
    IF @ws IS NULL
        THROW 50404, N'Dependency not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND EXISTS (SELECT 1 FROM [pm].[task] WHERE id IN (@task, @other) AND created_by = @actor_user_id))
        THROW 50403, N'Only team leaders and above, or the task''s creator, can unlink tasks.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'dependencies' AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change dependencies (column permission).', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE [pm].[task_dependency] WHERE id = @id;
        UPDATE [pm].[task] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @task;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task, N'dependency', (SELECT code FROM [pm].[task] WHERE id = @other), N'unlink', @actor_user_id, @now);
    COMMIT;
END
GO

-- Checklist items (BRD: at most 20 per task). Team leaders and above, the creator and the assignees.
CREATE OR ALTER PROCEDURE [pm].[usp_checklist_item_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @task_id       BIGINT = NULL,
    @item_text     NVARCHAR(500),
    @is_done       BIT = 0,
    @sort_order    INT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @id IS NOT NULL
        SET @task_id = (SELECT task_id FROM [pm].[checklist_item] WHERE id = @id);
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Checklist item not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND (EXISTS (SELECT 1 FROM [pm].[task] WHERE id = @task_id AND created_by = @actor_user_id)
                                          OR EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @task_id AND employee_id = @me)))
        THROW 50403, N'Only team leaders and above, the creator or the assignees can change the checklist.', 1;

    SET @item_text = LTRIM(RTRIM(@item_text));
    IF @item_text IS NULL OR @item_text = N''
        THROW 50400, N'itemText|Checklist item text is required.', 1;

    IF @id IS NULL
    BEGIN
        IF (SELECT COUNT(*) FROM [pm].[checklist_item] WHERE task_id = @task_id) >= 20
            THROW 50409, N'itemText|CHECKLIST_FULL|A task can have at most 20 checklist items.', 1;
        INSERT [pm].[checklist_item] (task_id, item_text, is_done, sort_order, created_by)
        VALUES (@task_id, @item_text, ISNULL(@is_done, 0),
                ISNULL(@sort_order, ISNULL((SELECT MAX(sort_order) FROM [pm].[checklist_item] WHERE task_id = @task_id), 0) + 10), @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [pm].[checklist_item]
        SET item_text = @item_text, is_done = ISNULL(@is_done, 0), sort_order = ISNULL(@sort_order, sort_order),
            updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this checklist item. Reload it and try again', 1;
    END

    SELECT c.id, c.task_id, c.item_text, c.is_done, c.sort_order, c.row_version FROM [pm].[checklist_item] c WHERE c.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_checklist_item_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @task_id BIGINT = (SELECT task_id FROM [pm].[checklist_item] WHERE id = @id);
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Checklist item not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND (EXISTS (SELECT 1 FROM [pm].[task] WHERE id = @task_id AND created_by = @actor_user_id)
                                          OR EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @task_id AND employee_id = @me)))
        THROW 50403, N'Only team leaders and above, the creator or the assignees can change the checklist.', 1;

    DELETE [pm].[checklist_item] WHERE id = @id;
END
