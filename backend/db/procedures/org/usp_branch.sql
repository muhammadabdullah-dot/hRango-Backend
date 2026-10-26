-- Branches (Settings -> Control Panel -> Organization -> Branch): a branch sits in a location and
-- optionally one of its areas, has a manager, an address (country, state, city) and coordinates.

CREATE OR ALTER PROCEDURE [org].[usp_branch_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Branch not found', 1;

    SELECT b.id, b.company_id, c.name AS company_name, b.name, b.employee_prefix, b.description,
           b.location_id, l.name AS location_name, b.area_id, a.name AS area_name,
           b.manager_id, NULLIF(CONCAT(m.first_name, N' ', m.last_name), N' ') AS manager_name,
           b.country_id, co.iso_code AS country_code, co.name AS country_name,
           b.state_id, s.code AS state_code, s.name AS state_name, b.city_id, ci.name AS city_name,
           b.latitude, b.longitude,
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.branch_id = b.id AND e.status NOT IN (N'left', N'inactive')) AS employee_count,
           b.created_at, b.updated_at, b.row_version
    FROM [org].[branch] b
    JOIN [org].[company] c ON c.id = b.company_id
    JOIN [org].[location] l ON l.id = b.location_id
    LEFT JOIN [org].[area] a ON a.id = b.area_id
    LEFT JOIN [hr].[employee] m ON m.id = b.manager_id
    LEFT JOIN [org].[country] co ON co.id = b.country_id
    LEFT JOIN [org].[state] s ON s.id = b.state_id
    LEFT JOIN [org].[city] ci ON ci.id = b.city_id
    WHERE b.id = @id AND b.company_id = @company_id;
END
GO

