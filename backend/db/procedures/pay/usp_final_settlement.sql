-- Final Settlement. The list is the End of Employment records that need one (sep.end_of_employment, owned
-- by off-boarding); payroll works the settlement payslip out and closes it (sep.final_settlement).
-- URLs use the end-of-employment id, so a settlement can be opened before it is first worked out.

CREATE OR ALTER PROCEDURE [pay].[usp_final_settlement_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @status          NVARCHAR(30) = NULL,
    @month           DATE = NULL,
    @branch_id       BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @location_id     BIGINT = NULL,
    @employee_status NVARCHAR(30) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT x.id INTO #ids
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
    JOIN [hr].[employee] e ON e.id = x.employee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    WHERE x.company_id = @company_id AND x.needs_final_settlement = 1
      AND (@status IS NULL OR ISNULL(fs.status, N'pending') = @status)
      AND (@month IS NULL OR (YEAR(x.last_working_date) = YEAR(@month) AND MONTH(x.last_working_date) = MONTH(@month)))
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@location_id IS NULL OR e.location_id = @location_id)
      AND (@employee_status IS NULL OR e.status = @employee_status)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT x.id, fs.id AS final_settlement_id, x.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, dp.name AS department_name, b.name AS branch_name,
           x.reason, rq.created_at AS resignation_date, x.last_working_date, x.description,
           ISNULL(fs.status, N'pending') AS status, fs.payslip_id, p.total_earnings, p.total_deductions, p.net_payable,
           fs.closed_at, fs.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = fs.file_id) AS file_name,
           fs.row_version
    FROM #ids i
    JOIN [sep].[end_of_employment] x ON x.id = i.id
    JOIN [hr].[employee] e ON e.id = x.employee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    LEFT JOIN [pay].[payslip] p ON p.id = fs.payslip_id
    LEFT JOIN [req].[request] rq ON rq.id = x.resignation_request_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    ORDER BY x.last_working_date DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_final_settlement_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [sep].[end_of_employment] x
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
                   WHERE x.id = @id AND x.company_id = @company_id AND x.needs_final_settlement = 1)
        THROW 50404, N'Final settlement not found', 1;

    SELECT x.id, fs.id AS final_settlement_id, x.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, dp.name AS department_name, b.name AS branch_name,
           x.reason, rq.created_at AS resignation_date, x.last_working_date, x.description,
           ISNULL(fs.status, N'pending') AS status, fs.payslip_id, p.total_earnings, p.total_deductions, p.net_payable,
           fs.closed_at, fs.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = fs.file_id) AS file_name,
           fs.row_version
    FROM [sep].[end_of_employment] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    LEFT JOIN [pay].[payslip] p ON p.id = fs.payslip_id
    LEFT JOIN [req].[request] rq ON rq.id = x.resignation_request_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    WHERE x.id = @id;
END
GO

-- Inputs for working out a settlement: the month of the last working day up to that day, every pay item,
-- every unpaid loan installment, and the encashable leave balance. The month's salary is left out when the
-- person already has a payslip in a monthly run of that month. Result sets as usp_payroll_run_inputs.
CREATE OR ALTER PROCEDURE [pay].[usp_final_settlement_inputs]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @employee_id BIGINT, @lwd DATE, @fs_status NVARCHAR(30), @payslip_id BIGINT;
    SELECT @employee_id = x.employee_id, @lwd = x.last_working_date, @fs_status = fs.status, @payslip_id = fs.payslip_id
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    WHERE x.id = @id AND x.company_id = @company_id AND x.needs_final_settlement = 1;
    IF @employee_id IS NULL
        THROW 50404, N'Final settlement not found', 1;
    IF @fs_status = N'closed'
        THROW 50409, N'status|SETTLEMENT_CLOSED|This final settlement is closed. It cannot be worked out again', 1;

    EXEC [pay].[usp_pay_item_system_ensure] @company_id = @company_id;

    DECLARE @month DATE = DATEFROMPARTS(YEAR(@lwd), MONTH(@lwd), 1);
    DECLARE @tax_structure_id BIGINT = (SELECT TOP 1 id FROM [pay].[tax_structure]
                                        WHERE company_id = @company_id AND start_date <= @lwd AND end_date >= @lwd
                                        ORDER BY start_date DESC, id DESC);
    DECLARE @has_month_slip BIT = CASE WHEN EXISTS (
        SELECT 1 FROM [pay].[payslip] p JOIN [pay].[payroll] pr ON pr.id = p.payroll_id AND pr.kind = N'monthly'
        WHERE p.employee_id = @employee_id AND p.payslip_month = @month) THEN 1 ELSE 0 END;

    CREATE TABLE #emp (employee_id BIGINT PRIMARY KEY, period_start DATE, period_end DATE, month_start DATE, month_end DATE,
                       payslip_id BIGINT NULL, include_salary BIT, loans_all BIT, encash_balance BIT, skip_reason NVARCHAR(400) NULL);
    CREATE TABLE #items (pay_item_id BIGINT PRIMARY KEY, is_taxable BIT, calculate_only BIT);
    INSERT #emp (employee_id, period_start, period_end, month_start, month_end, payslip_id, include_salary, loans_all, encash_balance)
    VALUES (@employee_id, @month, @lwd, @month, EOMONTH(@month), @payslip_id, CASE WHEN @has_month_slip = 1 THEN 0 ELSE 1 END, 1, 1);
    INSERT #items SELECT id, is_taxable, 0 FROM [pay].[pay_item] WHERE company_id = @company_id AND is_display_only = 0;

    SELECT CAST(NULL AS BIGINT) AS id, CAST(NULL AS NVARCHAR(30)) AS code, N'Final settlement' AS name, N'final_settlement' AS kind,
           @month AS payroll_month, EOMONTH(@month) AS month_end, DAY(EOMONTH(@month)) AS month_days, N'actual' AS applicable_days,
           CAST(NULL AS INT) AS fixed_days, CAST(CASE WHEN @tax_structure_id IS NULL THEN 0 ELSE 1 END AS BIT) AS tax_applicable,
           t.id AS tax_structure_id, t.start_date AS tax_start_date, t.end_date AS tax_end_date, t.surcharge_type, t.surcharge_value,
           CAST(1 AS BIT) AS is_final_settlement, ISNULL(@fs_status, N'pending') AS status
    FROM (SELECT 1 AS one) o LEFT JOIN [pay].[tax_structure] t ON t.id = @tax_structure_id;

    SELECT employee_id, skip_reason FROM #emp WHERE skip_reason IS NOT NULL;

    EXEC [pay].[usp_calc_inputs] @company_id = @company_id, @tax_structure_id = @tax_structure_id;
