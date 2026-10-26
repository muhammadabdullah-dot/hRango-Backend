-- E-Budget Settings -> Employee Position: where a job sits (station, group, division, department,
-- sub-department, cost center, grade, reports-to) and its salary band (mp.position_salary_range).
CREATE OR ALTER PROCEDURE [mp].[usp_position_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [mp].[position] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Position not found', 1;

    SELECT * FROM [mp].[fn_position_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, by title then code.
CREATE OR ALTER PROCEDURE [mp].[usp_position_list]
    @company_id        BIGINT,
    @search            NVARCHAR(200) = NULL,
    @job_title_id      BIGINT = NULL,
    @branch_id         BIGINT = NULL,
    @division_id       BIGINT = NULL,
    @department_id     BIGINT = NULL,
    @employee_group_id BIGINT = NULL,
    @status            NVARCHAR(30) = NULL,
    @page              INT = 1,
    @page_size         INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [mp].[fn_position_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.code LIKE @pattern OR r.job_title_name LIKE @pattern)
      AND (@job_title_id IS NULL OR r.job_title_id = @job_title_id)
      AND (@branch_id IS NULL OR r.branch_id = @branch_id)
      AND (@division_id IS NULL OR r.division_id = @division_id)
      AND (@department_id IS NULL OR r.department_id = @department_id)
      AND (@employee_group_id IS NULL OR r.employee_group_id = @employee_group_id)
      AND (@status IS NULL OR r.status = @status)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [mp].[fn_position_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.code LIKE @pattern OR r.job_title_name LIKE @pattern)
      AND (@job_title_id IS NULL OR r.job_title_id = @job_title_id)
      AND (@branch_id IS NULL OR r.branch_id = @branch_id)
      AND (@division_id IS NULL OR r.division_id = @division_id)
      AND (@department_id IS NULL OR r.department_id = @department_id)
      AND (@employee_group_id IS NULL OR r.employee_group_id = @employee_group_id)
      AND (@status IS NULL OR r.status = @status)
    ORDER BY r.job_title_name, r.code, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL) or edits a position. A blank code takes the next POS-0001 number. The band given
-- becomes the position's range from today when it differs from the one in force.
CREATE OR ALTER PROCEDURE [mp].[usp_position_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @id                BIGINT = NULL,
    @code              NVARCHAR(30) = NULL,
    @job_title_id      BIGINT,
    @branch_id         BIGINT,
    @employee_group_id BIGINT,
    @division_id       BIGINT = NULL,
    @department_id     BIGINT = NULL,
    @sub_department_id BIGINT = NULL,
    @cost_center_id    BIGINT = NULL,
    @grade_id          BIGINT = NULL,
    @reports_to_id     BIGINT = NULL,
    @employee_id       BIGINT = NULL,
    @status            NVARCHAR(30) = N'active',
    @min_salary        DECIMAL(18,2),
    @max_salary        DECIMAL(18,2),
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @code = NULLIF(LTRIM(RTRIM(@code)), N'');
    SET @status = ISNULL(NULLIF(@status, N''), N'active');
    IF @job_title_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50400, N'jobTitleId|Choose the position title.', 1;
    IF @branch_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Choose the station.', 1;
    IF @employee_group_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[employee_group] WHERE id = @employee_group_id AND company_id = @company_id)
        THROW 50400, N'employeeGroupId|Choose the employee group.', 1;
    IF @division_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[division] WHERE id = @division_id AND company_id = @company_id)
        THROW 50400, N'divisionId|Division not found.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @sub_department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @sub_department_id AND company_id = @company_id
                                                      AND (@department_id IS NULL OR parent_id = @department_id))
        THROW 50400, N'subDepartmentId|Choose a sub-department of the department.', 1;
    IF @cost_center_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[cost_center] WHERE id = @cost_center_id AND company_id = @company_id)
        THROW 50400, N'costCenterId|Cost center not found.', 1;
    IF @grade_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[grade] WHERE id = @grade_id AND company_id = @company_id)
        THROW 50400, N'gradeId|Grade not found.', 1;
    IF @employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @reports_to_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [mp].[position] WHERE id = @reports_to_id AND company_id = @company_id)
        THROW 50400, N'reportsToId|Reports-to position not found.', 1;
    IF @status NOT IN (N'active', N'inactive')
        THROW 50400, N'status|Status is active or inactive.', 1;
    IF @min_salary IS NULL OR @min_salary < 0
        THROW 50400, N'minSalary|Enter the min salary.', 1;
    IF @max_salary IS NULL OR @max_salary <= 0
        THROW 50400, N'maxSalary|Enter the max salary.', 1;
    IF @max_salary < @min_salary
        THROW 50400, N'maxSalary|Max salary cannot be below the min salary.', 1;
    IF @code IS NOT NULL AND EXISTS (SELECT 1 FROM [mp].[position] WHERE company_id = @company_id AND code = @code AND (@id IS NULL OR id <> @id))
        THROW 50409, N'code|POSITION_DUPLICATE|A position with this code already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a position.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [mp].[position] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Position not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this position. Reload it and try again', 1;
        IF @reports_to_id IS NOT NULL
        BEGIN
            DECLARE @loop BIT = 0;
            WITH up AS (
                SELECT id, reports_to_id FROM [mp].[position] WHERE id = @reports_to_id
                UNION ALL
                SELECT p.id, p.reports_to_id FROM [mp].[position] p JOIN up ON p.id = up.reports_to_id
            )
            SELECT @loop = 1 FROM up WHERE id = @id OPTION (MAXRECURSION 100);
            IF @loop = 1
                THROW 50400, N'reportsToId|A position cannot report to itself or to one that reports to it.', 1;
        END
    END

    BEGIN TRAN;
        IF @code IS NULL
        BEGIN
            DECLARE @next INT = 1 + ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(code, 5, 26) AS INT))
                                           FROM [mp].[position] WITH (UPDLOCK, HOLDLOCK)
                                           WHERE company_id = @company_id AND code LIKE N'POS-%'), 0);
            SET @code = N'POS-' + RIGHT(N'0000' + CAST(@next AS NVARCHAR(10)), CASE WHEN @next > 9999 THEN 10 ELSE 4 END);
        END

        IF @id IS NULL
        BEGIN
            INSERT [mp].[position] (company_id, code, branch_id, job_title_id, employee_group_id, division_id, department_id,
                                    sub_department_id, cost_center_id, grade_id, reports_to_id, employee_id, status, created_by)
            VALUES (@company_id, @code, @branch_id, @job_title_id, @employee_group_id, @division_id, @department_id,
                    @sub_department_id, @cost_center_id, @grade_id, @reports_to_id, @employee_id, @status, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.position', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [mp].[position]
            SET code = @code, branch_id = @branch_id, job_title_id = @job_title_id, employee_group_id = @employee_group_id,
                division_id = @division_id, department_id = @department_id, sub_department_id = @sub_department_id,
                cost_center_id = @cost_center_id, grade_id = @grade_id, reports_to_id = @reports_to_id,
                employee_id = @employee_id, status = @status, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this position. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.position', @id, N'update', @actor_user_id, @now);
        END

        IF NOT EXISTS (SELECT 1 FROM [mp].[fn_position_band](@id, @today) b WHERE b.min_salary = @min_salary AND b.max_salary = @max_salary)
        BEGIN
            UPDATE [mp].[position_salary_range]
            SET min_salary = @min_salary, max_salary = @max_salary, updated_at = @now, updated_by = @actor_user_id
            WHERE position_id = @id AND effective_date = @today;
            IF @@ROWCOUNT = 0
                INSERT [mp].[position_salary_range] (position_id, effective_date, min_salary, max_salary, created_by)
                VALUES (@id, @today, @min_salary, @max_salary, @actor_user_id);
        END
    COMMIT;

    EXEC [mp].[usp_position_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [mp].[usp_position_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [mp].[position] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Position not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this position. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [mp].[manpower_plan_line] WHERE position_id = @id)
       OR EXISTS (SELECT 1 FROM [mp].[open_position] WHERE position_id = @id)
        THROW 50409, N'This position is used by plans or open positions. Deactivate it instead.', 1;
    IF EXISTS (SELECT 1 FROM [mp].[position] WHERE reports_to_id = @id)
        THROW 50409, N'Other positions report to this one. Change them first.', 1;

    BEGIN TRAN;
        DELETE [mp].[position_salary_range] WHERE position_id = @id;
        DELETE [mp].[position] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.position', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- A position's salary bands over time, newest first.
CREATE OR ALTER PROCEDURE [mp].[usp_position_salary_range_list]
    @company_id  BIGINT,
    @position_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [mp].[position] WHERE id = @position_id AND company_id = @company_id)
        THROW 50404, N'Position not found', 1;

    SELECT r.id, r.position_id, r.effective_date, r.min_salary, r.max_salary,
           r.created_at, cb.name AS created_by_name, r.updated_at, r.row_version
    FROM [mp].[position_salary_range] r
    OUTER APPLY [mp].[fn_actor_name](r.created_by) cb
    WHERE r.position_id = @position_id
    ORDER BY r.effective_date DESC;
END
GO

-- Sets the band from a date (a new range, or the one already starting that day). Returns the bands.
CREATE OR ALTER PROCEDURE [mp].[usp_position_salary_range_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT = NULL,
    @position_id    BIGINT,
    @effective_date DATE,
    @min_salary     DECIMAL(18,2),
    @max_salary     DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [mp].[position] WHERE id = @position_id AND company_id = @company_id)
        THROW 50404, N'Position not found', 1;
    IF @effective_date IS NULL
        THROW 50400, N'effectiveDate|Effective date is required.', 1;
    IF @min_salary IS NULL OR @min_salary < 0
        THROW 50400, N'minSalary|Enter the min salary.', 1;
    IF @max_salary IS NULL OR @max_salary <= 0
        THROW 50400, N'maxSalary|Enter the max salary.', 1;
    IF @max_salary < @min_salary
        THROW 50400, N'maxSalary|Max salary cannot be below the min salary.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [mp].[position_salary_range]
        SET min_salary = @min_salary, max_salary = @max_salary, updated_at = @now, updated_by = @actor_user_id
        WHERE position_id = @position_id AND effective_date = @effective_date;
        IF @@ROWCOUNT = 0
            INSERT [mp].[position_salary_range] (position_id, effective_date, min_salary, max_salary, created_by)
            VALUES (@position_id, @effective_date, @min_salary, @max_salary, @actor_user_id);
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.position', @position_id, N'salary_range',
                CONCAT(CONVERT(NVARCHAR(10), @effective_date, 23), N': ', @min_salary, N' - ', @max_salary),
                N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [mp].[usp_position_salary_range_list] @company_id = @company_id, @position_id = @position_id;
END
