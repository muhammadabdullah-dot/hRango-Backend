-- Locations (Settings -> Control Panel -> Organization -> Location): name, employee code prefix,
-- description and map coordinates.

CREATE OR ALTER PROCEDURE [org].[usp_location_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[location] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Location not found', 1;

    SELECT l.id, l.company_id, c.name AS company_name, l.name, l.employee_prefix, l.description,
           l.latitude, l.longitude,
           (SELECT COUNT(*) FROM [org].[branch] b WHERE b.location_id = l.id) AS branch_count,
           l.created_at, l.updated_at, l.row_version
    FROM [org].[location] l
    JOIN [org].[company] c ON c.id = l.company_id
    WHERE l.id = @id AND l.company_id = @company_id;
END
GO

-- Result set 1: total matching rows. Result set 2: the requested page.
CREATE OR ALTER PROCEDURE [org].[usp_location_list]
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
    FROM [org].[location] l
    WHERE l.company_id = @company_id AND (@pattern IS NULL OR l.name LIKE @pattern OR l.employee_prefix LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT l.id, l.company_id, c.name AS company_name, l.name, l.employee_prefix, l.description,
           l.latitude, l.longitude,
           (SELECT COUNT(*) FROM [org].[branch] b WHERE b.location_id = l.id) AS branch_count,
           l.created_at, l.updated_at, l.row_version
    FROM [org].[location] l
    JOIN [org].[company] c ON c.id = l.company_id
    WHERE l.company_id = @company_id AND (@pattern IS NULL OR l.name LIKE @pattern OR l.employee_prefix LIKE @pattern)
    ORDER BY l.name, l.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a location (@id NULL) or edits one (@id and the @row_version last read). Returns the saved row.
CREATE OR ALTER PROCEDURE [org].[usp_location_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @employee_prefix NVARCHAR(10) = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @latitude        DECIMAL(9,6) = NULL,
    @longitude       DECIMAL(9,6) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @employee_prefix = NULLIF(LTRIM(RTRIM(@employee_prefix)), N'');
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Location name is required.', 1;
    IF (@latitude IS NULL AND @longitude IS NOT NULL) OR (@latitude IS NOT NULL AND @longitude IS NULL)
        THROW 50400, N'longitude|Give both latitude and longitude, or neither.', 1;
    IF @latitude NOT BETWEEN -90 AND 90
        THROW 50400, N'latitude|Latitude must be between -90 and 90.', 1;
    IF @longitude NOT BETWEEN -180 AND 180
        THROW 50400, N'longitude|Longitude must be between -180 and 180.', 1;
    IF EXISTS (SELECT 1 FROM [org].[location] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|LOCATION_DUPLICATE|A location with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[location] (company_id, name, employee_prefix, description, latitude, longitude, created_by)
            VALUES (@company_id, @name, @employee_prefix, @description, @latitude, @longitude, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.location', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a location.', 1;

        DECLARE @o_name NVARCHAR(200), @o_prefix NVARCHAR(10), @o_desc NVARCHAR(MAX), @o_lat DECIMAL(9,6),
                @o_lng DECIMAL(9,6), @o_rv BINARY(8);
        SELECT @o_name = name, @o_prefix = employee_prefix, @o_desc = description, @o_lat = latitude,
               @o_lng = longitude, @o_rv = row_version
        FROM [org].[location] WHERE id = @id AND company_id = @company_id;

        IF @o_rv IS NULL
            THROW 50404, N'Location not found', 1;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed this location. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [org].[location]
            SET name = @name, employee_prefix = @employee_prefix, description = @description, latitude = @latitude,
                longitude = @longitude, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this location. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.location', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @o_name, @name), (N'employee_prefix', @o_prefix, @employee_prefix),
                (N'description', @o_desc, @description),
                (N'latitude', CONVERT(NVARCHAR(30), @o_lat), CONVERT(NVARCHAR(30), @latitude)),
                (N'longitude', CONVERT(NVARCHAR(30), @o_lng), CONVERT(NVARCHAR(30), @longitude))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_location_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_location_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [org].[location] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Location not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this location. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [org].[branch] WHERE location_id = @id)
        THROW 50409, N'This location has branches. Move or delete them first', 1;
    IF EXISTS (SELECT 1 FROM [org].[area] WHERE location_id = @id)
        THROW 50409, N'This location has areas. Move or delete them first', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE location_id = @id)
        THROW 50409, N'Employees are assigned to this location. Move them first', 1;

    BEGIN TRAN;
        DELETE [org].[location] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.location', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
