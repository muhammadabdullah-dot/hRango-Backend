-- Sign-in, sessions and the permission check.

-- The account behind an email address, for the password check (done in Python).
CREATE OR ALTER PROCEDURE [auth].[usp_login_get]
    @email NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, password_hash, is_active, company_id
    FROM [auth].[user_account]
    WHERE email = LTRIM(RTRIM(@email));
END
GO

-- Starts a session after a successful password check. Returns the session id.
CREATE OR ALTER PROCEDURE [auth].[usp_session_create]
    @user_id     BIGINT,
    @device      NVARCHAR(200) = NULL,
    @ip_address  NVARCHAR(45) = NULL,
    @expires_at  DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @company_id BIGINT = (SELECT company_id FROM [auth].[user_account] WHERE id = @user_id AND is_active = 1);
    IF @company_id IS NULL
        THROW 50403, N'This account is switched off.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @id BIGINT;
    BEGIN TRAN;
        INSERT [auth].[user_session] (user_account_id, company_id, device, ip_address, last_seen_at, expires_at, created_by)
        VALUES (@user_id, @company_id, @device, @ip_address, @now, @expires_at, @user_id);
        SET @id = SCOPE_IDENTITY();
    COMMIT;

    SELECT @id AS session_id, @company_id AS company_id;
END
GO

-- Who is calling. Returns no row when the session is ended, expired, or the account is off.
-- @company_id switches the active company for this request; it must be one the user may see.
CREATE OR ALTER PROCEDURE [auth].[usp_session_context]
    @session_id BIGINT,
    @user_id    BIGINT,
    @company_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @session_company BIGINT, @last_seen DATETIME2(0);

    SELECT @session_company = s.company_id, @last_seen = s.last_seen_at
    FROM [auth].[user_session] s
    JOIN [auth].[user_account] u ON u.id = s.user_account_id AND u.is_active = 1
    WHERE s.id = @session_id AND s.user_account_id = @user_id
      AND s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > @now);

    IF @session_company IS NULL
        RETURN;

    SET @company_id = ISNULL(@company_id, @session_company);
    IF @company_id <> @session_company
       AND NOT EXISTS (SELECT 1 FROM [auth].[user_company] WHERE user_account_id = @user_id AND company_id = @company_id)
       AND NOT EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @user_id AND is_system_admin = 1)
        THROW 50403, N'You do not have access to that company.', 1;

    -- Touch the session at most every five minutes, not on every request.
    IF @last_seen IS NULL OR @last_seen < DATEADD(MINUTE, -5, @now)
        UPDATE [auth].[user_session] SET last_seen_at = @now WHERE id = @session_id;

    SELECT u.id AS user_id, @company_id AS company_id, u.employee_id, u.is_system_admin, u.email,
           (SELECT c.name FROM [org].[company] c WHERE c.id = @company_id) AS company_name,
           (SELECT c.logo_file_id FROM [org].[company] c WHERE c.id = @company_id) AS company_logo_file_id,
           e.photo_file_id,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email) AS name,
           COALESCE(
               (SELECT TOP 1 r.name FROM [auth].[user_role] ur
                JOIN [auth].[role] r ON r.id = ur.role_id AND r.company_id = @company_id AND r.is_active = 1
                WHERE ur.user_account_id = u.id ORDER BY r.name),
               CASE WHEN u.is_system_admin = 1 THEN N'System Administrator' END,
               N'') AS role_name
    FROM [auth].[user_account] u
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE u.id = @user_id;
END
GO

CREATE OR ALTER PROCEDURE [auth].[usp_session_end]
    @session_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [auth].[user_session] SET revoked_at = SYSUTCDATETIME(), updated_at = SYSUTCDATETIME()
    WHERE id = @session_id AND revoked_at IS NULL;
END
GO

-- Whether a user holds one permission in a company, and with which scopes (comma separated).
CREATE OR ALTER PROCEDURE [auth].[usp_permission_check]
    @company_id BIGINT,
    @user_id    BIGINT,
    @code       NVARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS BIT) AS allowed,
           STRING_AGG(s.scope, N',') AS scopes
    FROM (SELECT DISTINCT scope FROM [auth].[fn_effective_grants](@company_id, @user_id) WHERE code = @code) s;
END
GO

-- Every permission a user holds in a company, for the frontend to hide what they cannot use.
CREATE OR ALTER PROCEDURE [auth].[usp_user_permission_list]
    @company_id BIGINT,
    @user_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT code, scope
    FROM [auth].[fn_effective_grants](@company_id, @user_id)
    ORDER BY code, scope;
END
GO

