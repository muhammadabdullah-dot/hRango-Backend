-- Cover images of a workspace (its banner) and of a task. The image is uploaded first (POST /api/files);
-- @file_id NULL removes the cover. Responses give the cover as id, name and a signed link.

-- Workspace admins and HR, as Edit Workspace. Returns the workspace.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_cover_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @file_id       BIGINT = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can edit the workspace.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[stored_file] WHERE id = @file_id
                                            AND LOWER(extension) IN (N'png', N'jpg', N'jpeg', N'gif', N'webp'))
        THROW 50400, N'fileId|A cover must be a PNG, JPG, GIF or WEBP image.', 1;

    DECLARE @old BIGINT, @rv BINARY(8), @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @old = cover_file_id, @rv = row_version FROM [pm].[workspace] WHERE id = @id;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;

    BEGIN TRAN;
        UPDATE [pm].[workspace] SET cover_file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'pm.workspace', @id, N'cover_file_id', CONVERT(NVARCHAR(30), @old), CONVERT(NVARCHAR(30), @file_id),
                N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_workspace_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Team leaders and above, or the task's creator, as Edit Task. Returns the task.
CREATE OR ALTER PROCEDURE [pm].[usp_task_cover_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @file_id       BIGINT = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Task not found', 1;
    DECLARE @old BIGINT, @rv BINARY(8), @creator BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @old = cover_file_id, @rv = row_version, @creator = created_by FROM [pm].[task] WHERE id = @id;
    IF @rank < 2 AND NOT (@rank >= 1 AND @creator = @actor_user_id)
        THROW 50403, N'Only team leaders and above, or the task''s creator, can edit this task.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[stored_file] WHERE id = @file_id
                                            AND LOWER(extension) IN (N'png', N'jpg', N'jpeg', N'gif', N'webp'))
        THROW 50400, N'fileId|A cover must be a PNG, JPG, GIF or WEBP image.', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this task. Reload it and try again', 1;

    BEGIN TRAN;
        UPDATE [pm].[task] SET cover_file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this task. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'pm.task', @id, N'cover_file_id', CONVERT(NVARCHAR(30), @old), CONVERT(NVARCHAR(30), @file_id),
                N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
