-- Training -> Settings: General (core.company_setting, module 'training') and Categories.

CREATE OR ALTER PROCEDURE [trn].[usp_training_settings_get]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.min_attendance_percent, s.allow_self_nomination, s.row_version FROM [trn].[fn_settings](@company_id) s;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_settings_save]
    @company_id             BIGINT,
    @actor_user_id          BIGINT = NULL,
    @min_attendance_percent DECIMAL(5,2),
    @allow_self_nomination  BIT,
    @row_version            BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @min_attendance_percent IS NULL OR @min_attendance_percent < 0 OR @min_attendance_percent > 100
        THROW 50400, N'minAttendancePercent|Give a percentage from 0 to 100.', 1;
    DECLARE @current BINARY(8) = (SELECT MAX(row_version) FROM [core].[company_setting] WHERE company_id = @company_id AND module = N'training');
    IF @current IS NOT NULL AND (@row_version IS NULL OR @row_version <> @current)
        THROW 50409, N'Someone else changed the training settings. Reload them and try again', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @new TABLE (setting_key NVARCHAR(100), setting_value NVARCHAR(MAX));
    INSERT @new VALUES (N'min_attendance_percent', CONVERT(NVARCHAR(20), @min_attendance_percent)),
                       (N'allow_self_nomination', CASE WHEN @allow_self_nomination = 1 THEN N'1' ELSE N'0' END);
    BEGIN TRAN;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'trn.settings', @company_id, n.setting_key, s.setting_value, n.setting_value, N'update', @actor_user_id, @now
        FROM @new n
        LEFT JOIN [core].[company_setting] s ON s.company_id = @company_id AND s.module = N'training' AND s.setting_key = n.setting_key
        WHERE EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);
        UPDATE s SET setting_value = n.setting_value, updated_at = @now, updated_by = @actor_user_id
        FROM [core].[company_setting] s JOIN @new n ON n.setting_key = s.setting_key
        WHERE s.company_id = @company_id AND s.module = N'training' AND EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);
        INSERT [core].[company_setting] (company_id, module, setting_key, setting_value, created_by)
        SELECT @company_id, N'training', n.setting_key, n.setting_value, @actor_user_id FROM @new n
        WHERE NOT EXISTS (SELECT 1 FROM [core].[company_setting] s WHERE s.company_id = @company_id AND s.module = N'training'
                          AND s.setting_key = n.setting_key);
    COMMIT;
    EXEC [trn].[usp_training_settings_get] @company_id = @company_id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_category_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SELECT COUNT(*) AS total FROM [trn].[training_category] c
    WHERE c.company_id = @company_id AND (@pattern IS NULL OR c.name LIKE @pattern) AND (@is_active IS NULL OR c.is_active = @is_active)
    OPTION (RECOMPILE);
    SELECT c.id, c.name, c.is_active,
           (SELECT COUNT(*) FROM [trn].[training_program] p WHERE p.training_category_id = c.id) AS in_use,
           c.created_at, c.updated_at, c.row_version
    FROM [trn].[training_category] c
    WHERE c.company_id = @company_id AND (@pattern IS NULL OR c.name LIKE @pattern) AND (@is_active IS NULL OR c.is_active = @is_active)
    ORDER BY c.name, c.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_category_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @is_active     BIT,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [trn].[training_category] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|CATEGORY_DUPLICATE|A category with this name already exists.', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        INSERT [trn].[training_category] (company_id, name, is_active, created_by) VALUES (@company_id, @name, @is_active, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [trn].[training_category] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Category not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this category. Reload it and try again', 1;
        UPDATE [trn].[training_category] SET name = @name, is_active = @is_active, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
    END
    SELECT c.id, c.name, c.is_active,
           (SELECT COUNT(*) FROM [trn].[training_program] p WHERE p.training_category_id = c.id) AS in_use,
           c.created_at, c.updated_at, c.row_version
    FROM [trn].[training_category] c WHERE c.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_category_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [trn].[training_category] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Category not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this category. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [trn].[training_program] WHERE training_category_id = @id)
        THROW 50409, N'id|CATEGORY_IN_USE|Programs use this category. Make it inactive instead', 1;
    DELETE [trn].[training_category] WHERE id = @id AND company_id = @company_id;
END
