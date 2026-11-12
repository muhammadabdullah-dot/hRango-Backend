-- Platform staff: hRango's own people (Super Admin, Admin, Support, Billing, Sales). Separate accounts and sessions from
-- customers' auth.user_account: nothing here reads or reaches a company. Every change lands in plat.staff_audit.

CREATE OR ALTER PROCEDURE [plat].[usp_staff_login_get]
    @email NVARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, email, display_name, password_hash, role, is_active
    FROM [plat].[staff_account] WHERE email = @email;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_staff_audit_add]
    @staff_id    BIGINT = NULL,
    @action      NVARCHAR(50),
    @entity_type NVARCHAR(50) = NULL,
    @entity_ref  NVARCHAR(100) = NULL,
    @detail      NVARCHAR(1000) = NULL,
    @ip_address  NVARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT [plat].[staff_audit] (staff_account_id, action_name, entity_type, entity_ref, detail, ip_address)
    VALUES (@staff_id, @action, @entity_type, @entity_ref, @detail, @ip_address);
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_staff_session_create]
    @staff_id   BIGINT,
    @device     NVARCHAR(200) = NULL,
    @ip_address NVARCHAR(45) = NULL,
    @expires_at DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @id BIGINT;
    BEGIN TRAN;
        INSERT [plat].[staff_session] (staff_account_id, device, ip_address, expires_at, last_seen_at)
        VALUES (@staff_id, @device, @ip_address, @expires_at, @now);
        SET @id = SCOPE_IDENTITY();
        UPDATE [plat].[staff_account] SET last_login_at = @now WHERE id = @staff_id;
        EXEC [plat].[usp_staff_audit_add] @staff_id = @staff_id, @action = N'signed_in', @ip_address = @ip_address;
    COMMIT;
    SELECT @id AS session_id;
END
GO

-- The caller of a token: no row when the session ended, expired or the account is off.
CREATE OR ALTER PROCEDURE [plat].[usp_staff_session_context]
    @session_id BIGINT,
    @staff_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    UPDATE [plat].[staff_session] SET last_seen_at = @now
    WHERE id = @session_id AND staff_account_id = @staff_id AND revoked_at IS NULL
      AND (last_seen_at IS NULL OR last_seen_at < DATEADD(MINUTE, -5, @now));

    SELECT a.id AS staff_id, a.email, a.display_name, a.role
    FROM [plat].[staff_session] s
    JOIN [plat].[staff_account] a ON a.id = s.staff_account_id AND a.is_active = 1
    WHERE s.id = @session_id AND s.staff_account_id = @staff_id AND s.revoked_at IS NULL
      AND (s.expires_at IS NULL OR s.expires_at > @now);
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_staff_session_end]
    @session_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [plat].[staff_session] SET revoked_at = SYSUTCDATETIME(), updated_at = SYSUTCDATETIME()
    WHERE id = @session_id AND revoked_at IS NULL;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_staff_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, email, display_name, role, is_active, last_login_at, created_at, updated_at, row_version
    FROM [plat].[staff_account] WHERE id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Staff member not found', 1;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [plat].[usp_staff_list]
    @search    NVARCHAR(200) = NULL,
    @page      INT = 1,
    @page_size INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [plat].[staff_account]
    WHERE @pattern IS NULL OR display_name LIKE @pattern OR email LIKE @pattern;

    SELECT id, email, display_name, role, is_active, last_login_at, created_at, updated_at, row_version
    FROM [plat].[staff_account]
    WHERE @pattern IS NULL OR display_name LIKE @pattern OR email LIKE @pattern
    ORDER BY display_name, id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Add when @id is NULL (needs @password_hash), else edit. The last active Super Admin stays one, and
