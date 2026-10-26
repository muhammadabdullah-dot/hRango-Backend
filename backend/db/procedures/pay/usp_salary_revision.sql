-- Salary Revision: rows of hr.employee_salary (the table belongs to the employee module; payroll writes
-- revision and import rows through these procedures). A revision is always the person's newest salary
-- row, and cannot fall in a month whose payroll is closed for them (arrears are not in the first build).

CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @salary_from     DECIMAL(18,2) = NULL,
    @salary_to       DECIMAL(18,2) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT s.id INTO #ids
    FROM [hr].[employee_salary] s
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
    JOIN [hr].[employee] e ON e.id = s.employee_id AND e.company_id = @company_id
    WHERE (@employee_id IS NULL OR s.employee_id = @employee_id)
      AND (@from_date IS NULL OR s.effective_date >= @from_date) AND (@to_date IS NULL OR s.effective_date <= @to_date)
      AND (@salary_from IS NULL OR s.amount >= @salary_from) AND (@salary_to IS NULL OR s.amount <= @salary_to)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT s.id, s.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           s.effective_date, s.previous_amount, s.amount, s.change_type, s.change_value, s.source,
           CAST(CASE WHEN s.source IN (N'revision', N'import')
                      AND NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] n WHERE n.employee_id = s.employee_id
                                      AND (n.effective_date > s.effective_date OR (n.effective_date = s.effective_date AND n.id > s.id)))
                      AND [pay].[fn_month_locked_since](s.employee_id, s.effective_date) = 0 THEN 1 ELSE 0 END AS BIT) AS can_edit,
           dp.name AS department_name, l.name AS location_name, b.name AS branch_name, jt.name AS job_title_name, ep.joining_date,
           s.created_at, s.updated_at, s.row_version
    FROM #ids i
    JOIN [hr].[employee_salary] s ON s.id = i.id
    JOIN [hr].[employee] e ON e.id = s.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[location] l ON l.id = e.location_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    OUTER APPLY (SELECT TOP 1 joining_date FROM [hr].[employment_period] x WHERE x.employee_id = e.id ORDER BY x.joining_date DESC) ep
    ORDER BY s.effective_date DESC, s.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Result set 1: the revision with the person (Salary Revision View).
CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] s
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
                   WHERE s.id = @id)
        THROW 50404, N'Salary revision not found', 1;
    SELECT s.id, s.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           s.effective_date, s.previous_amount, s.amount, s.change_type, s.change_value, s.source,
           CAST(CASE WHEN s.source IN (N'revision', N'import')
                      AND NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] n WHERE n.employee_id = s.employee_id
                                      AND (n.effective_date > s.effective_date OR (n.effective_date = s.effective_date AND n.id > s.id)))
                      AND [pay].[fn_month_locked_since](s.employee_id, s.effective_date) = 0 THEN 1 ELSE 0 END AS BIT) AS can_edit,
           dp.name AS department_name, l.name AS location_name, b.name AS branch_name, jt.name AS job_title_name, ep.joining_date,
           s.created_at, s.updated_at, s.row_version
    FROM [hr].[employee_salary] s
    JOIN [hr].[employee] e ON e.id = s.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[location] l ON l.id = e.location_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    OUTER APPLY (SELECT TOP 1 joining_date FROM [hr].[employment_period] x WHERE x.employee_id = e.id ORDER BY x.joining_date DESC) ep
    WHERE s.id = @id;
END
GO

-- The salary in force on @as_of (today when NULL), for the create form.
CREATE OR ALTER PROCEDURE [pay].[usp_salary_current]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT,
    @as_of           DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;
    SET @as_of = ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE));
    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, jt.name AS job_title_name, ep.joining_date, s.amount AS salary, s.effective_date
    FROM [hr].[employee] e
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    OUTER APPLY (SELECT TOP 1 joining_date FROM [hr].[employment_period] x WHERE x.employee_id = e.id ORDER BY x.joining_date DESC) ep
    OUTER APPLY (SELECT TOP 1 amount, effective_date FROM [hr].[employee_salary] x WHERE x.employee_id = e.id AND x.effective_date <= @as_of
                 ORDER BY x.effective_date DESC, x.id DESC) s
    WHERE e.id = @employee_id;
