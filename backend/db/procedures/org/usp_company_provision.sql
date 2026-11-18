-- Creates a company with its defaults (registration, sign-up, installer and tests). Returns its id.
-- @reuse = 1 (the installer's --bootstrap only, so running it twice is harmless) returns an existing
-- company of that name instead. Names are unique per organisation, not platform-wide, so nothing else
-- may look a company up by name: a registration would join somebody else's company.
CREATE OR ALTER PROCEDURE [org].[usp_company_provision]
    @name     NVARCHAR(200),
    @currency CHAR(3) = 'PKR',
    @timezone NVARCHAR(64) = N'Asia/Karachi',
    @reuse    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Company name is required.', 1;

    DECLARE @id BIGINT = CASE WHEN @reuse = 1 THEN (SELECT TOP 1 id FROM [org].[company] WHERE name = @name ORDER BY id) END;
    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[company] (name, currency, timezone, date_format, week_start_day, fiscal_year_start_month, is_active)
            VALUES (@name, @currency, @timezone, N'dd/MM/yyyy', N'monday', 7, 1);
            SET @id = SCOPE_IDENTITY();
            EXEC [org].[usp_company_defaults_apply] @company_id = @id;
        COMMIT;
    END

    SELECT @id AS company_id;
END
