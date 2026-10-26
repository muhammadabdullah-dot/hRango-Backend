-- Users screen (Mini SRS 3.1): sign-in accounts of the active company, their companies and roles.
-- ACC-11: nobody grants what they do not hold, changes their own roles or switches themselves off;
-- only a system administrator makes, changes or switches off another system administrator.
-- ACC-15: every change to a user's roles is written to core.audit_log (entity auth.user_account).

CREATE OR ALTER PROCEDURE [auth].[usp_access_user_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_access_company_users](@company_id) WHERE id = @id)
        THROW 50404, N'User not found', 1;

    SELECT u.id, u.email, u.display_name,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email) AS name,
           u.employee_id, e.code AS employee_code, u.company_id AS home_company_id, hc.name AS home_company_name,
           u.is_active, u.is_system_admin, (SELECT MAX(s.created_at) FROM [auth].[user_session] s WHERE s.user_account_id = u.id) AS last_login_at,
           (SELECT STRING_AGG(r.name, N', ') FROM [auth].[user_role] ur
            JOIN [auth].[role] r ON r.id = ur.role_id AND r.company_id = @company_id
            WHERE ur.user_account_id = u.id) AS role_names,
           u.created_at, u.updated_at, u.row_version
    FROM [auth].[user_account] u
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    LEFT JOIN [org].[company] hc ON hc.id = u.company_id
    WHERE u.id = @id;

    -- Roles in the active company.
    SELECT r.id, r.code, r.name, r.is_active
    FROM [auth].[user_role] ur
    JOIN [auth].[role] r ON r.id = ur.role_id AND r.company_id = @company_id
    WHERE ur.user_account_id = @id
    ORDER BY r.name;

    -- Companies the user may switch to (home company first).
    SELECT c.id, c.name
    FROM [org].[company] c
    WHERE c.id = (SELECT company_id FROM [auth].[user_account] WHERE id = @id)
       OR EXISTS (SELECT 1 FROM [auth].[user_company] uc WHERE uc.user_account_id = @id AND uc.company_id = c.id)
    ORDER BY CASE WHEN c.id = (SELECT company_id FROM [auth].[user_account] WHERE id = @id) THEN 0 ELSE 1 END, c.name;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [auth].[usp_access_user_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @role_id    BIGINT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT u.id
    FROM [auth].[user_account] u
    JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = u.id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE (@pattern IS NULL OR u.email LIKE @pattern OR u.display_name LIKE @pattern
           OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@is_active IS NULL OR u.is_active = @is_active)
      AND (@role_id IS NULL OR EXISTS (SELECT 1 FROM [auth].[user_role] ur WHERE ur.user_account_id = u.id AND ur.role_id = @role_id))
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM @ids;

    SELECT u.id, u.email, u.display_name,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email) AS name,
           u.employee_id, e.code AS employee_code, u.company_id AS home_company_id, hc.name AS home_company_name,
           u.is_active, u.is_system_admin, (SELECT MAX(s.created_at) FROM [auth].[user_session] s WHERE s.user_account_id = u.id) AS last_login_at,
           (SELECT STRING_AGG(r.name, N', ') FROM [auth].[user_role] ur
            JOIN [auth].[role] r ON r.id = ur.role_id AND r.company_id = @company_id
            WHERE ur.user_account_id = u.id) AS role_names,
           u.created_at, u.updated_at, u.row_version
    FROM @ids i
    JOIN [auth].[user_account] u ON u.id = i.id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    LEFT JOIN [org].[company] hc ON hc.id = u.company_id
    ORDER BY COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), u.display_name, u.email), u.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a user (@id NULL; home company = the active company, @password_hash required) or edits one.
