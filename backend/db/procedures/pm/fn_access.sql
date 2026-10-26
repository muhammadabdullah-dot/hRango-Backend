-- Who may open which workspace and task, and with which workspace role.
--
-- Workspace roles rank: workspace_admin 5, hr 4, manager 3, team_leader 2, contributor 1.
-- A company employee who is not a member ranks 0 and may only read a workspace that is not private.
-- A user with no employee record (a system user) is never a member.
CREATE OR ALTER FUNCTION [pm].[fn_workspace_access] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT w.id AS workspace_id, w.privacy, m.member_role, me.employee_id,
       CASE m.member_role WHEN N'workspace_admin' THEN 5 WHEN N'hr' THEN 4 WHEN N'manager' THEN 3
                          WHEN N'team_leader' THEN 2 WHEN N'contributor' THEN 1 ELSE 0 END AS role_rank
FROM [pm].[workspace] w
OUTER APPLY (SELECT u.employee_id FROM [auth].[user_account] u WHERE u.id = @user_id) me
LEFT JOIN [pm].[workspace_member] m ON m.workspace_id = w.id AND m.employee_id = me.employee_id
WHERE w.company_id = @company_id
  AND (m.employee_id IS NOT NULL OR w.privacy <> N'private');
GO

-- The tasks a user may see. On top of the workspace: a private list is seen by its members and by
-- workspace admins and HR; in a private workspace a contributor sees the tasks assigned to them or
-- created by them, and the subtasks of tasks assigned to them.
CREATE OR ALTER FUNCTION [pm].[fn_task_access] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT t.id AS task_id, t.workspace_id, a.role_rank, a.member_role, a.employee_id
FROM [pm].[task] t
JOIN [pm].[fn_workspace_access](@company_id, @user_id) a ON a.workspace_id = t.workspace_id
LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id
WHERE t.company_id = @company_id
  AND (   l.id IS NULL OR ISNULL(l.privacy, N'workspace') <> N'private' OR a.role_rank >= 4
       OR EXISTS (SELECT 1 FROM [pm].[task_list_member] lm WHERE lm.task_list_id = l.id AND lm.employee_id = a.employee_id))
  AND (   a.role_rank <> 1 OR a.privacy <> N'private' OR t.created_by = @user_id
       OR EXISTS (SELECT 1 FROM [pm].[task_assignee] x WHERE x.task_id = t.id AND x.employee_id = a.employee_id)
       OR EXISTS (SELECT 1 FROM [pm].[task_assignee] x WHERE x.task_id = t.parent_task_id AND x.employee_id = a.employee_id));
GO

-- Column permissions in effect for one person in one workspace ("Set Role Permission"): a custom
-- permission for the person wins over their role's, which wins over the workspace default. Columns
-- with no row inherit the workspace role rules. Workspace admins can always edit every column.
CREATE OR ALTER FUNCTION [pm].[fn_column_levels] (@workspace_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT m.member_role FROM [pm].[workspace_member] m
    WHERE m.workspace_id = @workspace_id AND m.employee_id = @employee_id
),
k AS (SELECT DISTINCT column_key FROM [pm].[column_permission] WHERE workspace_id = @workspace_id)
SELECT k.column_key,
       CASE WHEN EXISTS (SELECT 1 FROM me WHERE member_role = N'workspace_admin') THEN N'can_edit'
            ELSE COALESCE(
                (SELECT TOP 1 p.permission_level FROM [pm].[column_permission] p
                 WHERE p.workspace_id = @workspace_id AND p.column_key = k.column_key AND p.employee_id = @employee_id),
                (SELECT TOP 1 p.permission_level FROM [pm].[column_permission] p
                 WHERE p.workspace_id = @workspace_id AND p.column_key = k.column_key AND p.employee_id IS NULL
                   AND p.member_role = (SELECT member_role FROM me)),
                (SELECT TOP 1 p.permission_level FROM [pm].[column_permission] p
                 WHERE p.workspace_id = @workspace_id AND p.column_key = k.column_key AND p.employee_id IS NULL
                   AND p.member_role IS NULL),
                N'default') END AS permission_level
FROM k;