END
GO

-- Adds a revision (@id NULL) or edits the newest one. change_type 'flat': @change_value is added to the
-- previous salary; 'percent': the previous salary rises by @change_value percent. Returns the revision.
CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @effective_date  DATE,
    @change_type     NVARCHAR(30),
    @change_value    DECIMAL(18,2),
    @source          NVARCHAR(30) = N'revision',
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;

    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8), @old_emp BIGINT, @old_source NVARCHAR(30), @old_date DATE;
        SELECT @rv = s.row_version, @old_emp = s.employee_id, @old_source = s.source, @old_date = s.effective_date
        FROM [hr].[employee_salary] s
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
        WHERE s.id = @id;
        IF @rv IS NULL
            THROW 50404, N'Salary revision not found', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this salary revision. Reload it and try again', 1;
        IF @old_emp <> @employee_id
            THROW 50400, N'employeeId|A revision cannot move to another employee.', 1;
        IF @old_source NOT IN (N'revision', N'import')
            THROW 50409, N'status|SALARY_NOT_REVISION|This salary came from joining or a promotion. It cannot be edited here', 1;
        IF EXISTS (SELECT 1 FROM [hr].[employee_salary] n WHERE n.employee_id = @employee_id AND n.id <> @id
                   AND (n.effective_date > @old_date OR (n.effective_date = @old_date AND n.id > @id)))
            THROW 50409, N'status|SALARY_NOT_LATEST|Only the newest salary can be edited', 1;
        IF [pay].[fn_month_locked_since](@employee_id, @old_date) = 1
            THROW 50409, N'effectiveDate|MONTH_LOCKED|A payroll from that month on is closed for this person.', 1;
    END

    DECLARE @prev DECIMAL(18,2), @prev_date DATE;
    SELECT TOP 1 @prev = amount, @prev_date = effective_date FROM [hr].[employee_salary]
    WHERE employee_id = @employee_id AND (@id IS NULL OR id <> @id)
    ORDER BY effective_date DESC, id DESC;

    IF @prev_date IS NOT NULL AND @effective_date <= @prev_date
        THROW 50409, N'effectiveDate|SALARY_DATE|The effective date must be after the current salary''s.', 1;
    IF [pay].[fn_month_locked_since](@employee_id, @effective_date) = 1
        THROW 50409, N'effectiveDate|MONTH_LOCKED|A payroll from that month on is closed for this person.', 1;
    IF @change_type = N'percent' AND @prev IS NULL
        THROW 50400, N'changeType|There is no previous salary to raise by a percentage.', 1;

    DECLARE @amount DECIMAL(18,2) = CASE WHEN @change_type = N'percent' THEN ROUND(@prev * (1 + @change_value / 100.0), 2)
                                         ELSE ISNULL(@prev, 0) + @change_value END;
    IF @amount < 0
        THROW 50400, N'changeValue|The new salary cannot be below zero.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [hr].[employee_salary] (employee_id, effective_date, amount, previous_amount, change_type, change_value, source, created_by)
            VALUES (@employee_id, @effective_date, @amount, @prev, @change_type, @change_value, @source, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'hr.employee_salary', @id, N'amount', CONVERT(NVARCHAR(40), @prev), CONVERT(NVARCHAR(40), @amount), N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @old_amount DECIMAL(18,2) = (SELECT amount FROM [hr].[employee_salary] WHERE id = @id);
            UPDATE [hr].[employee_salary]
            SET effective_date = @effective_date, amount = @amount, previous_amount = @prev, change_type = @change_type,
                change_value = @change_value, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this salary revision. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'hr.employee_salary', @id, N'amount', CONVERT(NVARCHAR(40), @old_amount), CONVERT(NVARCHAR(40), @amount), N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [pay].[usp_salary_revision_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @emp BIGINT, @source NVARCHAR(30), @date DATE;
    SELECT @rv = s.row_version, @emp = s.employee_id, @source = s.source, @date = s.effective_date
    FROM [hr].[employee_salary] s
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
    WHERE s.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Salary revision not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this salary revision. Reload it and try again', 1;
    IF @source NOT IN (N'revision', N'import')
        THROW 50409, N'status|SALARY_NOT_REVISION|This salary came from joining or a promotion. It cannot be deleted here', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_salary] n WHERE n.employee_id = @emp AND n.id <> @id
               AND (n.effective_date > @date OR (n.effective_date = @date AND n.id > @id)))
        THROW 50409, N'status|SALARY_NOT_LATEST|Only the newest salary can be deleted', 1;
    IF [pay].[fn_month_locked_since](@emp, @date) = 1
        THROW 50409, N'effectiveDate|MONTH_LOCKED|A payroll from that month on is closed for this person.', 1;
    BEGIN TRAN;
        DELETE [hr].[employee_salary] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'hr.employee_salary', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Import File: @rows JSON [{"employeeCode","effectiveDate","salary"}]; each row is the new salary. Rows are
