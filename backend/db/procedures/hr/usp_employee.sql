-- Employee records (Talent Management): directory, card, add, edit, switch off and on.
-- Every procedure takes the permission code the endpoint required and reaches only the employees
-- that code's scope covers (auth.fn_visible_employees). Another company's or an out-of-scope
-- employee is "not found". The CNIC is returned only to holders of employees.identity.view.

CREATE OR ALTER PROCEDURE [hr].[usp_employee_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @permission_code NVARCHAR(150) = N'employees.directory.view'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
                   WHERE e.id = @id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT r.*, CASE WHEN iv.employee_id IS NOT NULL THEN e.cnic END AS cnic,
           CAST(CASE WHEN iv.employee_id IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS can_see_identity,
           (SELECT TOP 1 u.id FROM [auth].[user_account] u WHERE u.employee_id = e.id) AS user_account_id
    FROM [hr].[fn_employee_rows](@company_id) r
    JOIN [hr].[employee] e ON e.id = r.id
    LEFT JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.identity.view') iv ON iv.employee_id = r.id
    WHERE r.id = @id;
END
GO

-- The directory. Result set 1: total. Result set 2: the page. Left and switched-off employees are
-- hidden unless @status names them or @include_inactive = 1.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_list]
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
    @gender             NVARCHAR(30) = NULL,
    @page               INT = 1,
    @page_size          INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT e.id
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

    SELECT COUNT(*) AS total FROM @ids;

    SELECT r.*, CASE WHEN iv.employee_id IS NOT NULL THEN e.cnic END AS cnic,
           CAST(CASE WHEN iv.employee_id IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS can_see_identity,
           CAST(NULL AS BIGINT) AS user_account_id
    FROM @ids i
    JOIN [hr].[fn_employee_rows](@company_id) r ON r.id = i.id
    JOIN [hr].[employee] e ON e.id = r.id
    LEFT JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.identity.view') iv ON iv.employee_id = r.id
    ORDER BY r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Picker: up to @limit employees the caller reaches through @permission_code (any catalogue code,
-- e.g. the request screen's create code), matching @search. Ids, codes, names, placement and photo.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_lookup]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @search           NVARCHAR(200) = NULL,
    @branch_id        BIGINT = NULL,
    @department_id    BIGINT = NULL,
    @include_inactive BIT = 0,
    @limit            INT = 50,     -- the page size when @page_size is not given (older callers)
    @page             INT = 1,
    @page_size        INT = NULL
AS
-- Result set 1: the total; 2: the page.
BEGIN
    SET NOCOUNT ON;
    SET @page_size = ISNULL(@page_size, @limit);
    IF @page_size < 1 SET @page_size = 1;
    IF @page_size > 100 SET @page_size = 100;
    IF @page IS NULL OR @page < 1 SET @page = 1;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT e.id
    INTO #hit
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    WHERE e.company_id = @company_id
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@include_inactive = 1 OR e.status NOT IN (N'left', N'inactive'))
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #hit;

    SELECT e.id, e.code, LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))) AS name,
           ds.name AS designation_name, jt.name AS job_title_name, e.department_id, d.name AS department_name,
           e.branch_id, b.name AS branch_name, e.status, e.photo_file_id
    FROM #hit h
    JOIN [hr].[employee] e ON e.id = h.id
    JOIN [org].[branch] b ON b.id = e.branch_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    ORDER BY e.first_name, e.last_name, e.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds an employee (@id NULL, with their first employment period from @joining_date) or edits one
