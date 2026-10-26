-- Adds a cost center (@id NULL) or edits one (@id and the @row_version last read). Returns the saved row.
CREATE OR ALTER PROCEDURE [org].[usp_cost_center_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @code          NVARCHAR(30) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @code = NULLIF(LTRIM(RTRIM(@code)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Cost center name is required.', 1;
    IF @code IS NULL
        THROW 50400, N'code|Cost center code is required.', 1;
    IF EXISTS (SELECT 1 FROM [org].[cost_center] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|COST_CENTER_DUPLICATE|A cost center with this name already exists.', 1;
    IF EXISTS (SELECT 1 FROM [org].[cost_center] WHERE company_id = @company_id AND code = @code AND (@id IS NULL OR id <> @id))
        THROW 50409, N'code|COST_CENTER_DUPLICATE|A cost center with this code already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[cost_center] (company_id, name, code, created_by)
            VALUES (@company_id, @name, @code, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.cost_center', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a cost center.', 1;

        DECLARE @old_name NVARCHAR(200), @old_code NVARCHAR(30), @old_rv BINARY(8);
        SELECT @old_name = name, @old_code = code, @old_rv = row_version
        FROM [org].[cost_center] WHERE id = @id AND company_id = @company_id;

        IF @old_rv IS NULL
            THROW 50404, N'Cost center not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this cost center. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [org].[cost_center]
            SET name = @name, code = @code, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this cost center. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.cost_center', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @old_name, @name),
                (N'code', CONVERT(NVARCHAR(400), @old_code), CONVERT(NVARCHAR(400), @code))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_cost_center_get] @company_id = @company_id, @id = @id;
END