END
GO

-- Saves the worked-out settlement payslip (@payslip: one object shaped like a run's) and opens the
-- settlement record when there is none. Result: the settlement.
CREATE OR ALTER PROCEDURE [pay].[usp_final_settlement_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @payslip         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @lwd DATE, @fs_id BIGINT, @fs_status NVARCHAR(30), @payslip_id BIGINT;
    SELECT @employee_id = x.employee_id, @lwd = x.last_working_date, @fs_id = fs.id, @fs_status = fs.status, @payslip_id = fs.payslip_id
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    WHERE x.id = @id AND x.company_id = @company_id AND x.needs_final_settlement = 1;
    IF @employee_id IS NULL
        THROW 50404, N'Final settlement not found', 1;
    IF @fs_status = N'closed'
        THROW 50409, N'status|SETTLEMENT_CLOSED|This final settlement is closed. It cannot be worked out again', 1;

    DECLARE @month DATE = DATEFROMPARTS(YEAR(@lwd), MONTH(@lwd), 1), @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @j TABLE (applicable_days DECIMAL(6,2), worked_days DECIMAL(6,2), worked_minutes INT, expected_minutes INT,
                      leave_days DECIMAL(6,2), absent_days DECIMAL(6,2), overtime_minutes INT, taxable_income DECIMAL(18,2),
                      payment_method NVARCHAR(30), lines NVARCHAR(MAX), postings NVARCHAR(MAX));
    INSERT @j
    SELECT applicable_days, worked_days, worked_minutes, expected_minutes, leave_days, absent_days, overtime_minutes,
           taxable_income, payment_method, lines, postings
    FROM OPENJSON(@payslip) WITH (applicable_days DECIMAL(6,2) '$.applicableDays', worked_days DECIMAL(6,2) '$.workedDays',
         worked_minutes INT '$.workedMinutes', expected_minutes INT '$.expectedMinutes', leave_days DECIMAL(6,2) '$.leaveDays',
         absent_days DECIMAL(6,2) '$.absentDays', overtime_minutes INT '$.overtimeMinutes', taxable_income DECIMAL(18,2) '$.taxableIncome',
         payment_method NVARCHAR(30) '$.paymentMethod', lines NVARCHAR(MAX) '$.lines' AS JSON, postings NVARCHAR(MAX) '$.postings' AS JSON);

    BEGIN TRAN;
        IF @payslip_id IS NULL
        BEGIN
            INSERT [pay].[payslip] (company_id, payroll_id, employee_id, payslip_month, status, is_final_settlement, created_by)
            VALUES (@company_id, NULL, @employee_id, @month, N'ready', 1, @actor_user_id);
            SET @payslip_id = SCOPE_IDENTITY();
        END
        UPDATE p
        SET applicable_days = j.applicable_days, worked_days = j.worked_days, worked_minutes = j.worked_minutes,
            expected_minutes = j.expected_minutes, leave_days = j.leave_days, absent_days = j.absent_days,
            overtime_minutes = j.overtime_minutes, taxable_income = j.taxable_income, payment_method = j.payment_method,
            payslip_month = @month, updated_at = @now, updated_by = @actor_user_id
        FROM [pay].[payslip] p CROSS JOIN @j j WHERE p.id = @payslip_id;

        DELETE [pay].[payslip_line] WHERE payslip_id = @payslip_id;
        INSERT [pay].[payslip_line] (payslip_id, pay_item_id, amount, employer_contribution, is_taxable, is_manually_updated, created_by)
        SELECT @payslip_id, x.pay_item_id, x.amount, x.employer_contribution, ISNULL(x.is_taxable, 0), ISNULL(x.is_manual, 0), @actor_user_id
        FROM @j j CROSS APPLY OPENJSON(j.lines) WITH (pay_item_id BIGINT '$.payItemId', amount DECIMAL(18,2) '$.amount',
             employer_contribution DECIMAL(18,2) '$.employerContribution', is_taxable BIT '$.isTaxable', is_manual BIT '$.isManual') x;

        DELETE [pay].[employee_account_entry] WHERE payslip_id = @payslip_id AND pay_rule_id IS NOT NULL;
        INSERT [pay].[employee_account_entry] (employee_id, account_type_id, entry_month, credit, debit, is_processed, payslip_id,
                                               pay_rule_id, description, created_by)
        SELECT @employee_id, x.account_type_id, @month, ISNULL(x.credit, 0), ISNULL(x.debit, 0), 0, @payslip_id, x.pay_rule_id,
               x.description, @actor_user_id
        FROM @j j CROSS APPLY OPENJSON(ISNULL(j.postings, N'[]')) WITH (pay_rule_id BIGINT '$.payRuleId',
             account_type_id BIGINT '$.accountTypeId', credit DECIMAL(18,2) '$.credit', debit DECIMAL(18,2) '$.debit',
             description NVARCHAR(MAX) '$.description') x;

        EXEC [pay].[usp_payslip_totals_refresh] @payslip_id = @payslip_id;

        IF @fs_id IS NULL
            INSERT [sep].[final_settlement] (company_id, end_of_employment_id, payslip_id, status, created_by)
            VALUES (@company_id, @id, @payslip_id, N'open', @actor_user_id);
        ELSE
            UPDATE [sep].[final_settlement] SET payslip_id = @payslip_id, status = N'open', updated_at = @now, updated_by = @actor_user_id
            WHERE id = @fs_id;

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.payslip', @payslip_id, N'recalculate', @actor_user_id, @now);
    COMMIT;

    EXEC [pay].[usp_final_settlement_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Close FS: cannot be reverted. Releases the settlement payslip, marks every unpaid loan installment
-- recovered, debits the encashed leave days, links penalties and leave encashments, freezes the time
-- sheet up to the last working day. @file_id: the signed settlement letter (an uploaded file), optional.
-- Publishes payroll.final_settlement_closed and tells the employee the settlement payslip is out.
CREATE OR ALTER PROCEDURE [pay].[usp_final_settlement_close]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8),
    @file_id         BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @lwd DATE, @fs_id BIGINT, @fs_status NVARCHAR(30), @payslip_id BIGINT, @rv BINARY(8);
    SELECT @employee_id = x.employee_id, @lwd = x.last_working_date, @fs_id = fs.id, @fs_status = fs.status,
           @payslip_id = fs.payslip_id, @rv = fs.row_version
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    WHERE x.id = @id AND x.company_id = @company_id AND x.needs_final_settlement = 1;
    IF @employee_id IS NULL
        THROW 50404, N'Final settlement not found', 1;
    IF @fs_id IS NULL OR @payslip_id IS NULL
        THROW 50409, N'status|SETTLEMENT_NOT_CALCULATED|Work the settlement out (Recalculate) before closing it', 1;
    IF @fs_status = N'closed'
        THROW 50409, N'status|SETTLEMENT_CLOSED|This final settlement is already closed', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this final settlement. Reload it and try again', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @month DATE = DATEFROMPARTS(YEAR(@lwd), MONTH(@lwd), 1);
    BEGIN TRAN;
        UPDATE [sep].[final_settlement]
        SET status = N'closed', closed_at = @now, file_id = ISNULL(@file_id, file_id), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @fs_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this final settlement. Reload it and try again', 1;
        UPDATE [pay].[payslip] SET status = N'released', released_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @payslip_id;

        IF EXISTS (SELECT 1 FROM [pay].[payslip_line] ln JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
                   WHERE ln.payslip_id = @payslip_id AND ln.amount > 0)
        BEGIN
            UPDATE i SET status = N'paid', paid_amount = i.amount, paid_at = @now, payslip_id = @payslip_id,
                   updated_at = @now, updated_by = @actor_user_id
            FROM [loan].[loan_installment] i
            JOIN [loan].[loan] l ON l.id = i.loan_id AND l.status = N'active' AND l.employee_id = @employee_id
            JOIN [loan].[loan_type] lt ON lt.id = l.loan_type_id
            WHERE ISNULL(i.status, N'') <> N'paid'
              AND EXISTS (SELECT 1 FROM [pay].[payslip_line] ln JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
                          WHERE ln.payslip_id = @payslip_id AND ln.amount > 0
                            AND (ln.pay_item_id = lt.deduction_pay_item_id OR (lt.deduction_pay_item_id IS NULL AND pi.system_code = N'loan_deduction')));
            UPDATE l SET status = N'settled', settled_at = @now, updated_at = @now, updated_by = @actor_user_id
            FROM [loan].[loan] l
            WHERE l.employee_id = @employee_id AND l.status = N'active'
              AND EXISTS (SELECT 1 FROM [loan].[loan_installment] i WHERE i.loan_id = l.id)
              AND NOT EXISTS (SELECT 1 FROM [loan].[loan_installment] i WHERE i.loan_id = l.id AND ISNULL(i.status, N'') <> N'paid');
        END

        -- Encashed leave: the same balances the settlement paid, debited on the last working day.
        IF EXISTS (SELECT 1 FROM [pay].[payslip_line] ln JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
                   WHERE ln.payslip_id = @payslip_id AND pi.system_code = N'leave_encashment' AND ln.amount > 0)
        BEGIN
            INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, remarks, created_by)
            SELECT @employee_id, lt.id, b.fiscal_year, @lwd,
                   -CASE WHEN lt.encashment_max IS NOT NULL AND b.balance > lt.encashment_max THEN lt.encashment_max ELSE b.balance END,
                   N'encashed', N'Final settlement', @actor_user_id
            FROM [lv].[leave_type] lt
            CROSS APPLY (SELECT MAX(l.fiscal_year) AS fiscal_year FROM [lv].[leave_ledger] l
                         WHERE l.employee_id = @employee_id AND l.leave_type_id = lt.id) fy
            CROSS APPLY (SELECT fy.fiscal_year, SUM(l.days) AS balance FROM [lv].[leave_ledger] l
                         WHERE l.employee_id = @employee_id AND l.leave_type_id = lt.id AND l.fiscal_year = fy.fiscal_year) b
            WHERE lt.company_id = @company_id AND lt.allow_encashment = 1 AND b.balance > 0
              AND (lt.encashment_min IS NULL OR b.balance >= lt.encashment_min);

            UPDATE r SET payslip_id = @payslip_id
            FROM [lv].[leave_encashment_employee] r
            JOIN [lv].[leave_encashment] h ON h.id = r.leave_encashment_id AND h.mode = N'payroll' AND h.encashment_date <= @lwd
            WHERE r.employee_id = @employee_id AND r.payslip_id IS NULL;
        END

        UPDATE [att].[warning] SET payslip_id = @payslip_id
        WHERE employee_id = @employee_id AND payslip_id IS NULL AND work_date BETWEEN @month AND @lwd
          AND ISNULL(deduction, N'payroll') IN (N'payroll', N'both');
        UPDATE [att].[timesheet_day] SET is_frozen = 1 WHERE employee_id = @employee_id AND work_date <= @lwd AND is_frozen = 0;
        UPDATE [pay].[employee_account_entry] SET is_processed = 1, updated_at = @now WHERE payslip_id = @payslip_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sep.final_settlement', @fs_id, N'status', N'open', N'closed', N'close', @actor_user_id, @now);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), @fs_id) AS finalSettlementId, CONVERT(NVARCHAR(30), @id) AS endOfEmploymentId,
                   CONVERT(NVARCHAR(30), @employee_id) AS employeeId, CONVERT(NVARCHAR(10), @lwd, 23) AS lastWorkingDate,
                   CONVERT(NVARCHAR(30), p.id) AS payslipId, p.total_earnings AS totalEarnings,
                   p.total_deductions AS totalDeductions, p.net_payable AS netPayable,
                   CONVERT(NVARCHAR(30), @actor_user_id) AS closedBy
            FROM [pay].[payslip] p WHERE p.id = @payslip_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'payroll.final_settlement_closed',
             @entity_type = N'sep.final_settlement', @entity_id = @fs_id, @payload = @payload;
        DECLARE @slip NVARCHAR(100) = CONCAT(N'[', @payslip_id, N']');
        EXEC [pay].[usp_payslip_notify_released] @company_id = @company_id, @payslip_ids = @slip;

        -- The settlement was what the leaving record waited for: let it complete if nothing else is.
        EXEC [sep].[usp_end_of_employment_try_complete] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
    COMMIT;

    EXEC [pay].[usp_final_settlement_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
