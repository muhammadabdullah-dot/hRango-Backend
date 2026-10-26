-- The workspaces panel: workspaces the caller may open, with their workspace role and marks.
-- Result set 1: total. Result set 2: the page. Hidden workspaces come last ("Hide Space").
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
    @favorites_only BIT = 0,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    SELECT COUNT(*) AS total
    FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) a
    JOIN [pm].[workspace] w ON w.id = a.workspace_id
    WHERE (@pattern IS NULL OR w.name LIKE @pattern)
      AND (@favorites_only = 0 OR EXISTS (SELECT 1 FROM [pm].[favorite] f WHERE f.employee_id = @me
               AND f.entity_type = N'workspace' AND f.entity_id = w.id AND f.kind = N'favorite'))
    OPTION (RECOMPILE);

    SELECT w.id, w.name, w.description, w.privacy, w.department_id, d.name AS department_name,
           w.owner_id, NULLIF(CONCAT(o.first_name, N' ', o.last_name), N' ') AS owner_name,
           a.member_role AS my_role,
           CAST(CASE WHEN fv.id IS NULL THEN 0 ELSE 1 END AS BIT) AS is_favorite,
           CAST(CASE WHEN hd.id IS NULL THEN 0 ELSE 1 END AS BIT) AS is_hidden,
           (SELECT COUNT(*) FROM [pm].[workspace_member] m WHERE m.workspace_id = w.id) AS member_count,
           w.cover_file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = w.cover_file_id) AS cover_file_name,
           w.created_at, w.updated_at, w.row_version
    FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) a
    JOIN [pm].[workspace] w ON w.id = a.workspace_id
    LEFT JOIN [org].[department] d ON d.id = w.department_id
    LEFT JOIN [hr].[employee] o ON o.id = w.owner_id
    LEFT JOIN [pm].[favorite] fv ON fv.employee_id = @me AND fv.entity_type = N'workspace' AND fv.entity_id = w.id AND fv.kind = N'favorite'
    LEFT JOIN [pm].[favorite] hd ON hd.employee_id = @me AND hd.entity_type = N'workspace' AND hd.entity_id = w.id AND hd.kind = N'hidden'
    WHERE (@pattern IS NULL OR w.name LIKE @pattern)
      AND (@favorites_only = 0 OR fv.id IS NOT NULL)
    ORDER BY CASE WHEN hd.id IS NULL THEN 0 ELSE 1 END, w.name, w.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
