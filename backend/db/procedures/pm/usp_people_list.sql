-- The company directory for the owner, member and assignee pickers ("Showing 250 Employees").
-- @workspace_id limits the list to that workspace's members (assignees must be members).
-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [pm].[usp_people_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
    @workspace_id  BIGINT = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @workspace_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [hr].[employee] e
    WHERE e.company_id = @company_id AND ISNULL(e.status, N'active') <> N'left'
      AND (@pattern IS NULL OR NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') LIKE @pattern OR e.code LIKE @pattern)
      AND (@workspace_id IS NULL OR EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @workspace_id AND m.employee_id = e.id))
    OPTION (RECOMPILE);

    SELECT e.id, e.code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name, ds.name AS designation_name,
           d.name AS department_name, e.photo_file_id, m.member_role
    FROM [hr].[employee] e
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [pm].[workspace_member] m ON m.workspace_id = @workspace_id AND m.employee_id = e.id
    WHERE e.company_id = @company_id AND ISNULL(e.status, N'active') <> N'left'
      AND (@pattern IS NULL OR NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') LIKE @pattern OR e.code LIKE @pattern)
      AND (@workspace_id IS NULL OR m.employee_id IS NOT NULL)
    ORDER BY e.first_name, e.last_name, e.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
