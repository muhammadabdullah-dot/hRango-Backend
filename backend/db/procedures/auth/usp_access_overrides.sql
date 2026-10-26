-- A user's own grants and denials (ACC-6): a grant adds a permission with a scope, a denial takes
-- one away whatever the roles give. Nobody changes their own, and nobody grants what they do not
-- hold (ACC-11). Every change is written to core.audit_log (entity auth.user_account, ACC-15).

CREATE OR ALTER PROCEDURE [auth].[usp_access_override_list]
    @company_id BIGINT,
    @user_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_access_company_users](@company_id) WHERE id = @user_id)
        THROW 50404, N'User not found', 1;

    SELECT o.id, o.user_account_id, p.code, p.module, p.label, p.is_sensitive, o.effect, o.scope, o.reason,
           o.created_at, o.updated_at, o.row_version
    FROM [auth].[user_permission_override] o
    JOIN [auth].[permission] p ON p.id = o.permission_id
    WHERE o.user_account_id = @user_id AND o.company_id = @company_id
    ORDER BY p.sort_order;
END
GO

-- Adds or replaces the user's grant or denial of one permission. Returns the row.
CREATE OR ALTER PROCEDURE [auth].[usp_access_override_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @user_id       BIGINT,
    @code          NVARCHAR(150),
    @effect        NVARCHAR(30),
    @scope         NVARCHAR(30) = NULL,
    @reason        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_admin BIT = ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    DECLARE @target_admin BIT = (SELECT u.is_system_admin FROM [auth].[user_account] u
                                 JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = u.id WHERE u.id = @user_id);
    IF @target_admin IS NULL
        THROW 50404, N'User not found', 1;
    IF @user_id = @actor_user_id
        THROW 50403, N'You cannot change your own access.', 1;
    IF @target_admin = 1 AND @actor_admin = 0
        THROW 50403, N'Only a system administrator can change a system administrator.', 1;

    DECLARE @permission_id BIGINT = (SELECT id FROM [auth].[permission] WHERE code = @code);
    IF @permission_id IS NULL
        THROW 50400, N'code|This is not a permission.', 1;
    IF @effect NOT IN (N'grant', N'deny')
        THROW 50400, N'effect|Choose grant or deny.', 1;
    IF @effect = N'deny'
        SET @scope = NULL;
    ELSE IF @scope IS NULL OR @scope NOT IN (N'own', N'team', N'department', N'branch', N'company')
        THROW 50400, N'scope|A grant needs a scope: own, team, department, branch or company.', 1;

    DECLARE @rank INT = CASE @scope WHEN N'company' THEN 4 WHEN N'department' THEN 3 WHEN N'branch' THEN 3
                                    WHEN N'team' THEN 2 ELSE 1 END;
    IF @effect = N'grant' AND @actor_admin = 0
       AND NOT EXISTS (SELECT 1 FROM [auth].[fn_access_held](@company_id, @actor_user_id) h
                       WHERE h.permission_id = @permission_id AND h.max_rank >= @rank)
        THROW 50403, N'scope|PERMISSION_NOT_HELD|You cannot grant access you do not hold that widely yourself.', 1;

    DECLARE @old_effect NVARCHAR(30), @old_scope NVARCHAR(30), @id BIGINT;
    SELECT @id = id, @old_effect = effect, @old_scope = scope
    FROM [auth].[user_permission_override]
    WHERE company_id = @company_id AND user_account_id = @user_id AND permission_id = @permission_id;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [auth].[user_permission_override] (company_id, user_account_id, permission_id, effect, scope, reason, created_by)
            VALUES (@company_id, @user_id, @permission_id, @effect, @scope, NULLIF(LTRIM(RTRIM(@reason)), N''), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
            UPDATE [auth].[user_permission_override]
            SET effect = @effect, scope = @scope, reason = NULLIF(LTRIM(RTRIM(@reason)), N''), updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id;

        UPDATE [auth].[user_account] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @user_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @user_id, @code,
                CASE WHEN @old_effect IS NULL THEN NULL ELSE CONCAT(@old_effect, N' ', @old_scope) END,
                RTRIM(CONCAT(@effect, N' ', @scope)), CONCAT(N'override_', @effect), @actor_user_id, @now);
    COMMIT;

    SELECT o.id, o.user_account_id, p.code, p.module, p.label, p.is_sensitive, o.effect, o.scope, o.reason,
           o.created_at, o.updated_at, o.row_version
    FROM [auth].[user_permission_override] o
    JOIN [auth].[permission] p ON p.id = o.permission_id
    WHERE o.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [auth].[usp_access_override_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @user_id       BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_admin BIT = ISNULL((SELECT is_system_admin FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    DECLARE @target_admin BIT = (SELECT u.is_system_admin FROM [auth].[user_account] u
                                 JOIN [auth].[fn_access_company_users](@company_id) cu ON cu.id = u.id WHERE u.id = @user_id);
    IF @target_admin IS NULL
        THROW 50404, N'User not found', 1;
    IF @user_id = @actor_user_id
        THROW 50403, N'You cannot change your own access.', 1;
    IF @target_admin = 1 AND @actor_admin = 0
        THROW 50403, N'Only a system administrator can change a system administrator.', 1;

    DECLARE @rv BINARY(8), @code NVARCHAR(150), @effect NVARCHAR(30), @scope NVARCHAR(30);
    SELECT @rv = o.row_version, @code = p.code, @effect = o.effect, @scope = o.scope
    FROM [auth].[user_permission_override] o JOIN [auth].[permission] p ON p.id = o.permission_id
    WHERE o.id = @id AND o.user_account_id = @user_id AND o.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Grant or denial not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this grant. Reload it and try again', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE [auth].[user_permission_override] WHERE id = @id;
        UPDATE [auth].[user_account] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @user_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'auth.user_account', @user_id, @code, RTRIM(CONCAT(@effect, N' ', @scope)), N'override_removed',
                @actor_user_id, @now);
    COMMIT;
END
