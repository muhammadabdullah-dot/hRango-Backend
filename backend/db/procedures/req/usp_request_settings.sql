-- Request types (the fixed reference list) and Request Settings -> Request Restriction.
CREATE OR ALTER PROCEDURE [req].[usp_request_type_list]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, code, name, kind, prefix, is_admin_only, is_active, sort_order
    FROM [req].[request_type]
    ORDER BY sort_order, id;
END
GO

-- Restrictions list. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [req].[usp_request_restriction_list]
    @company_id BIGINT,
    @type_code  NVARCHAR(30) = NULL,
    @start_from DATE = NULL,
    @start_to   DATE = NULL,
    @end_from   DATE = NULL,
    @end_to     DATE = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [req].[request_restriction] x JOIN [req].[request_type] t ON t.id = x.request_type_id
    WHERE x.company_id = @company_id AND (@type_code IS NULL OR t.code = @type_code)
      AND (@start_from IS NULL OR x.start_date >= @start_from) AND (@start_to IS NULL OR x.start_date <= @start_to)
      AND (@end_from IS NULL OR x.end_date >= @end_from) AND (@end_to IS NULL OR x.end_date <= @end_to)
    OPTION (RECOMPILE);

    SELECT x.id, c.name AS company_name, t.code AS request_type, t.name AS request_type_name, x.start_date, x.end_date,
           x.description, x.created_at, x.updated_at, x.row_version
    FROM [req].[request_restriction] x
    JOIN [req].[request_type] t ON t.id = x.request_type_id
    JOIN [org].[company] c ON c.id = x.company_id
    WHERE x.company_id = @company_id AND (@type_code IS NULL OR t.code = @type_code)
      AND (@start_from IS NULL OR x.start_date >= @start_from) AND (@start_to IS NULL OR x.start_date <= @start_to)
      AND (@end_from IS NULL OR x.end_date >= @end_from) AND (@end_to IS NULL OR x.end_date <= @end_to)
    ORDER BY x.start_date DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_request_restriction_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [req].[request_restriction] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Restriction not found', 1;
    SELECT x.id, c.name AS company_name, t.code AS request_type, t.name AS request_type_name, x.start_date, x.end_date,
           x.description, x.created_at, x.updated_at, x.row_version
    FROM [req].[request_restriction] x
    JOIN [req].[request_type] t ON t.id = x.request_type_id
    JOIN [org].[company] c ON c.id = x.company_id
    WHERE x.id = @id;
END
GO

-- Adds a restriction (@id NULL) or edits one (with the @row_version last read): end on or after
-- start, no overlap with another restriction of the same type (Functional Requirements p. 1). A new
-- start date must be in the future; an edit may keep a start date that has already passed, and its
-- end date may not be moved into the past.
CREATE OR ALTER PROCEDURE [req].[usp_request_restriction_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @type_code     NVARCHAR(30),
    @start_date    DATE,
    @end_date      DATE,
    @description   NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @type_id BIGINT = (SELECT id FROM [req].[request_type] WHERE code = @type_code AND is_active = 1);
    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @rv BINARY(8), @old_type BIGINT, @old_start DATE, @old_end DATE, @old_desc NVARCHAR(MAX);
    IF @id IS NOT NULL
    BEGIN
        SELECT @rv = row_version, @old_type = request_type_id, @old_start = start_date, @old_end = end_date,
               @old_desc = description
        FROM [req].[request_restriction] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Restriction not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this restriction. Reload it and try again', 1;
    END
    IF @type_id IS NULL
        THROW 50400, N'requestType|Request type is required.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Start date is required.', 1;
    IF @end_date IS NULL
        THROW 50400, N'endDate|End date is required.', 1;
    IF @start_date <= @today AND (@id IS NULL OR @start_date <> @old_start)
        THROW 50400, N'startDate|Start date must be in the future.', 1;
    IF @end_date < @start_date
        THROW 50400, N'endDate|End date must be on or after the start date.', 1;
    IF @id IS NOT NULL AND @end_date < @today AND @end_date <> @old_end
        THROW 50400, N'endDate|End date cannot be moved into the past.', 1;
    IF EXISTS (SELECT 1 FROM [req].[request_restriction] WHERE company_id = @company_id AND request_type_id = @type_id
               AND start_date <= @end_date AND end_date >= @start_date AND (@id IS NULL OR id <> @id))
        THROW 50409, N'startDate|RESTRICTION_OVERLAP|Another restriction of this type covers some of these dates.', 1;

    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [req].[request_restriction] (company_id, request_type_id, start_date, end_date, description, created_by)
            VALUES (@company_id, @type_id, @start_date, @end_date, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'req.request_restriction', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [req].[request_restriction]
            SET request_type_id = @type_id, start_date = @start_date, end_date = @end_date, description = @description,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this restriction. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'req.request_restriction', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES (N'request_type_id', CONVERT(NVARCHAR(30), @old_type), CONVERT(NVARCHAR(30), @type_id)),
                         (N'start_date', CONVERT(NVARCHAR(10), @old_start, 23), CONVERT(NVARCHAR(10), @start_date, 23)),
                         (N'end_date', CONVERT(NVARCHAR(10), @old_end, 23), CONVERT(NVARCHAR(10), @end_date, 23)),
                         (N'description', @old_desc, @description)) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        END
    COMMIT;

    EXEC [req].[usp_request_restriction_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_request_restriction_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [req].[request_restriction] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Restriction not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this restriction. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [req].[request_restriction] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request_restriction', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