-- @company_ids: JSON array of extra companies; only companies the actor may see are added or
-- removed. NULL leaves them as they are. @role_ids (new users only): JSON array of role ids in the
-- active company, checked like auth.usp_access_user_roles_set.
CREATE OR ALTER PROCEDURE [auth].[usp_access_user_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT = NULL,
    @email           NVARCHAR(254),
    @display_name    NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @password_hash   NVARCHAR(255) = NULL,
    @is_active       BIT = 1,
    @is_system_admin BIT = 0,
    @company_ids     NVARCHAR(MAX) = NULL,
    @role_ids        NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @email = LOWER(NULLIF(LTRIM(RTRIM(@email)), N''));
    SET @display_name = NULLIF(LTRIM(RTRIM(@display_name)), N'');
    DECLARE @actor_admin BIT = ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    DECLARE @old_email NVARCHAR(254), @old_display NVARCHAR(200), @old_employee BIGINT, @old_active BIT, @old_admin BIT,
            @old_rv BINARY(8);

    IF @id IS NOT NULL
    BEGIN
        SELECT @old_email = u.email, @old_display = u.display_name, @old_employee = u.employee_id,
               @old_active = u.is_active, @old_admin = u.is_system_admin, @old_rv = u.row_version
        FROM [auth].[user_account] u
        JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = u.id
        WHERE u.id = @id;

        IF @old_rv IS NULL
            THROW 50404, N'User not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a user.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this user. Reload it and try again', 1;
        IF @old_admin = 1 AND @actor_admin = 0
            THROW 50403, N'Only a system administrator can change a system administrator.', 1;
        IF @id = @actor_user_id AND @is_active = 0
            THROW 50403, N'isActive|You cannot switch off your own account.', 1;
        IF @id = @actor_user_id AND @is_system_admin <> @old_admin
            THROW 50403, N'isSystemAdmin|You cannot change your own administrator rights.', 1;
    END
    ELSE IF @password_hash IS NULL
        THROW 50400, N'password|A password is required for a new user.', 1;

    IF @email IS NULL OR @email NOT LIKE N'%_@_%._%'
        THROW 50400, N'email|Enter a valid email address.', 1;
    IF @is_system_admin = 1 AND @actor_admin = 0 AND (@id IS NULL OR @old_admin = 0)
        THROW 50403, N'isSystemAdmin|Only a system administrator can make another one.', 1;
    IF EXISTS (SELECT 1 FROM [auth].[user_account] WHERE email = @email AND (@id IS NULL OR id <> @id))
        THROW 50409, N'email|USER_EMAIL_DUPLICATE|Another user signs in with this email.', 1;
    IF @employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @employee_id IS NOT NULL AND EXISTS (SELECT 1 FROM [auth].[user_account] WHERE employee_id = @employee_id AND (@id IS NULL OR id <> @id))
        THROW 50409, N'employeeId|USER_EMPLOYEE_TAKEN|This employee already has a sign-in account.', 1;
    IF @employee_id IS NULL AND @display_name IS NULL
        THROW 50400, N'displayName|Give a name, or link the user to an employee.', 1;

    -- Companies the actor may hand out.
    DECLARE @actor_home BIGINT = (SELECT company_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @mine TABLE (id BIGINT PRIMARY KEY);
    INSERT @mine SELECT c.id FROM [org].[company] c
    WHERE @actor_admin = 1 OR c.id = @company_id OR c.id = @actor_home
       OR EXISTS (SELECT 1 FROM [auth].[user_company] uc WHERE uc.user_account_id = @actor_user_id AND uc.company_id = c.id);

    DECLARE @wanted TABLE (id BIGINT PRIMARY KEY);
    IF @company_ids IS NOT NULL
    BEGIN
        IF ISJSON(@company_ids) = 0
            THROW 50400, N'companyIds|Not a list of companies.', 1;
        INSERT @wanted SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@company_ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
        IF EXISTS (SELECT 1 FROM @wanted w WHERE NOT EXISTS (SELECT 1 FROM @mine m WHERE m.id = w.id))
            THROW 50403, N'companyIds|You can only give access to companies you can reach yourself.', 1;
    END

    DECLARE @roles TABLE (id BIGINT PRIMARY KEY);
    IF @id IS NULL AND @role_ids IS NOT NULL
    BEGIN
        IF ISJSON(@role_ids) = 0
            THROW 50400, N'roleIds|Not a list of roles.', 1;
        INSERT @roles SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@role_ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
        IF EXISTS (SELECT 1 FROM @roles r WHERE NOT EXISTS (SELECT 1 FROM [auth].[role] x WHERE x.id = r.id AND x.company_id = @company_id AND x.is_active = 1))
            THROW 50400, N'roleIds|A role was not found or is retired.', 1;
        IF @actor_admin = 0 AND EXISTS (
            SELECT 1 FROM @roles r
            JOIN [auth].[role_permission] rp ON rp.role_id = r.id
            WHERE NOT EXISTS (SELECT 1 FROM [auth].[fn_access_held](@company_id, @actor_user_id) h
                              WHERE h.permission_id = rp.permission_id
                                AND h.max_rank >= CASE rp.scope WHEN N'company' THEN 4 WHEN N'department' THEN 3 WHEN N'branch' THEN 3
                                                                WHEN N'selected_units' THEN 3 WHEN N'team' THEN 2 ELSE 1 END))
            THROW 50403, N'roleIds|ROLE_EXCEEDS_YOUR_ACCESS|A chosen role holds access you do not hold yourself.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [auth].[user_account] (employee_id, company_id, display_name, email, password_hash, is_active, is_system_admin, created_by)
        VALUES (@employee_id, @company_id, @display_name, @email, @password_hash, ISNULL(@is_active, 1), ISNULL(@is_system_admin, 0), @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        INSERT [auth].[user_company] (user_account_id, company_id, created_by)
        SELECT @id, c.id, @actor_user_id FROM (SELECT @company_id AS id UNION SELECT id FROM @wanted) c;

        INSERT [auth].[user_role] (user_account_id, role_id, created_by)
        SELECT @id, r.id, @actor_user_id FROM @roles r;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'auth.user_account', @id, NULL, @email, N'create', @actor_user_id, @now
        UNION ALL
        SELECT @company_id, N'auth.user_account', @id, N'role', r.name, N'role_added', @actor_user_id, @now
        FROM @roles x JOIN [auth].[role] r ON r.id = x.id;
    END
    ELSE
    BEGIN
        UPDATE [auth].[user_account]
        SET email = @email, display_name = @display_name, employee_id = @employee_id, is_active = @is_active,
            is_system_admin = @is_system_admin, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this user. Reload it and try again', 1;

        IF @is_active = 0 AND @old_active = 1
            UPDATE [auth].[user_session] SET revoked_at = @now, updated_at = @now WHERE user_account_id = @id AND revoked_at IS NULL;

        DECLARE @old_companies NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(30), company_id), N',') WITHIN GROUP (ORDER BY company_id)
                                                FROM [auth].[user_company] WHERE user_account_id = @id);
        IF @company_ids IS NOT NULL
        BEGIN
            -- Within the companies the actor can reach: add the wanted ones, remove the others.
            -- The home company always stays.
            DELETE uc FROM [auth].[user_company] uc
            WHERE uc.user_account_id = @id
              AND uc.company_id IN (SELECT id FROM @mine)
              AND uc.company_id NOT IN (SELECT id FROM @wanted)
              AND uc.company_id <> (SELECT company_id FROM [auth].[user_account] WHERE id = @id);
            INSERT [auth].[user_company] (user_account_id, company_id, created_by)
            SELECT @id, w.id, @actor_user_id FROM @wanted w
            WHERE NOT EXISTS (SELECT 1 FROM [auth].[user_company] x WHERE x.user_account_id = @id AND x.company_id = w.id);
        END
        DECLARE @new_companies NVARCHAR(MAX) = (SELECT STRING_AGG(CONVERT(NVARCHAR(30), company_id), N',') WITHIN GROUP (ORDER BY company_id)
                                                FROM [auth].[user_company] WHERE user_account_id = @id);

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'auth.user_account', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
        FROM (VALUES
            (N'email', @old_email, @email), (N'display_name', @old_display, @display_name),
            (N'employee_id', CONVERT(NVARCHAR(30), @old_employee), CONVERT(NVARCHAR(30), @employee_id)),
            (N'is_active', CONVERT(NVARCHAR(5), @old_active), CONVERT(NVARCHAR(5), @is_active)),
            (N'is_system_admin', CONVERT(NVARCHAR(5), @old_admin), CONVERT(NVARCHAR(5), @is_system_admin)),
            (N'companies', @old_companies, @new_companies)
        ) f (field_name, old_value, new_value)
        WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
    END
    COMMIT;

    EXEC [auth].[usp_access_user_get] @company_id = @company_id, @id = @id;
