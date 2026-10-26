-- Roles screen (Mini SRS 3.1, ACC-5 to ACC-8, ACC-11, ACC-15): each company creates, renames,
-- copies and retires its own roles and ticks their permissions, each with a scope (and the units
-- for selected_units). Every change is written to core.audit_log (entity auth.role).

CREATE OR ALTER PROCEDURE [auth].[usp_access_role_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[role] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Role not found', 1;

    SELECT r.id, r.code, r.name, r.description, r.is_system, r.is_active,
           (SELECT COUNT(*) FROM [auth].[role_permission] rp WHERE rp.role_id = r.id) AS permission_count,
           (SELECT COUNT(*) FROM [auth].[user_role] ur WHERE ur.role_id = r.id) AS user_count,
           r.created_at, r.updated_at, r.row_version
    FROM [auth].[role] r
    WHERE r.id = @id AND r.company_id = @company_id;

    SELECT p.id AS permission_id, p.code, p.module, p.screen, p.action_code, p.label, p.is_sensitive, rp.scope
    FROM [auth].[role_permission] rp
    JOIN [auth].[permission] p ON p.id = rp.permission_id
    WHERE rp.role_id = @id
    ORDER BY p.sort_order;

    SELECT p.code, u.unit_type, u.unit_id,
           COALESCE(b.name, d.name, l.name) AS unit_name
    FROM [auth].[role_permission_unit] u
    JOIN [auth].[permission] p ON p.id = u.permission_id
    LEFT JOIN [org].[branch] b ON u.unit_type = N'branch' AND b.id = u.unit_id
    LEFT JOIN [org].[department] d ON u.unit_type = N'department' AND d.id = u.unit_id
    LEFT JOIN [org].[location] l ON u.unit_type = N'location' AND l.id = u.unit_id
    WHERE u.role_id = @id
    ORDER BY p.sort_order, u.unit_type, u.unit_id;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [auth].[usp_access_role_list]
    @company_id      BIGINT,
    @search          NVARCHAR(200) = NULL,
    @include_retired BIT = 0,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [auth].[role] r
    WHERE r.company_id = @company_id AND (@include_retired = 1 OR r.is_active = 1)
      AND (@pattern IS NULL OR r.name LIKE @pattern OR r.description LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.id, r.code, r.name, r.description, r.is_system, r.is_active,
           (SELECT COUNT(*) FROM [auth].[role_permission] rp WHERE rp.role_id = r.id) AS permission_count,
           (SELECT COUNT(*) FROM [auth].[user_role] ur WHERE ur.role_id = r.id) AS user_count,
           r.created_at, r.updated_at, r.row_version
    FROM [auth].[role] r
    WHERE r.company_id = @company_id AND (@include_retired = 1 OR r.is_active = 1)
      AND (@pattern IS NULL OR r.name LIKE @pattern OR r.description LIKE @pattern)
    ORDER BY r.is_active DESC, r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a role (@id NULL, no permissions yet) or renames / re-describes one.
CREATE OR ALTER PROCEDURE [auth].[usp_access_role_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @description   NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Role name is required.', 1;
    IF EXISTS (SELECT 1 FROM [auth].[role] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|ROLE_DUPLICATE|A role with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [auth].[role] (company_id, code, name, description, is_system, is_active, created_by)
            VALUES (@company_id, CONCAT(N'custom_', LOWER(LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12))),
                    @name, @description, 0, 1, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'auth.role', @id, @name, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @o_name NVARCHAR(200), @o_desc NVARCHAR(MAX), @o_rv BINARY(8);
        SELECT @o_name = name, @o_desc = description, @o_rv = row_version
        FROM [auth].[role] WHERE id = @id AND company_id = @company_id;
        IF @o_rv IS NULL
            THROW 50404, N'Role not found', 1;
        IF @row_version IS NULL OR @o_rv <> @row_version
            THROW 50409, N'Someone else changed this role. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [auth].[role] SET name = @name, description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this role. Reload it and try again', 1;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'auth.role', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES (N'name', @o_name, @name), (N'description', @o_desc, @description)) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [auth].[usp_access_role_get] @company_id = @company_id, @id = @id;
END
GO

-- Replaces a role's ticks. @ticks: [{"code", "scope", "units": [{"unitType", "unitId"}]}].
-- ACC-11: a tick that is new, or wider than before, must be held by the actor with at least that
-- scope (a system administrator holds everything).
CREATE OR ALTER PROCEDURE [auth].[usp_access_role_permissions_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @ticks         NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [auth].[role] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Role not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this role. Reload it and try again', 1;
    IF ISJSON(@ticks) = 0
        THROW 50400, N'permissions|Not a list of permissions.', 1;

    DECLARE @t TABLE (code NVARCHAR(150) PRIMARY KEY, permission_id BIGINT, scope NVARCHAR(30), units NVARCHAR(MAX), rnk INT);
    INSERT @t (code, scope, units)
    SELECT code, scope, units
    FROM OPENJSON(@ticks) WITH (code NVARCHAR(150), scope NVARCHAR(30), units NVARCHAR(MAX) AS JSON);
    UPDATE t SET permission_id = p.id,
                 rnk = CASE t.scope WHEN N'company' THEN 4 WHEN N'department' THEN 3 WHEN N'branch' THEN 3
                                    WHEN N'selected_units' THEN 3 WHEN N'team' THEN 2 ELSE 1 END
    FROM @t t LEFT JOIN [auth].[permission] p ON p.code = t.code;

    DECLARE @bad NVARCHAR(150) = (SELECT TOP 1 code FROM @t WHERE permission_id IS NULL);
    IF @bad IS NOT NULL
    BEGIN
        DECLARE @m1 NVARCHAR(400) = CONCAT(N'permissions|', @bad, N' is not a permission.');
        THROW 50400, @m1, 1;
    END
    IF EXISTS (SELECT 1 FROM @t WHERE scope IS NULL OR scope NOT IN (N'own', N'team', N'department', N'branch', N'selected_units', N'company'))
        THROW 50400, N'permissions|Each permission needs a scope: own, team, department, branch, selected_units or company.', 1;

    DECLARE @u TABLE (permission_id BIGINT, unit_type NVARCHAR(30), unit_id BIGINT, PRIMARY KEY (permission_id, unit_type, unit_id));
    INSERT @u
    SELECT DISTINCT t.permission_id, x.unit_type, x.unit_id
    FROM @t t
    CROSS APPLY OPENJSON(t.units) WITH (unit_type NVARCHAR(30) '$.unitType', unit_id BIGINT '$.unitId') x
    WHERE t.scope = N'selected_units';

    IF EXISTS (SELECT 1 FROM @t t WHERE t.scope = N'selected_units' AND NOT EXISTS (SELECT 1 FROM @u u WHERE u.permission_id = t.permission_id))
        THROW 50400, N'permissions|Pick at least one branch, department or location for a selected-units permission.', 1;
    IF EXISTS (SELECT 1 FROM @u u
               WHERE NOT (   (u.unit_type = N'branch' AND EXISTS (SELECT 1 FROM [org].[branch] b WHERE b.id = u.unit_id AND b.company_id = @company_id))
                          OR (u.unit_type = N'department' AND EXISTS (SELECT 1 FROM [org].[department] d WHERE d.id = u.unit_id AND d.company_id = @company_id))
                          OR (u.unit_type = N'location' AND EXISTS (SELECT 1 FROM [org].[location] l WHERE l.id = u.unit_id AND l.company_id = @company_id))))
        THROW 50400, N'permissions|A selected unit was not found in this company.', 1;

    IF ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0) = 0
    BEGIN
        DECLARE @over NVARCHAR(150) = (
            SELECT TOP 1 t.code FROM @t t
            LEFT JOIN [auth].[role_permission] old ON old.role_id = @id AND old.permission_id = t.permission_id
            WHERE (old.permission_id IS NULL OR old.scope <> t.scope)
              AND NOT EXISTS (SELECT 1 FROM [auth].[fn_access_held](@company_id, @actor_user_id) h
                              WHERE h.permission_id = t.permission_id AND h.max_rank >= t.rnk));
        IF @over IS NOT NULL
        BEGIN
            DECLARE @m2 NVARCHAR(400) = CONCAT(N'permissions|PERMISSION_NOT_HELD|You cannot give ', @over,
                                               N' with that scope: you do not hold it that widely yourself.');
            THROW 50403, @m2, 1;
        END
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'auth.role', @id, COALESCE(p.code, t.code), old.scope, t.scope,
               CASE WHEN old.permission_id IS NULL THEN N'permission_added'
                    WHEN t.permission_id IS NULL THEN N'permission_removed' ELSE N'permission_changed' END,
               @actor_user_id, @now
        FROM (SELECT * FROM [auth].[role_permission] WHERE role_id = @id) old
        FULL JOIN @t t ON t.permission_id = old.permission_id
        LEFT JOIN [auth].[permission] p ON p.id = old.permission_id
        WHERE old.permission_id IS NULL OR t.permission_id IS NULL OR old.scope <> t.scope;

        DELETE [auth].[role_permission_unit] WHERE role_id = @id;
        DELETE rp FROM [auth].[role_permission] rp
        WHERE rp.role_id = @id AND NOT EXISTS (SELECT 1 FROM @t t WHERE t.permission_id = rp.permission_id);
        UPDATE rp SET scope = t.scope, updated_at = @now, updated_by = @actor_user_id
        FROM [auth].[role_permission] rp JOIN @t t ON t.permission_id = rp.permission_id
        WHERE rp.role_id = @id AND rp.scope <> t.scope;
        INSERT [auth].[role_permission] (role_id, permission_id, scope, created_by)
        SELECT @id, t.permission_id, t.scope, @actor_user_id FROM @t t
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[role_permission] rp WHERE rp.role_id = @id AND rp.permission_id = t.permission_id);
        INSERT [auth].[role_permission_unit] (role_id, permission_id, unit_type, unit_id, created_by)
        SELECT @id, permission_id, unit_type, unit_id, @actor_user_id FROM @u;

        UPDATE [auth].[role] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    EXEC [auth].[usp_access_role_get] @company_id = @company_id, @id = @id;
END
GO

-- Copies a role with its ticks and units under a new name. The copy is a customer role.
CREATE OR ALTER PROCEDURE [auth].[usp_access_role_copy]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @name          NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF NOT EXISTS (SELECT 1 FROM [auth].[role] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Role not found', 1;
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Role name is required.', 1;
    IF EXISTS (SELECT 1 FROM [auth].[role] WHERE company_id = @company_id AND name = @name)
        THROW 50409, N'name|ROLE_DUPLICATE|A role with this name already exists.', 1;

    DECLARE @new BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [auth].[role] (company_id, code, name, description, is_system, is_active, created_by)
        SELECT @company_id, CONCAT(N'custom_', LOWER(LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12))),
               @name, description, 0, 1, @actor_user_id
        FROM [auth].[role] WHERE id = @id;
        SET @new = SCOPE_IDENTITY();

        INSERT [auth].[role_permission] (role_id, permission_id, scope, created_by)
        SELECT @new, permission_id, scope, @actor_user_id FROM [auth].[role_permission] WHERE role_id = @id;
        INSERT [auth].[role_permission_unit] (role_id, permission_id, unit_type, unit_id, created_by)
        SELECT @new, permission_id, unit_type, unit_id, @actor_user_id FROM [auth].[role_permission_unit] WHERE role_id = @id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'auth.role', @new, N'copied_from', r.name, @name, N'copy', @actor_user_id, @now
        FROM [auth].[role] r WHERE r.id = @id;
    COMMIT;

    EXEC [auth].[usp_access_role_get] @company_id = @company_id, @id = @new;
END
GO

-- Retires a role (@active 0: its holders lose what it gives, it cannot be given) or brings it back.
CREATE OR ALTER PROCEDURE [auth].[usp_access_role_active_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @active        BIT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @old BIT;
    SELECT @rv = row_version, @old = is_active FROM [auth].[role] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Role not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this role. Reload it and try again', 1;
    IF @old = @active
        THROW 50409, N'The role is already in that state.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [auth].[role] SET is_active = @active, updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.role', @id, N'is_active', CONVERT(NVARCHAR(5), @old), CONVERT(NVARCHAR(5), @active),
                CASE WHEN @active = 1 THEN N'restore' ELSE N'retire' END, @actor_user_id, @now);
    COMMIT;

    EXEC [auth].[usp_access_role_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a customer role nobody holds. Default roles are retired instead (the next release would
-- offer them again).
CREATE OR ALTER PROCEDURE [auth].[usp_access_role_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @system BIT, @name NVARCHAR(200);
    SELECT @rv = row_version, @system = is_system, @name = name FROM [auth].[role] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Role not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this role. Reload it and try again', 1;
    IF @system = 1
        THROW 50409, N'A default role cannot be deleted. Retire it instead.', 1;
    IF EXISTS (SELECT 1 FROM [auth].[user_role] WHERE role_id = @id)
        THROW 50409, N'Users hold this role. Take it away from them first, or retire it.', 1;

    BEGIN TRAN;
        DELETE [auth].[role_permission_unit] WHERE role_id = @id;
        DELETE [auth].[role_permission] WHERE role_id = @id;
        DELETE [auth].[role_default_offer] WHERE role_id = @id;
        DELETE [auth].[role] WHERE id = @id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.role', @id, @name, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- The catalogue for the role screen: every permission, in screen order.
CREATE OR ALTER PROCEDURE [auth].[usp_access_permission_list]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, code, module, screen, action_code, label, hint, is_sensitive, sort_order
    FROM [auth].[permission]
    ORDER BY sort_order, code;
END
