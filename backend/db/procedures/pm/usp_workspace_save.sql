-- Edit Workspace: name, description, visibility, department, owner (workspace admins and HR;
-- only a workspace admin hands the workspace to another owner). Returns the workspace.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @name          NVARCHAR(200),
    @description   NVARCHAR(MAX) = NULL,
    @privacy       NVARCHAR(30),
    @department_id BIGINT,
    @owner_id      BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can edit the workspace.', 1;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @name IS NULL OR LEN(@name) < 3 OR LEN(@name) > 50
        THROW 50400, N'name|Workspace name must be 3 to 50 characters.', 1;
    IF LEN(@description) > 300
        THROW 50400, N'description|Description must be under 300 characters.', 1;
    IF @privacy IS NULL OR @privacy NOT IN (N'private', N'workspace', N'public')
        THROW 50400, N'privacy|Choose who can see this workspace.', 1;
    IF NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Select your department.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @owner_id AND company_id = @company_id)
        THROW 50400, N'ownerId|Workspace owner not found.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[workspace] WHERE company_id = @company_id AND name = @name AND id <> @id)
        THROW 50409, N'name|WORKSPACE_DUPLICATE|A workspace with this name already exists.', 1;

    DECLARE @old_name NVARCHAR(200), @old_desc NVARCHAR(MAX), @old_privacy NVARCHAR(30), @old_dept BIGINT, @old_owner BIGINT, @old_rv BINARY(8);
    SELECT @old_name = name, @old_desc = description, @old_privacy = privacy, @old_dept = department_id,
           @old_owner = owner_id, @old_rv = row_version
    FROM [pm].[workspace] WHERE id = @id;
    IF @old_rv <> @row_version
        THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;
    IF @owner_id <> @old_owner AND @rank < 5
        THROW 50403, N'Only a workspace admin can change the owner.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [pm].[workspace]
        SET name = @name, description = @description, privacy = @privacy, department_id = @department_id,
            owner_id = @owner_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;

        IF @owner_id <> @old_owner
        BEGIN
            UPDATE [pm].[workspace_member] SET member_role = N'workspace_admin', updated_at = @now, updated_by = @actor_user_id
            WHERE workspace_id = @id AND employee_id = @owner_id;
            IF @@ROWCOUNT = 0
                INSERT [pm].[workspace_member] (workspace_id, employee_id, member_role, created_by)
                VALUES (@id, @owner_id, N'workspace_admin', @actor_user_id);
        END

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pm.workspace', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
        FROM (VALUES
            (N'name', @old_name, @name),
            (N'description', @old_desc, @description),
            (N'privacy', @old_privacy, @privacy),
            (N'department_id', CONVERT(NVARCHAR(30), @old_dept), CONVERT(NVARCHAR(30), @department_id)),
            (N'owner_id', CONVERT(NVARCHAR(30), @old_owner), CONVERT(NVARCHAR(30), @owner_id))
        ) f (field_name, old_value, new_value)
        WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
    COMMIT;

    EXEC [pm].[usp_workspace_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Edit Statuses after creation: the whole status set, with the status mode and template. Statuses
-- sent with an id are renamed / recoloured / moved; missing ones are removed unless tasks use them.
-- @statuses: [{"id", "name", "color", "status_group", "wip_limit"}]
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_statuses_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @status_mode     NVARCHAR(30) = NULL,
    @status_template NVARCHAR(30) = NULL,
    @statuses        NVARCHAR(MAX),
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can edit statuses.', 1;
    IF (SELECT row_version FROM [pm].[workspace] WHERE id = @id) <> @row_version
        THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;

    DECLARE @status_template_id BIGINT = NULL;
    IF @status_template IS NOT NULL
    BEGIN
        SET @status_template_id = (SELECT id FROM [pm].[template] WHERE template_kind = N'status' AND code = @status_template);
        IF @status_template_id IS NULL
            THROW 50400, N'statusTemplate|Status template not found.', 1;
    END

    DECLARE @st TABLE (id BIGINT, name NVARCHAR(200), color NVARCHAR(20), status_group NVARCHAR(30), wip_limit INT, sort_order INT);
    INSERT @st SELECT j.id, LTRIM(RTRIM(j.name)), j.color, j.status_group, j.wip_limit, (CAST(k.[key] AS INT) + 1) * 10
    FROM OPENJSON(ISNULL(@statuses, N'[]')) k
    CROSS APPLY OPENJSON(k.value) WITH (id BIGINT '$.id', name NVARCHAR(200) '$.name', color NVARCHAR(20) '$.color',
                                        status_group NVARCHAR(30) '$.status_group', wip_limit INT '$.wip_limit') j;

    IF EXISTS (SELECT 1 FROM @st WHERE name IS NULL OR name = N'')
        THROW 50400, N'statuses|Every status needs a name.', 1;
    IF EXISTS (SELECT 1 FROM @st WHERE status_group IS NULL OR status_group NOT IN (N'not_started', N'active', N'done', N'closed'))
        THROW 50400, N'statuses|Statuses belong to Not Started, Active, Done or Closed.', 1;
    IF EXISTS (SELECT name FROM @st GROUP BY name HAVING COUNT(*) > 1)
        THROW 50400, N'statuses|Status names must be unique.', 1;
    IF NOT EXISTS (SELECT 1 FROM @st WHERE status_group = N'not_started')
       OR NOT EXISTS (SELECT 1 FROM @st WHERE status_group IN (N'done', N'closed'))
        THROW 50400, N'statuses|Keep at least one Not Started status and one Done or Closed status.', 1;
    IF EXISTS (SELECT 1 FROM @st s WHERE s.id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_status] w WHERE w.id = s.id AND w.workspace_id = @id))
        THROW 50400, N'statuses|A status does not belong to this workspace.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[workspace_status] w JOIN [pm].[task] t ON t.status_id = w.id
               WHERE w.workspace_id = @id AND NOT EXISTS (SELECT 1 FROM @st s WHERE s.id = w.id))
        THROW 50409, N'statuses|STATUS_IN_USE|Tasks still use a status you removed. Move them first.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        -- Free the names first so a rename onto a removed status's name does not collide.
        DELETE w FROM [pm].[workspace_status] w
        WHERE w.workspace_id = @id AND NOT EXISTS (SELECT 1 FROM @st s WHERE s.id = w.id);
        UPDATE w SET name = CONCAT(N'~', w.id) FROM [pm].[workspace_status] w JOIN @st s ON s.id = w.id;
        UPDATE w SET name = s.name, color = s.color, status_group = s.status_group, wip_limit = s.wip_limit,
                     sort_order = s.sort_order, updated_at = @now, updated_by = @actor_user_id
        FROM [pm].[workspace_status] w JOIN @st s ON s.id = w.id;
        INSERT [pm].[workspace_status] (workspace_id, status_group, name, color, sort_order, wip_limit, created_by)
        SELECT @id, status_group, name, color, sort_order, wip_limit, @actor_user_id FROM @st WHERE id IS NULL;

        UPDATE [pm].[workspace]
        SET status_mode = ISNULL(@status_mode, status_mode), status_template_id = ISNULL(@status_template_id, status_template_id),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @id, N'statuses', N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_workspace_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Organizer features after creation: the full set that is switched on.