END
GO

-- Gives a user exactly these roles in the active company (@role_ids: JSON array of ids).
-- Refused for the actor's own account, and for a role holding access the actor does not hold.
CREATE OR ALTER PROCEDURE [auth].[usp_access_user_roles_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @role_ids      NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_admin BIT = ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    DECLARE @rv BINARY(8), @target_admin BIT;
    SELECT @rv = u.row_version, @target_admin = u.is_system_admin
    FROM [auth].[user_account] u JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = u.id
    WHERE u.id = @id;

    IF @rv IS NULL
        THROW 50404, N'User not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this user. Reload it and try again', 1;
    IF @id = @actor_user_id
        THROW 50403, N'You cannot change your own roles.', 1;
    IF @target_admin = 1 AND @actor_admin = 0
        THROW 50403, N'Only a system administrator can change a system administrator.', 1;
    IF ISJSON(@role_ids) = 0
        THROW 50400, N'roleIds|Not a list of roles.', 1;

    DECLARE @wanted TABLE (id BIGINT PRIMARY KEY);
    INSERT @wanted SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@role_ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @wanted w WHERE NOT EXISTS (SELECT 1 FROM [auth].[role] r WHERE r.id = w.id AND r.company_id = @company_id))
        THROW 50400, N'roleIds|A role was not found.', 1;

    DECLARE @added TABLE (id BIGINT PRIMARY KEY);
    INSERT @added SELECT w.id FROM @wanted w
    WHERE NOT EXISTS (SELECT 1 FROM [auth].[user_role] ur WHERE ur.user_account_id = @id AND ur.role_id = w.id);
    IF EXISTS (SELECT 1 FROM @added a JOIN [auth].[role] r ON r.id = a.id WHERE r.is_active = 0)
        THROW 50400, N'roleIds|A retired role cannot be given.', 1;
    IF @actor_admin = 0 AND EXISTS (
        SELECT 1 FROM @added a
        JOIN [auth].[role_permission] rp ON rp.role_id = a.id
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[fn_access_held](@company_id, @actor_user_id) h
                          WHERE h.permission_id = rp.permission_id
                            AND h.max_rank >= CASE rp.scope WHEN N'company' THEN 4 WHEN N'department' THEN 3 WHEN N'branch' THEN 3
                                                            WHEN N'selected_units' THEN 3 WHEN N'team' THEN 2 ELSE 1 END))
        THROW 50403, N'roleIds|ROLE_EXCEEDS_YOUR_ACCESS|A chosen role holds access you do not hold yourself.', 1;

    DECLARE @removed TABLE (id BIGINT PRIMARY KEY);
    INSERT @removed SELECT ur.role_id FROM [auth].[user_role] ur
    JOIN [auth].[role] r ON r.id = ur.role_id AND r.company_id = @company_id
    WHERE ur.user_account_id = @id AND ur.role_id NOT IN (SELECT id FROM @wanted);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE ur FROM [auth].[user_role] ur WHERE ur.user_account_id = @id AND ur.role_id IN (SELECT id FROM @removed);
        INSERT [auth].[user_role] (user_account_id, role_id, created_by) SELECT @id, id, @actor_user_id FROM @added;
        UPDATE [auth].[user_account] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'auth.user_account', @id, N'role', NULL, r.name, N'role_added', @actor_user_id, @now
        FROM @added a JOIN [auth].[role] r ON r.id = a.id
        UNION ALL
        SELECT @company_id, N'auth.user_account', @id, N'role', r.name, NULL, N'role_removed', @actor_user_id, @now
        FROM @removed x JOIN [auth].[role] r ON r.id = x.id;
    COMMIT;

    EXEC [auth].[usp_access_user_get] @company_id = @company_id, @id = @id;
