-- Task attachments: core.attachment rows (entity_type pm.task) linking files uploaded first through
-- POST /api/files. BRD: PDF, DOCX, XLSX, PNG, JPG, up to 10 MB per file. Removing an attachment leaves the
-- file itself to the file service (its uploader can delete it there once nothing uses it).

CREATE OR ALTER PROCEDURE [pm].[usp_task_attachment_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT = NULL,
    @id            BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL
        SET @task_id = (SELECT entity_id FROM [core].[attachment] WHERE id = @id AND company_id = @company_id AND entity_type = N'pm.task');
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id)
        THROW 50404, N'Task not found', 1;

    SELECT a.id, a.entity_id AS task_id, f.id AS file_id, f.name, f.mime_type, f.size_bytes, a.created_by AS uploaded_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS uploaded_by_name,
           a.created_at
    FROM [core].[attachment] a
    JOIN [core].[stored_file] f ON f.id = a.file_id
    LEFT JOIN [auth].[user_account] u ON u.id = a.created_by
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE a.company_id = @company_id AND a.entity_type = N'pm.task' AND a.entity_id = @task_id AND (@id IS NULL OR a.id = @id)
    ORDER BY a.created_at, a.id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_task_attachment_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT,
    @file_id       BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND (EXISTS (SELECT 1 FROM [pm].[task] WHERE id = @task_id AND created_by = @actor_user_id)
                                          OR EXISTS (SELECT 1 FROM [pm].[task_assignee] WHERE task_id = @task_id AND employee_id = @me)))
        THROW 50403, N'Only team leaders and above, the creator or the assignees can attach files.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'files' AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change the files (column permission).', 1;

    IF @file_id IS NULL OR NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    DECLARE @name NVARCHAR(255), @ext NVARCHAR(20), @size BIGINT;
    SELECT @name = name, @ext = LOWER(extension), @size = size_bytes FROM [core].[stored_file] WHERE id = @file_id;
    IF @ext NOT IN (N'pdf', N'docx', N'xlsx', N'png', N'jpg', N'jpeg')
        THROW 50400, N'fileId|Attach a PDF, DOCX, XLSX, PNG or JPG file.', 1;
    IF @size > 10485760
        THROW 50400, N'fileId|A file can be up to 10 MB.', 1;
    IF EXISTS (SELECT 1 FROM [core].[attachment] WHERE entity_type = N'pm.task' AND entity_id = @task_id AND file_id = @file_id)
        THROW 50409, N'fileId|FILE_DUPLICATE|This file is already attached to the task.', 1;

    DECLARE @id BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[attachment] (company_id, entity_type, entity_id, file_id, created_by)
        VALUES (@company_id, N'pm.task', @task_id, @file_id, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        UPDATE [pm].[task] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @task_id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task_id, N'attachment', @name, N'attach', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_attachment_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Removes an attachment: whoever attached it, or managers and above.
CREATE OR ALTER PROCEDURE [pm].[usp_task_attachment_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @task_id BIGINT, @attacher BIGINT, @name NVARCHAR(255);
    SELECT @task_id = a.entity_id, @attacher = a.created_by, @name = f.name
    FROM [core].[attachment] a JOIN [core].[stored_file] f ON f.id = a.file_id
    WHERE a.id = @id AND a.company_id = @company_id AND a.entity_type = N'pm.task';
    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Attachment not found', 1;
    IF @rank < 3 AND NOT (@rank >= 1 AND @attacher = @actor_user_id)
        THROW 50403, N'Only whoever attached the file, or a manager, can remove it.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE [core].[attachment] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.task', @task_id, N'attachment', @name, N'detach', @actor_user_id, @now);
    COMMIT;
END
