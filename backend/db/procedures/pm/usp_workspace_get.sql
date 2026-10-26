-- One workspace with everything its page needs.
-- Result sets: 1 workspace, 2 statuses, 3 organizer features, 4 members, 5 views (shared, and the
-- caller's private ones), 6 folders, 7 lists with progress (closed / total tasks) and last change.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rank INT, @me BIGINT, @role NVARCHAR(30);
    SELECT @rank = role_rank, @me = employee_id, @role = member_role
    FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;

    SELECT w.id, w.name, w.description, w.privacy, w.department_id, d.name AS department_name,
           wt.code AS workflow_template, wt.name AS workflow_template_name, w.status_mode,
           st.code AS status_template, w.owner_id, NULLIF(CONCAT(o.first_name, N' ', o.last_name), N' ') AS owner_name,
           @role AS my_role,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [pm].[favorite] f WHERE f.employee_id = @me AND f.entity_type = N'workspace'
                AND f.entity_id = w.id AND f.kind = N'favorite') THEN 1 ELSE 0 END AS BIT) AS is_favorite,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [pm].[favorite] f WHERE f.employee_id = @me AND f.entity_type = N'workspace'
                AND f.entity_id = w.id AND f.kind = N'hidden') THEN 1 ELSE 0 END AS BIT) AS is_hidden,
           (SELECT COUNT(*) FROM [pm].[workspace_member] m WHERE m.workspace_id = w.id) AS member_count,
           w.cover_file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = w.cover_file_id) AS cover_file_name,
           w.created_at, w.updated_at, w.row_version
    FROM [pm].[workspace] w
    JOIN [pm].[template] wt ON wt.id = w.workflow_template_id
    LEFT JOIN [pm].[template] st ON st.id = w.status_template_id
    LEFT JOIN [org].[department] d ON d.id = w.department_id
    LEFT JOIN [hr].[employee] o ON o.id = w.owner_id
    WHERE w.id = @id;

    SELECT s.id, s.name, s.color, s.status_group, s.sort_order, s.wip_limit
    FROM [pm].[workspace_status] s WHERE s.workspace_id = @id
    ORDER BY CASE s.status_group WHEN N'not_started' THEN 1 WHEN N'active' THEN 2 WHEN N'done' THEN 3 ELSE 4 END, s.sort_order, s.id;

    SELECT f.feature_code, f.setting_value
    FROM [pm].[workspace_feature] f WHERE f.workspace_id = @id ORDER BY f.feature_code;

    SELECT m.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name, ds.name AS designation_name,
           dp.name AS department_name, m.member_role
    FROM [pm].[workspace_member] m
    JOIN [hr].[employee] e ON e.id = m.employee_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    WHERE m.workspace_id = @id
    ORDER BY CASE m.member_role WHEN N'workspace_admin' THEN 1 WHEN N'hr' THEN 2 WHEN N'manager' THEN 3
                                WHEN N'team_leader' THEN 4 ELSE 5 END, e.first_name, e.last_name;

    SELECT v.id, v.task_list_id, v.view_type, v.name, v.config, v.is_pinned, v.is_private, v.is_protected,
           v.is_default, v.is_required, v.sort_order, v.owner_id, v.row_version
    FROM [pm].[list_view] v
    WHERE v.workspace_id = @id AND (v.is_private = 0 OR v.owner_id = @me)
    ORDER BY v.is_pinned DESC, v.sort_order, v.id;

    SELECT f.id, f.name, f.sort_order, f.row_version
    FROM [pm].[folder] f WHERE f.workspace_id = @id ORDER BY f.sort_order, f.name;

    SELECT l.id, l.folder_id, l.name, l.privacy, l.color, l.description, l.start_at, l.end_at, l.priority, l.sort_order,
           ISNULL(p.total, 0) AS task_count, ISNULL(p.closed, 0) AS closed_count,
           (SELECT MAX(x.v) FROM (VALUES (l.created_at), (l.updated_at), (p.last_change)) x (v)) AS last_modified_at,
           (SELECT lm.employee_id FROM [pm].[task_list_member] lm WHERE lm.task_list_id = l.id FOR JSON PATH) AS members_json,
           l.row_version
    FROM [pm].[task_list] l
    OUTER APPLY (
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN s.status_group IN (N'done', N'closed') THEN 1 ELSE 0 END) AS closed,
               MAX(ISNULL(t.updated_at, t.created_at)) AS last_change
        FROM [pm].[task] t JOIN [pm].[workspace_status] s ON s.id = t.status_id
        WHERE t.task_list_id = l.id
    ) p
    WHERE l.workspace_id = @id
      AND (ISNULL(l.privacy, N'workspace') <> N'private' OR @rank >= 4
           OR EXISTS (SELECT 1 FROM [pm].[task_list_member] lm WHERE lm.task_list_id = l.id AND lm.employee_id = @me))
    ORDER BY l.sort_order, l.name;
END
