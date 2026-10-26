-- Workspace tags ("Search or create new tag"; Rename, Delete, colour). Unique in the workspace,
-- up to 25 characters (BRD). Team leaders and above manage them.

CREATE OR ALTER PROCEDURE [pm].[usp_tag_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    SELECT t.id, t.workspace_id, t.name, t.color, t.row_version,
           (SELECT COUNT(*) FROM [pm].[task_tag] x WHERE x.tag_id = t.id) AS task_count
    FROM [pm].[tag] t WHERE t.workspace_id = @workspace_id ORDER BY t.name;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_tag_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @workspace_id  BIGINT = NULL,
    @name          NVARCHAR(200),
    @color         NVARCHAR(20) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @id IS NOT NULL
        SET @workspace_id = (SELECT workspace_id FROM [pm].[tag] WHERE id = @id);
    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Tag not found', 1;
    IF @rank < 2
        THROW 50403, N'Only team leaders and above can manage tags.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @workspace_id AND feature_code = N'tags')
        THROW 50409, N'features|FEATURE_OFF|Tags are switched off for this workspace.', 1;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N'' OR LEN(@name) > 25
        THROW 50400, N'name|Tag name must be 1 to 25 characters.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[tag] WHERE workspace_id = @workspace_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|TAG_DUPLICATE|A tag with this name already exists in this workspace.', 1;

    IF @id IS NULL
    BEGIN
        INSERT [pm].[tag] (workspace_id, name, color, created_by) VALUES (@workspace_id, @name, @color, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [pm].[tag] SET name = @name, color = @color, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this tag. Reload it and try again', 1;
    END

    SELECT t.id, t.workspace_id, t.name, t.color, t.row_version,
           (SELECT COUNT(*) FROM [pm].[task_tag] x WHERE x.tag_id = t.id) AS task_count
    FROM [pm].[tag] t WHERE t.id = @id;
END
GO

-- Deletes a tag and takes it off every task.
CREATE OR ALTER PROCEDURE [pm].[usp_tag_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @workspace_id BIGINT, @rv BINARY(8), @rank INT;
    SELECT @workspace_id = workspace_id, @rv = row_version FROM [pm].[tag] WHERE id = @id;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Tag not found', 1;
    IF @rank < 2
        THROW 50403, N'Only team leaders and above can manage tags.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this tag. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [pm].[task_tag] WHERE tag_id = @id;
        DELETE [pm].[tag] WHERE id = @id;
    COMMIT;
END
