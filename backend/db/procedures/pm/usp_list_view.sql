-- Views of a workspace or list (view bar: List, Board, ... "+ View"; Customize View: name, pin,
-- private, protect, default; config holds columns, filters, sort, grouping, subtask display).
-- Shared views are managed by workspace admins and HR; anyone in the workspace keeps private views.

CREATE OR ALTER PROCEDURE [pm].[usp_list_view_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT;
    SELECT @me = a.employee_id FROM [pm].[list_view] v
    JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = v.workspace_id
    WHERE v.id = @id AND (v.is_private = 0 OR v.owner_id = a.employee_id);
    IF @@ROWCOUNT = 0
        THROW 50404, N'View not found', 1;

    SELECT v.id, v.workspace_id, v.task_list_id, v.view_type, v.name, v.config, v.is_pinned, v.is_private, v.is_protected,
           v.is_default, v.is_required, v.sort_order, v.owner_id, v.row_version
    FROM [pm].[list_view] v WHERE v.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_list_view_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @workspace_id  BIGINT = NULL,
    @task_list_id  BIGINT = NULL,
    @view_type     NVARCHAR(30),
    @name          NVARCHAR(200),
    @config        NVARCHAR(MAX) = NULL,
    @is_pinned     BIT = 0,
    @is_private    BIT = 0,
    @is_protected  BIT = 0,
    @is_default    BIT = 0,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @old_private BIT, @old_owner BIGINT, @old_protected BIT, @old_type NVARCHAR(30), @required BIT;
    IF @id IS NOT NULL
        SELECT @workspace_id = workspace_id, @task_list_id = task_list_id, @old_private = is_private, @old_owner = owner_id,
               @old_protected = is_protected, @old_type = view_type, @required = is_required
        FROM [pm].[list_view] WHERE id = @id;

    DECLARE @rank INT, @me BIGINT;
    SELECT @rank = role_rank, @me = employee_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL OR (@old_private = 1 AND @old_owner <> ISNULL(@me, 0))
        THROW 50404, N'View not found', 1;
    -- Shared views: workspace admins and HR. Private views: their owner (a workspace member).
    IF ((@id IS NULL AND @is_private = 0) OR (@id IS NOT NULL AND (@old_private = 0 OR @is_private = 0))) AND @rank < 4
        THROW 50403, N'Only workspace admins and HR can change shared views.', 1;
    IF @is_private = 1 AND @rank < 1
        THROW 50403, N'Only workspace members can keep views.', 1;
    IF @old_protected = 1 AND @rank < 4
        THROW 50403, N'This view is protected.', 1;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|View name is required.', 1;
    IF @view_type NOT IN (N'list', N'board', N'calendar', N'map', N'activity', N'team', N'table', N'timeline',
                          N'gantt', N'mind_map', N'workload', N'custom')
        THROW 50400, N'viewType|Unknown view.', 1;
    IF @required = 1 AND @view_type <> @old_type
        THROW 50409, N'viewType|The List view is always required.', 1;
    IF @task_list_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[task_list] WHERE id = @task_list_id AND workspace_id = @workspace_id)
        THROW 50400, N'taskListId|List not found in this workspace.', 1;
    IF @config IS NOT NULL AND ISJSON(@config) = 0
        THROW 50400, N'config|View settings are not valid.', 1;
    IF @view_type = N'custom' AND EXISTS (SELECT 1 FROM [pm].[list_view] WHERE workspace_id = @workspace_id
            AND ISNULL(task_list_id, 0) = ISNULL(@task_list_id, 0) AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|VIEW_DUPLICATE|A view with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @is_default = 1 AND @is_private = 0
            UPDATE [pm].[list_view] SET is_default = 0
            WHERE workspace_id = @workspace_id AND ISNULL(task_list_id, 0) = ISNULL(@task_list_id, 0) AND is_default = 1 AND ISNULL(id, 0) <> ISNULL(@id, 0);

        IF @id IS NULL
        BEGIN
            INSERT [pm].[list_view] (workspace_id, task_list_id, owner_id, view_type, name, config, is_pinned, is_private,
                                     is_protected, is_default, is_required, sort_order, created_by)
            VALUES (@workspace_id, @task_list_id, CASE WHEN @is_private = 1 THEN @me END, @view_type, @name, @config, @is_pinned,
                    @is_private, @is_protected, CASE WHEN @is_private = 1 THEN 0 ELSE @is_default END, 0,
                    ISNULL((SELECT MAX(sort_order) FROM [pm].[list_view] WHERE workspace_id = @workspace_id), 0) + 10, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            IF @row_version IS NULL
                THROW 50400, N'rowVersion is required to edit a view', 1;
            UPDATE [pm].[list_view]
            SET view_type = @view_type, name = @name, config = @config, is_pinned = @is_pinned, is_private = @is_private,
                owner_id = CASE WHEN @is_private = 1 THEN ISNULL(owner_id, @me) ELSE owner_id END,
                is_protected = @is_protected, is_default = CASE WHEN @is_private = 1 THEN 0 ELSE @is_default END,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this view. Reload it and try again', 1;
        END
    COMMIT;

    EXEC [pm].[usp_list_view_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_list_view_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @workspace_id BIGINT, @private BIT, @owner BIGINT, @protected BIT, @required BIT, @rv BINARY(8), @rank INT, @me BIGINT;
    SELECT @workspace_id = workspace_id, @private = is_private, @owner = owner_id, @protected = is_protected,
           @required = is_required, @rv = row_version
    FROM [pm].[list_view] WHERE id = @id;
    SELECT @rank = role_rank, @me = employee_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL OR (@private = 1 AND @owner <> ISNULL(@me, 0))
        THROW 50404, N'View not found', 1;
    IF @private = 0 AND @rank < 4
        THROW 50403, N'Only workspace admins and HR can delete shared views.', 1;
    IF @required = 1
        THROW 50409, N'The List view is required and cannot be deleted.', 1;
    IF @protected = 1
        THROW 50409, N'This view is protected. Unprotect it first.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this view. Reload it and try again', 1;

    DELETE [pm].[list_view] WHERE id = @id;
END
