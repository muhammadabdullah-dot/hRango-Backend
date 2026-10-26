-- Salary over time (employees.salary, sensitive). The current salary is the latest row whose
-- effective date has come. Payroll's Salary Revision screen may add rows with source = revision
-- through hr.usp_employee_salary_save.

CREATE OR ALTER PROCEDURE [hr].[usp_employee_salary_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.view') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @current BIGINT = (SELECT TOP 1 id FROM [hr].[employee_salary]
                               WHERE employee_id = @employee_id AND effective_date <= @today
                               ORDER BY effective_date DESC, id DESC);

    SELECT s.id, s.employee_id, s.effective_date, s.amount, s.previous_amount, s.change_type, s.change_value,
           s.source, s.source_request_id, s.remarks,
           CAST(CASE WHEN s.id = @current THEN 1 ELSE 0 END AS BIT) AS is_current,
           s.created_at, s.updated_at, s.row_version
    FROM [hr].[employee_salary] s
    WHERE s.employee_id = @employee_id
    ORDER BY s.effective_date DESC, s.id DESC;
END
GO

-- Adds a salary row (@id NULL) or corrects one. previous_amount is the salary in force the day
-- before the effective date, so the history reads as a chain.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_salary_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @employee_id       BIGINT,
    @id                BIGINT = NULL,
    @effective_date    DATE,
    @amount            DECIMAL(18,2),
    @change_type       NVARCHAR(30) = NULL,
    @change_value      DECIMAL(18,2) = NULL,
    @source            NVARCHAR(30) = N'revision',
    @source_request_id BIGINT = NULL,
    @remarks           NVARCHAR(MAX) = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
    IF @effective_date IS NULL
        THROW 50400, N'effectiveDate|Effective date is required.', 1;
    IF @amount IS NULL OR @amount < 0
        THROW 50400, N'amount|Enter a salary of 0 or more.', 1;
    IF @source NOT IN (N'joining', N'revision', N'promotion', N'import')
        THROW 50400, N'source|Choose joining, revision, promotion or import.', 1;
    IF @change_type IS NOT NULL AND @change_type NOT IN (N'flat', N'percent')
        THROW 50400, N'changeType|Choose flat or percent.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_salary] WHERE employee_id = @employee_id AND effective_date = @effective_date
               AND (@id IS NULL OR id <> @id))
        THROW 50409, N'effectiveDate|SALARY_DATE_TAKEN|This employee already has a salary from this date. Edit that one instead.', 1;

    DECLARE @previous DECIMAL(18,2) = (SELECT TOP 1 amount FROM [hr].[employee_salary]
                                       WHERE employee_id = @employee_id AND effective_date < @effective_date
                                         AND (@id IS NULL OR id <> @id)
                                       ORDER BY effective_date DESC, id DESC);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_salary] (employee_id, effective_date, amount, previous_amount, change_type, change_value,
                                       source, source_request_id, remarks, created_by)
        VALUES (@employee_id, @effective_date, @amount, @previous, @change_type, @change_value, @source,
                @source_request_id, NULLIF(LTRIM(RTRIM(@remarks)), N''), @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_salary]
        SET effective_date = @effective_date, amount = @amount, previous_amount = @previous, change_type = @change_type,
            change_value = @change_value, source = @source, remarks = NULLIF(LTRIM(RTRIM(@remarks)), N''),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Salary entry not found', 1;
            THROW 50409, N'Someone else changed this salary entry. Reload it and try again', 1;
        END
    END

    -- Keep the next row's previous_amount in step.
    UPDATE n SET previous_amount = @amount
    FROM [hr].[employee_salary] n
    WHERE n.id = (SELECT TOP 1 id FROM [hr].[employee_salary]
                  WHERE employee_id = @employee_id AND effective_date > @effective_date
                  ORDER BY effective_date, id);

    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
    VALUES (@company_id, N'hr.employee', @employee_id, N'salary', CONVERT(NVARCHAR(10), @effective_date, 23),
            CASE WHEN @row_version IS NULL THEN N'create' ELSE N'update' END, @actor_user_id, @now);
    COMMIT;

    SELECT s.id, s.employee_id, s.effective_date, s.amount, s.previous_amount, s.change_type, s.change_value,
           s.source, s.source_request_id, s.remarks,
           CAST(CASE WHEN s.effective_date <= CAST(SYSUTCDATETIME() AS DATE)
                      AND NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] x WHERE x.employee_id = s.employee_id
                                      AND x.effective_date <= CAST(SYSUTCDATETIME() AS DATE)
                                      AND (x.effective_date > s.effective_date OR (x.effective_date = s.effective_date AND x.id > s.id)))
                THEN 1 ELSE 0 END AS BIT) AS is_current,
           s.created_at, s.updated_at, s.row_version
    FROM [hr].[employee_salary] s WHERE s.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_salary_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    DECLARE @rv BINARY(8), @date DATE, @source NVARCHAR(30);
    SELECT @rv = row_version, @date = effective_date, @source = source
    FROM [hr].[employee_salary] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Salary entry not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this salary entry. Reload it and try again', 1;
    IF @source = N'promotion'
        THROW 50409, N'This salary came from an approved promotion. Cancel the promotion request instead.', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_salary] WHERE id = @id;
        UPDATE n SET previous_amount = (SELECT TOP 1 amount FROM [hr].[employee_salary] p
                                        WHERE p.employee_id = @employee_id AND p.effective_date < n.effective_date
                                        ORDER BY p.effective_date DESC, p.id DESC)
        FROM [hr].[employee_salary] n
        WHERE n.id = (SELECT TOP 1 id FROM [hr].[employee_salary]
                      WHERE employee_id = @employee_id AND effective_date > @date ORDER BY effective_date, id);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee', @employee_id, N'salary', CONVERT(NVARCHAR(10), @date, 23), N'delete',
                @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
