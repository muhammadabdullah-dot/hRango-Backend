-- Companies and their general settings (Settings -> Control Panel -> General Settings).
-- A user reaches their home company, the companies in auth.user_company, or every company when
-- they are a system administrator. Any other company is "not found".

CREATE OR ALTER PROCEDURE [org].[usp_company_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[company] c WHERE c.id = @id)
       OR NOT (   @id = @company_id
               OR EXISTS (SELECT 1 FROM [auth].[user_account] u WHERE u.id = @actor_user_id AND (u.is_system_admin = 1 OR u.company_id = @id))
               OR EXISTS (SELECT 1 FROM [auth].[user_company] uc WHERE uc.user_account_id = @actor_user_id AND uc.company_id = @id))
        THROW 50404, N'Company not found', 1;

    SELECT c.id, c.name, c.legal_name, c.email, c.phone, c.website, c.address, c.logo_file_id,
           c.country_id, co.name AS country_name, RTRIM(c.currency) AS currency, c.timezone, c.date_format,
           c.week_start_day, c.fiscal_year_start_month, c.is_active,
           c.created_at, c.updated_at, c.row_version
    FROM [org].[company] c
    LEFT JOIN [org].[country] co ON co.id = c.country_id
    WHERE c.id = @id;
END
GO

-- Companies the user may see. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [org].[usp_company_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @admin BIT = ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    DECLARE @home BIGINT = (SELECT company_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    DECLARE @mine TABLE (id BIGINT PRIMARY KEY);
    INSERT @mine
    SELECT c.id FROM [org].[company] c
    WHERE (@admin = 1 OR c.id = @company_id OR c.id = @home
           OR EXISTS (SELECT 1 FROM [auth].[user_company] uc WHERE uc.user_account_id = @actor_user_id AND uc.company_id = c.id))
      AND (@pattern IS NULL OR c.name LIKE @pattern OR c.legal_name LIKE @pattern);

    SELECT COUNT(*) AS total FROM @mine;

    SELECT c.id, c.name, c.legal_name, c.email, c.phone, c.website, c.address, c.logo_file_id,
           c.country_id, co.name AS country_name, RTRIM(c.currency) AS currency, c.timezone, c.date_format,
           c.week_start_day, c.fiscal_year_start_month, c.is_active,
           c.created_at, c.updated_at, c.row_version
    FROM @mine m
    JOIN [org].[company] c ON c.id = m.id
    LEFT JOIN [org].[country] co ON co.id = c.country_id
    ORDER BY c.name, c.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a company (@id NULL; the actor is given access to it) or edits one the actor may see.
-- Returns the saved row. The service applies the default roles to a new company afterwards.
CREATE OR ALTER PROCEDURE [org].[usp_company_save]
    @company_id              BIGINT,
    @actor_user_id           BIGINT,
    @id                      BIGINT = NULL,
    @name                    NVARCHAR(200),
    @legal_name              NVARCHAR(200) = NULL,
    @email                   NVARCHAR(254) = NULL,
    @phone                   NVARCHAR(30) = NULL,
    @website                 NVARCHAR(200) = NULL,
    @address                 NVARCHAR(500) = NULL,
    @country_id              BIGINT = NULL,
    @currency                CHAR(3),
    @timezone                NVARCHAR(64),
    @date_format             NVARCHAR(30),
    @week_start_day          NVARCHAR(30),
    @fiscal_year_start_month INT,
    @row_version             BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @legal_name = NULLIF(LTRIM(RTRIM(@legal_name)), N'');
    SET @email = NULLIF(LTRIM(RTRIM(@email)), N'');
    SET @phone = NULLIF(LTRIM(RTRIM(@phone)), N'');
    SET @website = NULLIF(LTRIM(RTRIM(@website)), N'');
    SET @address = NULLIF(LTRIM(RTRIM(@address)), N'');

    IF @name IS NULL OR @name = N''
        THROW 50400, N'organizationName|Organization name is required.', 1;
    IF @country_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[country] WHERE id = @country_id)
        THROW 50400, N'countryId|Country not found.', 1;
    IF @fiscal_year_start_month IS NULL OR @fiscal_year_start_month NOT BETWEEN 1 AND 12
        THROW 50400, N'fiscalYearStartMonth|Select a month from 1 to 12.', 1;
    IF EXISTS (SELECT 1 FROM [org].[company] WHERE name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'organizationName|COMPANY_DUPLICATE|A company with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[company] (name, legal_name, email, phone, website, address, country_id, currency, timezone,
                                    date_format, week_start_day, fiscal_year_start_month, is_active, created_by)
            VALUES (@name, @legal_name, @email, @phone, @website, @address, @country_id, @currency, @timezone,
                    @date_format, @week_start_day, @fiscal_year_start_month, 1, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            EXEC [org].[usp_company_defaults_apply] @company_id = @id;

            INSERT [auth].[user_company] (user_account_id, company_id)
            SELECT @actor_user_id, @id
            WHERE @actor_user_id IS NOT NULL;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@id, N'org.company', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit the settings.', 1;

        DECLARE @o_name NVARCHAR(200), @o_legal NVARCHAR(200), @o_email NVARCHAR(254), @o_phone NVARCHAR(30),
                @o_web NVARCHAR(200), @o_addr NVARCHAR(500), @o_country BIGINT, @o_cur CHAR(3), @o_tz NVARCHAR(64),
                @o_df NVARCHAR(200), @o_ws NVARCHAR(30), @o_fy INT, @o_rv BINARY(8);
        SELECT @o_name = name, @o_legal = legal_name, @o_email = email, @o_phone = phone, @o_web = website,
               @o_addr = address, @o_country = country_id, @o_cur = currency, @o_tz = timezone, @o_df = date_format,
               @o_ws = week_start_day, @o_fy = fiscal_year_start_month, @o_rv = row_version
        FROM [org].[company] WHERE id = @id;

        IF @o_rv IS NULL
           OR NOT (   @id = @company_id
                   OR EXISTS (SELECT 1 FROM [auth].[user_account] u WHERE u.id = @actor_user_id AND (u.is_system_admin = 1 OR u.company_id = @id))
                   OR EXISTS (SELECT 1 FROM [auth].[user_company] uc WHERE uc.user_account_id = @actor_user_id AND uc.company_id = @id))
            THROW 50404, N'Company not found', 1;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed these settings. Reload them and try again', 1;

        BEGIN TRAN;
            UPDATE [org].[company]
            SET name = @name, legal_name = @legal_name, email = @email, phone = @phone, website = @website,
                address = @address, country_id = @country_id, currency = @currency, timezone = @timezone,
                date_format = @date_format, week_start_day = @week_start_day,
                fiscal_year_start_month = @fiscal_year_start_month, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed these settings. Reload them and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @id, N'org.company', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @o_name, @name), (N'legal_name', @o_legal, @legal_name), (N'email', @o_email, @email),
                (N'phone', @o_phone, @phone), (N'website', @o_web, @website), (N'address', @o_addr, @address),
                (N'country_id', CONVERT(NVARCHAR(30), @o_country), CONVERT(NVARCHAR(30), @country_id)),
                (N'currency', CONVERT(NVARCHAR(10), @o_cur), CONVERT(NVARCHAR(10), @currency)),
                (N'timezone', @o_tz, @timezone), (N'date_format', @o_df, @date_format),
                (N'week_start_day', @o_ws, @week_start_day),
                (N'fiscal_year_start_month', CONVERT(NVARCHAR(10), @o_fy), CONVERT(NVARCHAR(10), @fiscal_year_start_month))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_company_get] @company_id = @id, @actor_user_id = @actor_user_id, @id = @id;
END
