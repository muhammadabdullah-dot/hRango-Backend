-- Holidays with the rules that say whom they apply to (none = everyone). See sch.fn_employee_holidays.
-- Result set 1: the holiday. Result set 2: its rules.
CREATE OR ALTER PROCEDURE [sch].[usp_holiday_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[holiday] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Holiday not found', 1;

    SELECT h.id, h.name, h.holiday_type, h.start_date, h.end_date, h.description, h.attendance_exempt,
           DATEDIFF(DAY, h.start_date, h.end_date) + 1 AS day_count,
           h.created_at, h.updated_at, h.row_version
    FROM [sch].[holiday] h
    WHERE h.id = @id AND h.company_id = @company_id;

    SELECT r.id, r.rule_type, r.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           r.location_id, l.name AS location_name, r.branch_id, b.name AS branch_name,
           r.country_id, c.name AS country_name, r.state_id, s.name AS state_name, r.city_id, ci.name AS city_name,
           r.religion
    FROM [sch].[holiday_rule] r
    LEFT JOIN [hr].[employee] e ON e.id = r.employee_id
    LEFT JOIN [org].[location] l ON l.id = r.location_id
    LEFT JOIN [org].[branch] b ON b.id = r.branch_id
    LEFT JOIN [org].[country] c ON c.id = r.country_id
    LEFT JOIN [org].[state] s ON s.id = r.state_id
    LEFT JOIN [org].[city] ci ON ci.id = r.city_id
    WHERE r.holiday_id = @id
    ORDER BY r.id;
END
GO

-- Holiday list. @year: holidays that touch that calendar year. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [sch].[usp_holiday_list]
    @company_id   BIGINT,
    @year         INT = NULL,
    @search       NVARCHAR(200) = NULL,
    @holiday_type NVARCHAR(30) = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @y_from DATE = CASE WHEN @year IS NULL THEN NULL ELSE DATEFROMPARTS(@year, 1, 1) END;
    DECLARE @y_to DATE = CASE WHEN @year IS NULL THEN NULL ELSE DATEFROMPARTS(@year, 12, 31) END;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sch].[holiday] h
    WHERE h.company_id = @company_id
      AND (@y_from IS NULL OR (h.start_date <= @y_to AND h.end_date >= @y_from))
      AND (@pattern IS NULL OR h.name LIKE @pattern)
      AND (@holiday_type IS NULL OR h.holiday_type = @holiday_type)
    OPTION (RECOMPILE);

    SELECT h.id, h.name, h.holiday_type, h.start_date, h.end_date, h.description, h.attendance_exempt,
           DATEDIFF(DAY, h.start_date, h.end_date) + 1 AS day_count,
           (SELECT COUNT(*) FROM [sch].[holiday_rule] r WHERE r.holiday_id = h.id) AS rule_count,
           h.created_at, h.updated_at, h.row_version
    FROM [sch].[holiday] h
    WHERE h.company_id = @company_id
      AND (@y_from IS NULL OR (h.start_date <= @y_to AND h.end_date >= @y_from))
      AND (@pattern IS NULL OR h.name LIKE @pattern)
      AND (@holiday_type IS NULL OR h.holiday_type = @holiday_type)
    ORDER BY h.start_date, h.name, h.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds or edits a holiday with its rules. @rules is a JSON array of
