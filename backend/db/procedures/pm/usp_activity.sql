-- History (BRD "Maintain History"): what happened, to which item, by whom and when, newest first,
-- with filter by action and date and a search over item, field and values. Read from core.audit_log.

-- One task's history. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [pm].[usp_task_activity]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_id       BIGINT,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id)
        THROW 50404, N'Task not found', 1;

    SELECT COUNT(*) AS total FROM [core].[audit_log] WHERE entity_type = N'pm.task' AND entity_id = @task_id;

    SELECT l.id, l.entity_type, l.entity_id, t.code AS item_code, t.name AS item_name, l.action_name, l.field_name,
           l.old_value, l.new_value, l.performed_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS performed_by_name, l.performed_at
    FROM [core].[audit_log] l
    JOIN [pm].[task] t ON t.id = l.entity_id
    LEFT JOIN [auth].[user_account] u ON u.id = l.performed_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE l.entity_type = N'pm.task' AND l.entity_id = @task_id
    ORDER BY l.performed_at DESC, l.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- A workspace's history: changes to the workspace itself and to the tasks the caller can see.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_activity]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT,
    @action_name   NVARCHAR(50) = NULL,
    @from_date     DATE = NULL,
    @to_date       DATE = NULL,
    @search        NVARCHAR(200) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    CREATE TABLE #a (id BIGINT PRIMARY KEY, item_code NVARCHAR(30), item_name NVARCHAR(200));
    INSERT #a
    SELECT l.id, NULL, w.name
    FROM [core].[audit_log] l JOIN [pm].[workspace] w ON w.id = l.entity_id
    WHERE l.entity_type = N'pm.workspace' AND l.entity_id = @workspace_id
    UNION ALL
    SELECT l.id, t.code, t.name
    FROM [core].[audit_log] l
    JOIN [pm].[task] t ON t.id = l.entity_id
    JOIN [pm].[fn_task_access](@company_id, @actor_user_id) a ON a.task_id = t.id
    WHERE l.entity_type = N'pm.task' AND t.workspace_id = @workspace_id;

    SELECT COUNT(*) AS total
    FROM #a x JOIN [core].[audit_log] l ON l.id = x.id
    WHERE (@action_name IS NULL OR l.action_name = @action_name)
      AND (@from_date IS NULL OR l.performed_at >= @from_date)
      AND (@to_date IS NULL OR l.performed_at < DATEADD(DAY, 1, CAST(@to_date AS DATETIME2(0))))
      AND (@pattern IS NULL OR x.item_name LIKE @pattern OR x.item_code LIKE @pattern OR l.field_name LIKE @pattern
           OR l.old_value LIKE @pattern OR l.new_value LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT l.id, l.entity_type, l.entity_id, x.item_code, x.item_name, l.action_name, l.field_name, l.old_value, l.new_value,
           l.performed_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS performed_by_name, l.performed_at
    FROM #a x
    JOIN [core].[audit_log] l ON l.id = x.id
    LEFT JOIN [auth].[user_account] u ON u.id = l.performed_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE (@action_name IS NULL OR l.action_name = @action_name)
      AND (@from_date IS NULL OR l.performed_at >= @from_date)
      AND (@to_date IS NULL OR l.performed_at < DATEADD(DAY, 1, CAST(@to_date AS DATETIME2(0))))
      AND (@pattern IS NULL OR x.item_name LIKE @pattern OR x.item_code LIKE @pattern OR l.field_name LIKE @pattern
           OR l.old_value LIKE @pattern OR l.new_value LIKE @pattern)
    ORDER BY l.performed_at DESC, l.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
