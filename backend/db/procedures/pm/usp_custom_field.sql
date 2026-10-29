-- Custom task fields ("Add Fields" organizer feature). Managers and above define them.
-- config is JSON checked by the service per type: {"options": [...], "min", "max", "currency", "end", "multiple"}.

CREATE OR ALTER PROCEDURE [pm].[usp_custom_field_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    SELECT f.id, f.workspace_id, f.name, f.field_type, f.description, f.config, f.sort_order, f.row_version
    FROM [pm].[custom_field] f WHERE f.workspace_id = @workspace_id
    ORDER BY f.sort_order, f.id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_custom_field_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[custom_field] f
                   JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = f.workspace_id
                   WHERE f.id = @id)
        THROW 50404, N'Custom field not found', 1;

    SELECT f.id, f.workspace_id, f.name, f.field_type, f.description, f.config, f.sort_order, f.row_version
    FROM [pm].[custom_field] f WHERE f.id = @id;
END
GO

-- Adds a field to @workspace_id (@id NULL) or edits one (its type cannot change once tasks hold values).
CREATE OR ALTER PROCEDURE [pm].[usp_custom_field_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @workspace_id  BIGINT = NULL,
    @name          NVARCHAR(200),
    @field_type    NVARCHAR(30),
    @description   NVARCHAR(MAX) = NULL,
    @config        NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @id IS NOT NULL
        SET @workspace_id = (SELECT workspace_id FROM [pm].[custom_field] WHERE id = @id);
    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Custom field not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can define custom fields.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @workspace_id AND feature_code = N'custom_fields')
        THROW 50409, N'features|FEATURE_OFF|Custom fields are switched off for this workspace (Organizer: Add Fields).', 1;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Field name is required.', 1;
    IF @field_type NOT IN (N'text', N'long_text', N'number', N'money', N'date', N'checkbox', N'dropdown', N'labels',
                           N'email', N'phone', N'website', N'rating', N'progress_manual', N'people', N'location')
        THROW 50400, N'fieldType|This field type is not available.', 1;
    IF @config IS NOT NULL AND ISJSON(@config) = 0
        THROW 50400, N'config|Field settings are not valid.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[custom_field] WHERE workspace_id = @workspace_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|FIELD_DUPLICATE|A field with this name already exists in this workspace.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [pm].[custom_field] (workspace_id, name, field_type, description, config, sort_order, created_by)
            VALUES (@workspace_id, @name, @field_type, @description, @config,
                    ISNULL((SELECT MAX(sort_order) FROM [pm].[custom_field] WHERE workspace_id = @workspace_id), 0) + 10, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.workspace', @workspace_id, N'custom_field', @name, N'field_add', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a field', 1;
        DECLARE @old_type NVARCHAR(30) = (SELECT field_type FROM [pm].[custom_field] WHERE id = @id);
        IF @old_type <> @field_type AND EXISTS (SELECT 1 FROM [pm].[task_field_value] WHERE custom_field_id = @id)
            THROW 50409, N'fieldType|Tasks already hold values for this field, so its type cannot change.', 1;
        BEGIN TRAN;
            UPDATE [pm].[custom_field]
            SET name = @name, field_type = @field_type, description = @description, config = @config,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this field. Reload it and try again', 1;
        COMMIT;
    END

    EXEC [pm].[usp_custom_field_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_custom_field_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @workspace_id BIGINT, @rv BINARY(8), @name NVARCHAR(200), @rank INT;
    SELECT @workspace_id = workspace_id, @rv = row_version, @name = name FROM [pm].[custom_field] WHERE id = @id;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Custom field not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can delete custom fields.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this field. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [pm].[task_field_value] WHERE custom_field_id = @id;
        DELETE [pm].[column_permission] WHERE workspace_id = @workspace_id AND column_key = CONCAT(N'cf_', @id);
        DELETE [pm].[custom_field] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @workspace_id, N'custom_field', @name, N'field_delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
