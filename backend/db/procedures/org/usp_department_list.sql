-- Departments list. Result set 1: total matching rows. Result set 2: the requested page.
CREATE OR ALTER PROCEDURE [org].[usp_department_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @parent_id  BIGINT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [org].[department] d
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.name LIKE @pattern)
      AND (@parent_id IS NULL OR d.parent_id = @parent_id)
    OPTION (RECOMPILE);

    SELECT d.id, d.name, d.parent_id, p.name AS parent_name,
           d.head_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS head_name,
           d.created_at, d.updated_at, d.row_version
    FROM [org].[department] d
    LEFT JOIN [org].[department] p ON p.id = d.parent_id
    LEFT JOIN [hr].[employee] e ON e.id = d.head_id
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.name LIKE @pattern)
      AND (@parent_id IS NULL OR d.parent_id = @parent_id)
    ORDER BY d.name, d.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
