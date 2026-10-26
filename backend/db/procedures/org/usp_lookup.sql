-- Picker lists for any signed-in user: ids and names only, no settings or counts.

-- One organisation list of the company. @kind: location, area, branch, department, division,
-- cost_center, designation, job_title, grade, job_level, employee_group, employment_type.
-- @parent_id narrows areas and branches to a location, departments to a parent department.
CREATE OR ALTER PROCEDURE [org].[usp_lookup_list]
    @company_id BIGINT,
    @kind       NVARCHAR(30),
    @parent_id  BIGINT = NULL,
    @search     NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @r TABLE (id BIGINT, name NVARCHAR(200), code NVARCHAR(30), parent_id BIGINT, sort_order INT);

    IF @kind = N'location'
        INSERT @r SELECT id, name, employee_prefix, NULL, NULL FROM [org].[location] WHERE company_id = @company_id;
    ELSE IF @kind = N'area'
        INSERT @r SELECT id, name, NULL, location_id, NULL FROM [org].[area]
        WHERE company_id = @company_id AND (@parent_id IS NULL OR location_id = @parent_id);
    ELSE IF @kind = N'branch'
        INSERT @r SELECT id, name, employee_prefix, location_id, NULL FROM [org].[branch]
        WHERE company_id = @company_id AND (@parent_id IS NULL OR location_id = @parent_id);
    ELSE IF @kind = N'department'
        INSERT @r SELECT id, name, NULL, parent_id, NULL FROM [org].[department]
        WHERE company_id = @company_id AND (@parent_id IS NULL OR parent_id = @parent_id);
    ELSE IF @kind = N'division'
        INSERT @r SELECT id, name, NULL, NULL, NULL FROM [org].[division] WHERE company_id = @company_id;
    ELSE IF @kind = N'cost_center'
        INSERT @r SELECT id, name, code, NULL, NULL FROM [org].[cost_center] WHERE company_id = @company_id;
    ELSE IF @kind = N'designation'
        INSERT @r SELECT id, name, NULL, NULL, NULL FROM [org].[designation] WHERE company_id = @company_id;
    ELSE IF @kind = N'job_title'
        INSERT @r SELECT id, name, NULL, NULL, NULL FROM [org].[job_title] WHERE company_id = @company_id;
    ELSE IF @kind = N'grade'
        INSERT @r SELECT id, name, NULL, NULL, sort_order FROM [org].[grade] WHERE company_id = @company_id;
    ELSE IF @kind = N'job_level'
        INSERT @r SELECT id, name, NULL, NULL, sort_order FROM [org].[job_level] WHERE company_id = @company_id;
    ELSE IF @kind = N'employee_group'
        INSERT @r SELECT id, name, NULL, NULL, NULL FROM [org].[employee_group] WHERE company_id = @company_id;
    ELSE IF @kind = N'employment_type'
        INSERT @r SELECT id, name, NULL, NULL, NULL FROM [org].[employment_type] WHERE company_id = @company_id;
    ELSE
        THROW 50404, N'No such list', 1;

    SELECT id, name, code, parent_id
    FROM @r
    WHERE @pattern IS NULL OR name LIKE @pattern OR code LIKE @pattern
    ORDER BY sort_order, name, id;
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_geo_country_list]
    @search NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT id, iso_code AS code, name
    FROM [org].[country]
    WHERE @pattern IS NULL OR name LIKE @pattern OR iso_code LIKE @pattern
    ORDER BY name;
END
GO

-- States of a country, by id or ISO code.
CREATE OR ALTER PROCEDURE [org].[usp_geo_state_list]
    @country_id   BIGINT = NULL,
    @country_code CHAR(2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.id, s.code, s.name, s.country_id, c.iso_code AS country_code
    FROM [org].[state] s
    JOIN [org].[country] c ON c.id = s.country_id
    WHERE (s.country_id = @country_id OR c.iso_code = @country_code)
    ORDER BY s.name;
END
GO

-- Cities of a state, by id or ISO 3166-2 code.
CREATE OR ALTER PROCEDURE [org].[usp_geo_city_list]
    @state_id   BIGINT = NULL,
    @state_code NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ci.id, ci.name, ci.state_id, s.code AS state_code
    FROM [org].[city] ci
    JOIN [org].[state] s ON s.id = ci.state_id
    WHERE (ci.state_id = @state_id OR s.code = @state_code)
    ORDER BY ci.name;
END
