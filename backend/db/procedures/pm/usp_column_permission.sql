-- Set Role Permission on a List view column: a workspace default, a level per workspace role, and
-- custom levels for single members. Levels: can_edit, can_view, private ("default" = no row, inherit).
-- Column keys: the built-in columns below, or cf_<custom field id>.

CREATE OR ALTER PROCEDURE [pm].[usp_column_permission_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT;
    SELECT @me = employee_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    -- Result set 1: the rows as set. Result set 2: the levels in effect for the caller.
    SELECT p.id, p.column_key, p.member_role, p.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           p.permission_level
    FROM [pm].[column_permission] p
    LEFT JOIN [hr].[employee] e ON e.id = p.employee_id
    WHERE p.workspace_id = @workspace_id
    ORDER BY p.column_key, CASE WHEN p.member_role IS NULL AND p.employee_id IS NULL THEN 0 WHEN p.employee_id IS NULL THEN 1 ELSE 2 END, p.id;

    SELECT column_key, permission_level FROM [pm].[fn_column_levels](@workspace_id, @me);
END
GO

-- Replaces one column's permissions. @roles: [{"member_role", "permission_level"}];
-- @members: [{"employee_id", "permission_level"}]. Workspace admins and HR only.
CREATE OR ALTER PROCEDURE [pm].[usp_column_permission_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT,
    @column_key    NVARCHAR(50),
    @default_level NVARCHAR(30) = NULL,
    @roles         NVARCHAR(MAX) = NULL,
    @members       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can set column permissions.', 1;

    IF @column_key = N'name'
        THROW 50400, N'columnKey|Task Name is always visible.', 1;
    IF @column_key NOT IN (N'assignees', N'start_date', N'due_date', N'priority', N'tags', N'dependencies', N'status',
                           N'progress', N'time_estimate', N'time_tracked', N'task_id', N'created_by', N'date_created',
                           N'date_closed', N'latest_comment', N'story_points', N'files')
       AND NOT EXISTS (SELECT 1 FROM [pm].[custom_field] f WHERE f.workspace_id = @workspace_id AND CONCAT(N'cf_', f.id) = @column_key)
        THROW 50400, N'columnKey|Unknown column.', 1;

    DECLARE @rows TABLE (member_role NVARCHAR(30), employee_id BIGINT, permission_level NVARCHAR(30));
    IF NULLIF(@default_level, N'default') IS NOT NULL
        INSERT @rows VALUES (NULL, NULL, @default_level);
    INSERT @rows SELECT j.member_role, NULL, j.permission_level
    FROM OPENJSON(ISNULL(@roles, N'[]')) WITH (member_role NVARCHAR(30) '$.member_role', permission_level NVARCHAR(30) '$.permission_level') j
    WHERE ISNULL(j.permission_level, N'default') <> N'default';
    INSERT @rows SELECT NULL, j.employee_id, j.permission_level
    FROM OPENJSON(ISNULL(@members, N'[]')) WITH (employee_id BIGINT '$.employee_id', permission_level NVARCHAR(30) '$.permission_level') j
    WHERE ISNULL(j.permission_level, N'default') <> N'default';

    IF EXISTS (SELECT 1 FROM @rows WHERE permission_level NOT IN (N'can_edit', N'can_view', N'private'))
        THROW 50400, N'permissionLevel|Choose Default, Can Edit, Can View or Private Field.', 1;
    IF EXISTS (SELECT 1 FROM @rows WHERE employee_id IS NULL AND member_role IS NOT NULL
               AND member_role NOT IN (N'workspace_admin', N'hr', N'manager', N'team_leader', N'contributor'))
        THROW 50400, N'roles|Unknown workspace role.', 1;
    IF EXISTS (SELECT member_role FROM @rows WHERE employee_id IS NULL AND member_role IS NOT NULL GROUP BY member_role HAVING COUNT(*) > 1)
       OR EXISTS (SELECT employee_id FROM @rows WHERE employee_id IS NOT NULL GROUP BY employee_id HAVING COUNT(*) > 1)
        THROW 50400, N'roles|Each role or member can be listed once.', 1;
    IF EXISTS (SELECT 1 FROM @rows r WHERE r.employee_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @workspace_id AND m.employee_id = r.employee_id))
        THROW 50400, N'members|Custom permissions are for workspace members.', 1;

    BEGIN TRAN;
        DELETE [pm].[column_permission] WHERE workspace_id = @workspace_id AND column_key = @column_key;
        INSERT [pm].[column_permission] (workspace_id, column_key, member_role, employee_id, permission_level, created_by)
        SELECT @workspace_id, @column_key, member_role, employee_id, permission_level, @actor_user_id FROM @rows;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @workspace_id, N'column_permission:' + @column_key, N'update', @actor_user_id, SYSUTCDATETIME());
    COMMIT;

    EXEC [pm].[usp_column_permission_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @workspace_id = @workspace_id;
END
