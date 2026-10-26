-- Moves a task to another status. Team leaders and above, the task's assignees and its creator.
--   A task waiting on unfinished tasks stays in Not Started and cannot be completed (BRD
--   "Blocking Enforcement", "Task Completion").
--   With "Work In-Progress Limits" on, a status with a WIP limit takes no more tasks than that.
--   Entering Done or Closed stamps closed_at; after the due date the task is marked closed late
--   (story points impact; an approved extension moves the due date first). Leaving clears both.
CREATE OR ALTER PROCEDURE [pm].[usp_task_status_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @status_id     BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;

    DECLARE @old_status BIGINT, @creator BIGINT, @rv BINARY(8), @due DATE;
    SELECT @old_status = status_id, @creator = created_by, @rv = row_version, @due = due_date FROM [pm].[task] WHERE id = @id;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this task. Reload it and try again', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND (@creator = @actor_user_id
                          OR EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @id AND employee_id = @me)))
        THROW 50403, N'Only team leaders and above, or the task''s assignees, can change its status.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'status' AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change the status (column permission).', 1;

    DECLARE @group NVARCHAR(30), @wip INT, @new_name NVARCHAR(200), @old_name NVARCHAR(200), @old_group NVARCHAR(30);
    SELECT @group = status_group, @wip = wip_limit, @new_name = name FROM [pm].[workspace_status] WHERE id = @status_id AND workspace_id = @ws;
    IF @group IS NULL
        THROW 50400, N'statusId|Status not found in this workspace.', 1;
    SELECT @old_name = name, @old_group = status_group FROM [pm].[workspace_status] WHERE id = @old_status;
    IF @status_id = @old_status
    BEGIN
        EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
        RETURN;
    END

    IF @group <> N'not_started' AND EXISTS (
        SELECT 1 FROM [pm].[task_dependency] d JOIN [pm].[task] o ON o.id = d.other_task_id
        JOIN [pm].[workspace_status] s ON s.id = o.status_id
        WHERE d.task_id = @id AND d.kind = N'waiting_on' AND s.status_group NOT IN (N'done', N'closed'))
        THROW 50409, N'statusId|DEPENDENCY_OPEN|This task is waiting on tasks that are not completed yet.', 1;

    IF @wip IS NOT NULL AND EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @ws AND feature_code = N'wip_limits')
       AND (SELECT COUNT(*) FROM [pm].[task] WHERE status_id = @status_id) >= @wip
        THROW 50409, N'statusId|WIP_LIMIT|This status has reached its work in progress limit.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @closing BIT = CASE WHEN @group IN (N'done', N'closed') AND @old_group NOT IN (N'done', N'closed') THEN 1 ELSE 0 END;
    DECLARE @reopening BIT = CASE WHEN @group NOT IN (N'done', N'closed') AND @old_group IN (N'done', N'closed') THEN 1 ELSE 0 END;

    BEGIN TRAN;
        UPDATE [pm].[task]
        SET status_id = @status_id,
            closed_at = CASE WHEN @closing = 1 THEN @now WHEN @reopening = 1 THEN NULL ELSE closed_at END,
            is_closed_late = CASE WHEN @closing = 1 THEN CASE WHEN @due < CAST(@now AS DATE) THEN 1 ELSE 0 END
                                  WHEN @reopening = 1 THEN 0 ELSE is_closed_late END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this task. Reload it and try again', 1;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @id, N'status', @old_name, @new_name, N'status', @actor_user_id, @now);
        IF @closing = 1 AND @due < CAST(@now AS DATE)
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @id, N'due_date', CONVERT(NVARCHAR(10), @due, 23), CONVERT(NVARCHAR(10), @now, 23), N'closed_late', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
