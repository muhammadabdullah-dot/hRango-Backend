-- Workspace members and their workspace roles ("Invite Members", "Share Visibility" member list).
-- Workspace admins and HR manage members; only a workspace admin grants or removes the
-- workspace_admin role. The owner stays a workspace admin.

-- Adds members (or changes the role of ones already there). @members: [{"employee_id", "member_role"}]
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_member_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT,
    @members       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can manage members.', 1;

    DECLARE @mb TABLE (employee_id BIGINT PRIMARY KEY, member_role NVARCHAR(30));
    INSERT @mb SELECT j.employee_id, MAX(ISNULL(j.member_role, N'contributor'))
    FROM OPENJSON(ISNULL(@members, N'[]')) WITH (employee_id BIGINT '$.employee_id', member_role NVARCHAR(30) '$.member_role') j
    WHERE j.employee_id IS NOT NULL
    GROUP BY j.employee_id;

    IF NOT EXISTS (SELECT 1 FROM @mb)
        THROW 50400, N'members|Pick at least one employee.', 1;
    IF EXISTS (SELECT 1 FROM @mb m WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = m.employee_id AND e.company_id = @company_id))
        THROW 50400, N'members|An employee was not found.', 1;
    IF EXISTS (SELECT 1 FROM @mb WHERE member_role NOT IN (N'workspace_admin', N'hr', N'manager', N'team_leader', N'contributor'))
        THROW 50400, N'memberRole|Unknown workspace role.', 1;
    DECLARE @owner BIGINT = (SELECT owner_id FROM [pm].[workspace] WHERE id = @workspace_id);
    IF EXISTS (SELECT 1 FROM @mb WHERE employee_id = @owner AND member_role <> N'workspace_admin')
        THROW 50409, N'memberRole|The workspace owner stays a workspace admin.', 1;
    IF @rank < 5 AND (EXISTS (SELECT 1 FROM @mb WHERE member_role = N'workspace_admin')
                      OR EXISTS (SELECT 1 FROM @mb s JOIN [pm].[workspace_member] m ON m.employee_id = s.employee_id
                                 WHERE m.workspace_id = @workspace_id AND m.member_role = N'workspace_admin'))
        THROW 50403, N'Only a workspace admin can grant or change the workspace admin role.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pm.workspace', @workspace_id, N'member:' + CONVERT(NVARCHAR(30), s.employee_id), m.member_role, s.member_role,
               CASE WHEN m.employee_id IS NULL THEN N'member_add' ELSE N'member_role' END, @actor_user_id, @now
        FROM @mb s LEFT JOIN [pm].[workspace_member] m ON m.workspace_id = @workspace_id AND m.employee_id = s.employee_id
        WHERE m.employee_id IS NULL OR m.member_role <> s.member_role;

        UPDATE m SET member_role = s.member_role, updated_at = @now, updated_by = @actor_user_id
        FROM [pm].[workspace_member] m JOIN @mb s ON s.employee_id = m.employee_id
        WHERE m.workspace_id = @workspace_id AND m.member_role <> s.member_role;
        INSERT [pm].[workspace_member] (workspace_id, employee_id, member_role, created_by)
        SELECT @workspace_id, s.employee_id, s.member_role, @actor_user_id FROM @mb s
        WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @workspace_id AND m.employee_id = s.employee_id);
    COMMIT;

    EXEC [pm].[usp_workspace_member_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @workspace_id = @workspace_id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_workspace_member_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    SELECT m.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name, ds.name AS designation_name,
           dp.name AS department_name, m.member_role
    FROM [pm].[workspace_member] m
    JOIN [hr].[employee] e ON e.id = m.employee_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    WHERE m.workspace_id = @workspace_id
    ORDER BY CASE m.member_role WHEN N'workspace_admin' THEN 1 WHEN N'hr' THEN 2 WHEN N'manager' THEN 3
                                WHEN N'team_leader' THEN 4 ELSE 5 END, e.first_name, e.last_name;
END
GO

-- Removes a member ("Admin can remove the people from workspace"). Their task assignments stay.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_member_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can remove members.', 1;

    DECLARE @role NVARCHAR(30) = (SELECT member_role FROM [pm].[workspace_member] WHERE workspace_id = @workspace_id AND employee_id = @employee_id);
    IF @role IS NULL
        THROW 50404, N'Member not found', 1;
    IF @employee_id = (SELECT owner_id FROM [pm].[workspace] WHERE id = @workspace_id)
        THROW 50409, N'The workspace owner cannot be removed. Change the owner first.', 1;
    IF @role = N'workspace_admin' AND @rank < 5
        THROW 50403, N'Only a workspace admin can remove another workspace admin.', 1;

    BEGIN TRAN;
        DELETE [pm].[workspace_member] WHERE workspace_id = @workspace_id AND employee_id = @employee_id;
        DELETE [pm].[column_permission] WHERE workspace_id = @workspace_id AND employee_id = @employee_id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @workspace_id, N'member:' + CONVERT(NVARCHAR(30), @employee_id), @role, N'member_remove',
                @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
