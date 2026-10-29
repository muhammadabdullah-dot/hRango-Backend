-- Sharing & Permissions of a task, list or workspace: people with Full Edit / Limited / Commenter,
-- invites by email, the private link, "Share link with anyone" with a validity period and an access
-- limit, and the task properties shown. Public links open /api/public/shares/{token} (usp_public_share.sql); no email is sent yet.
-- Managers and above change sharing.

CREATE OR ALTER PROCEDURE [pm].[usp_share_link_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @entity_type   NVARCHAR(50),
    @entity_id     BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ws BIGINT;
    IF @entity_type = N'task'
        SELECT @ws = workspace_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @entity_id;
    ELSE IF @entity_type = N'task_list'
        SELECT @ws = a.workspace_id FROM [pm].[task_list] l JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = l.workspace_id WHERE l.id = @entity_id;
    ELSE IF @entity_type = N'workspace'
        SELECT @ws = workspace_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @entity_id;
    IF @ws IS NULL
        THROW 50404, N'Item not found', 1;

    SELECT s.id, s.workspace_id, s.entity_type, s.entity_id, s.share_scope, s.token, s.is_public, s.allow_open_tasks,
           s.valid_from, s.valid_to, s.max_access,
           (SELECT COUNT(*) FROM [pm].[share_access] x WHERE x.share_link_id = s.id) AS access_count, s.properties, s.row_version
    FROM [pm].[share_link] s WHERE s.entity_type = @entity_type AND s.entity_id = @entity_id;

    SELECT m.id, m.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, m.email, m.access_level
    FROM [pm].[share_member] m
    JOIN [pm].[share_link] s ON s.id = m.share_link_id
    LEFT JOIN [hr].[employee] e ON e.id = m.employee_id
    WHERE s.entity_type = @entity_type AND s.entity_id = @entity_id
    ORDER BY m.id;
END
GO

-- Saves the sharing settings (first save creates the link with @token).
-- @members: [{"employee_id" or "email", "access_level"}]; @properties: JSON array of property codes.
CREATE OR ALTER PROCEDURE [pm].[usp_share_link_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @entity_type      NVARCHAR(50),
    @entity_id        BIGINT,
    @token            NVARCHAR(100),
    @share_scope      NVARCHAR(30) = N'list',
    @is_public        BIT = 0,
    @allow_open_tasks BIT = 1,
    @valid_from       DATETIME2(0) = NULL,
    @valid_to         DATETIME2(0) = NULL,
    @max_access       INT = NULL,
    @properties       NVARCHAR(MAX) = NULL,
    @members          NVARCHAR(MAX) = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT;
    IF @entity_type = N'task'
        SELECT @ws = workspace_id, @rank = role_rank FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @entity_id;
    ELSE IF @entity_type = N'task_list'
        SELECT @ws = a.workspace_id, @rank = a.role_rank FROM [pm].[task_list] l
        JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = l.workspace_id WHERE l.id = @entity_id;
    ELSE IF @entity_type = N'workspace'
        SELECT @ws = workspace_id, @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @entity_id;
    ELSE
        THROW 50400, N'entityType|Share a task, list or workspace.', 1;
    IF @ws IS NULL
        THROW 50404, N'Item not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can change sharing.', 1;

    IF @share_scope NOT IN (N'list', N'page')
        THROW 50400, N'shareScope|Share as a single list view or as a whole page.', 1;
    IF @valid_from IS NOT NULL AND @valid_to IS NOT NULL AND @valid_to <= @valid_from
        THROW 50400, N'validTo|The link must expire after it begins.', 1;
    IF @max_access IS NOT NULL AND @max_access < 1
        THROW 50400, N'maxAccess|Allow at least one access.', 1;
    IF @properties IS NOT NULL AND ISJSON(@properties) = 0
        THROW 50400, N'properties|Task properties are not valid.', 1;

    DECLARE @mb TABLE (employee_id BIGINT, email NVARCHAR(254), access_level NVARCHAR(30));
    INSERT @mb SELECT j.employee_id, NULLIF(LTRIM(RTRIM(j.email)), N''), j.access_level
    FROM OPENJSON(ISNULL(@members, N'[]')) WITH (employee_id BIGINT '$.employee_id', email NVARCHAR(254) '$.email',
                                                 access_level NVARCHAR(30) '$.access_level') j;
    IF EXISTS (SELECT 1 FROM @mb WHERE ISNULL(access_level, N'') NOT IN (N'full_edit', N'limited', N'commenter'))
        THROW 50400, N'members|Choose Full Edit, Limited or Commenter.', 1;
    IF EXISTS (SELECT 1 FROM @mb WHERE employee_id IS NULL AND (email IS NULL OR email NOT LIKE N'%_@_%._%' OR email LIKE N'% %'))
        THROW 50400, N'members|Enter a valid email address.', 1;
    IF EXISTS (SELECT 1 FROM @mb m WHERE m.employee_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = m.employee_id AND e.company_id = @company_id))
        THROW 50400, N'members|A person was not found.', 1;

    DECLARE @id BIGINT, @rv BINARY(8), @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @id = id, @rv = row_version FROM [pm].[share_link] WHERE entity_type = @entity_type AND entity_id = @entity_id;
    IF @id IS NOT NULL AND @rv <> ISNULL(@row_version, 0x)
        THROW 50409, N'Someone else changed the sharing settings. Reload them and try again', 1;

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pm].[share_link] (workspace_id, entity_type, entity_id, share_scope, token, is_public, allow_open_tasks,
                                      valid_from, valid_to, max_access, access_count, properties, created_by)
            VALUES (@ws, @entity_type, @entity_id, @share_scope, @token, @is_public, @allow_open_tasks, @valid_from, @valid_to,
                    @max_access, 0, @properties, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
            UPDATE [pm].[share_link]
            SET share_scope = @share_scope, is_public = @is_public, allow_open_tasks = @allow_open_tasks, valid_from = @valid_from,
                valid_to = @valid_to, max_access = @max_access, properties = @properties, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id;

        DELETE [pm].[share_member] WHERE share_link_id = @id;
        INSERT [pm].[share_member] (share_link_id, employee_id, email, access_level, created_by)
        SELECT @id, employee_id, CASE WHEN employee_id IS NULL THEN email END, access_level, @actor_user_id FROM @mb;
    COMMIT;

    EXEC [pm].[usp_share_link_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @entity_type = @entity_type, @entity_id = @entity_id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_share_link_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT = (SELECT workspace_id FROM [pm].[share_link] WHERE id = @id);
    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @ws;
    IF @rank IS NULL
        THROW 50404, N'Share link not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can change sharing.', 1;

    BEGIN TRAN;
        DELETE [pm].[share_member] WHERE share_link_id = @id;
        DELETE [pm].[share_access] WHERE share_link_id = @id;
        DELETE [pm].[share_link] WHERE id = @id;
    COMMIT;
END