-- Creates the default roles in a company and offers them their permissions.
-- @roles: [{"code","name","description","grants":[{"code","scope"}]}], patterns already expanded.
-- A permission is offered to a role once (auth.role_default_offer); if the customer later removes
-- it, running this again does not put it back. New catalogue codes are offered on the next run.
CREATE OR ALTER PROCEDURE [auth].[usp_role_defaults_apply]
    @company_id BIGINT,
    @roles      NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @r TABLE (code NVARCHAR(30) PRIMARY KEY, name NVARCHAR(200), description NVARCHAR(MAX));
    INSERT @r SELECT code, name, description
    FROM OPENJSON(@roles) WITH (code NVARCHAR(30), name NVARCHAR(200), description NVARCHAR(MAX));

    DECLARE @g TABLE (role_code NVARCHAR(30), permission_code NVARCHAR(150), scope NVARCHAR(30));
    INSERT @g SELECT r.code, g.code, g.scope
    FROM OPENJSON(@roles) WITH (code NVARCHAR(30), grants NVARCHAR(MAX) AS JSON) r
    CROSS APPLY OPENJSON(r.grants) WITH (code NVARCHAR(150), scope NVARCHAR(30)) g;

    DECLARE @roles_added INT, @offered INT;
    BEGIN TRAN;
        INSERT [auth].[role] (company_id, code, name, description, is_system, is_active)
        SELECT @company_id, r.code, r.name, r.description, 1, 1
        FROM @r r
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[role] x WHERE x.company_id = @company_id AND x.code = r.code);
        SET @roles_added = @@ROWCOUNT;

        DECLARE @todo TABLE (role_id BIGINT, permission_id BIGINT, scope NVARCHAR(30), PRIMARY KEY (role_id, permission_id));
        INSERT @todo
        SELECT ro.id, p.id, MIN(g.scope)
        FROM @g g
        JOIN [auth].[role] ro ON ro.company_id = @company_id AND ro.code = g.role_code
        JOIN [auth].[permission] p ON p.code = g.permission_code
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[role_default_offer] o WHERE o.role_id = ro.id AND o.permission_id = p.id)
        GROUP BY ro.id, p.id;

        INSERT [auth].[role_permission] (role_id, permission_id, scope)
        SELECT t.role_id, t.permission_id, t.scope
        FROM @todo t
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[role_permission] rp WHERE rp.role_id = t.role_id AND rp.permission_id = t.permission_id);

        INSERT [auth].[role_default_offer] (role_id, permission_id)
        SELECT role_id, permission_id FROM @todo;
        SET @offered = @@ROWCOUNT;
    COMMIT;

    SELECT @roles_added AS roles_added, @offered AS permissions_offered;
END
GO

-- Creates or updates a sign-in account (installer and demo data; the Users screen gets its own
-- procedures). @role_codes: comma separated role codes in the home company.
CREATE OR ALTER PROCEDURE [auth].[usp_user_provision]
    @company_id      BIGINT,
    @email           NVARCHAR(254),
    @password_hash   NVARCHAR(255),
    @employee_id     BIGINT = NULL,
    @display_name    NVARCHAR(200) = NULL,
    @is_system_admin BIT = 0,
    @role_codes      NVARCHAR(500) = NULL,
    @company_ids     NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @email = LOWER(LTRIM(RTRIM(@email)));
    DECLARE @id BIGINT = (SELECT id FROM [auth].[user_account] WHERE email = @email);

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [auth].[user_account] (employee_id, company_id, display_name, email, password_hash, is_active, is_system_admin)
            VALUES (@employee_id, @company_id, @display_name, @email, @password_hash, 1, @is_system_admin);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
            UPDATE [auth].[user_account]
            SET employee_id = @employee_id, company_id = @company_id, display_name = @display_name,
                password_hash = @password_hash, is_active = 1, is_system_admin = @is_system_admin,
                updated_at = SYSUTCDATETIME()
            WHERE id = @id;

        INSERT [auth].[user_company] (user_account_id, company_id)
        SELECT @id, c.company_id
        FROM (SELECT @company_id AS company_id
              UNION SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@company_ids, N''), N',') WHERE value <> N'') c
        WHERE c.company_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM [auth].[user_company] x WHERE x.user_account_id = @id AND x.company_id = c.company_id);

        INSERT [auth].[user_role] (user_account_id, role_id)
        SELECT @id, r.id
        FROM STRING_SPLIT(ISNULL(@role_codes, N''), N',') s
        JOIN [auth].[role] r ON r.company_id = @company_id AND r.code = LTRIM(RTRIM(s.value))
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[user_role] x WHERE x.user_account_id = @id AND x.role_id = r.id);
    COMMIT;

    SELECT @id AS user_id;
END
