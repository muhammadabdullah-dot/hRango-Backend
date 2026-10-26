-- The Create Workspace wizard in one call: details (step 1), department and workflow template
-- (step 2), views, statuses and organizer features (step 3), and the members.
-- JSON parameters (snake_case keys):
--   @statuses  [{"name", "color", "status_group", "wip_limit"}]   blank: the template's statuses
--   @views     [{"view_type", "is_default"}]                     blank: the template's views; List is always added
--   @features  [{"feature_code", "setting_value"}]               blank: the template's features
--   @members   [{"employee_id", "member_role"}]
-- The owner, and the creator when they are an employee, become members with workspace_admin.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_create]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @name              NVARCHAR(200),
    @description       NVARCHAR(MAX) = NULL,
    @privacy           NVARCHAR(30),
    @department_id     BIGINT,
    @workflow_template NVARCHAR(30) = NULL,
    @owner_id          BIGINT,
    @status_mode       NVARCHAR(30) = N'default',
    @status_template   NVARCHAR(30) = NULL,
    @statuses          NVARCHAR(MAX) = NULL,
    @views             NVARCHAR(MAX) = NULL,
    @features          NVARCHAR(MAX) = NULL,
    @members           NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @workflow_template = ISNULL(NULLIF(@workflow_template, N''), N'work_starter');
    SET @status_mode = ISNULL(@status_mode, N'default');

    IF @name IS NULL OR LEN(@name) < 3 OR LEN(@name) > 50
        THROW 50400, N'name|Workspace name must be 3 to 50 characters.', 1;
    IF LEN(@description) > 300
        THROW 50400, N'description|Description must be under 300 characters.', 1;
    IF @privacy IS NULL OR @privacy NOT IN (N'private', N'workspace', N'public')
        THROW 50400, N'privacy|Choose who can see this workspace.', 1;
    IF NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Select your department.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @owner_id AND company_id = @company_id AND ISNULL(status, N'active') <> N'left')
        THROW 50400, N'ownerId|Workspace owner not found.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[workspace] WHERE company_id = @company_id AND name = @name)
        THROW 50409, N'name|WORKSPACE_DUPLICATE|A workspace with this name already exists.', 1;

    DECLARE @workflow_id BIGINT = (SELECT id FROM [pm].[template] WHERE template_kind = N'workflow' AND code = @workflow_template);
    IF @workflow_id IS NULL
        THROW 50400, N'workflowTemplate|Workflow template not found.', 1;
    DECLARE @status_template_id BIGINT = NULL;
    IF @status_mode = N'custom' AND @status_template IS NOT NULL
    BEGIN
        SET @status_template_id = (SELECT id FROM [pm].[template] WHERE template_kind = N'status' AND code = @status_template);
        IF @status_template_id IS NULL
            THROW 50400, N'statusTemplate|Status template not found.', 1;
    END

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    -- Only members see a private workspace, and members are employees: an account without an employee
    -- record would create one it cannot open. Refuse before anything is written.
    IF @privacy = N'private' AND @me IS NULL
        THROW 50400, N'privacy|WORKSPACE_CREATOR_NOT_EMPLOYEE|A private workspace needs an employee as its creator. Choose Workspace or Public, or create it from an employee account.', 1;

    -- Statuses: as sent, else the status template's (custom mode), else the workflow template's.
    DECLARE @st TABLE (name NVARCHAR(200), color NVARCHAR(20), status_group NVARCHAR(30), wip_limit INT, sort_order INT);
    IF @statuses IS NOT NULL AND ISJSON(@statuses) = 1 AND EXISTS (SELECT 1 FROM OPENJSON(@statuses))
        INSERT @st SELECT LTRIM(RTRIM(j.name)), j.color, j.status_group, j.wip_limit, (CAST(k.[key] AS INT) + 1) * 10
        FROM OPENJSON(@statuses) k
        CROSS APPLY OPENJSON(k.value) WITH (name NVARCHAR(200) '$.name', color NVARCHAR(20) '$.color',
                                            status_group NVARCHAR(30) '$.status_group', wip_limit INT '$.wip_limit') j;
    ELSE
        INSERT @st SELECT i.name, i.color, i.status_group, NULL, i.sort_order
        FROM [pm].[template_item] i
        WHERE i.template_id = ISNULL(@status_template_id, @workflow_id) AND i.item_type = N'status';

    IF EXISTS (SELECT 1 FROM @st WHERE name IS NULL OR name = N'')
        THROW 50400, N'statuses|Every status needs a name.', 1;
    IF EXISTS (SELECT 1 FROM @st WHERE status_group IS NULL OR status_group NOT IN (N'not_started', N'active', N'done', N'closed'))
        THROW 50400, N'statuses|Statuses belong to Not Started, Active, Done or Closed.', 1;
    IF EXISTS (SELECT name FROM @st GROUP BY name HAVING COUNT(*) > 1)
        THROW 50400, N'statuses|Status names must be unique.', 1;
    IF NOT EXISTS (SELECT 1 FROM @st WHERE status_group = N'not_started')
       OR NOT EXISTS (SELECT 1 FROM @st WHERE status_group IN (N'done', N'closed'))
        THROW 50400, N'statuses|Keep at least one Not Started status and one Done or Closed status.', 1;

    -- Views: as sent, else the workflow template's. List is always there.
    DECLARE @vw TABLE (view_type NVARCHAR(30), is_default BIT, sort_order INT);
    IF @views IS NOT NULL AND ISJSON(@views) = 1 AND EXISTS (SELECT 1 FROM OPENJSON(@views))
        INSERT @vw SELECT j.view_type, ISNULL(j.is_default, 0), (CAST(k.[key] AS INT) + 1) * 10
        FROM OPENJSON(@views) k CROSS APPLY OPENJSON(k.value) WITH (view_type NVARCHAR(30) '$.view_type', is_default BIT '$.is_default') j;
    ELSE
        INSERT @vw SELECT i.item_code, i.is_default, i.sort_order
        FROM [pm].[template_item] i WHERE i.template_id = @workflow_id AND i.item_type = N'view';
    IF EXISTS (SELECT view_type FROM @vw GROUP BY view_type HAVING COUNT(*) > 1)
        THROW 50400, N'views|Each view can be added once.', 1;
    IF NOT EXISTS (SELECT 1 FROM @vw WHERE view_type = N'list')
        INSERT @vw VALUES (N'list', 0, 0);
    IF (SELECT COUNT(*) FROM @vw WHERE is_default = 1) <> 1
    BEGIN
        UPDATE @vw SET is_default = 0;
        UPDATE @vw SET is_default = 1 WHERE view_type = N'list';
    END

    -- Organizer features: as sent (an empty array switches all off), else the template's.
    DECLARE @ft TABLE (feature_code NVARCHAR(50), setting_value NVARCHAR(MAX));
    IF @features IS NOT NULL AND ISJSON(@features) = 1
        INSERT @ft SELECT j.feature_code, MAX(j.setting_value)
        FROM OPENJSON(@features) WITH (feature_code NVARCHAR(50) '$.feature_code', setting_value NVARCHAR(4000) '$.setting_value') j
        WHERE j.feature_code IS NOT NULL
        GROUP BY j.feature_code;
    ELSE
        INSERT @ft SELECT i.item_code, NULL
        FROM [pm].[template_item] i WHERE i.template_id = @workflow_id AND i.item_type = N'feature';

    -- Members. The owner and the creator are admins.
    DECLARE @mb TABLE (employee_id BIGINT PRIMARY KEY, member_role NVARCHAR(30));
    IF @members IS NOT NULL AND ISJSON(@members) = 1
        INSERT @mb SELECT j.employee_id, MAX(ISNULL(j.member_role, N'contributor'))
        FROM OPENJSON(@members) WITH (employee_id BIGINT '$.employee_id', member_role NVARCHAR(30) '$.member_role') j
        WHERE j.employee_id IS NOT NULL
        GROUP BY j.employee_id;
    IF EXISTS (SELECT 1 FROM @mb m WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = m.employee_id AND e.company_id = @company_id))
        THROW 50400, N'members|A member was not found.', 1;
    IF EXISTS (SELECT 1 FROM @mb WHERE member_role NOT IN (N'workspace_admin', N'hr', N'manager', N'team_leader', N'contributor'))
        THROW 50400, N'members|Unknown workspace role.', 1;
    IF @privacy = N'private' AND NOT EXISTS (SELECT 1 FROM @mb WHERE employee_id <> @owner_id AND employee_id <> ISNULL(@me, 0))
        THROW 50400, N'members|A private workspace needs at least one invited member.', 1;
    UPDATE @mb SET member_role = N'workspace_admin' WHERE employee_id IN (@owner_id, ISNULL(@me, 0));
    INSERT @mb (employee_id, member_role) SELECT @owner_id, N'workspace_admin' WHERE NOT EXISTS (SELECT 1 FROM @mb WHERE employee_id = @owner_id);
    INSERT @mb (employee_id, member_role) SELECT @me, N'workspace_admin' WHERE @me IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @mb WHERE employee_id = @me);

    DECLARE @id BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [pm].[workspace] (company_id, name, description, privacy, department_id, workflow_template_id, status_mode,
                                 status_template_id, owner_id, created_by)
        VALUES (@company_id, @name, @description, @privacy, @department_id, @workflow_id, @status_mode,
                @status_template_id, @owner_id, @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        INSERT [pm].[workspace_status] (workspace_id, status_group, name, color, sort_order, wip_limit, created_by)
        SELECT @id, status_group, name, color, sort_order, wip_limit, @actor_user_id FROM @st;

        INSERT [pm].[list_view] (workspace_id, view_type, name, is_default, is_required, sort_order, created_by)
        SELECT @id, v.view_type,
               CASE v.view_type WHEN N'mind_map' THEN N'Mind Map' ELSE UPPER(LEFT(v.view_type, 1)) + SUBSTRING(v.view_type, 2, 30) END,
               v.is_default, CASE WHEN v.view_type = N'list' THEN 1 ELSE 0 END, v.sort_order, @actor_user_id
        FROM @vw v;

        INSERT [pm].[workspace_feature] (workspace_id, feature_code, setting_value, created_by)
        SELECT @id, feature_code, setting_value, @actor_user_id FROM @ft;

        INSERT [pm].[workspace_member] (workspace_id, employee_id, member_role, created_by)
        SELECT @id, employee_id, member_role, @actor_user_id FROM @mb;

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @id, N'create', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_workspace_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
