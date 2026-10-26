-- Benefits -> Employees: the people the user reaches (benefits.elections.view), their election for a plan
-- year, and the details enrolment needs that are missing (date of birth, marital status; from hr.employee).
-- Result set 1: total. Result set 2: the page, by name. @missing_only = 1 lists only people missing details.
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_employee_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @plan_year_id    BIGINT = NULL,
    @missing_only    BIT = 0,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @v TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @v SELECT DISTINCT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [hr].[employee] em
    JOIN @v v ON v.employee_id = em.id
    WHERE em.company_id = @company_id AND em.status <> N'left'
      AND (@pattern IS NULL OR CONCAT(em.first_name, N' ', em.last_name) LIKE @pattern OR em.code LIKE @pattern)
      AND (ISNULL(@missing_only, 0) = 0 OR em.date_of_birth IS NULL OR em.marital_status IS NULL)
    OPTION (RECOMPILE);

    SELECT em.id, em.code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS name,
           jt.name AS job_title_name, dp.name AS department_name, em.date_of_birth, em.marital_status,
           CONCAT_WS(N',', CASE WHEN em.date_of_birth IS NULL THEN N'date_of_birth' END,
                           CASE WHEN em.marital_status IS NULL THEN N'marital_status' END) AS missing,
           el.id AS election_id, el.status AS election_status
    FROM [hr].[employee] em
    JOIN @v v ON v.employee_id = em.id
    LEFT JOIN [org].[job_title] jt ON jt.id = em.job_title_id
    LEFT JOIN [org].[department] dp ON dp.id = em.department_id
    LEFT JOIN [ben].[election] el ON el.employee_id = em.id AND el.plan_year_id = @plan_year_id
    WHERE em.company_id = @company_id AND em.status <> N'left'
      AND (@pattern IS NULL OR CONCAT(em.first_name, N' ', em.last_name) LIKE @pattern OR em.code LIKE @pattern)
      AND (ISNULL(@missing_only, 0) = 0 OR em.date_of_birth IS NULL OR em.marital_status IS NULL)
    ORDER BY em.first_name, em.last_name, em.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
