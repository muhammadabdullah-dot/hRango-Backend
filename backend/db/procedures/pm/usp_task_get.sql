-- The task screen. Result sets: 1 task (with the caller's workspace role), 2 dependencies (as seen
-- from this task: waiting_on, blocking, linked), 3 checklist, 4 subtasks, 5 extension requests,
-- 6 column levels in effect for the caller (the service hides private columns).
CREATE OR ALTER PROCEDURE [pm].[usp_task_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ws BIGINT, @me BIGINT, @role NVARCHAR(30);
    SELECT @ws = workspace_id, @me = employee_id, @role = member_role
    FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;

    SELECT r.*, @role AS my_role,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [pm].[favorite] f WHERE f.employee_id = @me AND f.entity_type = N'task'
                AND f.entity_id = r.id AND f.kind = N'favorite') THEN 1 ELSE 0 END AS BIT) AS is_favorite
    FROM [pm].[fn_task_rows](@company_id) r WHERE r.id = @id;

    SELECT d.id, CASE WHEN d.kind = N'linked' THEN N'linked' WHEN d.task_id = @id THEN N'waiting_on' ELSE N'blocking' END AS kind,
           o.id AS task_id, o.code, o.name, s.name AS status_name, s.color AS status_color, s.status_group
    FROM [pm].[task_dependency] d
    JOIN [pm].[task] o ON o.id = CASE WHEN d.task_id = @id THEN d.other_task_id ELSE d.task_id END
    JOIN [pm].[workspace_status] s ON s.id = o.status_id
    WHERE d.task_id = @id OR d.other_task_id = @id
    ORDER BY d.id;

    SELECT c.id, c.item_text, c.is_done, c.sort_order, c.row_version
    FROM [pm].[checklist_item] c WHERE c.task_id = @id ORDER BY c.sort_order, c.id;

    SELECT c.id, c.code, c.name, s.name AS status_name, s.color AS status_color, s.status_group, c.due_date
    FROM [pm].[task] c
    JOIN [pm].[fn_task_access](@company_id, @actor_user_id) a ON a.task_id = c.id
    JOIN [pm].[workspace_status] s ON s.id = c.status_id
    WHERE c.parent_task_id = @id ORDER BY c.sort_order, c.id;

    SELECT x.id, x.requested_by_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS requested_by_name, x.old_due_date, x.new_due_date,
           x.reason, x.status, x.decided_by_id, NULLIF(CONCAT(d.first_name, N' ', d.last_name), N' ') AS decided_by_name, x.decided_at,
           x.remarks, x.created_at, x.row_version
    FROM [pm].[task_extension] x
    JOIN [hr].[employee] e ON e.id = x.requested_by_id
    LEFT JOIN [hr].[employee] d ON d.id = x.decided_by_id
    WHERE x.task_id = @id ORDER BY x.id;

    SELECT column_key, permission_level FROM [pm].[fn_column_levels](@ws, @me);
END
