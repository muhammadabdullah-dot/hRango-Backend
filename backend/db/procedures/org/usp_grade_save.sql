-- Adds a grade (@id NULL) or edits one (@id and the @row_version last read). Returns the saved row.
CREATE OR ALTER PROCEDURE [org].[usp_grade_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @sort_order    INT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Grade name is required.', 1;
    IF @sort_order IS NOT NULL AND @sort_order < 0
        THROW 50400, N'sortOrder|Order cannot be negative.', 1;
    IF EXISTS (SELECT 1 FROM [org].[grade] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|GRADE_DUPLICATE|A grade with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[grade] (company_id, name, sort_order, created_by)
            VALUES (@company_id, @name, @sort_order, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.grade', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a grade.', 1;

        DECLARE @old_name NVARCHAR(200), @old_sort_order INT, @old_rv BINARY(8);
        SELECT @old_name = name, @old_sort_order = sort_order, @old_rv = row_version
        FROM [org].[grade] WHERE id = @id AND company_id = @company_id;

        IF @old_rv IS NULL
            THROW 50404, N'Grade not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this grade. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [org].[grade]
            SET name = @name, sort_order = @sort_order, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this grade. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.grade', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @old_name, @name),
                (N'sort_order', CONVERT(NVARCHAR(400), @old_sort_order), CONVERT(NVARCHAR(400), @sort_order))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_grade_get] @company_id = @company_id, @id = @id;
END