END
GO

-- Sets another user's password (the service hashes it) and signs them out everywhere.
CREATE OR ALTER PROCEDURE [auth].[usp_access_user_password_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_admin BIT = ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    DECLARE @target_admin BIT = (SELECT u.is_system_admin FROM [auth].[user_account] u
                                 JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = u.id WHERE u.id = @id);
    IF @target_admin IS NULL
        THROW 50404, N'User not found', 1;
    IF @target_admin = 1 AND @actor_admin = 0
        THROW 50403, N'Only a system administrator can change a system administrator.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [auth].[user_account] SET password_hash = @password_hash, updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
        UPDATE [auth].[user_session] SET revoked_at = @now, updated_at = @now WHERE user_account_id = @id AND revoked_at IS NULL;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @id, N'password', N'password_reset', @actor_user_id, @now);
    COMMIT;
END
GO

-- The signed-in user's own password hash, for the "current password" check.
CREATE OR ALTER PROCEDURE [auth].[usp_access_password_get]
    @user_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT password_hash FROM [auth].[user_account] WHERE id = @user_id AND is_active = 1;
END
GO

-- The signed-in user changes their own password; their other sessions end.
CREATE OR ALTER PROCEDURE [auth].[usp_access_password_change]
    @company_id    BIGINT,
    @user_id       BIGINT,
    @session_id    BIGINT,
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [auth].[user_account] SET password_hash = @password_hash, updated_at = @now, updated_by = @user_id WHERE id = @user_id;
        UPDATE [auth].[user_session] SET revoked_at = @now, updated_at = @now
        WHERE user_account_id = @user_id AND revoked_at IS NULL AND id <> @session_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @user_id, N'password', N'password_change', @user_id, @now);
    COMMIT;
