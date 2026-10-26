-- Payrolls -> Daily Wages: one run per day and time slot. Wages come from the day's time sheet:
--   hourly rate x hours worked, daily rate x the day (half for a half day), or monthly salary / days in
--   the month x the day. The rate is the person's salary (hr.employee_salary) read with their salary
--   frequency (hr.employee.salary_frequency).

-- Adds a daily-wage run (@id NULL) with its employees, or edits its name. Result: the run.
CREATE OR ALTER PROCEDURE [pay].[usp_daily_wage_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @work_date       DATE = NULL,
    @time_slot_id    BIGINT = NULL,
    @employee_ids    NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    IF @id IS NULL
    BEGIN
        IF @work_date IS NULL
            THROW 50400, N'workDate|Date is required.', 1;
        IF @time_slot_id IS NULL OR NOT EXISTS (SELECT 1 FROM [sch].[time_slot] WHERE id = @time_slot_id AND company_id = @company_id)
            THROW 50400, N'timeSlotId|Time slot not found.', 1;
        BEGIN TRAN;
            EXEC [pay].[usp_sequence_next] @company_id, N'PR-', 5, @code OUTPUT;
            INSERT [pay].[payroll] (company_id, code, name, kind, work_date, time_slot_id, applicable_days, status, created_by)
            VALUES (@company_id, @code, @name, N'daily_wage', @work_date, @time_slot_id, N'actual', N'open', @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.payroll', @id, N'create', @actor_user_id, @now);
            IF @employee_ids IS NOT NULL
                EXEC [pay].[usp_payroll_employee_set] @company_id = @company_id, @actor_user_id = @actor_user_id,
                     @permission_code = @permission_code, @id = @id, @employee_ids = @employee_ids, @mode = N'replace';
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8), @status NVARCHAR(30);
        SELECT @rv = row_version, @status = status FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = N'daily_wage';
        IF @rv IS NULL
            THROW 50404, N'Payroll not found', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;
        IF @status = N'closed'
            THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. It cannot be changed', 1;
        BEGIN TRAN;
            UPDATE [pay].[payroll] SET name = @name, updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
            IF @employee_ids IS NOT NULL
                EXEC [pay].[usp_payroll_employee_set] @company_id = @company_id, @actor_user_id = @actor_user_id,
                     @permission_code = @permission_code, @id = @id, @employee_ids = @employee_ids, @mode = N'replace';
        COMMIT;
    END
    SELECT @id AS id;
END
GO

-- Works out every wage of the run from the time sheet. Wages typed by hand are kept. Result: the run log.
CREATE OR ALTER PROCEDURE [pay].[usp_daily_wage_process]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @work_date DATE, @slot_minutes INT;
    SELECT @status = p.status, @work_date = p.work_date, @slot_minutes = ts.workable_minutes
    FROM [pay].[payroll] p LEFT JOIN [sch].[time_slot] ts ON ts.id = p.time_slot_id
    WHERE p.id = @id AND p.company_id = @company_id AND p.kind = N'daily_wage';
    IF @status IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. It cannot be processed again', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll_employee] WHERE payroll_id = @id)
        THROW 50400, N'employeeIds|Add employees to the payroll before processing it.', 1;

    DECLARE @days_in_month INT = DAY(EOMONTH(@work_date));
    DECLARE @w TABLE (employee_id BIGINT PRIMARY KEY, rate DECIMAL(18,2), frequency NVARCHAR(30), has_day BIT,
                      worked_minutes INT, expected_minutes INT, fraction DECIMAL(6,2), wage DECIMAL(18,2), payment_method NVARCHAR(30),
                      error NVARCHAR(400));
    INSERT @w (employee_id, rate, frequency, has_day, worked_minutes, expected_minutes, fraction, payment_method)
    SELECT pe.employee_id, sal.amount, ISNULL(e.salary_frequency, N'monthly'),
           CASE WHEN t.id IS NULL THEN 0 ELSE 1 END, ISNULL(t.worked_minutes, 0),
           COALESCE(t.expected_minutes, DATEDIFF(MINUTE, t.expected_in, t.expected_out), @slot_minutes),
           CASE WHEN t.day_status IN (N'present', N'wfh', N'official_visit', N'short_day') THEN 1.0
                WHEN t.day_status = N'half_day' THEN 0.5 ELSE 0 END,
           CASE WHEN EXISTS (SELECT 1 FROM [hr].[employee_bank_account] ba WHERE ba.employee_id = pe.employee_id) THEN N'bank' ELSE N'cash' END
    FROM [pay].[payroll_employee] pe
    JOIN [hr].[employee] e ON e.id = pe.employee_id
    LEFT JOIN [att].[timesheet_day] t ON t.employee_id = pe.employee_id AND t.work_date = @work_date
    OUTER APPLY (SELECT TOP 1 s.amount FROM [hr].[employee_salary] s WHERE s.employee_id = pe.employee_id AND s.effective_date <= @work_date
                 ORDER BY s.effective_date DESC, s.id DESC) sal
    WHERE pe.payroll_id = @id;

    UPDATE @w SET error = N'No salary or wage rate on record.' WHERE rate IS NULL;
    UPDATE @w SET error = N'No time sheet for the day.' WHERE error IS NULL AND has_day = 0;
    UPDATE @w SET wage = ROUND(CASE frequency
                                   WHEN N'hourly' THEN rate * worked_minutes / 60.0
                                   WHEN N'daily' THEN rate * fraction
                                   ELSE rate / @days_in_month * fraction END, 2)
    WHERE error IS NULL;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @log_id BIGINT;
    BEGIN TRAN;
        INSERT [pay].[payroll_run_log] (payroll_id, kind, started_at, finished_at, status, run_by_user_id, processed_count, error_count, created_by)
        VALUES (@id, N'run', @now, @now, CASE WHEN EXISTS (SELECT 1 FROM @w WHERE error IS NOT NULL) THEN N'completed_with_errors' ELSE N'completed' END,
                @actor_user_id, (SELECT COUNT(*) FROM @w WHERE error IS NULL), (SELECT COUNT(*) FROM @w WHERE error IS NOT NULL), @actor_user_id);
        SET @log_id = SCOPE_IDENTITY();
        INSERT [pay].[payroll_run_error] (payroll_run_log_id, employee_id, message, created_by)
        SELECT @log_id, employee_id, error, @actor_user_id FROM @w WHERE error IS NOT NULL;

        DELETE p FROM [pay].[payslip] p JOIN @w w ON w.employee_id = p.employee_id
        WHERE p.payroll_id = @id AND w.error IS NOT NULL AND p.status <> N'released';

        UPDATE p
        SET worked_minutes = w.worked_minutes, expected_minutes = w.expected_minutes, worked_days = w.fraction, applicable_days = 1,
            payment_method = w.payment_method,
            gross = w.wage,
            total_earnings = CASE WHEN p.is_manually_updated = 1 THEN p.total_earnings ELSE w.wage END,
            total_deductions = CASE WHEN p.is_manually_updated = 1 THEN p.total_deductions ELSE 0 END,
            net_payable = CASE WHEN p.is_manually_updated = 1 THEN p.net_payable ELSE w.wage END,
            updated_at = @now, updated_by = @actor_user_id
        FROM [pay].[payslip] p JOIN @w w ON w.employee_id = p.employee_id
        WHERE p.payroll_id = @id AND w.error IS NULL AND p.status <> N'released';

        INSERT [pay].[payslip] (company_id, payroll_id, employee_id, payslip_month, applicable_days, worked_days, worked_minutes,
                                expected_minutes, gross, total_earnings, total_deductions, total_reimbursements, net_payable,
                                status, payment_method, created_by)
        SELECT @company_id, @id, w.employee_id, DATEFROMPARTS(YEAR(@work_date), MONTH(@work_date), 1), 1, w.fraction, w.worked_minutes,
               w.expected_minutes, w.wage, w.wage, 0, 0, w.wage, N'ready', w.payment_method, @actor_user_id
        FROM @w w
        WHERE w.error IS NULL AND NOT EXISTS (SELECT 1 FROM [pay].[payslip] p WHERE p.payroll_id = @id AND p.employee_id = w.employee_id);

        UPDATE [pay].[payroll] SET status = CASE WHEN status = N'open' THEN N'running' ELSE status END, last_run_at = @now,
               updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;
    COMMIT;

    SELECT l.id, l.kind, l.started_at, l.finished_at, l.status, l.processed_count, l.error_count, l.run_by_user_id,
           COALESCE(NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N''), u.display_name, u.email) AS run_by_name
    FROM [pay].[payroll_run_log] l
    LEFT JOIN [auth].[user_account] u ON u.id = l.run_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE l.id = @log_id;
