-- Adds a department (@id NULL) or edits one (@id and the @row_version last read). Returns the saved row.
-- Every change is written to core.audit_log, one row per changed field, for the History popup.
CREATE OR ALTER PROCEDURE [org].[usp_department_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @parent_id     BIGINT = NULL,
    @head_id       BIGINT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Department name is required.', 1;
    IF @parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @parent_id AND company_id = @company_id)
        THROW 50400, N'parentId|Parent department not found.', 1;
    IF @head_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @head_id AND company_id = @company_id)
        THROW 50400, N'headId|Head of department not found.', 1;
    IF EXISTS (SELECT 1 FROM [org].[department] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|DEPARTMENT_DUPLICATE|A department with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[department] (company_id, parent_id, name, head_id, created_by)
            VALUES (@company_id, @parent_id, @name, @head_id, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.department', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a department', 1;

        DECLARE @old_name NVARCHAR(200), @old_parent BIGINT, @old_head BIGINT, @old_rv BINARY(8);
        SELECT @old_name = name, @old_parent = parent_id, @old_head = head_id, @old_rv = row_version
        FROM [org].[department] WHERE id = @id AND company_id = @company_id;

        IF @old_rv IS NULL
            THROW 50404, N'Department not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this department. Reload it and try again', 1;

        IF @parent_id IS NOT NULL
        BEGIN
            DECLARE @loop BIT = 0;
            WITH up AS (
                SELECT id, parent_id FROM [org].[department] WHERE id = @parent_id
                UNION ALL
                SELECT d.id, d.parent_id FROM [org].[department] d JOIN up ON d.id = up.parent_id
            )
            SELECT @loop = 1 FROM up WHERE id = @id OPTION (MAXRECURSION 100);
            IF @loop = 1
                THROW 50400, N'parentId|A department cannot sit under itself or one of its own sub-departments.', 1;
        END

        BEGIN TRAN;
            UPDATE [org].[department]
            SET name = @name, parent_id = @parent_id, head_id = @head_id,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this department. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.department', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @old_name, @name),
                (N'parent_id', CONVERT(NVARCHAR(30), @old_parent), CONVERT(NVARCHAR(30), @parent_id)),
                (N'head_id', CONVERT(NVARCHAR(30), @old_head), CONVERT(NVARCHAR(30), @head_id))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_department_get] @company_id = @company_id, @id = @id;
END
