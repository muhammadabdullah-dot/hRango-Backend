-- Break types (Attendance settings -> Break Types). The start and end identifiers are what a device
-- or a log sends to mark a break out and a break in, so they are unique across the company's types.
CREATE OR ALTER PROCEDURE [sch].[usp_break_type_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[break_type] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Break type not found', 1;

    SELECT id, name, start_identifier, end_identifier, created_at, updated_at, row_version
    FROM [sch].[break_type]
    WHERE id = @id AND company_id = @company_id;
END
GO

-- Break type list. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [sch].[usp_break_type_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sch].[break_type] b
    WHERE b.company_id = @company_id
      AND (@pattern IS NULL OR b.name LIKE @pattern OR b.start_identifier LIKE @pattern OR b.end_identifier LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT b.id, b.name, b.start_identifier, b.end_identifier, b.created_at, b.updated_at, b.row_version
    FROM [sch].[break_type] b
    WHERE b.company_id = @company_id
      AND (@pattern IS NULL OR b.name LIKE @pattern OR b.start_identifier LIKE @pattern OR b.end_identifier LIKE @pattern)
    ORDER BY b.name, b.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [sch].[usp_break_type_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT = NULL,
    @id               BIGINT = NULL,
    @name             NVARCHAR(200),
    @start_identifier NVARCHAR(50),
    @end_identifier   NVARCHAR(50),
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @start_identifier = LTRIM(RTRIM(@start_identifier));
    SET @end_identifier = LTRIM(RTRIM(@end_identifier));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Break type name is required.', 1;
    IF @start_identifier IS NULL OR @start_identifier = N''
        THROW 50400, N'startIdentifier|Start identifier is required.', 1;
    IF @end_identifier IS NULL OR @end_identifier = N''
        THROW 50400, N'endIdentifier|End identifier is required.', 1;
    IF @start_identifier = @end_identifier
        THROW 50400, N'endIdentifier|The end identifier must differ from the start identifier.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[break_type] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|BREAK_TYPE_DUPLICATE|A break type with this name already exists.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[break_type] WHERE company_id = @company_id AND (@id IS NULL OR id <> @id)
               AND @start_identifier IN (start_identifier, end_identifier))
        THROW 50409, N'startIdentifier|IDENTIFIER_DUPLICATE|Another break type already uses this identifier.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[break_type] WHERE company_id = @company_id AND (@id IS NULL OR id <> @id)
               AND @end_identifier IN (start_identifier, end_identifier))
        THROW 50409, N'endIdentifier|IDENTIFIER_DUPLICATE|Another break type already uses this identifier.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [sch].[break_type] (company_id, name, start_identifier, end_identifier, created_by)
            VALUES (@company_id, @name, @start_identifier, @end_identifier, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.break_type', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a break type.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sch].[break_type] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Break type not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this break type. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [sch].[break_type]
            SET name = @name, start_identifier = @start_identifier, end_identifier = @end_identifier,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this break type. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.break_type', @id, N'update', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [sch].[usp_break_type_get] @company_id = @company_id, @id = @id;
END
GO

-- Refused while a time slot or a scheduled shift uses the type; a punch pointing here stops it with error 547.
CREATE OR ALTER PROCEDURE [sch].[usp_break_type_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sch].[break_type] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Break type not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this break type. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sch].[time_slot_break] WHERE break_type_id = @id)
        THROW 50409, N'A time slot uses this break type. Remove it from the slot first', 1;
    IF EXISTS (SELECT 1 FROM [sch].[schedule_break] WHERE break_type_id = @id)
        THROW 50409, N'Scheduled shifts use this break type', 1;

    BEGIN TRAN;
        DELETE [sch].[break_type] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.break_type', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
