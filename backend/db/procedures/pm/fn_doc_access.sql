-- The docs a user may open: docs of workspaces they reach (pm.fn_workspace_access); a private doc only
-- by its owner. is_owner and role_rank decide edits in the doc procedures.
CREATE OR ALTER FUNCTION [pm].[fn_doc_access] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT d.id AS doc_id, d.workspace_id, a.role_rank, a.employee_id,
       CAST(CASE WHEN d.owner_id = a.employee_id THEN 1 ELSE 0 END AS BIT) AS is_owner
FROM [pm].[doc] d
JOIN [pm].[fn_workspace_access](@company_id, @user_id) a ON a.workspace_id = d.workspace_id
WHERE d.company_id = @company_id
  AND (d.visibility <> N'private' OR d.owner_id = a.employee_id);
GO

-- The tasks a share link shows (public share page): the task and its subtasks, the list's tasks, or the
-- workspace's tasks outside private lists.
CREATE OR ALTER FUNCTION [pm].[fn_share_tasks] (@share_link_id BIGINT)
RETURNS TABLE
AS RETURN
WITH s AS (SELECT entity_type, entity_id, workspace_id FROM [pm].[share_link] WHERE id = @share_link_id),
tree AS (
    SELECT t.id FROM [pm].[task] t JOIN s ON s.entity_type = N'task' AND t.id = s.entity_id
    UNION ALL
    SELECT c.id FROM [pm].[task] c JOIN tree ON c.parent_task_id = tree.id
)
SELECT id AS task_id FROM tree
UNION
SELECT t.id FROM [pm].[task] t JOIN s ON s.entity_type = N'task_list' AND t.task_list_id = s.entity_id
UNION
SELECT t.id FROM [pm].[task] t JOIN s ON s.entity_type = N'workspace' AND t.workspace_id = s.entity_id
LEFT JOIN [pm].[task_list] l ON l.id = t.task_list_id
WHERE l.id IS NULL OR ISNULL(l.privacy, N'workspace') <> N'private';