END
GO

-- "Daily Wages Details": result set 1 the run, 2 its pay items (none), 3 one row per person.
CREATE OR ALTER PROCEDURE [pay].[usp_daily_wage_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [pay].[usp_payroll_get] @company_id = @company_id, @id = @id, @kind = N'daily_wage';

    DECLARE @work_date DATE = (SELECT work_date FROM [pay].[payroll] WHERE id = @id);
    SELECT pe.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           t.first_in AS check_in, t.last_out AS check_out, p.expected_minutes, p.worked_minutes,
           p.id AS payslip_id, p.gross AS wage, p.total_earnings, p.total_deductions, p.net_payable, p.status AS payslip_status,
           p.payment_method, p.is_manually_updated, v.id AS voucher_id, v.voucher_no, v.status AS voucher_status
    FROM [pay].[payroll_employee] pe
    JOIN [hr].[employee] e ON e.id = pe.employee_id
    LEFT JOIN [att].[timesheet_day] t ON t.employee_id = pe.employee_id AND t.work_date = @work_date
    LEFT JOIN [pay].[payslip] p ON p.payroll_id = @id AND p.employee_id = pe.employee_id
    LEFT JOIN [pay].[voucher] v ON v.payroll_id = @id AND v.employee_id = pe.employee_id
    WHERE pe.payroll_id = @id
    ORDER BY e.first_name, e.last_name, e.id;
END
GO

-- "Daily Wage Edit": the run's name and each person's earnings and deductions, typed by hand.
-- @rows: JSON [{"employeeId","totalEarnings","totalDeductions"}].
CREATE OR ALTER PROCEDURE [pay].[usp_daily_wage_rows_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @name          NVARCHAR(200),
    @rows          NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = row_version, @status = status FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = N'daily_wage';
    IF @rv IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. It cannot be changed', 1;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;

    DECLARE @r TABLE (employee_id BIGINT PRIMARY KEY, total_earnings DECIMAL(18,2), total_deductions DECIMAL(18,2));
    INSERT @r SELECT employee_id, total_earnings, total_deductions
    FROM OPENJSON(@rows) WITH (employee_id BIGINT '$.employeeId', total_earnings DECIMAL(18,2) '$.totalEarnings',
                               total_deductions DECIMAL(18,2) '$.totalDeductions');
    IF EXISTS (SELECT 1 FROM @r r WHERE NOT EXISTS (SELECT 1 FROM [pay].[payslip] p WHERE p.payroll_id = @id AND p.employee_id = r.employee_id))
        THROW 50400, N'rows|Process the payroll before editing wages; someone in the list has no wage yet.', 1;
    IF EXISTS (SELECT 1 FROM @r r JOIN [pay].[payslip] p ON p.payroll_id = @id AND p.employee_id = r.employee_id AND p.status = N'released')
        THROW 50409, N'rows|A released wage cannot be changed.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pay.payslip', p.id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
        FROM [pay].[payslip] p JOIN @r r ON p.payroll_id = @id AND p.employee_id = r.employee_id
        CROSS APPLY (VALUES (N'total_earnings', CONVERT(NVARCHAR(40), p.total_earnings), CONVERT(NVARCHAR(40), r.total_earnings)),
                            (N'total_deductions', CONVERT(NVARCHAR(40), p.total_deductions), CONVERT(NVARCHAR(40), r.total_deductions))) f (field_name, old_value, new_value)
        WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);

        UPDATE p
        SET total_earnings = r.total_earnings, total_deductions = r.total_deductions,
            net_payable = r.total_earnings - r.total_deductions, is_manually_updated = 1, updated_at = @now, updated_by = @actor_user_id
        FROM [pay].[payslip] p JOIN @r r ON p.payroll_id = @id AND p.employee_id = r.employee_id
        WHERE p.total_earnings <> r.total_earnings OR p.total_deductions <> r.total_deductions;

        UPDATE [pay].[payroll] SET name = @name, updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    EXEC [pay].[usp_daily_wage_get] @company_id = @company_id, @id = @id;
END
GO

-- Makes a voucher (type daily_wage, status approved, waiting for Finance to verify) for every paid wage of
-- a closed run that has none yet. Result: how many were made.
CREATE OR ALTER PROCEDURE [pay].[usp_daily_wage_vouchers]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @work_date DATE, @currency CHAR(3);
    SELECT @status = p.status, @work_date = p.work_date, @currency = ISNULL(p.currency, c.currency)
    FROM [pay].[payroll] p JOIN [org].[company] c ON c.id = p.company_id
    WHERE p.id = @id AND p.company_id = @company_id AND p.kind = N'daily_wage';
    IF @status IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @status <> N'closed'
        THROW 50409, N'status|PAYROLL_NOT_CLOSED|Close the daily wages payroll before making its vouchers', 1;

    DECLARE @requester BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @todo TABLE (n INT IDENTITY(1,1), employee_id BIGINT, amount DECIMAL(18,2), payment_method NVARCHAR(30));
    INSERT @todo (employee_id, amount, payment_method)
    SELECT p.employee_id, p.net_payable, p.payment_method
    FROM [pay].[payslip] p
    WHERE p.payroll_id = @id AND p.net_payable > 0
      AND NOT EXISTS (SELECT 1 FROM [pay].[voucher] v WHERE v.payroll_id = @id AND v.employee_id = p.employee_id)
    ORDER BY p.employee_id;

    DECLARE @i INT = 1, @count INT = (SELECT COUNT(*) FROM @todo), @code NVARCHAR(30), @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        WHILE @i <= @count
        BEGIN
            EXEC [pay].[usp_sequence_next] @company_id, N'VCH-', 5, @code OUTPUT;
            INSERT [pay].[voucher] (company_id, voucher_no, employee_id, voucher_type, voucher_date, currency, amount, payment_method,
                                    purpose, payroll_id, requested_by_id, approved_by_id, approved_at, status, created_by)
            SELECT @company_id, @code, t.employee_id, N'daily_wage', @work_date, @currency, t.amount, t.payment_method,
                   N'Daily wages', @id, @requester, @requester, @now, N'approved', @actor_user_id
            FROM @todo t WHERE t.n = @i;
            SET @i += 1;
        END
    COMMIT;
    SELECT @count AS created;
END