-- @features: [{"feature_code", "setting_value"}]
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_features_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @features      NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can change organizer features.', 1;
    IF (SELECT row_version FROM [pm].[workspace] WHERE id = @id) <> @row_version
        THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;

    DECLARE @ft TABLE (feature_code NVARCHAR(50) PRIMARY KEY, setting_value NVARCHAR(4000));
    INSERT @ft SELECT j.feature_code, MAX(j.setting_value)
    FROM OPENJSON(ISNULL(@features, N'[]')) WITH (feature_code NVARCHAR(50) '$.feature_code', setting_value NVARCHAR(4000) '$.setting_value') j
    WHERE j.feature_code IS NOT NULL
    GROUP BY j.feature_code;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE f FROM [pm].[workspace_feature] f
        WHERE f.workspace_id = @id AND NOT EXISTS (SELECT 1 FROM @ft s WHERE s.feature_code = f.feature_code);
        UPDATE f SET setting_value = s.setting_value, updated_at = @now, updated_by = @actor_user_id
        FROM [pm].[workspace_feature] f JOIN @ft s ON s.feature_code = f.feature_code
        WHERE f.workspace_id = @id AND EXISTS (SELECT f.setting_value EXCEPT SELECT s.setting_value);
        INSERT [pm].[workspace_feature] (workspace_id, feature_code, setting_value, created_by)
        SELECT @id, s.feature_code, s.setting_value, @actor_user_id FROM @ft s
        WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] f WHERE f.workspace_id = @id AND f.feature_code = s.feature_code);

        UPDATE [pm].[workspace] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @id, N'features', N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_workspace_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
