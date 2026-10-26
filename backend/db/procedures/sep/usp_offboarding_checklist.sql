-- Settings -> Off Boarding Checklist (ECL-00001) and its "Additional Information" fields. The
-- fields of active checklists make the Checklist tab of every pending end of employment.
CREATE OR ALTER PROCEDURE [sep].[usp_offboarding_checklist_list]
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

    SELECT COUNT(*) AS total
    FROM [sep].[offboarding_checklist] k
    WHERE k.company_id = @company_id
      AND (@pattern IS NULL OR k.name LIKE @pattern OR k.code LIKE @pattern)
      AND (@is_active IS NULL OR k.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT k.id, k.code, k.name, k.description, k.is_active,
           (SELECT COUNT(*) FROM [sep].[checklist_field] f WHERE f.offboarding_checklist_id = k.id) AS field_count,
           k.created_at, k.updated_at, k.row_version
    FROM [sep].[offboarding_checklist] k
    WHERE k.company_id = @company_id
      AND (@pattern IS NULL OR k.name LIKE @pattern OR k.code LIKE @pattern)
      AND (@is_active IS NULL OR k.is_active = @is_active)
    ORDER BY k.code, k.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Result set 1: the checklist. Result set 2: its fields in order.
CREATE OR ALTER PROCEDURE [sep].[usp_offboarding_checklist_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[offboarding_checklist] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Checklist not found', 1;

    SELECT k.id, k.code, k.name, k.description, k.is_active,
           (SELECT COUNT(*) FROM [sep].[checklist_field] f WHERE f.offboarding_checklist_id = k.id) AS field_count,
           k.created_at, k.updated_at, k.row_version
    FROM [sep].[offboarding_checklist] k
    WHERE k.id = @id;

    SELECT f.id, f.offboarding_checklist_id, f.name, f.field_type, f.is_required, f.min_value, f.max_value,
           f.min_length, f.max_length, f.sort_order
    FROM [sep].[checklist_field] f
    WHERE f.offboarding_checklist_id = @id
    ORDER BY f.sort_order, f.id;
END
GO

-- Adds (@id NULL) or edits a checklist with its fields in one go. @fields is a JSON array of
-- {"id" (existing field, or null), "name", "field_type", "is_required", "min_value", "max_value",
-- "min_length", "max_length"}; fields left out are removed unless an end of employment answered them.
CREATE OR ALTER PROCEDURE [sep].[usp_offboarding_checklist_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @fields        NVARCHAR(MAX) = N'[]',
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(2048), @bad INT, @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Checklist name is required.', 1;
    IF EXISTS (SELECT 1 FROM [sep].[offboarding_checklist] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|CHECKLIST_DUPLICATE|A checklist with this name already exists.', 1;
    IF ISJSON(ISNULL(@fields, N'[]')) = 0
        THROW 50400, N'fields|Fields are not valid.', 1;

    DECLARE @f TABLE (idx INT, id BIGINT NULL, name NVARCHAR(200), field_type NVARCHAR(30), is_required BIT,
                      min_value DECIMAL(18,4) NULL, max_value DECIMAL(18,4) NULL, min_length INT NULL, max_length INT NULL);
    INSERT @f
    SELECT CAST(j.[key] AS INT), x.id, LTRIM(RTRIM(x.name)), x.field_type, ISNULL(x.is_required, 0),
           x.min_value, x.max_value, x.min_length, x.max_length
    FROM OPENJSON(ISNULL(@fields, N'[]')) j
    CROSS APPLY OPENJSON(j.value) WITH (
        id BIGINT '$.id', name NVARCHAR(200) '$.name', field_type NVARCHAR(30) '$.field_type', is_required BIT '$.is_required',
        min_value DECIMAL(18,4) '$.min_value', max_value DECIMAL(18,4) '$.max_value',
        min_length INT '$.min_length', max_length INT '$.max_length') x;

    SELECT TOP 1 @bad = idx FROM @f WHERE name IS NULL OR name = N'' ORDER BY idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.name|Field name is required.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = i.idx FROM @f i WHERE EXISTS (SELECT 1 FROM @f o WHERE o.name = i.name AND o.idx < i.idx) ORDER BY i.idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.name|Two fields have this name.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = idx FROM @f WHERE field_type IS NULL OR field_type NOT IN (N'number', N'string', N'date', N'boolean') ORDER BY idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.fieldType|Type must be number, string, date or boolean.');
        THROW 50400, @msg, 1;
    END
    -- Only numbers keep a value range and only strings a length range.
    UPDATE @f SET min_value = NULL, max_value = NULL WHERE field_type <> N'number';
    UPDATE @f SET min_length = NULL, max_length = NULL WHERE field_type <> N'string';
    SELECT TOP 1 @bad = idx FROM @f WHERE min_value > max_value ORDER BY idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.maxValue|Max must not be less than Min.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = idx FROM @f WHERE min_length < 0 OR max_length < 0 OR min_length > max_length ORDER BY idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.maxLength|Lengths must be 0 or more, and Max not less than Min.');
        THROW 50400, @msg, 1;
    END

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a checklist.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sep].[offboarding_checklist] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Checklist not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this checklist. Reload it and try again', 1;
    END
    SELECT TOP 1 @bad = i.idx FROM @f i
    WHERE i.id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [sep].[checklist_field] x WHERE x.id = i.id AND x.offboarding_checklist_id = @id)
    ORDER BY i.idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'fields.', @bad, N'.id|This field is not on the checklist.');
        THROW 50400, @msg, 1;
    END
    IF @id IS NOT NULL AND EXISTS (
            SELECT 1 FROM [sep].[checklist_field] x
            WHERE x.offboarding_checklist_id = @id AND NOT EXISTS (SELECT 1 FROM @f i WHERE i.id = x.id)
              AND EXISTS (SELECT 1 FROM [sep].[checklist_answer] a WHERE a.checklist_field_id = x.id))
        THROW 50409, N'fields|CHECKLIST_FIELD_IN_USE|A removed field has answers on an end of employment. Keep it, or deactivate the checklist.', 1;

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            EXEC [sep].[usp_number_next] @company_id = @company_id, @prefix = N'ECL', @code = @code OUTPUT;
            INSERT [sep].[offboarding_checklist] (company_id, code, name, description, is_active, created_by)
            VALUES (@company_id, @code, @name, @description, ISNULL(@is_active, 1), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [sep].[offboarding_checklist]
            SET name = @name, description = @description, is_active = ISNULL(@is_active, 1),
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this checklist. Reload it and try again', 1;

            DELETE x FROM [sep].[checklist_field] x
            WHERE x.offboarding_checklist_id = @id AND NOT EXISTS (SELECT 1 FROM @f i WHERE i.id = x.id);

            UPDATE x
            SET name = i.name, field_type = i.field_type, is_required = i.is_required, min_value = i.min_value,
                max_value = i.max_value, min_length = i.min_length, max_length = i.max_length, sort_order = i.idx,
                updated_at = @now, updated_by = @actor_user_id
            FROM [sep].[checklist_field] x JOIN @f i ON i.id = x.id;
        END

        INSERT [sep].[checklist_field] (offboarding_checklist_id, name, field_type, is_required, min_value, max_value,
                                        min_length, max_length, sort_order, created_by)
        SELECT @id, name, field_type, is_required, min_value, max_value, min_length, max_length, idx, @actor_user_id
        FROM @f WHERE id IS NULL ORDER BY idx;
    COMMIT;

    EXEC [sep].[usp_offboarding_checklist_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [sep].[usp_offboarding_checklist_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sep].[offboarding_checklist] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Checklist not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this checklist. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sep].[checklist_answer] a JOIN [sep].[checklist_field] f ON f.id = a.checklist_field_id
               WHERE f.offboarding_checklist_id = @id)
        THROW 50409, N'End of employment records have answers on this checklist. Deactivate it instead.', 1;

    BEGIN TRAN;
        DELETE [sep].[checklist_field] WHERE offboarding_checklist_id = @id;
        DELETE [sep].[offboarding_checklist] WHERE id = @id;
    COMMIT;
END
GO

-- The Checklist tab: fields of every active checklist.
CREATE OR ALTER PROCEDURE [sep].[usp_checklist_field_active_list]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.id, f.offboarding_checklist_id, k.name AS checklist_name, f.name, f.field_type, f.is_required,
           f.min_value, f.max_value, f.min_length, f.max_length, f.sort_order
    FROM [sep].[checklist_field] f
    JOIN [sep].[offboarding_checklist] k ON k.id = f.offboarding_checklist_id
    WHERE k.company_id = @company_id AND k.is_active = 1
    ORDER BY k.code, f.sort_order, f.id;
END
