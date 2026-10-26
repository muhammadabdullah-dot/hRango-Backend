-- E-Budget Settings -> Position Title. Position titles are org.job_title (owned by Organisation, added and
-- edited on Control Panel -> Job titles); this list shows them with how manpower uses them.
-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [mp].[usp_position_title_list]
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
    FROM [org].[job_title] t
    WHERE t.company_id = @company_id AND (@pattern IS NULL OR t.name LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT t.id, t.name,
           (SELECT COUNT(*) FROM [mp].[position] p WHERE p.job_title_id = t.id) AS position_count,
           (SELECT COUNT(*) FROM [mp].[position] p WHERE p.job_title_id = t.id AND p.status = N'active') AS active_position_count,
           (SELECT COUNT(*) FROM [mp].[open_position] o WHERE o.job_title_id = t.id AND o.status = N'active') AS open_position_count,
           t.created_at, cb.name AS created_by_name, t.updated_at
    FROM [org].[job_title] t
    OUTER APPLY [mp].[fn_actor_name](t.created_by) cb
    WHERE t.company_id = @company_id AND (@pattern IS NULL OR t.name LIKE @pattern)
    ORDER BY t.name, t.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
