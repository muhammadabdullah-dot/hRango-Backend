-- Folders and lists of a workspace ("Create New: List, Folder"). Managers and above.
-- Names are unique within the workspace (BRD).

CREATE OR ALTER PROCEDURE [pm].[usp_folder_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @workspace_id  BIGINT = NULL,
    @name          NVARCHAR(200),
    @sort_order    INT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @id IS NOT NULL
        SET @workspace_id = (SELECT workspace_id FROM [pm].[folder] WHERE id = @id);
    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Folder not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can manage folders.', 1;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Folder name is required.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[folder] WHERE workspace_id = @workspace_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|FOLDER_DUPLICATE|A folder with this name already exists in this workspace.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        INSERT [pm].[folder] (workspace_id, name, sort_order, created_by)
        VALUES (@workspace_id, @name, ISNULL(@sort_order, ISNULL((SELECT MAX(sort_order) FROM [pm].[folder] WHERE workspace_id = @workspace_id), 0) + 10),
                @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [pm].[folder] SET name = @name, sort_order = ISNULL(@sort_order, sort_order), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this folder. Reload it and try again', 1;
    END

    SELECT f.id, f.workspace_id, f.name, f.sort_order, f.row_version FROM [pm].[folder] f WHERE f.id = @id;
END
GO

-- Deletes a folder. Its lists move to the workspace's top level.
CREATE OR ALTER PROCEDURE [pm].[usp_folder_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @workspace_id BIGINT, @rv BINARY(8), @rank INT;
    SELECT @workspace_id = workspace_id, @rv = row_version FROM [pm].[folder] WHERE id = @id;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Folder not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can manage folders.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this folder. Reload it and try again', 1;

    BEGIN TRAN;
        UPDATE [pm].[task_list] SET folder_id = NULL, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id WHERE folder_id = @id;
        UPDATE [pm].[doc] SET folder_id = NULL WHERE folder_id = @id;
        DELETE [pm].[recent_item] WHERE entity_type = N'folder' AND entity_id = @id;
        DELETE [pm].[favorite] WHERE entity_type = N'folder' AND entity_id = @id;
        DELETE [pm].[folder] WHERE id = @id;
    COMMIT;
END
GO

-- A list (the BRD's "project"): name, folder, privacy, colour, description (500), priority, start and end.
-- @member_ids: JSON array of employee ids who may see a private list.
CREATE OR ALTER PROCEDURE [pm].[usp_list_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @workspace_id  BIGINT = NULL,
    @folder_id     BIGINT = NULL,
    @name          NVARCHAR(200),
    @privacy       NVARCHAR(30) = NULL,
    @color         NVARCHAR(20) = NULL,
    @description   NVARCHAR(MAX) = NULL,
    @start_at      DATETIME2(0) = NULL,
    @end_at        DATETIME2(0) = NULL,
    @priority      NVARCHAR(30) = NULL,
    @sort_order    INT = NULL,
    @member_ids    NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @id IS NOT NULL
        SET @workspace_id = (SELECT workspace_id FROM [pm].[task_list] WHERE id = @id);
    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'List not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can manage lists.', 1;

    SET @name = LTRIM(RTRIM(@name));
    SET @privacy = ISNULL(@privacy, N'workspace');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|List name is required.', 1;
    IF @privacy NOT IN (N'private', N'workspace', N'public')
        THROW 50400, N'privacy|Choose who can see this list.', 1;
    IF LEN(@description) > 500
        THROW 50400, N'description|Description must be within 500 characters.', 1;
    IF @priority IS NOT NULL AND @priority NOT IN (N'urgent', N'high', N'normal', N'low')
        THROW 50400, N'priority|Choose Urgent, High, Normal or Low.', 1;
    IF @start_at IS NOT NULL AND @end_at IS NOT NULL AND @end_at <= @start_at
        THROW 50400, N'endAt|End must be after the start.', 1;
    IF @folder_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[folder] WHERE id = @folder_id AND workspace_id = @workspace_id)
        THROW 50400, N'folderId|Folder not found in this workspace.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[task_list] WHERE workspace_id = @workspace_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|LIST_DUPLICATE|A list with this name already exists in this workspace.', 1;

    DECLARE @mb TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @mb SELECT DISTINCT CAST(value AS BIGINT) FROM OPENJSON(ISNULL(@member_ids, N'[]'));
    IF EXISTS (SELECT 1 FROM @mb m WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] w WHERE w.workspace_id = @workspace_id AND w.employee_id = m.employee_id))
        THROW 50400, N'memberIds|List members must be workspace members.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pm].[task_list] (workspace_id, folder_id, name, privacy, color, description, start_at, end_at, priority, sort_order, created_by)
            VALUES (@workspace_id, @folder_id, @name, @privacy, @color, @description, @start_at, @end_at, @priority,
                    ISNULL(@sort_order, ISNULL((SELECT MAX(sort_order) FROM [pm].[task_list] WHERE workspace_id = @workspace_id), 0) + 10),
                    @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            IF @row_version IS NULL
                THROW 50400, N'rowVersion is required to edit a list', 1;
            UPDATE [pm].[task_list]
            SET folder_id = @folder_id, name = @name, privacy = @privacy, color = @color, description = @description,
                start_at = @start_at, end_at = @end_at, priority = @priority, sort_order = ISNULL(@sort_order, sort_order),
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this list. Reload it and try again', 1;
        END

        IF @member_ids IS NOT NULL
        BEGIN
            DELETE m FROM [pm].[task_list_member] m WHERE m.task_list_id = @id AND m.employee_id NOT IN (SELECT employee_id FROM @mb);
            INSERT [pm].[task_list_member] (task_list_id, employee_id, created_by)
            SELECT @id, employee_id, @actor_user_id FROM @mb s
            WHERE NOT EXISTS (SELECT 1 FROM [pm].[task_list_member] m WHERE m.task_list_id = @id AND m.employee_id = s.employee_id);
        END
    COMMIT;

    SELECT l.id, l.workspace_id, l.folder_id, l.name, l.privacy, l.color, l.description, l.start_at, l.end_at, l.priority, l.sort_order,
           (SELECT COUNT(*) FROM [pm].[task] t WHERE t.task_list_id = l.id) AS task_count,
           (SELECT COUNT(*) FROM [pm].[task] t JOIN [pm].[workspace_status] s ON s.id = t.status_id
            WHERE t.task_list_id = l.id AND s.status_group IN (N'done', N'closed')) AS closed_count,
           ISNULL(l.updated_at, l.created_at) AS last_modified_at,
           (SELECT lm.employee_id FROM [pm].[task_list_member] lm WHERE lm.task_list_id = l.id FOR JSON PATH) AS members_json,
           l.row_version
    FROM [pm].[task_list] l WHERE l.id = @id;
END
GO

-- Deletes a list. Lists that still hold tasks are refused (move or delete the tasks first).
CREATE OR ALTER PROCEDURE [pm].[usp_list_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @workspace_id BIGINT, @rv BINARY(8), @rank INT;
    SELECT @workspace_id = workspace_id, @rv = row_version FROM [pm].[task_list] WHERE id = @id;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'List not found', 1;
    IF @rank < 3
        THROW 50403, N'Only managers and above can manage lists.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this list. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [pm].[task] WHERE task_list_id = @id)
        THROW 50409, N'This list still has tasks. Move or delete them first', 1;

    BEGIN TRAN;
        DELETE [pm].[task_list_member] WHERE task_list_id = @id;
        DELETE [pm].[list_view] WHERE task_list_id = @id;
        DELETE [pm].[favorite] WHERE entity_type = N'task_list' AND entity_id = @id;
        DELETE [pm].[reminder] WHERE entity_type = N'task_list' AND entity_id = @id;
        DELETE m FROM [pm].[share_member] m JOIN [pm].[share_link] s ON s.id = m.share_link_id WHERE s.entity_type = N'task_list' AND s.entity_id = @id;
        DELETE x FROM [pm].[share_access] x JOIN [pm].[share_link] s ON s.id = x.share_link_id WHERE s.entity_type = N'task_list' AND s.entity_id = @id;
        DELETE [pm].[share_link] WHERE entity_type = N'task_list' AND entity_id = @id;
        UPDATE [pm].[doc] SET task_list_id = NULL WHERE task_list_id = @id;
        DELETE [pm].[recent_item] WHERE entity_type = N'task_list' AND entity_id = @id;
        DELETE [pm].[task_list] WHERE id = @id;
    COMMIT;
END
