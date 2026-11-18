-- One-time e-mail links (auth.user_token): password reset and invitations. The API makes the token and
-- passes only its SHA-256 (@token_hash); the plain token exists only in the e-mail.

-- "Forgot password": a reset link for an active account whose organisation is active. Returns nothing
-- for an unknown, switched-off or suspended account, so the caller answers the same either way.
CREATE OR ALTER PROCEDURE [auth].[usp_password_reset_request]
    @email      NVARCHAR(254),
    @token_hash CHAR(64),
    @minutes    INT = 60
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @user_id BIGINT, @company_id BIGINT;
    SELECT @user_id = u.id, @company_id = u.company_id
    FROM [auth].[user_account] u
    WHERE u.email = LOWER(LTRIM(RTRIM(@email))) AND u.is_active = 1 AND [plat].[fn_company_blocked](u.company_id) = 0;
    IF @user_id IS NULL
        RETURN;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        -- Only the newest link works.
        UPDATE [auth].[user_token] SET used_at = @now, updated_at = @now
        WHERE user_account_id = @user_id AND purpose = N'password_reset' AND used_at IS NULL;
        INSERT [auth].[user_token] (user_account_id, purpose, token_hash, expires_at, created_by)
        VALUES (@user_id, N'password_reset', @token_hash, DATEADD(MINUTE, @minutes, @now), @user_id);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @user_id, N'password', N'password_reset_requested', @user_id, @now);
    COMMIT;

    SELECT u.id AS user_id, u.email, u.company_id, c.name AS company_name,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email) AS name
    FROM [auth].[user_account] u
    JOIN [org].[company] c ON c.id = u.company_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE u.id = @user_id;
END
GO

-- An invitation to set a first password, sent by an administrator of the user's home company who may
-- change that account (the same rules as a password reset by an administrator).
CREATE OR ALTER PROCEDURE [auth].[usp_invite_create]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @token_hash    CHAR(64),
    @days          INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_access_company_users](@company_id) cu WHERE cu.id = @id)
        THROW 50404, N'User not found', 1;
    IF EXISTS (SELECT 1 FROM [auth].[fn_access_outranks](@company_id, @id, @actor_user_id))
        THROW 50403, N'user|ACCOUNT_PROTECTED|This account holds access you do not hold yourself, or belongs to an administrator or the Account Owner.', 1;
    IF EXISTS (SELECT 1 FROM [auth].[fn_access_not_home](@company_id, @id))
        THROW 50403, N'user|ACCOUNT_HOME_ONLY|Only an administrator of this user''s home company can invite them.', 1;
    IF NOT EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @id AND is_active = 1)
        THROW 50400, N'user|Switch the account on before inviting.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [auth].[user_token] SET used_at = @now, updated_at = @now
        WHERE user_account_id = @id AND purpose = N'invite' AND used_at IS NULL;
        INSERT [auth].[user_token] (user_account_id, purpose, token_hash, expires_at, created_by)
        VALUES (@id, N'invite', @token_hash, DATEADD(DAY, @days, @now), @actor_user_id);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @id, N'password', N'invited', @actor_user_id, @now);
    COMMIT;

    SELECT u.id AS user_id, u.email, u.company_id, c.name AS company_name,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email) AS name,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ae.first_name, N' ', ae.last_name))), N''), a.display_name, a.email) AS invited_by
    FROM [auth].[user_account] u
    JOIN [org].[company] c ON c.id = @company_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    LEFT JOIN [auth].[user_account] a ON a.id = @actor_user_id
    LEFT JOIN [hr].[employee] ae ON ae.id = a.employee_id
    WHERE u.id = @id;
END
GO

-- A link for an account the system itself set up (self-service sign-up's Account Owner). No actor checks:
-- the caller has just created the account in the same transaction.
CREATE OR ALTER PROCEDURE [auth].[usp_user_token_issue]
    @user_id    BIGINT,
    @purpose    NVARCHAR(30),
    @token_hash CHAR(64),
    @minutes    INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    UPDATE [auth].[user_token] SET used_at = @now, updated_at = @now
    WHERE user_account_id = @user_id AND purpose = @purpose AND used_at IS NULL;
    INSERT [auth].[user_token] (user_account_id, purpose, token_hash, expires_at, created_by)
    VALUES (@user_id, @purpose, @token_hash, DATEADD(MINUTE, @minutes, @now), @user_id);
END
GO

-- What a link is for, without using it (the reset and invitation pages show whose account it is).
-- state: ok, used, expired or not_found.
CREATE OR ALTER PROCEDURE [auth].[usp_user_token_inspect]
    @token_hash CHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CASE WHEN t.used_at IS NOT NULL THEN N'used'
                WHEN t.expires_at <= SYSUTCDATETIME() THEN N'expired'
                WHEN u.is_active = 0 OR [plat].[fn_company_blocked](u.company_id) = 1 THEN N'not_found'
                ELSE N'ok' END AS state,
           t.purpose, u.email, t.expires_at, c.name AS company_name
    FROM [auth].[user_token] t
    JOIN [auth].[user_account] u ON u.id = t.user_account_id
    JOIN [org].[company] c ON c.id = u.company_id
    WHERE t.token_hash = @token_hash;
END
GO

-- Uses a link: sets the password, spends the link and ends every open session of the account (a reset
-- after a stolen password throws the thief out). Returns the state and, when ok, the account's email.
CREATE OR ALTER PROCEDURE [auth].[usp_user_token_use]
    @token_hash    CHAR(64),
    @purpose       NVARCHAR(30),
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @token_id BIGINT, @user_id BIGINT, @state NVARCHAR(20);
    BEGIN TRAN;
        SELECT @token_id = t.id, @user_id = t.user_account_id,
               @state = CASE WHEN t.used_at IS NOT NULL THEN N'used'
                             WHEN t.expires_at <= @now THEN N'expired'
                             WHEN u.is_active = 0 OR [plat].[fn_company_blocked](u.company_id) = 1 THEN N'not_found'
                             ELSE N'ok' END
        FROM [auth].[user_token] t WITH (UPDLOCK, HOLDLOCK)
        JOIN [auth].[user_account] u ON u.id = t.user_account_id
        WHERE t.token_hash = @token_hash AND t.purpose = @purpose;

        IF @token_id IS NULL
            SET @state = N'not_found';
        IF @state = N'ok'
        BEGIN
            UPDATE [auth].[user_token] SET used_at = @now, updated_at = @now WHERE id = @token_id;
            UPDATE [auth].[user_account] SET password_hash = @password_hash, updated_at = @now, updated_by = @user_id
            WHERE id = @user_id;
            UPDATE [auth].[user_session] SET revoked_at = @now, updated_at = @now
            WHERE user_account_id = @user_id AND revoked_at IS NULL;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
            SELECT company_id, N'auth.user_account', @user_id, N'password',
                   CASE @purpose WHEN N'invite' THEN N'invite_accepted' ELSE N'password_reset_by_link' END, @user_id, @now
            FROM [auth].[user_account] WHERE id = @user_id;
        END
    COMMIT;
    SELECT @state AS state, (SELECT email FROM [auth].[user_account] WHERE id = @user_id AND @state = N'ok') AS email;
END
GO