END
GO

-- Everything a user holds in the active company (roles + grants - denials), for the Users screen.
CREATE OR ALTER PROCEDURE [auth].[usp_access_user_effective_list]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_access_company_users](@company_id) WHERE id = @id)
        THROW 50404, N'User not found', 1;

    SELECT g.code, p.module, p.label, p.is_sensitive,
           STRING_AGG(g.scope, N',') AS scopes,
           STRING_AGG(COALESCE(r.name, CASE WHEN g.role_id IS NULL THEN N'grant' END), N', ') AS sources
    FROM (SELECT DISTINCT permission_id, code, scope, role_id FROM [auth].[fn_effective_grants](@company_id, @id)) g
    JOIN [auth].[permission] p ON p.id = g.permission_id
    LEFT JOIN [auth].[role] r ON r.id = g.role_id
    GROUP BY g.code, p.module, p.label, p.is_sensitive, p.sort_order
    ORDER BY p.sort_order;
END
GO

-- After a user creates a company: they get its Company Administrator role, so they can set it up.
CREATE OR ALTER PROCEDURE [auth].[usp_access_company_creator_grant]
    @company_id BIGINT,
    @user_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @role_id BIGINT, @role_name NVARCHAR(200);
    SELECT @role_id = r.id, @role_name = r.name FROM [auth].[role] r WHERE r.company_id = @company_id AND r.code = N'company_admin';

    IF @role_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [auth].[user_role] WHERE user_account_id = @user_id AND role_id = @role_id)
    BEGIN
        INSERT [auth].[user_role] (user_account_id, role_id, created_by) VALUES (@user_id, @role_id, @user_id);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @user_id, N'role', @role_name, N'role_added', @user_id, SYSUTCDATETIME());
    END
END
