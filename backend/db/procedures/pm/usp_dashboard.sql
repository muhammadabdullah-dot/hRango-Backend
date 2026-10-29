-- Dashboard aggregates (Backend Dependencies T7), for large workspaces; the screens can also compute them
-- from the task lists. Weeks start on Sunday. Only tasks the caller can see count (pm.fn_task_access).

-- Home dashboard of the signed-in person, across their workspaces. Result sets:
-- 1 recents (pm.usp_recent_list), 2 agenda (open tasks assigned to them due in the next 7 days),
-- 3 my work (their open tasks as task rows, 50 at most), 4 column levels of those tasks' workspaces
-- (the service hides private columns), 5 comments assigned to them and not resolved (20 at most),
-- 6 activity: per day of the last 14, tasks of theirs completed and tasks assigned to them.
CREATE OR ALTER PROCEDURE [pm].[usp_dashboard_home]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @today         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @today = ISNULL(@today, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    EXEC [pm].[usp_recent_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @limit = 8;

    CREATE TABLE #mine (task_id BIGINT PRIMARY KEY, workspace_id BIGINT, due_date DATE, due_time TIME(0), is_open BIT, closed_at DATETIME2(0));
    INSERT #mine
    SELECT t.id, t.workspace_id, t.due_date, t.due_time,
           CASE WHEN s.status_group IN (N'done', N'closed') THEN 0 ELSE 1 END, t.closed_at
    FROM [pm].[fn_task_access](@company_id, @actor_user_id) a
    JOIN [pm].[task] t ON t.id = a.task_id
    JOIN [pm].[workspace_status] s ON s.id = t.status_id
    WHERE @me IS NOT NULL AND EXISTS (SELECT 1 FROM [pm].[task_assignee] x WHERE x.task_id = t.id AND x.employee_id = @me);

    SELECT m.task_id, t.name, m.due_date, m.due_time, m.workspace_id
    FROM #mine m JOIN [pm].[task] t ON t.id = m.task_id
    WHERE m.is_open = 1 AND m.due_date BETWEEN @today AND DATEADD(DAY, 6, @today)
    ORDER BY m.due_date, CASE WHEN m.due_time IS NULL THEN 1 ELSE 0 END, m.due_time, m.task_id;

    SELECT TOP 50 r.*
    FROM #mine m JOIN [pm].[fn_task_rows](@company_id) r ON r.id = m.task_id
    WHERE m.is_open = 1
    ORDER BY CASE WHEN m.due_date IS NULL THEN 1 ELSE 0 END, m.due_date, m.task_id;

    SELECT w.workspace_id, l.column_key, l.permission_level
    FROM (SELECT DISTINCT workspace_id FROM #mine WHERE is_open = 1) w
    CROSS APPLY [pm].[fn_column_levels](w.workspace_id, @me) l;

    SELECT TOP 20 c.id, c.task_id, c.parent_id, c.author_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS author_name, c.body,
           c.assigned_to_id, NULLIF(CONCAT(t.first_name, N' ', t.last_name), N' ') AS assigned_to_name,
           c.assigned_by_id, NULLIF(CONCAT(b.first_name, N' ', b.last_name), N' ') AS assigned_by_name,
           CAST(0 AS BIT) AS is_resolved, c.resolved_by_id, CAST(NULL AS NVARCHAR(200)) AS resolved_by_name, c.resolved_at,
           c.edited_at, c.created_at,
           (SELECT COUNT(*) FROM [pm].[task_comment] x WHERE x.parent_id = c.id) AS reply_count,
           (SELECT x.employee_id, x.reaction FROM [pm].[comment_reaction] x WHERE x.comment_id = c.id FOR JSON PATH) AS reactions_json,
           (SELECT m.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name, m.mentioned_task_id AS task_id,
                   mt.code AS task_code, mt.name AS task_name
            FROM [pm].[comment_mention] m
            LEFT JOIN [hr].[employee] e ON e.id = m.employee_id
            LEFT JOIN [pm].[task] mt ON mt.id = m.mentioned_task_id
            WHERE m.comment_id = c.id FOR JSON PATH) AS mentions_json,
           c.row_version
    FROM [pm].[task_comment] c
    JOIN [pm].[fn_task_access](@company_id, @actor_user_id) ta ON ta.task_id = c.task_id
    JOIN [hr].[employee] a ON a.id = c.author_id
    LEFT JOIN [hr].[employee] t ON t.id = c.assigned_to_id
    LEFT JOIN [hr].[employee] b ON b.id = c.assigned_by_id
    WHERE @me IS NOT NULL AND c.assigned_to_id = @me AND c.resolved_at IS NULL
    ORDER BY c.created_at DESC, c.id DESC;

    WITH days AS (
        SELECT DATEADD(DAY, -13, @today) AS d
        UNION ALL
        SELECT DATEADD(DAY, 1, d) FROM days WHERE d < @today
    )
    SELECT days.d AS [date],
           (SELECT COUNT(*) FROM #mine m WHERE CAST(m.closed_at AS DATE) = days.d) AS completed,
           (SELECT COUNT(*) FROM [pm].[task_assignee] x JOIN #mine m ON m.task_id = x.task_id
            WHERE x.employee_id = @me AND CAST(x.created_at AS DATE) = days.d) AS assigned
    FROM days
    ORDER BY days.d
    OPTION (MAXRECURSION 20);
END
GO

-- Workspace dashboard (@folder_id NULL) or Project dashboard (one folder: its lists and their tasks).
-- Result sets: 1 by status (the workspace's statuses, with counts), 2 by assignee (open and total), 3 key
-- figures (due this week, overdue, completed this week, unassigned), 4 recent docs (6), 5 bookmarks (the
-- caller's favourites in scope), 6 resources (the newest 20 files and links on tasks in scope).
CREATE OR ALTER PROCEDURE [pm].[usp_dashboard_scope]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT = NULL,
    @folder_id     BIGINT = NULL,
    @today         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @folder_id IS NOT NULL
    BEGIN
        SET @workspace_id = (SELECT workspace_id FROM [pm].[folder] WHERE id = @folder_id);
        IF @workspace_id IS NULL OR NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
            THROW 50404, N'Folder not found', 1;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    SET @today = ISNULL(@today, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @week_start DATE = DATEADD(DAY, -(DATEDIFF(DAY, '19000107', @today) % 7), @today);   -- 1900-01-07 was a Sunday
    DECLARE @week_end DATE = DATEADD(DAY, 6, @week_start);
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    CREATE TABLE #t (id BIGINT PRIMARY KEY, status_id BIGINT, is_open BIT, due_date DATE, closed_at DATETIME2(0), task_list_id BIGINT);
    INSERT #t
    SELECT t.id, t.status_id, CASE WHEN s.status_group IN (N'done', N'closed') THEN 0 ELSE 1 END, t.due_date, t.closed_at, t.task_list_id
    FROM [pm].[fn_task_access](@company_id, @actor_user_id) a
    JOIN [pm].[task] t ON t.id = a.task_id
    JOIN [pm].[workspace_status] s ON s.id = t.status_id
    LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id
    WHERE t.workspace_id = @workspace_id AND (@folder_id IS NULL OR l.folder_id = @folder_id);

    SELECT s.id AS status_id, s.name, s.color, s.status_group, COUNT(t.id) AS [count]
    FROM [pm].[workspace_status] s
    LEFT JOIN #t t ON t.status_id = s.id
    WHERE s.workspace_id = @workspace_id
    GROUP BY s.id, s.name, s.color, s.status_group, s.sort_order
    ORDER BY CASE s.status_group WHEN N'not_started' THEN 1 WHEN N'active' THEN 2 WHEN N'done' THEN 3 ELSE 4 END, s.sort_order, s.id;

    SELECT x.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name,
           SUM(CAST(t.is_open AS INT)) AS [open], COUNT(*) AS total
    FROM #t t
    JOIN [pm].[task_assignee] x ON x.task_id = t.id
    JOIN [hr].[employee] e ON e.id = x.employee_id
    GROUP BY x.employee_id, e.first_name, e.last_name
    ORDER BY e.first_name, e.last_name;

    SELECT (SELECT COUNT(*) FROM #t WHERE is_open = 1 AND due_date BETWEEN @today AND @week_end) AS due_this_week,
           (SELECT COUNT(*) FROM #t WHERE is_open = 1 AND due_date < @today) AS overdue,
           (SELECT COUNT(*) FROM #t WHERE is_open = 0 AND closed_at >= @week_start) AS completed_this_week,
           (SELECT COUNT(*) FROM #t t WHERE t.is_open = 1 AND NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] x WHERE x.task_id = t.id)) AS unassigned;

    SELECT TOP 6 d.id, d.workspace_id, d.title, d.folder_id, d.task_list_id AS list_id,
           NULLIF(CONCAT(o.first_name, N' ', o.last_name), N' ') AS owner_name, ISNULL(d.word_count, 0) AS word_count,
           COALESCE(d.updated_at, d.created_at) AS updated_at
    FROM [pm].[doc] d
    JOIN [pm].[fn_doc_access](@company_id, @actor_user_id) a ON a.doc_id = d.id
    JOIN [hr].[employee] o ON o.id = d.owner_id
    LEFT JOIN [pm].[task_list] l ON l.id = d.task_list_id
    WHERE d.workspace_id = @workspace_id AND d.archived_at IS NULL
      AND (@folder_id IS NULL OR d.folder_id = @folder_id OR l.folder_id = @folder_id)
    ORDER BY COALESCE(d.updated_at, d.created_at) DESC, d.id DESC;

    SELECT f.entity_type, f.entity_id,
           CASE f.entity_type WHEN N'workspace' THEN w.name WHEN N'folder' THEN fo.name WHEN N'task_list' THEN l.name ELSE t.name END AS name,
           @workspace_id AS workspace_id, f.created_at
    FROM [pm].[favorite] f
    LEFT JOIN [pm].[workspace] w ON f.entity_type = N'workspace' AND w.id = f.entity_id
    LEFT JOIN [pm].[folder] fo ON f.entity_type = N'folder' AND fo.id = f.entity_id
    LEFT JOIN [pm].[task_list] l ON f.entity_type = N'task_list' AND l.id = f.entity_id
    LEFT JOIN [pm].[task] t ON f.entity_type = N'task' AND t.id = f.entity_id
    WHERE @me IS NOT NULL AND f.employee_id = @me AND f.kind = N'favorite'
      AND (   (@folder_id IS NULL AND f.entity_type = N'workspace' AND w.id = @workspace_id)
           OR (f.entity_type = N'folder' AND fo.workspace_id = @workspace_id AND (@folder_id IS NULL OR fo.id = @folder_id))
           OR (f.entity_type = N'task_list' AND l.workspace_id = @workspace_id AND (@folder_id IS NULL OR l.folder_id = @folder_id))
           OR (f.entity_type = N'task' AND f.entity_id IN (SELECT id FROM #t)))
    ORDER BY f.created_at DESC, f.id DESC;

    SELECT TOP 20 r.* FROM (
        SELECT CONVERT(NVARCHAR(30), a.id) AS id, a.entity_id AS task_id, t.name AS task_name, sf.id AS file_id, sf.name, sf.mime_type,
               sf.size_bytes, a.created_at, CAST(NULL AS NVARCHAR(30)) AS provider, CAST(NULL AS NVARCHAR(2000)) AS web_url
        FROM [core].[attachment] a
        JOIN #t x ON x.id = a.entity_id
        JOIN [pm].[task] t ON t.id = a.entity_id
        JOIN [core].[stored_file] sf ON sf.id = a.file_id
        WHERE a.company_id = @company_id AND a.entity_type = N'pm.task'
        UNION ALL
        SELECT CONCAT(N'link-', xf.id), xf.task_id, t.name, NULL, xf.name, xf.mime_type, xf.size_bytes, xf.created_at, xf.provider, xf.web_url
        FROM [pm].[task_external_file] xf
        JOIN #t x ON x.id = xf.task_id
        JOIN [pm].[task] t ON t.id = xf.task_id
    ) r
    ORDER BY r.created_at DESC, r.id DESC;
END
