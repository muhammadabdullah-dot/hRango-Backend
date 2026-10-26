-- Areas: parts of a location (Settings -> Control Panel -> Organization -> Area).

CREATE OR ALTER PROCEDURE [org].[usp_area_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[area] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Area not found', 1;

    SELECT a.id, a.location_id, l.name AS location_name, a.name, a.description,
           (SELECT COUNT(*) FROM [org].[branch] b WHERE b.area_id = a.id) AS branch_count,
           a.created_at, a.updated_at, a.row_version
    FROM [org].[area] a
    JOIN [org].[location] l ON l.id = a.location_id
    WHERE a.id = @id AND a.company_id = @company_id;
END
GO

-- Result set 1: total matching rows. Result set 2: the requested page.
CREATE OR ALTER PROCEDURE [org].[usp_area_list]
    @company_id  BIGINT,
    @search      NVARCHAR(200) = NULL,
    @location_id BIGINT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [org].[area] a
    WHERE a.company_id = @company_id AND (@pattern IS NULL OR a.name LIKE @pattern)
      AND (@location_id IS NULL OR a.location_id = @location_id)
    OPTION (RECOMPILE);

    SELECT a.id, a.location_id, l.name AS location_name, a.name, a.description,
           (SELECT COUNT(*) FROM [org].[branch] b WHERE b.area_id = a.id) AS branch_count,
           a.created_at, a.updated_at, a.row_version
    FROM [org].[area] a
    JOIN [org].[location] l ON l.id = a.location_id
    WHERE a.company_id = @company_id AND (@pattern IS NULL OR a.name LIKE @pattern)
      AND (@location_id IS NULL OR a.location_id = @location_id)
    ORDER BY l.name, a.name, a.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_area_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @location_id   BIGINT,
    @name          NVARCHAR(200),
    @description   NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Area name is required.', 1;
    IF @location_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[location] WHERE id = @location_id AND company_id = @company_id)
        THROW 50400, N'locationId|Location not found.', 1;
    IF EXISTS (SELECT 1 FROM [org].[area] WHERE location_id = @location_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|AREA_DUPLICATE|This location already has an area with this name.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[area] (company_id, location_id, name, description, created_by)
            VALUES (@company_id, @location_id, @name, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.area', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an area.', 1;

        DECLARE @o_name NVARCHAR(200), @o_loc BIGINT, @o_desc NVARCHAR(MAX), @o_rv BINARY(8);
        SELECT @o_name = name, @o_loc = location_id, @o_desc = description, @o_rv = row_version
        FROM [org].[area] WHERE id = @id AND company_id = @company_id;

        IF @o_rv IS NULL
            THROW 50404, N'Area not found', 1;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed this area. Reload it and try again', 1;
        IF @o_loc <> @location_id AND EXISTS (SELECT 1 FROM [org].[branch] WHERE area_id = @id)
            THROW 50409, N'locationId|Branches sit in this area. Move them before moving the area to another location.', 1;

        BEGIN TRAN;
            UPDATE [org].[area]
            SET location_id = @location_id, name = @name, description = @description,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this area. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.area', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @o_name, @name), (N'description', @o_desc, @description),
                (N'location_id', CONVERT(NVARCHAR(30), @o_loc), CONVERT(NVARCHAR(30), @location_id))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_area_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_area_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [org].[area] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Area not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this area. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [org].[branch] WHERE area_id = @id)
        THROW 50409, N'Branches sit in this area. Move or delete them first', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE area_id = @id)
        THROW 50409, N'Employees are assigned to this area. Move them first', 1;

    BEGIN TRAN;
        DELETE [org].[area] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.area', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
