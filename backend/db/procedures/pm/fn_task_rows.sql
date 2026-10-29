-- A task as the List view and the task screen show it: names resolved, counts, time totals and the
-- assignees, tags and custom field values as JSON. Join it to fn_task_access to stay in scope.
CREATE OR ALTER FUNCTION [pm].[fn_task_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT t.id, t.workspace_id, t.task_list_id, l.name AS list_name, t.parent_task_id, p.name AS parent_name,
       t.code, t.name, t.description, t.task_type,
       t.status_id, s.name AS status_name, s.color AS status_color, s.status_group,
       CASE s.status_group WHEN N'not_started' THEN 1 WHEN N'active' THEN 2 WHEN N'done' THEN 3 ELSE 4 END * 100000 + ISNULL(s.sort_order, 0) AS status_sort,
       t.priority,
       CASE t.priority WHEN N'urgent' THEN 1 WHEN N'high' THEN 2 WHEN N'normal' THEN 3 WHEN N'low' THEN 4 END AS priority_rank,
       t.start_date, t.start_time, t.due_date, t.due_time, t.original_due_date,
       CAST(CASE WHEN t.due_date < CAST(SYSUTCDATETIME() AS DATE) AND s.status_group NOT IN (N'done', N'closed') THEN 1 ELSE 0 END AS BIT) AS is_overdue,
       t.time_estimate_minutes,
       ISNULL((SELECT SUM(ISNULL(te.minutes, DATEDIFF(MINUTE, te.start_at, SYSUTCDATETIME())))
               FROM [pm].[time_entry] te WHERE te.task_id = t.id), 0) AS time_tracked_minutes,
       sp.total AS story_points_total,
       -- Story point penalty (Overdue settings): a task closed late loses penalty_percent of its points;
       -- 0 when it was not closed late; NULL when the task has no story points.
       CAST(CASE WHEN sp.total IS NULL THEN NULL WHEN t.is_closed_late = 1 THEN ROUND(sp.total * ISNULL(os.penalty_percent, 0) / 100.0, 2)
                 ELSE 0 END AS DECIMAL(9, 2)) AS story_points_penalty,
       CAST(CASE WHEN sp.total IS NULL THEN NULL WHEN t.is_closed_late = 1 THEN sp.total - ROUND(sp.total * ISNULL(os.penalty_percent, 0) / 100.0, 2)
                 ELSE sp.total END AS DECIMAL(9, 2)) AS story_points_effective,
       le.status AS latest_extension_status, le.new_due_date AS latest_extension_new_due_date,
       t.rating, t.url, t.recurrence, t.closed_at, t.is_closed_late, t.sort_order,
       t.cover_file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = t.cover_file_id) AS cover_file_name,
       t.created_by AS created_by_user_id,
       COALESCE(NULLIF(CONCAT(ce.first_name, N' ', ce.last_name), N' '), cu.display_name, cu.email) AS created_by_name,
       t.created_at, t.updated_at,
       (SELECT COUNT(*) FROM [pm].[task] c WHERE c.parent_task_id = t.id) AS subtask_count,
       (SELECT COUNT(*) FROM [pm].[task] c JOIN [pm].[workspace_status] cs ON cs.id = c.status_id
        WHERE c.parent_task_id = t.id AND cs.status_group NOT IN (N'done', N'closed')) AS open_subtask_count,
       (SELECT COUNT(*) FROM [pm].[task_comment] c WHERE c.task_id = t.id) AS comment_count,
       (SELECT COUNT(*) FROM [core].[attachment] a WHERE a.company_id = t.company_id AND a.entity_type = N'pm.task'
        AND a.entity_id = t.id)
       + (SELECT COUNT(*) FROM [pm].[task_external_file] xf WHERE xf.task_id = t.id) AS attachment_count,
       (SELECT COUNT(*) FROM [pm].[task_dependency] d JOIN [pm].[task] o ON o.id = d.other_task_id
        JOIN [pm].[workspace_status] os ON os.id = o.status_id
        WHERE d.task_id = t.id AND d.kind = N'waiting_on' AND os.status_group NOT IN (N'done', N'closed')) AS open_dependency_count,
       (SELECT COUNT(*) FROM [pm].[task_dependency] d WHERE d.other_task_id = t.id AND d.kind = N'waiting_on') AS blocking_count,
       (SELECT COUNT(*) FROM [pm].[checklist_item] ci WHERE ci.task_id = t.id) AS checklist_count,
       (SELECT COUNT(*) FROM [pm].[checklist_item] ci WHERE ci.task_id = t.id AND ci.is_done = 1) AS checklist_done_count,
       lc.body AS latest_comment_body, lc.author_name AS latest_comment_author, lc.created_at AS latest_comment_at,
       (SELECT a.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name, a.story_points
        FROM [pm].[task_assignee] a JOIN [hr].[employee] e ON e.id = a.employee_id
        WHERE a.task_id = t.id ORDER BY e.first_name, e.last_name FOR JSON PATH) AS assignees_json,
       (SELECT g.id, g.name, g.color FROM [pm].[task_tag] x JOIN [pm].[tag] g ON g.id = x.tag_id
        WHERE x.task_id = t.id ORDER BY g.name FOR JSON PATH) AS tags_json,
       (SELECT v.custom_field_id, v.field_value FROM [pm].[task_field_value] v
        WHERE v.task_id = t.id ORDER BY v.custom_field_id FOR JSON PATH) AS field_values_json,
       t.row_version
FROM [pm].[task] t
JOIN [pm].[workspace_status] s ON s.id = t.status_id
LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id
LEFT JOIN [pm].[task] p ON p.id = t.parent_task_id
LEFT JOIN [auth].[user_account] cu ON cu.id = t.created_by
LEFT JOIN [hr].[employee] ce ON ce.id = cu.employee_id
LEFT JOIN [pm].[workspace_overdue_setting] os ON os.workspace_id = t.workspace_id
OUTER APPLY (SELECT SUM(a.story_points) AS total FROM [pm].[task_assignee] a WHERE a.task_id = t.id) sp
OUTER APPLY (SELECT TOP 1 x.status, x.new_due_date FROM [pm].[task_extension] x WHERE x.task_id = t.id ORDER BY x.id DESC) le
OUTER APPLY (
    SELECT TOP 1 c.body, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS author_name, c.created_at
    FROM [pm].[task_comment] c JOIN [hr].[employee] e ON e.id = c.author_id
    WHERE c.task_id = t.id ORDER BY c.created_at DESC, c.id DESC
) lc
WHERE t.company_id = @company_id;
