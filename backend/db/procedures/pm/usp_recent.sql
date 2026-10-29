-- Recents (Backend Dependencies T7): what the signed-in person opened lately (a workspace, folder, list,
-- task or doc). The screens record a visit when an item opens; the newest 50 per person are kept. Items
-- the person can no longer open (deleted, privacy changed) drop out of the list.

CREATE OR ALTER PROCEDURE [pm].[usp_recent_record]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @entity_type   NVARCHAR(50),
    @entity_id     BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT;
    IF @entity_type = N'workspace'
        SELECT @ws = workspace_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @entity_id;
    ELSE IF @entity_type = N'folder'
        SELECT @ws = a.workspace_id FROM [pm].[folder] f
        JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = f.workspace_id WHERE f.id = @entity_id;
    ELSE IF @entity_type = N'task_list'
        SELECT @ws = a.workspace_id FROM [pm].[task_list] l
        JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = l.workspace_id
        WHERE l.id = @entity_id
          AND (ISNULL(l.privacy, N'workspace') <> N'private' OR a.role_rank >= 4
               OR EXISTS (SELECT 1 FROM [pm].[task_list_member] m WHERE m.task_list_id = l.id AND m.employee_id = a.employee_id));
    ELSE IF @entity_type = N'task'
        SELECT @ws = workspace_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @entity_id;
    ELSE IF @entity_type = N'doc'
        SELECT @ws = workspace_id FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @entity_id;
    ELSE
        THROW 50400, N'entityType|Record a workspace, folder, list, task or doc.', 1;
    IF @ws IS NULL
        THROW 50404, N'Item not found', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [pm].[recent_item] SET opened_at = @now, workspace_id = @ws, updated_at = @now
        WHERE user_account_id = @actor_user_id AND entity_type = @entity_type AND entity_id = @entity_id;
        IF @@ROWCOUNT = 0
            INSERT [pm].[recent_item] (company_id, user_account_id, entity_type, entity_id, workspace_id, opened_at, created_by)
            VALUES (@company_id, @actor_user_id, @entity_type, @entity_id, @ws, @now, @actor_user_id);
        DELETE r FROM [pm].[recent_item] r
        WHERE r.user_account_id = @actor_user_id AND r.company_id = @company_id
          AND r.id NOT IN (SELECT TOP 50 x.id FROM [pm].[recent_item] x WHERE x.user_account_id = @actor_user_id AND x.company_id = @company_id
                           ORDER BY x.opened_at DESC, x.id DESC);
    COMMIT;
END
GO

-- Newest first. @workspace_id: items of one workspace; @folder_id: the folder, its lists, their tasks and
-- its docs.
CREATE OR ALTER PROCEDURE [pm].[usp_recent_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT = NULL,
    @folder_id     BIGINT = NULL,
    @limit         INT = 8
AS
BEGIN
    SET NOCOUNT ON;

    SET @limit = CASE WHEN @limit IS NULL OR @limit < 1 THEN 8 WHEN @limit > 50 THEN 50 ELSE @limit END;

    WITH r AS (
        SELECT ri.entity_type, ri.entity_id, ri.opened_at, ri.id,
               CASE ri.entity_type WHEN N'workspace' THEN w0.name WHEN N'folder' THEN f.name WHEN N'task_list' THEN l.name
                                   WHEN N'task' THEN t.name WHEN N'doc' THEN d.title END AS name,
               CASE ri.entity_type WHEN N'workspace' THEN w0.id WHEN N'folder' THEN f.workspace_id WHEN N'task_list' THEN l.workspace_id
                                   WHEN N'task' THEN t.workspace_id WHEN N'doc' THEN d.workspace_id END AS workspace_id,
               CASE ri.entity_type WHEN N'folder' THEN f.id WHEN N'task_list' THEN l.folder_id WHEN N'task' THEN tl.folder_id
                                   WHEN N'doc' THEN COALESCE(d.folder_id, dl.folder_id) END AS folder_id
        FROM [pm].[recent_item] ri
        LEFT JOIN [pm].[workspace] w0 ON ri.entity_type = N'workspace' AND w0.id = ri.entity_id
        LEFT JOIN [pm].[folder] f ON ri.entity_type = N'folder' AND f.id = ri.entity_id
        LEFT JOIN [pm].[task_list] l ON ri.entity_type = N'task_list' AND l.id = ri.entity_id
        LEFT JOIN [pm].[task] t ON ri.entity_type = N'task' AND t.id = ri.entity_id
        LEFT JOIN [pm].[task_list] tl ON tl.id = t.task_list_id
        LEFT JOIN [pm].[doc] d ON ri.entity_type = N'doc' AND d.id = ri.entity_id
        LEFT JOIN [pm].[task_list] dl ON dl.id = d.task_list_id
        WHERE ri.user_account_id = @actor_user_id AND ri.company_id = @company_id
    )
    SELECT TOP (@limit) r.entity_type, r.entity_id, r.name, r.workspace_id, w.name AS workspace_name, r.opened_at
    FROM r
    JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = r.workspace_id
    JOIN [pm].[workspace] w ON w.id = r.workspace_id
    WHERE r.name IS NOT NULL
      AND (@workspace_id IS NULL OR r.workspace_id = @workspace_id)
      AND (@folder_id IS NULL OR r.folder_id = @folder_id)
      AND (r.entity_type <> N'task' OR EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) x WHERE x.task_id = r.entity_id))
      AND (r.entity_type <> N'doc' OR EXISTS (SELECT 1 FROM [pm].[fn_doc_access](@company_id, @actor_user_id) x WHERE x.doc_id = r.entity_id))
    ORDER BY r.opened_at DESC, r.id DESC
    OPTION (RECOMPILE);
END