-- (@id and the @row_version last read). The CNIC is written only when @set_cnic = 1 (the service
-- checks employees.identity.edit). The code is generated from the branch (or location) prefix when
-- not given. Placement changes on an edit are kept in hr.employee_history as change_type edit.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @id                 BIGINT = NULL,
    @code               NVARCHAR(30) = NULL,
    @first_name         NVARCHAR(200),
    @last_name          NVARCHAR(200),
    @parent_name        NVARCHAR(200) = NULL,
    @gender             NVARCHAR(30) = NULL,
    @marital_status     NVARCHAR(30) = NULL,
    @religion           NVARCHAR(50) = NULL,
    @nationality        NVARCHAR(50) = NULL,
    @date_of_birth      DATE = NULL,
    @set_cnic           BIT = 0,
    @cnic               NVARCHAR(15) = NULL,
    @email              NVARCHAR(254) = NULL,
    @phone_1            NVARCHAR(30) = NULL,
    @phone_2            NVARCHAR(30) = NULL,
    @home_address       NVARCHAR(500) = NULL,
    @home_city_id       BIGINT = NULL,
    @branch_id          BIGINT,
    @location_id        BIGINT = NULL,
    @area_id            BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @division_id        BIGINT = NULL,
    @cost_center_id     BIGINT = NULL,
    @designation_id     BIGINT = NULL,
    @job_title_id       BIGINT = NULL,
    @grade_id           BIGINT = NULL,
    @job_level_id       BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @employment_type_id BIGINT = NULL,
    @line_manager_id    BIGINT = NULL,
    @final_authority_id BIGINT = NULL,
    @status             NVARCHAR(30) = N'active',
    @salary_frequency   NVARCHAR(30) = N'monthly',
    @joining_date       DATE = NULL,
    @probation_end_date DATE = NULL,
    @confirmation_date  DATE = NULL,
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @code = NULLIF(LTRIM(RTRIM(@code)), N'');
    SET @first_name = LTRIM(RTRIM(@first_name));
    SET @last_name = LTRIM(RTRIM(@last_name));
    SET @parent_name = NULLIF(LTRIM(RTRIM(@parent_name)), N'');
    SET @religion = NULLIF(LTRIM(RTRIM(@religion)), N'');
    SET @nationality = NULLIF(LTRIM(RTRIM(@nationality)), N'');
    SET @cnic = NULLIF(LTRIM(RTRIM(@cnic)), N'');
    SET @email = NULLIF(LOWER(LTRIM(RTRIM(@email))), N'');
    SET @phone_1 = NULLIF(LTRIM(RTRIM(@phone_1)), N'');
    SET @phone_2 = NULLIF(LTRIM(RTRIM(@phone_2)), N'');
    SET @home_address = NULLIF(LTRIM(RTRIM(@home_address)), N'');

    DECLARE @old_status NVARCHAR(30), @old_rv BINARY(8), @old_job_title BIGINT, @old_cnic NVARCHAR(15);
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_status = e.status, @old_rv = e.row_version, @old_job_title = e.job_title_id, @old_cnic = e.cnic
        FROM [hr].[employee] e
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
        WHERE e.id = @id AND e.company_id = @company_id;

        IF @old_rv IS NULL
            THROW 50404, N'Employee not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an employee.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;
        IF @set_cnic = 0
            SET @cnic = @old_cnic;
    END
    ELSE IF @set_cnic = 0
        SET @cnic = NULL;

    -- Field checks.
    IF @first_name IS NULL OR @first_name = N''
        THROW 50400, N'firstName|First name is required.', 1;
    IF @last_name IS NULL OR @last_name = N''
        THROW 50400, N'lastName|Last name is required.', 1;
    IF NOT (   @status IN (N'active', N'probation') OR (@id IS NOT NULL AND @status = N'notice')
            OR (@id IS NOT NULL AND @status = @old_status))
        THROW 50400, N'status|Choose active or probation (notice once employed). Leaving and switching off have their own steps.', 1;
    IF @id IS NULL AND @joining_date IS NULL
        THROW 50400, N'joiningDate|Joining date is required.', 1;
    IF @probation_end_date < @joining_date
        THROW 50400, N'probationEndDate|Probation cannot end before the joining date.', 1;
    IF @confirmation_date < @joining_date
        THROW 50400, N'confirmationDate|Confirmation cannot be before the joining date.', 1;
    IF @date_of_birth IS NOT NULL AND @date_of_birth > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'dateOfBirth|Date of birth is in the future.', 1;
    IF @home_city_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[city] WHERE id = @home_city_id)
        THROW 50400, N'homeCityId|City not found.', 1;

    -- Placement must belong to this company and fit together.
    DECLARE @branch_location BIGINT, @branch_area BIGINT;
    SELECT @branch_location = location_id, @branch_area = area_id FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id;
    IF @branch_location IS NULL
        THROW 50400, N'branchId|Branch not found.', 1;
    SET @location_id = ISNULL(@location_id, @branch_location);
    IF @location_id <> @branch_location
        THROW 50400, N'locationId|The branch is not in this location.', 1;
    SET @area_id = ISNULL(@area_id, @branch_area);
    IF @area_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[area] WHERE id = @area_id AND location_id = @location_id)
        THROW 50400, N'areaId|This area is not in the branch''s location.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @division_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[division] WHERE id = @division_id AND company_id = @company_id)
        THROW 50400, N'divisionId|Division not found.', 1;
    IF @cost_center_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[cost_center] WHERE id = @cost_center_id AND company_id = @company_id)
        THROW 50400, N'costCenterId|Cost center not found.', 1;
    IF @designation_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[designation] WHERE id = @designation_id AND company_id = @company_id)
        THROW 50400, N'designationId|Designation not found.', 1;
    IF @job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50400, N'jobTitleId|Job title not found.', 1;
    IF @grade_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[grade] WHERE id = @grade_id AND company_id = @company_id)
        THROW 50400, N'gradeId|Grade not found.', 1;
    IF @job_level_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_level] WHERE id = @job_level_id AND company_id = @company_id)
        THROW 50400, N'jobLevelId|Job level not found.', 1;
    IF @employee_group_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[employee_group] WHERE id = @employee_group_id AND company_id = @company_id)
        THROW 50400, N'employeeGroupId|Employee group not found.', 1;
    IF @employment_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[employment_type] WHERE id = @employment_type_id AND company_id = @company_id)
        THROW 50400, N'employmentTypeId|Employment type not found.', 1;
    IF @line_manager_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @line_manager_id AND company_id = @company_id)
        THROW 50400, N'lineManagerId|Line manager not found.', 1;
    IF @line_manager_id IS NOT NULL AND (@line_manager_id = @id
        OR EXISTS (SELECT 1 FROM [hr].[fn_manager_chain](@line_manager_id) c WHERE c.id = @id))
        THROW 50400, N'lineManagerId|LINE_MANAGER_CYCLE|An employee cannot report to themselves or to someone who reports to them.', 1;
    IF @final_authority_id IS NOT NULL AND (@final_authority_id = @id
        OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @final_authority_id AND company_id = @company_id))
        THROW 50400, N'finalAuthorityId|Final authority not found.', 1;

    -- Duplicates and limits.
    IF @code IS NOT NULL AND EXISTS (SELECT 1 FROM [hr].[employee] WHERE company_id = @company_id AND code = @code AND (@id IS NULL OR id <> @id))
        THROW 50409, N'code|EMPLOYEE_CODE_DUPLICATE|Another employee has this code.', 1;
    IF @cnic IS NOT NULL AND EXISTS (SELECT 1 FROM [hr].[employee] WHERE company_id = @company_id AND cnic = @cnic AND (@id IS NULL OR id <> @id))
        THROW 50409, N'cnic|EMPLOYEE_CNIC_DUPLICATE|Another employee has this CNIC.', 1;
    IF @job_title_id IS NOT NULL AND (@id IS NULL OR ISNULL(@old_job_title, 0) <> @job_title_id)
       AND EXISTS (SELECT 1 FROM [org].[job_title] j
                   WHERE j.id = @job_title_id AND j.limit_head_count = 1
                     AND j.max_head_count <= (SELECT COUNT(*) FROM [hr].[employee] x
                                              WHERE x.job_title_id = j.id AND x.status NOT IN (N'left', N'inactive')))
        THROW 50409, N'jobTitleId|JOB_TITLE_FULL|This job title has reached its head-count limit.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        IF @code IS NULL
        BEGIN
            -- Next free number for the branch's (or location's) prefix.
            DECLARE @prefix NVARCHAR(10) = COALESCE(
                (SELECT employee_prefix FROM [org].[branch] WHERE id = @branch_id),
                (SELECT employee_prefix FROM [org].[location] WHERE id = @location_id), N'EMP');
            DECLARE @n INT;
            IF NOT EXISTS (SELECT 1 FROM [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK) WHERE company_id = @company_id AND prefix = @prefix)
                INSERT [core].[number_sequence] (company_id, prefix, next_number) VALUES (@company_id, @prefix, 1);
            WHILE 1 = 1
            BEGIN
                UPDATE [core].[number_sequence] SET @n = next_number, next_number = next_number + 1
                WHERE company_id = @company_id AND prefix = @prefix;
                SET @code = CONCAT(@prefix, N'-', RIGHT(CONCAT(N'0000', @n), CASE WHEN @n > 9999 THEN LEN(@n) ELSE 4 END));
                IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE company_id = @company_id AND code = @code)
                    BREAK;
            END
        END

        INSERT [hr].[employee] (company_id, code, first_name, last_name, parent_name, gender, marital_status, religion,
                                nationality, date_of_birth, cnic, email, phone_1, phone_2, home_address, home_city_id,
                                branch_id, location_id, area_id,
                                department_id, division_id, cost_center_id, designation_id, job_title_id, grade_id,
                                job_level_id, employee_group_id, employment_type_id, line_manager_id, final_authority_id,
                                status, salary_frequency, created_by)
        VALUES (@company_id, @code, @first_name, @last_name, @parent_name, @gender, @marital_status, @religion,
                @nationality, @date_of_birth, @cnic, @email, @phone_1, @phone_2, @home_address, @home_city_id,
                @branch_id, @location_id, @area_id,
                @department_id, @division_id, @cost_center_id, @designation_id, @job_title_id, @grade_id,
                @job_level_id, @employee_group_id, @employment_type_id, @line_manager_id, @final_authority_id,
                @status, @salary_frequency, @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        INSERT [hr].[employment_period] (employee_id, joining_date, probation_end_date, confirmation_date, created_by)
        VALUES (@id, @joining_date, @probation_end_date, @confirmation_date, @actor_user_id);

        INSERT [hr].[employee_history] (employee_id, change_type, effective_date, location_id, branch_id, department_id,
                                        designation_id, job_title_id, grade_id, job_level_id, line_manager_id,
                                        final_authority_id, created_by)
        VALUES (@id, N'joining', @joining_date, @location_id, @branch_id, @department_id, @designation_id, @job_title_id,
                @grade_id, @job_level_id, @line_manager_id, @final_authority_id, @actor_user_id);

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee', @id, N'create', @actor_user_id, @now);

        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @id,
             @event_type = N'employees.created', @change = N'joining', @actor_user_id = @actor_user_id;
    END
    ELSE
    BEGIN
        DECLARE @before NVARCHAR(MAX) = (
            SELECT code, first_name, last_name, parent_name, gender, marital_status, religion, nationality, date_of_birth,
                   email, phone_1, phone_2, home_address, home_city_id, location_id, branch_id, area_id, department_id,
                   division_id, cost_center_id,
                   designation_id, job_title_id, grade_id, job_level_id, employee_group_id, employment_type_id,
                   line_manager_id, final_authority_id, status, salary_frequency
            FROM [hr].[employee] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        DECLARE @placement_before NVARCHAR(MAX) = (
            SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
                   line_manager_id, final_authority_id
            FROM [hr].[employee] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

        UPDATE [hr].[employee]
        SET code = ISNULL(@code, code), first_name = @first_name, last_name = @last_name, parent_name = @parent_name,
            gender = @gender, marital_status = @marital_status, religion = @religion, nationality = @nationality,
            date_of_birth = @date_of_birth, cnic = @cnic, email = @email, phone_1 = @phone_1, phone_2 = @phone_2,
            home_address = @home_address, home_city_id = @home_city_id,
            branch_id = @branch_id, location_id = @location_id, area_id = @area_id, department_id = @department_id,
            division_id = @division_id, cost_center_id = @cost_center_id, designation_id = @designation_id,
            job_title_id = @job_title_id, grade_id = @grade_id, job_level_id = @job_level_id,
            employee_group_id = @employee_group_id, employment_type_id = @employment_type_id,
            line_manager_id = @line_manager_id, final_authority_id = @final_authority_id, status = @status,
            salary_frequency = @salary_frequency, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;

        DECLARE @after NVARCHAR(MAX) = (
            SELECT code, first_name, last_name, parent_name, gender, marital_status, religion, nationality, date_of_birth,
                   email, phone_1, phone_2, home_address, home_city_id, location_id, branch_id, area_id, department_id,
                   division_id, cost_center_id,
                   designation_id, job_title_id, grade_id, job_level_id, employee_group_id, employment_type_id,
                   line_manager_id, final_authority_id, status, salary_frequency
            FROM [hr].[employee] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

        -- One audit row per changed field (the CNIC's value is not copied into the log).
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'hr.employee', @id, b.[key], b.value, a.value, N'update', @actor_user_id, @now
        FROM OPENJSON(@before) b
        JOIN OPENJSON(@after) a ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);

        IF ISNULL(@old_cnic, N'') <> ISNULL(@cnic, N'')
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'hr.employee', @id, N'cnic', N'update', @actor_user_id, @now);

        IF @placement_before <> (SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id,
                                        job_level_id, line_manager_id, final_authority_id
                                 FROM [hr].[employee] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)
            INSERT [hr].[employee_history] (employee_id, change_type, effective_date, location_id, branch_id, department_id,
                                            designation_id, job_title_id, grade_id, job_level_id, line_manager_id,
                                            final_authority_id, previous_values, created_by)
            VALUES (@id, N'edit', @today, @location_id, @branch_id, @department_id, @designation_id, @job_title_id,
                    @grade_id, @job_level_id, @line_manager_id, @final_authority_id, @placement_before, @actor_user_id);

        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @id,
             @event_type = N'employees.updated', @change = N'edit', @actor_user_id = @actor_user_id;
    END

    -- The saved employee must still be someone the caller may reach with this permission (a
    -- department head cannot add or move people outside their department).
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = @id)
        THROW 50403, N'You can only add or place employees within the people your permission covers.', 1;
    COMMIT;

    EXEC [hr].[usp_employee_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = @permission_code;
END
GO

-- Sets the CNIC (employees.identity.edit).
CREATE OR ALTER PROCEDURE [hr].[usp_employee_identity_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @cnic          NVARCHAR(15) = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @cnic = NULLIF(LTRIM(RTRIM(@cnic)), N'');
    DECLARE @old_rv BINARY(8), @old_cnic NVARCHAR(15);
    SELECT @old_rv = e.row_version, @old_cnic = e.cnic
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.identity.edit') v ON v.employee_id = e.id
    WHERE e.id = @id AND e.company_id = @company_id;

    IF @old_rv IS NULL
        THROW 50404, N'Employee not found', 1;
    IF @old_rv <> @row_version
        THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;
    IF @cnic IS NOT NULL AND EXISTS (SELECT 1 FROM [hr].[employee] WHERE company_id = @company_id AND cnic = @cnic AND id <> @id)
        THROW 50409, N'cnic|EMPLOYEE_CNIC_DUPLICATE|Another employee has this CNIC.', 1;

    BEGIN TRAN;
        UPDATE [hr].[employee] SET cnic = @cnic, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;
        IF ISNULL(@old_cnic, N'') <> ISNULL(@cnic, N'')
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'hr.employee', @id, N'cnic', N'update', @actor_user_id, SYSUTCDATETIME());
        -- The CNIC itself is never put in an event.
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @id,
             @event_type = N'employees.updated', @change = N'identity', @actor_user_id = @actor_user_id;
    COMMIT;

    EXEC [hr].[usp_employee_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'employees.identity.edit';
END
GO

-- Switches an employee off (@active = 0: status inactive, their sign-in accounts switched off and
-- signed out) or back on (@active = 1: status active; accounts stay off until an administrator
-- switches them on). Leaving the company is the separation module's job, not this.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_active_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @active        BIT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30);
    SELECT @old_rv = e.row_version, @old_status = e.status
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.directory.delete') v ON v.employee_id = e.id
    WHERE e.id = @id AND e.company_id = @company_id;

    IF @old_rv IS NULL
        THROW 50404, N'Employee not found', 1;
    IF @old_rv <> @row_version
        THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;
    IF @active = 0 AND EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @actor_user_id AND employee_id = @id)
        THROW 50403, N'You cannot switch off your own record.', 1;
    IF @active = 0 AND @old_status = N'inactive'
        THROW 50409, N'This employee is already switched off.', 1;
    IF @active = 1 AND @old_status <> N'inactive'
        THROW 50409, N'This employee is not switched off.', 1;

    DECLARE @new NVARCHAR(30) = CASE WHEN @active = 1 THEN N'active' ELSE N'inactive' END;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [hr].[employee] SET status = @new, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;

        IF @active = 0
        BEGIN
            UPDATE [auth].[user_session] SET revoked_at = @now, updated_at = @now
            WHERE revoked_at IS NULL AND user_account_id IN (SELECT id FROM [auth].[user_account] WHERE employee_id = @id);
            UPDATE [auth].[user_account] SET is_active = 0, updated_at = @now, updated_by = @actor_user_id
            WHERE employee_id = @id AND is_active = 1;
        END

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee', @id, N'status', @old_status, @new, CASE WHEN @active = 1 THEN N'reactivate' ELSE N'deactivate' END,
                @actor_user_id, @now);

        DECLARE @event NVARCHAR(100) = CASE WHEN @active = 1 THEN N'employees.reactivated' ELSE N'employees.deactivated' END;
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @id,
             @event_type = @event, @change = @event, @actor_user_id = @actor_user_id;
    COMMIT;

    EXEC [hr].[usp_employee_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'employees.directory.delete';
END
GO

-- Sets or clears the profile photo (employees.photo.edit). The file must be one of this company's
-- uploads and an image. Returns the card.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_photo_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @file_id       BIGINT = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @old_rv BINARY(8), @old_file BIGINT;
    SELECT @old_rv = e.row_version, @old_file = e.photo_file_id
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.photo.edit') v ON v.employee_id = e.id
    WHERE e.id = @id AND e.company_id = @company_id;

    IF @old_rv IS NULL
        THROW 50404, N'Employee not found', 1;
    IF @row_version IS NULL OR @old_rv <> @row_version
        THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[stored_file] WHERE id = @file_id AND mime_type LIKE N'image/%')
        THROW 50400, N'fileId|PHOTO_NOT_IMAGE|A profile photo must be an image (PNG, JPEG, GIF or WebP).', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [hr].[employee] SET photo_file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this employee. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee', @id, N'photo_file_id', CONVERT(NVARCHAR(30), @old_file), CONVERT(NVARCHAR(30), @file_id),
                N'update', @actor_user_id, @now);
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @id,
             @event_type = N'employees.updated', @change = N'photo', @actor_user_id = @actor_user_id;
    COMMIT;

    EXEC [hr].[usp_employee_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'employees.photo.edit';
END
