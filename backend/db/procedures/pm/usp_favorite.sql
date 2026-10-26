-- Add to Favorites and Hide (per person) for workspaces, folders, lists and tasks.

-- The caller's favourites, with names, newest first.
CREATE OR ALTER PROCEDURE [pm].[usp_favorite_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @kind          NVARCHAR(30) = N'favorite'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    SELECT f.id, f.entity_type, f.entity_id, f.kind, x.name, x.workspace_id, f.created_at
    FROM [pm].[favorite] f
    CROSS APPLY (
        SELECT w.name, w.id AS workspace_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) a
        JOIN [pm].[workspace] w ON w.id = a.workspace_id WHERE f.entity_type = N'workspace' AND w.id = f.entity_id
        UNION ALL
        SELECT d.name, d.workspace_id FROM [pm].[folder] d
        JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = d.workspace_id
        WHERE f.entity_type = N'folder' AND d.id = f.entity_id
        UNION ALL
        SELECT l.name, l.workspace_id FROM [pm].[task_list] l
        JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = l.workspace_id
        WHERE f.entity_type = N'task_list' AND l.id = f.entity_id
        UNION ALL
        SELECT t.name, t.workspace_id FROM [pm].[task] t
        JOIN [pm].[fn_task_access](@company_id, @actor_user_id) a ON a.task_id = t.id
        WHERE f.entity_type = N'task' AND t.id = f.entity_id
    ) x
    WHERE f.employee_id = @me AND f.kind = @kind
    ORDER BY f.created_at DESC, f.id DESC;
END
GO

-- Turns a mark on or off for the caller. The item must be one they can open.
CREATE OR ALTER PROCEDURE [pm].[usp_favorite_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @entity_type   NVARCHAR(50),
    @entity_id     BIGINT,
    @kind          NVARCHAR(30) = N'favorite',
    @is_on         BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @me IS NULL
        THROW 50403, N'Only employees can keep favourites.', 1;
    IF @kind NOT IN (N'favorite', N'hidden')
        THROW 50400, N'kind|Choose favorite or hidden.', 1;
    IF @kind = N'hidden' AND @entity_type <> N'workspace'
        THROW 50400, N'entityType|Only workspaces can be hidden.', 1;
    IF NOT (   (@entity_type = N'workspace' AND EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @entity_id))
            OR (@entity_type = N'folder' AND EXISTS (SELECT 1 FROM [pm].[folder] d JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a
                                                    ON a.workspace_id = d.workspace_id WHERE d.id = @entity_id))
            OR (@entity_type = N'task_list' AND EXISTS (SELECT 1 FROM [pm].[task_list] l JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a
                                                       ON a.workspace_id = l.workspace_id WHERE l.id = @entity_id))
            OR (@entity_type = N'task' AND EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @entity_id)))
        THROW 50404, N'Item not found', 1;

    IF @is_on = 1
        INSERT [pm].[favorite] (employee_id, entity_type, entity_id, kind, created_by)
        SELECT @me, @entity_type, @entity_id, @kind, @actor_user_id
        WHERE NOT EXISTS (SELECT 1 FROM [pm].[favorite] WHERE employee_id = @me AND entity_type = @entity_type
                          AND entity_id = @entity_id AND kind = @kind);
    ELSE
        DELETE [pm].[favorite] WHERE employee_id = @me AND entity_type = @entity_type AND entity_id = @entity_id AND kind = @kind;
END
