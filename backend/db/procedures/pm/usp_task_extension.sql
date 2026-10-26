-- Request Extension (BRD "Overdue Task Handling", "Request Task Extension"): an assignee proposes a
-- new due date with a reason, once per task; a workspace manager (or above) approves or rejects.
-- Approval moves the due date and keeps the first one in original_due_date, so completing by the new
-- date does not count as late (story points unaffected).

CREATE OR ALTER PROCEDURE [pm].[usp_task_extension_request]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT,
    @new_due_date  DATE,
    @reason        NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @me BIGINT;
    SELECT @ws = workspace_id, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @task_id AND employee_id = @me)
        THROW 50403, N'Only the task''s assignees can request an extension.', 1;

    DECLARE @due DATE, @group NVARCHAR(30);
    SELECT @due = t.due_date, @group = s.status_group FROM [pm].[task] t JOIN [pm].[workspace_status] s ON s.id = t.status_id WHERE t.id = @task_id;
    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF @due IS NULL
        THROW 50409, N'This task has no due date to extend.', 1;
    IF @group IN (N'done', N'closed')
        THROW 50409, N'This task is already completed.', 1;
    IF @new_due_date IS NULL OR @new_due_date <= @due
        THROW 50400, N'newDueDate|Propose a date after the current due date.', 1;
    IF @reason IS NULL
        THROW 50400, N'reason|Give a reason for the extension.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[task_extension] WHERE task_id = @task_id)
        THROW 50409, N'newDueDate|EXTENSION_EXISTS|Only one extension request is allowed per task.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [pm].[task_extension] (task_id, requested_by_id, old_due_date, new_due_date, reason, status, created_by)
        VALUES (@task_id, @me, @due, @new_due_date, @reason, N'pending', @actor_user_id);
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task_id, N'due_date', CONVERT(NVARCHAR(10), @due, 23), CONVERT(NVARCHAR(10), @new_due_date, 23),
                N'extension_request', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @task_id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_task_extension_decide]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @is_approved   BIT,
    @remarks       NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task_id BIGINT, @requester BIGINT, @status NVARCHAR(30), @new_due DATE, @rv BINARY(8);
    SELECT @task_id = task_id, @requester = requested_by_id, @status = status, @new_due = new_due_date, @rv = row_version
    FROM [pm].[task_extension] WHERE id = @id;
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Extension request not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above decide extension requests.', 1;
    IF @requester = @me
        THROW 50403, N'You cannot decide your own extension request.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    IF @status <> N'pending'
        THROW 50409, N'This request has already been decided.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @old_due DATE = (SELECT due_date FROM [pm].[task] WHERE id = @task_id);
    BEGIN TRAN;
        UPDATE [pm].[task_extension]
        SET status = CASE WHEN @is_approved = 1 THEN N'approved' ELSE N'rejected' END, decided_by_id = @me, decided_at = @now,
            remarks = NULLIF(LTRIM(RTRIM(@remarks)), N''), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;
        IF @is_approved = 1
        BEGIN
            UPDATE [pm].[task] SET original_due_date = ISNULL(original_due_date, due_date), due_date = @new_due,
                                   updated_at = @now, updated_by = @actor_user_id
            WHERE id = @task_id;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @task_id, N'due_date', CONVERT(NVARCHAR(10), @old_due, 23), CONVERT(NVARCHAR(10), @new_due, 23),
                    N'extension_approve', @actor_user_id, @now);
        END
        ELSE
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @task_id, N'due_date', N'extension_reject', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @task_id;
END
