-- Cost centers list. Result set 1: total matching rows. Result set 2: the requested page.
CREATE OR ALTER PROCEDURE [org].[usp_cost_center_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [org].[cost_center] x
    WHERE x.company_id = @company_id AND (@pattern IS NULL OR x.name LIKE @pattern OR x.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT x.id, x.name, x.code, 
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.cost_center_id = x.id AND e.status NOT IN (N'left', N'inactive')) AS employee_count,
           x.created_at, x.updated_at, x.row_version
    FROM [org].[cost_center] x
    WHERE x.company_id = @company_id AND (@pattern IS NULL OR x.name LIKE @pattern OR x.code LIKE @pattern)
    ORDER BY x.name, x.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
