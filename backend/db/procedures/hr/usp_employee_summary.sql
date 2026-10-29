-- The directory's tiles (Talent Management: Total, Male, Female ...): counts over the same employees
-- and filters as hr.usp_employee_list (the caller's @permission_code scope; left and switched-off people
-- only when @status names them or @include_inactive = 1). One result set, one row: total, the genders
-- (male, female, other, unspecified) and the statuses (active, probation, notice, left, inactive).
CREATE OR ALTER PROCEDURE [hr].[usp_employee_summary]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150) = N'employees.directory.view',
    @search             NVARCHAR(200) = NULL,
    @status             NVARCHAR(30) = NULL,
    @include_inactive   BIT = 0,
    @branch_id          BIGINT = NULL,
    @location_id        BIGINT = NULL,
    @area_id            BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @division_id        BIGINT = NULL,
    @designation_id     BIGINT = NULL,
    @job_title_id       BIGINT = NULL,
    @grade_id           BIGINT = NULL,
    @employment_type_id BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @line_manager_id    BIGINT = NULL,
    @gender             NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total,
           SUM(CASE WHEN e.gender = N'male' THEN 1 ELSE 0 END) AS male,
           SUM(CASE WHEN e.gender = N'female' THEN 1 ELSE 0 END) AS female,
           SUM(CASE WHEN e.gender = N'other' THEN 1 ELSE 0 END) AS other,
           SUM(CASE WHEN e.gender IS NULL OR e.gender NOT IN (N'male', N'female', N'other') THEN 1 ELSE 0 END) AS unspecified,
           SUM(CASE WHEN e.status = N'active' THEN 1 ELSE 0 END) AS active,
           SUM(CASE WHEN e.status = N'probation' THEN 1 ELSE 0 END) AS probation,
           SUM(CASE WHEN e.status = N'notice' THEN 1 ELSE 0 END) AS notice,
           SUM(CASE WHEN e.status = N'left' THEN 1 ELSE 0 END) AS [left],
           SUM(CASE WHEN e.status = N'inactive' THEN 1 ELSE 0 END) AS inactive
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    WHERE e.company_id = @company_id
      AND (@pattern IS NULL OR e.code LIKE @pattern OR e.first_name LIKE @pattern OR e.last_name LIKE @pattern
           OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.email LIKE @pattern)
      AND (   (@status IS NOT NULL AND e.status = @status)
           OR (@status IS NULL AND (@include_inactive = 1 OR e.status NOT IN (N'left', N'inactive'))))
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@location_id IS NULL OR e.location_id = @location_id)
      AND (@area_id IS NULL OR e.area_id = @area_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@division_id IS NULL OR e.division_id = @division_id)
      AND (@designation_id IS NULL OR e.designation_id = @designation_id)
      AND (@job_title_id IS NULL OR e.job_title_id = @job_title_id)
      AND (@grade_id IS NULL OR e.grade_id = @grade_id)
      AND (@employment_type_id IS NULL OR e.employment_type_id = @employment_type_id)
      AND (@employee_group_id IS NULL OR e.employee_group_id = @employee_group_id)
      AND (@line_manager_id IS NULL OR e.line_manager_id = @line_manager_id)
      AND (@gender IS NULL OR e.gender = @gender)
    OPTION (RECOMPILE);
END