-- {"rule_type", "employee_id", "location_id", "branch_id", "country_id", "state_id", "city_id", "religion"}:
--   employee       employee_id
--   org_structure  location_id and branch_id (the branch must be in the location)
--   geo_location   country_id, state_id and city_id (matched against the employee's branch)
--   religion       religion
-- The rules are replaced by the list given.
CREATE OR ALTER PROCEDURE [sch].[usp_holiday_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @id                BIGINT = NULL,
    @name              NVARCHAR(200),
    @holiday_type      NVARCHAR(30),
    @start_date        DATE,
    @end_date          DATE,
    @description       NVARCHAR(MAX) = NULL,
    @attendance_exempt BIT = 0,
    @rules             NVARCHAR(MAX) = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Holiday name is required.', 1;
    IF @holiday_type IS NULL OR @holiday_type NOT IN (N'public', N'local')
        THROW 50400, N'holidayType|Type is public or local.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Start date is required.', 1;
    IF @end_date IS NULL
        THROW 50400, N'endDate|End date is required.', 1;
    IF @end_date < @start_date
        THROW 50400, N'endDate|End date cannot be before the start date.', 1;
    IF DATEDIFF(DAY, @start_date, @end_date) > 366
        THROW 50400, N'endDate|A holiday lasts at most a year.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[holiday] WHERE company_id = @company_id AND name = @name AND start_date = @start_date AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|HOLIDAY_DUPLICATE|A holiday with this name already starts on this date.', 1;
    IF @rules IS NOT NULL AND ISJSON(@rules) = 0
        THROW 50400, N'rules|Rules are not valid.', 1;

    DECLARE @r TABLE (n INT IDENTITY(1,1), rule_type NVARCHAR(30), employee_id BIGINT, location_id BIGINT, branch_id BIGINT,
                      country_id BIGINT, state_id BIGINT, city_id BIGINT, religion NVARCHAR(50));
    INSERT @r (rule_type, employee_id, location_id, branch_id, country_id, state_id, city_id, religion)
    SELECT j.rule_type,
           CASE WHEN j.rule_type = N'employee' THEN j.employee_id END,
           CASE WHEN j.rule_type = N'org_structure' THEN j.location_id END,
           CASE WHEN j.rule_type = N'org_structure' THEN j.branch_id END,
           CASE WHEN j.rule_type = N'geo_location' THEN j.country_id END,
           CASE WHEN j.rule_type = N'geo_location' THEN j.state_id END,
           CASE WHEN j.rule_type = N'geo_location' THEN j.city_id END,
           CASE WHEN j.rule_type = N'religion' THEN NULLIF(LTRIM(RTRIM(j.religion)), N'') END
    FROM OPENJSON(ISNULL(@rules, N'[]')) WITH (rule_type NVARCHAR(30), employee_id BIGINT, location_id BIGINT, branch_id BIGINT,
                                              country_id BIGINT, state_id BIGINT, city_id BIGINT, religion NVARCHAR(50)) j;

    IF EXISTS (SELECT 1 FROM @r WHERE rule_type IS NULL OR rule_type NOT IN (N'employee', N'org_structure', N'geo_location', N'religion'))
        THROW 50400, N'rules|A rule is employee, org_structure, geo_location or religion.', 1;
    IF EXISTS (SELECT 1 FROM @r x WHERE x.rule_type = N'employee'
               AND NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = x.employee_id AND e.company_id = @company_id))
        THROW 50400, N'rules|Employee not found.', 1;
    IF EXISTS (SELECT 1 FROM @r x WHERE x.rule_type = N'org_structure'
               AND NOT EXISTS (SELECT 1 FROM [org].[branch] b WHERE b.id = x.branch_id AND b.company_id = @company_id AND b.location_id = x.location_id))
        THROW 50400, N'rules|Pick a location and a branch in that location.', 1;
    IF EXISTS (SELECT 1 FROM @r x WHERE x.rule_type = N'geo_location'
               AND NOT EXISTS (SELECT 1 FROM [org].[city] ci JOIN [org].[state] s ON s.id = ci.state_id
                               WHERE ci.id = x.city_id AND s.id = x.state_id AND s.country_id = x.country_id))
        THROW 50400, N'rules|Pick a country, a state in it and a city in that state.', 1;
    IF EXISTS (SELECT 1 FROM @r WHERE rule_type = N'religion' AND religion IS NULL)
        THROW 50400, N'rules|Pick a religion.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a holiday.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sch].[holiday] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Holiday not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this holiday. Reload it and try again', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [sch].[holiday] (company_id, name, holiday_type, start_date, end_date, description, attendance_exempt, created_by)
            VALUES (@company_id, @name, @holiday_type, @start_date, @end_date, @description, ISNULL(@attendance_exempt, 0), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.holiday', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [sch].[holiday]
            SET name = @name, holiday_type = @holiday_type, start_date = @start_date, end_date = @end_date,
                description = @description, attendance_exempt = ISNULL(@attendance_exempt, 0),
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this holiday. Reload it and try again', 1;
            DELETE [sch].[holiday_rule] WHERE holiday_id = @id;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.holiday', @id, N'update', @actor_user_id, @now);
        END

        INSERT [sch].[holiday_rule] (holiday_id, rule_type, employee_id, location_id, branch_id, country_id, state_id, city_id, religion, created_by)
        SELECT @id, rule_type, employee_id, location_id, branch_id, country_id, state_id, city_id, religion, @actor_user_id
        FROM @r ORDER BY n;
    COMMIT;

    EXEC [sch].[usp_holiday_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [sch].[usp_holiday_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sch].[holiday] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Holiday not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this holiday. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [sch].[holiday_rule] WHERE holiday_id = @id;
        DELETE [sch].[holiday] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.holiday', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