-- taken in date order per person; a row that breaks a rule is reported (row number from 1) and skipped.
CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_import]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @rows            NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    CREATE TABLE #r (row_no INT PRIMARY KEY, employee_id BIGINT, effective_date DATE, salary DECIMAL(18,2), error NVARCHAR(400));
    INSERT #r (row_no, employee_id, effective_date, salary)
    SELECT CONVERT(INT, j.[key]) + 1, e.id, TRY_CONVERT(DATE, x.effective_date), x.salary
    FROM OPENJSON(@rows) j
    CROSS APPLY OPENJSON(j.[value]) WITH (employee_code NVARCHAR(30) '$.employeeCode', effective_date NVARCHAR(20) '$.effectiveDate',
                                          salary DECIMAL(18,2) '$.salary') x
    LEFT JOIN [hr].[employee] e ON e.company_id = @company_id AND e.code = x.employee_code
         AND e.id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code));

    UPDATE #r SET error = N'Employee code not found.' WHERE employee_id IS NULL;
    UPDATE #r SET error = N'Effective date is not a date.' WHERE error IS NULL AND effective_date IS NULL;
    UPDATE #r SET error = N'Salary must be above zero.' WHERE error IS NULL AND ISNULL(salary, 0) <= 0;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    UPDATE #r SET error = N'You cannot change your own salary.' WHERE error IS NULL AND employee_id = @me;

    DECLARE @n INT, @emp BIGINT, @date DATE, @salary DECIMAL(18,2), @prev DECIMAL(18,2), @prev_date DATE, @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT row_no, employee_id, effective_date, salary FROM #r WHERE error IS NULL ORDER BY employee_id, effective_date, row_no;
    BEGIN TRAN;
        OPEN c;
        FETCH NEXT FROM c INTO @n, @emp, @date, @salary;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @prev = NULL, @prev_date = NULL;
            SELECT TOP 1 @prev = amount, @prev_date = effective_date FROM [hr].[employee_salary]
            WHERE employee_id = @emp ORDER BY effective_date DESC, id DESC;
            IF @prev_date IS NOT NULL AND @date <= @prev_date
                UPDATE #r SET error = N'The effective date must be after the current salary''s.' WHERE row_no = @n;
            ELSE IF [pay].[fn_month_locked_since](@emp, @date) = 1
                UPDATE #r SET error = N'A payroll from that month on is closed for this person.' WHERE row_no = @n;
            ELSE
                INSERT [hr].[employee_salary] (employee_id, effective_date, amount, previous_amount, change_type, change_value, source, created_by)
                VALUES (@emp, @date, @salary, @prev, N'flat', @salary - ISNULL(@prev, 0), N'import', @actor_user_id);
            FETCH NEXT FROM c INTO @n, @emp, @date, @salary;
        END
        CLOSE c;
        DEALLOCATE c;
    COMMIT;

    SELECT COUNT(*) AS created FROM #r WHERE error IS NULL;
    SELECT row_no, error FROM #r WHERE error IS NOT NULL ORDER BY row_no;
END