-- Result set 1: total matching rows. Result set 2: the requested page.
CREATE OR ALTER PROCEDURE [org].[usp_branch_list]
    @company_id  BIGINT,
    @search      NVARCHAR(200) = NULL,
    @location_id BIGINT = NULL,
    @area_id     BIGINT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [org].[branch] b
    WHERE b.company_id = @company_id AND (@pattern IS NULL OR b.name LIKE @pattern OR b.employee_prefix LIKE @pattern)
      AND (@location_id IS NULL OR b.location_id = @location_id) AND (@area_id IS NULL OR b.area_id = @area_id)
    OPTION (RECOMPILE);

    SELECT b.id, b.company_id, c.name AS company_name, b.name, b.employee_prefix, b.description,
           b.location_id, l.name AS location_name, b.area_id, a.name AS area_name,
           b.manager_id, NULLIF(CONCAT(m.first_name, N' ', m.last_name), N' ') AS manager_name,
           b.country_id, co.iso_code AS country_code, co.name AS country_name,
           b.state_id, s.code AS state_code, s.name AS state_name, b.city_id, ci.name AS city_name,
           b.latitude, b.longitude,
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.branch_id = b.id AND e.status NOT IN (N'left', N'inactive')) AS employee_count,
           b.created_at, b.updated_at, b.row_version
    FROM [org].[branch] b
    JOIN [org].[company] c ON c.id = b.company_id
    JOIN [org].[location] l ON l.id = b.location_id
    LEFT JOIN [org].[area] a ON a.id = b.area_id
    LEFT JOIN [hr].[employee] m ON m.id = b.manager_id
    LEFT JOIN [org].[country] co ON co.id = b.country_id
    LEFT JOIN [org].[state] s ON s.id = b.state_id
    LEFT JOIN [org].[city] ci ON ci.id = b.city_id
    WHERE b.company_id = @company_id AND (@pattern IS NULL OR b.name LIKE @pattern OR b.employee_prefix LIKE @pattern)
      AND (@location_id IS NULL OR b.location_id = @location_id) AND (@area_id IS NULL OR b.area_id = @area_id)
    ORDER BY b.name, b.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_branch_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @employee_prefix NVARCHAR(10) = NULL,
    @location_id     BIGINT,
    @area_id         BIGINT = NULL,
    @manager_id      BIGINT = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @country_id      BIGINT = NULL,
    @state_id        BIGINT = NULL,
    @city_id         BIGINT = NULL,
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
        THROW 50400, N'name|Branch name is required.', 1;
    IF @location_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[location] WHERE id = @location_id AND company_id = @company_id)
        THROW 50400, N'locationId|Location not found.', 1;
    IF @area_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[area] WHERE id = @area_id AND location_id = @location_id)
        THROW 50400, N'areaId|This area is not in the chosen location.', 1;
    IF @manager_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @manager_id AND company_id = @company_id)
        THROW 50400, N'managerId|Manager not found.', 1;
    IF @country_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[country] WHERE id = @country_id)
        THROW 50400, N'countryId|Country not found.', 1;
    IF @state_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[state] WHERE id = @state_id AND country_id = @country_id)
        THROW 50400, N'stateId|This state is not in the chosen country.', 1;
    IF @city_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[city] WHERE id = @city_id AND state_id = @state_id)
        THROW 50400, N'cityId|This city is not in the chosen state.', 1;
    IF (@latitude IS NULL AND @longitude IS NOT NULL) OR (@latitude IS NOT NULL AND @longitude IS NULL)
        THROW 50400, N'longitude|Give both latitude and longitude, or neither.', 1;
    IF @latitude NOT BETWEEN -90 AND 90
        THROW 50400, N'latitude|Latitude must be between -90 and 90.', 1;
    IF @longitude NOT BETWEEN -180 AND 180
        THROW 50400, N'longitude|Longitude must be between -180 and 180.', 1;
    IF EXISTS (SELECT 1 FROM [org].[branch] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|BRANCH_DUPLICATE|A branch with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[branch] (company_id, location_id, area_id, name, employee_prefix, description, manager_id,
                                   country_id, state_id, city_id, latitude, longitude, created_by)
            VALUES (@company_id, @location_id, @area_id, @name, @employee_prefix, @description, @manager_id,
                    @country_id, @state_id, @city_id, @latitude, @longitude, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.branch', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a branch.', 1;

        DECLARE @o_name NVARCHAR(200), @o_prefix NVARCHAR(10), @o_loc BIGINT, @o_area BIGINT, @o_mgr BIGINT,
                @o_desc NVARCHAR(MAX), @o_country BIGINT, @o_state BIGINT, @o_city BIGINT, @o_lat DECIMAL(9,6),
                @o_lng DECIMAL(9,6), @o_rv BINARY(8);
        SELECT @o_name = name, @o_prefix = employee_prefix, @o_loc = location_id, @o_area = area_id, @o_mgr = manager_id,
               @o_desc = description, @o_country = country_id, @o_state = state_id, @o_city = city_id,
               @o_lat = latitude, @o_lng = longitude, @o_rv = row_version
        FROM [org].[branch] WHERE id = @id AND company_id = @company_id;

        IF @o_rv IS NULL
            THROW 50404, N'Branch not found', 1;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed this branch. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [org].[branch]
            SET name = @name, employee_prefix = @employee_prefix, location_id = @location_id, area_id = @area_id,
                manager_id = @manager_id, description = @description, country_id = @country_id, state_id = @state_id,
                city_id = @city_id, latitude = @latitude, longitude = @longitude,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this branch. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.branch', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @o_name, @name), (N'employee_prefix', @o_prefix, @employee_prefix),
                (N'description', @o_desc, @description),
                (N'location_id', CONVERT(NVARCHAR(30), @o_loc), CONVERT(NVARCHAR(30), @location_id)),
                (N'area_id', CONVERT(NVARCHAR(30), @o_area), CONVERT(NVARCHAR(30), @area_id)),
                (N'manager_id', CONVERT(NVARCHAR(30), @o_mgr), CONVERT(NVARCHAR(30), @manager_id)),
                (N'country_id', CONVERT(NVARCHAR(30), @o_country), CONVERT(NVARCHAR(30), @country_id)),
                (N'state_id', CONVERT(NVARCHAR(30), @o_state), CONVERT(NVARCHAR(30), @state_id)),
                (N'city_id', CONVERT(NVARCHAR(30), @o_city), CONVERT(NVARCHAR(30), @city_id)),
                (N'latitude', CONVERT(NVARCHAR(30), @o_lat), CONVERT(NVARCHAR(30), @latitude)),
                (N'longitude', CONVERT(NVARCHAR(30), @o_lng), CONVERT(NVARCHAR(30), @longitude))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_branch_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_branch_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [org].[branch] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Branch not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this branch. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE branch_id = @id)
        THROW 50409, N'Employees are assigned to this branch. Move them first', 1;

    BEGIN TRAN;
        -- Anything else still pointing here (devices, holidays, history) stops the delete with error 547.
        DELETE [org].[branch] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.branch', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
