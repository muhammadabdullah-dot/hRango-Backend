-- The tabs of an employee's record: employment periods, placement history, field changes.
-- Each takes the permission code the endpoint required; an out-of-scope employee is "not found".

CREATE OR ALTER PROCEDURE [hr].[usp_employment_period_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @permission_code NVARCHAR(150) = N'employees.directory.view'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT p.id, p.employee_id, p.joining_date, p.confirmation_date, p.probation_end_date, p.end_date,
           p.end_of_employment_id, p.created_at, p.updated_at, p.row_version
    FROM [hr].[employment_period] p
    WHERE p.employee_id = @employee_id
    ORDER BY p.joining_date DESC, p.id DESC;
END
GO

-- Adds an employment period (a rehire; the previous one must have ended) or edits one.
-- Periods may not overlap and only one may be open (no end date).
CREATE OR ALTER PROCEDURE [hr].[usp_employment_period_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @employee_id        BIGINT,
    @id                 BIGINT = NULL,
    @joining_date       DATE,
    @confirmation_date  DATE = NULL,
    @probation_end_date DATE = NULL,
    @end_date           DATE = NULL,
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.directory.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
    IF @joining_date IS NULL
        THROW 50400, N'joiningDate|Joining date is required.', 1;
    IF @end_date < @joining_date
        THROW 50400, N'endDate|The end date is before the joining date.', 1;
    IF @probation_end_date < @joining_date
        THROW 50400, N'probationEndDate|Probation cannot end before the joining date.', 1;
    IF @confirmation_date < @joining_date
        THROW 50400, N'confirmationDate|Confirmation cannot be before the joining date.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employment_period] p
               WHERE p.employee_id = @employee_id AND (@id IS NULL OR p.id <> @id)
                 AND p.joining_date <= ISNULL(@end_date, '9999-12-31')
                 AND ISNULL(p.end_date, '9999-12-31') >= @joining_date)
        THROW 50409, N'joiningDate|PERIOD_OVERLAP|This period overlaps another employment period of this employee.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [hr].[employment_period] (employee_id, joining_date, confirmation_date, probation_end_date, end_date, created_by)
            VALUES (@employee_id, @joining_date, @confirmation_date, @probation_end_date, @end_date, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'hr.employee', @employee_id, N'employment_period', CONVERT(NVARCHAR(10), @joining_date, 23),
                    N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [hr].[employment_period] WHERE id = @id AND employee_id = @employee_id);
        IF @rv IS NULL
            THROW 50404, N'Employment period not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this employment period. Reload it and try again', 1;
        BEGIN TRAN;
            UPDATE [hr].[employment_period]
            SET joining_date = @joining_date, confirmation_date = @confirmation_date,
                probation_end_date = @probation_end_date, end_date = @end_date, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this employment period. Reload it and try again', 1;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'hr.employee', @employee_id, N'employment_period', CONVERT(NVARCHAR(10), @joining_date, 23),
                    N'update', @actor_user_id, @now);
        COMMIT;
    END

    SELECT p.id, p.employee_id, p.joining_date, p.confirmation_date, p.probation_end_date, p.end_date,
           p.end_of_employment_id, p.created_at, p.updated_at, p.row_version
    FROM [hr].[employment_period] p WHERE p.id = @id;
END
GO

-- Placement over time: joining, transfers, promotions, demotions and edits, newest first.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_history_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.history.view') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT h.id, h.employee_id, h.change_type, h.effective_date,
           h.location_id, l.name AS location_name, h.branch_id, b.name AS branch_name,
           h.department_id, d.name AS department_name, h.designation_id, ds.name AS designation_name,
           h.job_title_id, jt.name AS job_title_name, h.grade_id, g.name AS grade_name,
           h.job_level_id, jl.name AS job_level_name,
           h.line_manager_id, NULLIF(LTRIM(RTRIM(CONCAT(lm.first_name, N' ', lm.last_name))), N'') AS line_manager_name,
           h.final_authority_id, NULLIF(LTRIM(RTRIM(CONCAT(fa.first_name, N' ', fa.last_name))), N'') AS final_authority_name,
           h.source_request_id, h.is_reverted, h.created_at,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.first_name, N' ', ue.last_name))), N''), u.display_name, u.email) AS created_by_name
    FROM [hr].[employee_history] h
    LEFT JOIN [org].[location] l ON l.id = h.location_id
    LEFT JOIN [org].[branch] b ON b.id = h.branch_id
    LEFT JOIN [org].[department] d ON d.id = h.department_id
    LEFT JOIN [org].[designation] ds ON ds.id = h.designation_id
    LEFT JOIN [org].[job_title] jt ON jt.id = h.job_title_id
    LEFT JOIN [org].[grade] g ON g.id = h.grade_id
    LEFT JOIN [org].[job_level] jl ON jl.id = h.job_level_id
    LEFT JOIN [hr].[employee] lm ON lm.id = h.line_manager_id
    LEFT JOIN [hr].[employee] fa ON fa.id = h.final_authority_id
    LEFT JOIN [auth].[user_account] u ON u.id = h.created_by
    LEFT JOIN [hr].[employee] ue ON ue.id = u.employee_id
    WHERE h.employee_id = @employee_id
    ORDER BY h.effective_date DESC, h.id DESC;
END
GO

-- Field-level changes to the employee record (core.audit_log). Result set 1: total. 2: the page.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_change_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.history.view') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT COUNT(*) AS total FROM [core].[audit_log] WHERE entity_type = N'hr.employee' AND entity_id = @employee_id;

    SELECT a.id, a.field_name, a.old_value, a.new_value, a.action_name, a.performed_at,
           a.performed_by_user_id,
           COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.first_name, N' ', ue.last_name))), N''), u.display_name, u.email) AS performed_by_name
    FROM [core].[audit_log] a
    LEFT JOIN [auth].[user_account] u ON u.id = a.performed_by_user_id
    LEFT JOIN [hr].[employee] ue ON ue.id = u.employee_id
    WHERE a.entity_type = N'hr.employee' AND a.entity_id = @employee_id
    ORDER BY a.performed_at DESC, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