-- nobody changes their own role or switches themselves off, so the platform can't be locked out.
CREATE OR ALTER PROCEDURE [plat].[usp_staff_save]
    @actor_id      BIGINT,
    @id            BIGINT = NULL,
    @email         NVARCHAR(254),
    @display_name  NVARCHAR(200),
    @role          NVARCHAR(30),
    @is_active     BIT = 1,
    @password_hash NVARCHAR(255) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @email = LOWER(NULLIF(LTRIM(RTRIM(@email)), N''));
    SET @display_name = NULLIF(LTRIM(RTRIM(@display_name)), N'');
    IF @email IS NULL OR @email NOT LIKE N'%_@_%._%'
        THROW 50400, N'email|Enter a valid email address.', 1;
    IF @display_name IS NULL
        THROW 50400, N'displayName|Enter a name.', 1;
    IF @role NOT IN (N'super_admin', N'admin', N'support', N'billing', N'sales')
        THROW 50400, N'role|Choose super_admin, admin, support, billing or sales.', 1;
    IF EXISTS (SELECT 1 FROM [plat].[staff_account] WHERE email = @email AND (@id IS NULL OR id <> @id))
        THROW 50409, N'email|STAFF_EMAIL_DUPLICATE|Another staff member signs in with this email.', 1;

    DECLARE @old_role NVARCHAR(30), @old_active BIT, @old_rv BINARY(8);
    IF @id IS NULL
    BEGIN
        IF @password_hash IS NULL
            THROW 50400, N'password|A password is required for a new staff member.', 1;
    END
    ELSE
    BEGIN
        SELECT @old_role = role, @old_active = is_active, @old_rv = row_version
        FROM [plat].[staff_account] WHERE id = @id;
        IF @old_rv IS NULL
            THROW 50404, N'Staff member not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a staff member.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this staff member. Reload and try again', 1;
        IF @id = @actor_id AND (@role <> @old_role OR @is_active = 0)
            THROW 50403, N'role|You cannot change your own role or switch yourself off.', 1;
        IF @old_role = N'super_admin' AND @old_active = 1 AND (@role <> N'super_admin' OR @is_active = 0)
           AND NOT EXISTS (SELECT 1 FROM [plat].[staff_account]
                           WHERE id <> @id AND role = N'super_admin' AND is_active = 1)
            THROW 50409, N'role|LAST_SUPER_ADMIN|The platform needs at least one active Super Admin.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @action NVARCHAR(50);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [plat].[staff_account] (email, display_name, password_hash, role, is_active, created_by)
            VALUES (@email, @display_name, @password_hash, @role, ISNULL(@is_active, 1), @actor_id);
            SET @id = SCOPE_IDENTITY();
            SET @action = N'staff_added';
        END
        ELSE
        BEGIN
            UPDATE [plat].[staff_account]
            SET email = @email, display_name = @display_name, role = @role, is_active = @is_active,
                updated_at = @now, updated_by = @actor_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this staff member. Reload and try again', 1;
            IF @is_active = 0
                UPDATE [plat].[staff_session] SET revoked_at = @now, updated_at = @now
                WHERE staff_account_id = @id AND revoked_at IS NULL;
            SET @action = N'staff_changed';
        END
        DECLARE @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action, @entity_type = N'staff_account',
             @entity_ref = @ref, @detail = @role;
    COMMIT;

    EXEC [plat].[usp_staff_get] @id = @id;
END
GO

-- Sets a new password and signs that person out everywhere.
CREATE OR ALTER PROCEDURE [plat].[usp_staff_password_set]
    @actor_id      BIGINT,
    @id            BIGINT,
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [plat].[staff_account] WHERE id = @id)
        THROW 50404, N'Staff member not found', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id);
    BEGIN TRAN;
        UPDATE [plat].[staff_account] SET password_hash = @password_hash, updated_at = @now, updated_by = @actor_id
        WHERE id = @id;
        UPDATE [plat].[staff_session] SET revoked_at = @now, updated_at = @now
        WHERE staff_account_id = @id AND revoked_at IS NULL;
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = N'staff_password_set',
             @entity_type = N'staff_account', @entity_ref = @ref;
    COMMIT;
END
GO

-- Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [plat].[usp_staff_audit_list]
    @page      INT = 1,
    @page_size INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS total FROM [plat].[staff_audit];

    SELECT l.id, l.action_name, l.entity_type, l.entity_ref, l.detail, l.ip_address, l.created_at,
           l.staff_account_id AS staff_id, a.display_name AS staff_name
    FROM [plat].[staff_audit] l
    LEFT JOIN [plat].[staff_account] a ON a.id = l.staff_account_id
    ORDER BY l.created_at DESC, l.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO
