-- The List view: a workspace's (or one list's) tasks with filters, grouping, sorting and subtask
-- display (BRD "Task Filtering and Viewing Options", "Grouping & Sorting", "Show Task Alignment").
--   CSV filters: @status_ids, @status_groups, @priorities (none = no priority), @assignee_ids,
--   @tag_ids, @created_by_ids (employee ids).
--   @subtasks: expanded (subtasks under their parent), collapsed (top-level rows only; counts show
--   the subtasks), separate (every task its own row).
--   @group_by: none, status, priority, assignee, tag, due_date, task_type, list. A task with two
--   assignees (or tags) appears in both groups; subtasks follow their top-level row's group.
--   @sort_by: manual, name, code, status, priority, due_date, start_date, date_created, date_closed,
--   time_estimate, story_points. Empty values sort last.
-- Result sets: 1 total rows, 2 the page, 3 group counts (all pages), 4 column levels for the caller.
CREATE OR ALTER PROCEDURE [pm].[usp_task_list]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @workspace_id       BIGINT,
    @task_list_id       BIGINT = NULL,
    @search             NVARCHAR(200) = NULL,
    @status_ids         NVARCHAR(MAX) = NULL,
    @status_groups      NVARCHAR(MAX) = NULL,
    @include_closed     BIT = 1,
    @priorities         NVARCHAR(MAX) = NULL,
    @assignee_ids       NVARCHAR(MAX) = NULL,
    @include_unassigned BIT = 0,
    @tag_ids            NVARCHAR(MAX) = NULL,
    @created_by_ids     NVARCHAR(MAX) = NULL,
    @task_type          NVARCHAR(30) = NULL,
    @due_from           DATE = NULL,
    @due_to             DATE = NULL,
    @start_from         DATE = NULL,
    @start_to           DATE = NULL,
    @overdue_only       BIT = 0,
    @subtasks           NVARCHAR(30) = N'expanded',
    @group_by           NVARCHAR(30) = N'status',
    @sort_by            NVARCHAR(30) = N'manual',
    @sort_dir           NVARCHAR(4) = N'asc',
    @page               INT = 1,
    @page_size          INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT;
    SELECT @me = employee_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    SET @subtasks = ISNULL(@subtasks, N'expanded');
    SET @group_by = ISNULL(@group_by, N'status');
    SET @sort_by = ISNULL(@sort_by, N'manual');
    SET @sort_dir = CASE WHEN @sort_dir = N'desc' THEN N'desc' ELSE N'asc' END;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'#', N''), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @f_status TABLE (id BIGINT PRIMARY KEY);
    INSERT @f_status SELECT DISTINCT TRY_CONVERT(BIGINT, value) FROM STRING_SPLIT(@status_ids, N',') WHERE TRY_CONVERT(BIGINT, value) IS NOT NULL;
    DECLARE @f_group TABLE (g NVARCHAR(30) PRIMARY KEY);
    INSERT @f_group SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@status_groups, N',') WHERE LTRIM(RTRIM(value)) <> N'';
    DECLARE @f_priority TABLE (p NVARCHAR(30) PRIMARY KEY);
    INSERT @f_priority SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@priorities, N',') WHERE LTRIM(RTRIM(value)) <> N'';
    DECLARE @f_assignee TABLE (id BIGINT PRIMARY KEY);
    INSERT @f_assignee SELECT DISTINCT TRY_CONVERT(BIGINT, value) FROM STRING_SPLIT(@assignee_ids, N',') WHERE TRY_CONVERT(BIGINT, value) IS NOT NULL;
    DECLARE @f_tag TABLE (id BIGINT PRIMARY KEY);
    INSERT @f_tag SELECT DISTINCT TRY_CONVERT(BIGINT, value) FROM STRING_SPLIT(@tag_ids, N',') WHERE TRY_CONVERT(BIGINT, value) IS NOT NULL;
    DECLARE @f_creator TABLE (id BIGINT PRIMARY KEY);
    INSERT @f_creator SELECT DISTINCT TRY_CONVERT(BIGINT, value) FROM STRING_SPLIT(@created_by_ids, N',') WHERE TRY_CONVERT(BIGINT, value) IS NOT NULL;
    DECLARE @has_status BIT = CASE WHEN EXISTS (SELECT 1 FROM @f_status) THEN 1 ELSE 0 END,
            @has_group BIT = CASE WHEN EXISTS (SELECT 1 FROM @f_group) THEN 1 ELSE 0 END,
            @has_priority BIT = CASE WHEN EXISTS (SELECT 1 FROM @f_priority) THEN 1 ELSE 0 END,
            @has_assignee BIT = CASE WHEN EXISTS (SELECT 1 FROM @f_assignee) OR @include_unassigned = 1 THEN 1 ELSE 0 END,
            @has_tag BIT = CASE WHEN EXISTS (SELECT 1 FROM @f_tag) THEN 1 ELSE 0 END,
            @has_creator BIT = CASE WHEN EXISTS (SELECT 1 FROM @f_creator) THEN 1 ELSE 0 END;

    -- 1. Tasks that match.
    CREATE TABLE #m (id BIGINT PRIMARY KEY, parent_task_id BIGINT, name NVARCHAR(200), code NVARCHAR(30), status_id BIGINT,
                     status_name NVARCHAR(200), status_sort INT, priority NVARCHAR(30), priority_rank INT, due_date DATE,
                     start_date DATE, created_at DATETIME2(0), closed_at DATETIME2(0), time_estimate_minutes INT,
                     story_points_total INT, sort_order INT, task_type NVARCHAR(30), task_list_id BIGINT, list_name NVARCHAR(200));
    INSERT #m
    SELECT t.id, t.parent_task_id, t.name, t.code, t.status_id, s.name,
           CASE s.status_group WHEN N'not_started' THEN 1 WHEN N'active' THEN 2 WHEN N'done' THEN 3 ELSE 4 END * 100000 + ISNULL(s.sort_order, 0),
           t.priority, CASE t.priority WHEN N'urgent' THEN 1 WHEN N'high' THEN 2 WHEN N'normal' THEN 3 WHEN N'low' THEN 4 END,
           t.due_date, t.start_date, t.created_at, t.closed_at, t.time_estimate_minutes,
           (SELECT SUM(a.story_points) FROM [pm].[task_assignee] a WHERE a.task_id = t.id), t.sort_order, t.task_type,
           t.task_list_id, l.name
    FROM [pm].[task] t
    JOIN [pm].[fn_task_access](@company_id, @actor_user_id) x ON x.task_id = t.id
    JOIN [pm].[workspace_status] s ON s.id = t.status_id
    LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id
    LEFT JOIN [auth].[user_account] cu ON cu.id = t.created_by
    WHERE t.workspace_id = @workspace_id
      AND (@task_list_id IS NULL OR t.task_list_id = @task_list_id)
      AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
      AND (@has_status = 0 OR t.status_id IN (SELECT id FROM @f_status))
      AND (@has_group = 0 OR s.status_group IN (SELECT g FROM @f_group))
      AND (@include_closed = 1 OR s.status_group NOT IN (N'done', N'closed'))
      AND (@has_priority = 0 OR ISNULL(t.priority, N'none') IN (SELECT p FROM @f_priority))
      AND (@has_assignee = 0
           OR EXISTS (SELECT 1 FROM [pm].[task_assignee] a WHERE a.task_id = t.id AND a.employee_id IN (SELECT id FROM @f_assignee))
           OR (@include_unassigned = 1 AND NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] a WHERE a.task_id = t.id)))
      AND (@has_tag = 0 OR EXISTS (SELECT 1 FROM [pm].[task_tag] g WHERE g.task_id = t.id AND g.tag_id IN (SELECT id FROM @f_tag)))
      AND (@has_creator = 0 OR cu.employee_id IN (SELECT id FROM @f_creator))
      AND (@task_type IS NULL OR t.task_type = @task_type)
      AND (@due_from IS NULL OR t.due_date >= @due_from)
      AND (@due_to IS NULL OR t.due_date <= @due_to)
      AND (@start_from IS NULL OR t.start_date >= @start_from)
      AND (@start_to IS NULL OR t.start_date <= @start_to)
      AND (@overdue_only = 0 OR (t.due_date < @today AND s.status_group NOT IN (N'done', N'closed')))
    OPTION (RECOMPILE);

    -- 2. Rows: top-level rows, and (expanded) subtasks under a matching parent.
    CREATE TABLE #tree (task_id BIGINT PRIMARY KEY, root_id BIGINT, depth INT, path VARCHAR(900));
    WITH tree AS (
        SELECT m.id AS task_id, m.id AS root_id, 0 AS depth, CAST('' AS VARCHAR(900)) AS path
        FROM #m m
        WHERE @subtasks = N'separate' OR m.parent_task_id IS NULL OR NOT EXISTS (SELECT 1 FROM #m p WHERE p.id = m.parent_task_id)
        UNION ALL
        SELECT c.id, tree.root_id, tree.depth + 1,
               CAST(tree.path + RIGHT('0000000000' + CAST(ISNULL(c.sort_order, 0) AS VARCHAR(10)), 10)
                    + RIGHT('0000000000000000000' + CAST(c.id AS VARCHAR(19)), 19) AS VARCHAR(900))
        FROM #m c JOIN tree ON c.parent_task_id = tree.task_id
        WHERE @subtasks = N'expanded'
    )
    INSERT #tree SELECT task_id, root_id, depth, path FROM tree OPTION (MAXRECURSION 30);

    -- 3. Groups of each top-level row.
    CREATE TABLE #g (root_id BIGINT, group_key NVARCHAR(100), group_name NVARCHAR(200), sort_num BIGINT, sort_text NVARCHAR(200));
    INSERT #g
    SELECT m.id, N'all', N'All tasks', 0, N'' FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0
    WHERE @group_by NOT IN (N'status', N'priority', N'assignee', N'tag', N'due_date', N'task_type', N'list')
    UNION ALL
    SELECT m.id, CONVERT(NVARCHAR(30), m.status_id), m.status_name, m.status_sort, N''
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0 WHERE @group_by = N'status'
    UNION ALL
    SELECT m.id, ISNULL(m.priority, N'none'),
           CASE m.priority WHEN N'urgent' THEN N'Urgent' WHEN N'high' THEN N'High' WHEN N'normal' THEN N'Normal' WHEN N'low' THEN N'Low' ELSE N'No priority' END,
           ISNULL(m.priority_rank, 9), N''
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0 WHERE @group_by = N'priority'
    UNION ALL
    SELECT m.id, ISNULL(CONVERT(NVARCHAR(30), a.employee_id), N'none'),
           CASE WHEN a.employee_id IS NULL THEN N'Unassigned' ELSE NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') END,
           CASE WHEN a.employee_id IS NULL THEN 2 ELSE 1 END,
           CASE WHEN a.employee_id IS NULL THEN N'' ELSE NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') END
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0
    LEFT JOIN [pm].[task_assignee] a ON a.task_id = m.id
    LEFT JOIN [hr].[employee] e ON e.id = a.employee_id
    WHERE @group_by = N'assignee'
    UNION ALL
    SELECT m.id, ISNULL(CONVERT(NVARCHAR(30), g.id), N'none'), ISNULL(g.name, N'No tags'),
           CASE WHEN g.id IS NULL THEN 2 ELSE 1 END, ISNULL(g.name, N'')
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0
    LEFT JOIN [pm].[task_tag] x ON x.task_id = m.id
    LEFT JOIN [pm].[tag] g ON g.id = x.tag_id
    WHERE @group_by = N'tag'
    UNION ALL
    SELECT m.id, ISNULL(CONVERT(NVARCHAR(10), m.due_date, 23), N'none'), ISNULL(CONVERT(NVARCHAR(10), m.due_date, 23), N'No due date'),
           ISNULL(YEAR(m.due_date) * 10000 + MONTH(m.due_date) * 100 + DAY(m.due_date), 99999999), N''
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0 WHERE @group_by = N'due_date'
    UNION ALL
    SELECT m.id, m.task_type, CASE m.task_type WHEN N'milestone' THEN N'Milestone' ELSE N'Task' END,
           CASE m.task_type WHEN N'milestone' THEN 2 ELSE 1 END, N''
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0 WHERE @group_by = N'task_type'
    UNION ALL
    SELECT m.id, ISNULL(CONVERT(NVARCHAR(30), m.task_list_id), N'none'), ISNULL(m.list_name, N'No list'),
           CASE WHEN m.task_list_id IS NULL THEN 2 ELSE 1 END, ISNULL(m.list_name, N'')
    FROM #m m JOIN #tree t ON t.task_id = m.id AND t.depth = 0 WHERE @group_by = N'list';

    -- 4. Ordered rows.
    CREATE TABLE #f (rn BIGINT, task_id BIGINT, root_id BIGINT, depth INT, group_key NVARCHAR(100), group_name NVARCHAR(200),
                     sort_num BIGINT, sort_text NVARCHAR(200));
    INSERT #f
    SELECT ROW_NUMBER() OVER (ORDER BY g.sort_num, g.sort_text, g.group_key,
               CASE WHEN @sort_by = N'name' AND @sort_dir = N'asc' THEN r.name END ASC,
               CASE WHEN @sort_by = N'name' AND @sort_dir = N'desc' THEN r.name END DESC,
               CASE WHEN @sort_by = N'code' AND @sort_dir = N'asc' THEN r.code END ASC,
               CASE WHEN @sort_by = N'code' AND @sort_dir = N'desc' THEN r.code END DESC,
               CASE WHEN @sort_by = N'status' AND @sort_dir = N'asc' THEN r.status_sort END ASC,
               CASE WHEN @sort_by = N'status' AND @sort_dir = N'desc' THEN r.status_sort END DESC,
               CASE WHEN @sort_by = N'priority' THEN CASE WHEN r.priority_rank IS NULL THEN 1 ELSE 0 END END,
               CASE WHEN @sort_by = N'priority' AND @sort_dir = N'asc' THEN r.priority_rank END ASC,
               CASE WHEN @sort_by = N'priority' AND @sort_dir = N'desc' THEN r.priority_rank END DESC,
               CASE WHEN @sort_by = N'due_date' THEN CASE WHEN r.due_date IS NULL THEN 1 ELSE 0 END END,
               CASE WHEN @sort_by = N'due_date' AND @sort_dir = N'asc' THEN r.due_date END ASC,
               CASE WHEN @sort_by = N'due_date' AND @sort_dir = N'desc' THEN r.due_date END DESC,
               CASE WHEN @sort_by = N'start_date' THEN CASE WHEN r.start_date IS NULL THEN 1 ELSE 0 END END,
               CASE WHEN @sort_by = N'start_date' AND @sort_dir = N'asc' THEN r.start_date END ASC,
               CASE WHEN @sort_by = N'start_date' AND @sort_dir = N'desc' THEN r.start_date END DESC,
               CASE WHEN @sort_by = N'date_created' AND @sort_dir = N'asc' THEN r.created_at END ASC,
               CASE WHEN @sort_by = N'date_created' AND @sort_dir = N'desc' THEN r.created_at END DESC,
               CASE WHEN @sort_by = N'date_closed' THEN CASE WHEN r.closed_at IS NULL THEN 1 ELSE 0 END END,
               CASE WHEN @sort_by = N'date_closed' AND @sort_dir = N'asc' THEN r.closed_at END ASC,
               CASE WHEN @sort_by = N'date_closed' AND @sort_dir = N'desc' THEN r.closed_at END DESC,
               CASE WHEN @sort_by = N'time_estimate' THEN CASE WHEN r.time_estimate_minutes IS NULL THEN 1 ELSE 0 END END,
               CASE WHEN @sort_by = N'time_estimate' AND @sort_dir = N'asc' THEN r.time_estimate_minutes END ASC,
               CASE WHEN @sort_by = N'time_estimate' AND @sort_dir = N'desc' THEN r.time_estimate_minutes END DESC,
               CASE WHEN @sort_by = N'story_points' THEN CASE WHEN r.story_points_total IS NULL THEN 1 ELSE 0 END END,
               CASE WHEN @sort_by = N'story_points' AND @sort_dir = N'asc' THEN r.story_points_total END ASC,
               CASE WHEN @sort_by = N'story_points' AND @sort_dir = N'desc' THEN r.story_points_total END DESC,
               r.sort_order, r.id, t.path),
           t.task_id, t.root_id, t.depth, g.group_key, g.group_name, g.sort_num, g.sort_text
    FROM #tree t
    JOIN #g g ON g.root_id = t.root_id
    JOIN #m r ON r.id = t.root_id
    WHERE @subtasks <> N'collapsed' OR t.depth = 0;

    SELECT COUNT(*) AS total FROM #f;

    SELECT f.group_key, f.group_name, f.depth, f.root_id, r.*
    FROM #f f
    JOIN [pm].[fn_task_rows](@company_id) r ON r.id = f.task_id
    WHERE f.rn > (@page - 1) * @page_size AND f.rn <= @page * @page_size
    ORDER BY f.rn;

    SELECT group_key, group_name, COUNT(*) AS task_count
    FROM #f GROUP BY group_key, group_name, sort_num, sort_text
    ORDER BY sort_num, sort_text, group_key;

    SELECT column_key, permission_level FROM [pm].[fn_column_levels](@workspace_id, @me);
END
