-- Who may open which workspace and task, and with which workspace role.
--
-- Workspace roles rank: workspace_admin 5, hr 4, manager 3, team_leader 2, contributor 1.
-- A company employee who is not a member: in a 'workspace' workspace works like a contributor (1);
-- in a 'public' one only reads (0); a private one they do not see. A user with no employee record
-- (a system user) is never a member and only reads.
-- member_role is the role in effect (contributor for those non-members); is_member tells members apart.
CREATE OR ALTER FUNCTION [pm].[fn_workspace_access] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT w.id AS workspace_id, w.privacy, r.member_role, me.employee_id,
       CAST(CASE WHEN m.employee_id IS NULL THEN 0 ELSE 1 END AS BIT) AS is_member,
       CASE r.member_role WHEN N'workspace_admin' THEN 5 WHEN N'hr' THEN 4 WHEN N'manager' THEN 3
                          WHEN N'team_leader' THEN 2 WHEN N'contributor' THEN 1 ELSE 0 END AS role_rank
FROM [pm].[workspace] w
OUTER APPLY (SELECT u.employee_id,
                    CAST(CASE WHEN EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = u.employee_id AND e.company_id = @company_id)
                         THEN 1 ELSE 0 END AS BIT) AS in_company
             FROM [auth].[user_account] u WHERE u.id = @user_id) me
LEFT JOIN [pm].[workspace_member] m ON m.workspace_id = w.id AND m.employee_id = me.employee_id
CROSS APPLY (SELECT ISNULL(m.member_role,
                           CASE WHEN w.privacy = N'workspace' AND me.in_company = 1 THEN N'contributor' END) AS member_role) r
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
-- A company employee working in a 'workspace' workspace without being a member gets the
-- contributor rules, as in pm.fn_workspace_access.
CREATE OR ALTER FUNCTION [pm].[fn_column_levels] (@workspace_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT m.member_role FROM [pm].[workspace_member] m
    WHERE m.workspace_id = @workspace_id AND m.employee_id = @employee_id
    UNION ALL
    SELECT N'contributor' FROM [pm].[workspace] w
    JOIN [hr].[employee] e ON e.id = @employee_id AND e.company_id = w.company_id
    WHERE w.id = @workspace_id AND w.privacy = N'workspace'
      AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @workspace_id AND m.employee_id = @employee_id)
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
