-- Pay Slips (My / All), the payslip view and edit, hold / pay, the change log, and the Employee Accounts
-- panel. Every query reaches only the employees the caller may see through @permission_code.

-- @scope 'my' = the caller's own slips. When the "Do Not Display Payslip After Run" setting is on
-- (@hide_unreleased = 1), a person's own slips show only once released.
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_list]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @permission_code   NVARCHAR(150),
    @scope             NVARCHAR(10) = N'all',
    @hide_unreleased   BIT = 0,
    @search            NVARCHAR(200) = NULL,
    @payroll_id        BIGINT = NULL,
    @month             DATE = NULL,
    @status            NVARCHAR(30) = NULL,
    @employee_id       BIGINT = NULL,
    @branch_id         BIGINT = NULL,
    @department_id     BIGINT = NULL,
    @employee_status   NVARCHAR(30) = NULL,
    @final_settlement  BIT = NULL,
    @earnings_from     DECIMAL(18,2) = NULL,
    @earnings_to       DECIMAL(18,2) = NULL,
    @deductions_from   DECIMAL(18,2) = NULL,
    @deductions_to     DECIMAL(18,2) = NULL,
    @net_from          DECIMAL(18,2) = NULL,
    @net_to            DECIMAL(18,2) = NULL,
    @page              INT = 1,
    @page_size         INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @month IS NOT NULL SET @month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1);

    SELECT p.id INTO #ids
    FROM [pay].[payslip] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
    WHERE p.company_id = @company_id
      AND (@scope <> N'my' OR p.employee_id = @me)
      AND (@hide_unreleased = 0 OR p.employee_id <> ISNULL(@me, 0) OR p.status = N'released')
      AND (@payroll_id IS NULL OR p.payroll_id = @payroll_id)
      AND (@month IS NULL OR p.payslip_month = @month)
      AND (@status IS NULL OR p.status = @status)
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@employee_status IS NULL OR e.status = @employee_status)
      AND (@final_settlement IS NULL OR p.is_final_settlement = @final_settlement)
      AND (@earnings_from IS NULL OR p.total_earnings >= @earnings_from) AND (@earnings_to IS NULL OR p.total_earnings <= @earnings_to)
      AND (@deductions_from IS NULL OR p.total_deductions >= @deductions_from) AND (@deductions_to IS NULL OR p.total_deductions <= @deductions_to)
      AND (@net_from IS NULL OR p.net_payable >= @net_from) AND (@net_to IS NULL OR p.net_payable <= @net_to)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern OR pr.name LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT p.id, p.payroll_id, pr.code AS payroll_code, pr.name AS payroll_name, pr.kind AS payroll_kind, pr.status AS payroll_status,
           p.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, b.name AS branch_name, p.payslip_month, p.gross, p.total_earnings, p.total_deductions,
           p.total_reimbursements, p.net_payable, p.tax_amount, p.status, p.payment_method, p.released_at, p.paid_at,
           p.is_final_settlement, p.created_at, p.updated_at, p.row_version
    FROM #ids i
    JOIN [pay].[payslip] p ON p.id = i.id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    ORDER BY p.payslip_month DESC, e.first_name, e.last_name, p.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Result set 1: the payslip with the person and the run. Result set 2: its lines.
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @hide_unreleased BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF NOT EXISTS (
        SELECT 1 FROM [pay].[payslip] p
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
        WHERE p.id = @id AND p.company_id = @company_id
          AND (@hide_unreleased = 0 OR p.employee_id <> ISNULL(@me, 0) OR p.status = N'released'))
        THROW 50404, N'Payslip not found', 1;

    SELECT p.id, p.payroll_id, pr.code AS payroll_code, pr.name AS payroll_name, pr.kind AS payroll_kind, pr.status AS payroll_status,
           p.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, b.name AS branch_name, ds.name AS designation_name, jt.name AS job_title_name,
           l.name AS location_name, ep.joining_date, ba.bank_name, ba.account_number,
           p.payslip_month, p.applicable_days, p.worked_days, p.worked_minutes, p.expected_minutes, p.leave_days, p.absent_days,
           p.overtime_minutes, p.gross, p.total_earnings, p.total_deductions, p.total_reimbursements, p.net_payable,
           p.taxable_income, p.tax_amount, p.status, p.payment_method, p.released_at, p.paid_at, p.is_final_settlement,
           p.is_manually_updated, ISNULL(pr.currency, c.currency) AS currency,
           p.created_at, p.updated_at, p.row_version
    FROM [pay].[payslip] p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    JOIN [org].[company] c ON c.id = p.company_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    LEFT JOIN [org].[location] l ON l.id = e.location_id
    OUTER APPLY (SELECT TOP 1 joining_date FROM [hr].[employment_period] x WHERE x.employee_id = e.id ORDER BY x.joining_date DESC) ep
    OUTER APPLY (SELECT TOP 1 bank_name, account_number FROM [hr].[employee_bank_account] x WHERE x.employee_id = e.id
                 ORDER BY x.is_primary DESC, x.id) ba
    WHERE p.id = @id;

    SELECT ln.id, ln.pay_item_id, pi.name AS pay_item_name, pi.label AS pay_item_label, pi.item_type, pi.system_code,
           ln.amount, ln.employer_contribution, ln.is_taxable, ln.is_manually_updated, pi.is_display_only,
           CAST(ISNULL(ppi.calculate_only, 0) AS BIT) AS calculate_only
    FROM [pay].[payslip_line] ln
    JOIN [pay].[payslip] p ON p.id = ln.payslip_id
    JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
    LEFT JOIN [pay].[payroll_pay_item] ppi ON ppi.payroll_id = p.payroll_id AND ppi.pay_item_id = ln.pay_item_id
    WHERE ln.payslip_id = @id
    ORDER BY CASE pi.item_type WHEN N'earning' THEN 1 WHEN N'reimbursement' THEN 2 WHEN N'deduction' THEN 3 ELSE 4 END,
             CASE WHEN pi.system_code = N'tax' THEN 1 ELSE 0 END, pi.id;
END
GO

-- Edits payslip lines by hand (Pay Slip Edit). @lines: JSON [{"payItemId","amount","employerContribution"}].
-- Each changed line is marked Manually Updated, kept by Recalculate, and written to the change log.
-- Not on a released slip or a closed run.
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_lines_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @lines           NVARCHAR(MAX),
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @run_status NVARCHAR(30), @payroll_id BIGINT, @kind NVARCHAR(30), @fs_closed BIT;
    SELECT @rv = p.row_version, @status = p.status, @run_status = pr.status, @payroll_id = p.payroll_id, @kind = pr.kind,
           @fs_closed = CASE WHEN EXISTS (SELECT 1 FROM [sep].[final_settlement] f WHERE f.payslip_id = p.id AND f.status = N'closed') THEN 1 ELSE 0 END
    FROM [pay].[payslip] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
    WHERE p.id = @id AND p.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Payslip not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this payslip. Reload it and try again', 1;
    IF @run_status = N'closed' OR @status = N'released' OR @fs_closed = 1
        THROW 50409, N'status|PAYSLIP_LOCKED|This payslip is released or its payroll is closed. It cannot be changed', 1;
    IF @kind = N'daily_wage'
        THROW 50400, N'Daily wages are edited on the daily wages payroll.', 1;

    DECLARE @in TABLE (pay_item_id BIGINT PRIMARY KEY, amount DECIMAL(18,2), employer_contribution DECIMAL(18,2));
    INSERT @in SELECT pay_item_id, amount, employer_contribution
    FROM OPENJSON(@lines) WITH (pay_item_id BIGINT '$.payItemId', amount DECIMAL(18,2) '$.amount',
                                employer_contribution DECIMAL(18,2) '$.employerContribution');
    IF EXISTS (SELECT 1 FROM @in i WHERE NOT EXISTS (SELECT 1 FROM [pay].[pay_item] pi WHERE pi.id = i.pay_item_id AND pi.company_id = @company_id))
        THROW 50400, N'lines|A pay item was not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pay.payslip', @id, pi.name, CONVERT(NVARCHAR(40), ln.amount), CONVERT(NVARCHAR(40), i.amount),
               CASE WHEN ln.id IS NULL THEN N'add' ELSE N'update' END, @actor_user_id, @now
        FROM @in i
        JOIN [pay].[pay_item] pi ON pi.id = i.pay_item_id
        LEFT JOIN [pay].[payslip_line] ln ON ln.payslip_id = @id AND ln.pay_item_id = i.pay_item_id
        WHERE ln.id IS NULL OR ln.amount <> i.amount OR ISNULL(ln.employer_contribution, 0) <> ISNULL(i.employer_contribution, ISNULL(ln.employer_contribution, 0));

        UPDATE ln SET amount = i.amount, employer_contribution = ISNULL(i.employer_contribution, ln.employer_contribution),
               is_manually_updated = 1, updated_at = @now, updated_by = @actor_user_id
        FROM [pay].[payslip_line] ln JOIN @in i ON i.pay_item_id = ln.pay_item_id
        WHERE ln.payslip_id = @id
          AND (ln.amount <> i.amount OR ISNULL(ln.employer_contribution, 0) <> ISNULL(i.employer_contribution, ISNULL(ln.employer_contribution, 0)));

        INSERT [pay].[payslip_line] (payslip_id, pay_item_id, amount, employer_contribution, is_taxable, is_manually_updated, created_by)
        SELECT @id, i.pay_item_id, i.amount, i.employer_contribution,
               ISNULL((SELECT ppi.is_taxable FROM [pay].[payroll_pay_item] ppi WHERE ppi.payroll_id = @payroll_id AND ppi.pay_item_id = i.pay_item_id),
                      (SELECT pi.is_taxable FROM [pay].[pay_item] pi WHERE pi.id = i.pay_item_id)), 1, @actor_user_id
        FROM @in i
        WHERE NOT EXISTS (SELECT 1 FROM [pay].[payslip_line] ln WHERE ln.payslip_id = @id AND ln.pay_item_id = i.pay_item_id);

        EXEC [pay].[usp_payslip_totals_refresh] @payslip_id = @id;
        UPDATE [pay].[payslip] SET updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    EXEC [pay].[usp_payslip_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = @permission_code, @id = @id;
END
GO

-- Hold, unhold or pay several payslips (@ids: JSON array). hold: ready -> on_hold. unhold: on_hold -> ready
-- (released when the run is already closed). pay: ready or released -> released and paid. Result: count changed.
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_status_set]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @ids             NVARCHAR(MAX),
    @action          NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @t TABLE (id BIGINT PRIMARY KEY, status NVARCHAR(30), run_status NVARCHAR(30));
    INSERT @t
    SELECT p.id, p.status, pr.status
    FROM (SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) AS id FROM OPENJSON(@ids)) j
    JOIN [pay].[payslip] p ON p.id = j.id AND p.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id;

    IF (SELECT COUNT(*) FROM @t) <> (SELECT COUNT(DISTINCT [value]) FROM OPENJSON(@ids))
        THROW 50404, N'Payslip not found', 1;
    IF @action = N'hold' AND EXISTS (SELECT 1 FROM @t WHERE status <> N'ready')
        THROW 50409, N'status|PAYSLIP_STATUS|Only payslips that are ready to release can be put on hold', 1;
    IF @action = N'unhold' AND EXISTS (SELECT 1 FROM @t WHERE status <> N'on_hold')
        THROW 50409, N'status|PAYSLIP_STATUS|Only payslips on hold can be taken off hold', 1;
    IF @action = N'pay' AND EXISTS (SELECT 1 FROM @t WHERE status = N'on_hold')
        THROW 50409, N'status|PAYSLIP_STATUS|A payslip on hold cannot be paid. Take it off hold first', 1;

    -- Slips released for the first time now (paid, or off hold after the run closed): their employees are told.
    DECLARE @first NVARCHAR(MAX) = (
        SELECT CONCAT(N'[', STRING_AGG(CONVERT(NVARCHAR(MAX), t.id), N','), N']')
        FROM @t t JOIN [pay].[payslip] p ON p.id = t.id
        WHERE p.released_at IS NULL AND (@action = N'pay' OR (@action = N'unhold' AND t.run_status = N'closed')));

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pay.payslip', t.id, N'status', t.status,
               CASE @action WHEN N'hold' THEN N'on_hold' WHEN N'unhold' THEN CASE WHEN t.run_status = N'closed' THEN N'released' ELSE N'ready' END
                            ELSE N'released' END,
               @action, @actor_user_id, @now
        FROM @t t;

        UPDATE p
        SET status = CASE @action WHEN N'hold' THEN N'on_hold'
                                  WHEN N'unhold' THEN CASE WHEN t.run_status = N'closed' THEN N'released' ELSE N'ready' END
                                  ELSE N'released' END,
            released_at = CASE WHEN @action = N'pay' OR (@action = N'unhold' AND t.run_status = N'closed') THEN ISNULL(p.released_at, @now) ELSE p.released_at END,
            paid_at = CASE WHEN @action = N'pay' THEN ISNULL(p.paid_at, @now) ELSE p.paid_at END,
            updated_at = @now, updated_by = @actor_user_id
        FROM [pay].[payslip] p JOIN @t t ON t.id = p.id;

        IF @first IS NOT NULL
            EXEC [pay].[usp_payslip_notify_released] @company_id = @company_id, @payslip_ids = @first;
    COMMIT;

    SELECT COUNT(*) AS changed FROM @t;
END
GO

-- The payslip's change log (History): field, old value, new value, action, when and by whom.
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_history]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payslip] p
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
                   WHERE p.id = @id AND p.company_id = @company_id)
        THROW 50404, N'Payslip not found', 1;
    SELECT a.id, a.field_name, a.old_value, a.new_value, a.action_name, a.performed_at, a.performed_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS performed_by_name
    FROM [core].[audit_log] a
    LEFT JOIN [auth].[user_account] u ON u.id = a.performed_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE a.entity_type = N'pay.payslip' AND a.entity_id = @id
    ORDER BY a.id DESC;
END
GO

-- The Employee Accounts panel (Provident Fund, EOBI, outstanding loans and advances) for one person
-- (@employee_id; the caller's own when NULL). Result set 1: the person. 2: balance per account.
CREATE OR ALTER PROCEDURE [pay].[usp_employee_account_summary]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @employee_id IS NULL
        SET @employee_id = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @employee_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;

    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           (SELECT SUM(i.amount - ISNULL(i.paid_amount, 0)) FROM [loan].[loan_installment] i
            JOIN [loan].[loan] l ON l.id = i.loan_id AND l.status = N'active'
            WHERE l.employee_id = e.id AND ISNULL(i.status, N'') <> N'paid') AS outstanding_loan,
           (SELECT SUM(v.amount) FROM [pay].[voucher] v
            WHERE v.employee_id = e.id AND v.voucher_type = N'salary_advance' AND v.status = N'processed') AS advances_paid
    FROM [hr].[employee] e WHERE e.id = @employee_id;

    SELECT a.account_type_id, t.name AS account_name, t.category, SUM(a.credit) AS credit, SUM(a.debit) AS debit,
           SUM(a.credit) - SUM(a.debit) AS balance
    FROM [pay].[employee_account_entry] a
    JOIN [pay].[account_type] t ON t.id = a.account_type_id
    WHERE a.employee_id = @employee_id
    GROUP BY a.account_type_id, t.name, t.category
    ORDER BY t.name;
END
GO

-- Salary Sheet: one row per payslip of a run (or of every monthly run of @month). Result set 1: the rows with
-- the fixed columns. Result set 2: every line, for the per-pay-item columns.
CREATE OR ALTER PROCEDURE [pay].[usp_salary_sheet]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @payroll_id      BIGINT = NULL,
    @month           DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @payroll_id IS NULL AND @month IS NULL
        THROW 50400, N'payrollId|Pick a payroll or a month.', 1;
    IF @payroll_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @payroll_id AND company_id = @company_id)
        THROW 50404, N'Payroll not found', 1;
    IF @month IS NOT NULL SET @month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1);

    SELECT p.id INTO #ids
    FROM [pay].[payslip] p
    JOIN [pay].[payroll] pr ON pr.id = p.payroll_id AND pr.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE (@payroll_id IS NULL OR p.payroll_id = @payroll_id)
      AND (@month IS NULL OR (pr.kind = N'monthly' AND pr.payroll_month = @month));

    SELECT p.id AS payslip_id, p.payroll_id, pr.name AS payroll_name, p.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, p.payment_method, p.status,
           p.gross, ISNULL(x.overtime, 0) AS overtime, ISNULL(x.tax, 0) AS tax, ISNULL(x.leave_deduction, 0) AS leave_deduction,
           ISNULL(x.short_deduction, 0) AS short_deduction, ISNULL(x.absent_deduction, 0) AS absent_deduction,
           p.total_earnings, p.total_reimbursements, p.total_deductions, p.net_payable
    FROM #ids i
    JOIN [pay].[payslip] p ON p.id = i.id
    JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    OUTER APPLY (
        SELECT SUM(CASE WHEN pi.system_code = N'overtime' THEN ln.amount END) AS overtime,
               SUM(CASE WHEN pi.system_code = N'tax' THEN ln.amount END) AS tax,
               SUM(CASE WHEN pi.system_code = N'leave_deduction' THEN ln.amount END) AS leave_deduction,
               SUM(CASE WHEN pi.system_code = N'short_deduction' THEN ln.amount END) AS short_deduction,
               SUM(CASE WHEN pi.system_code = N'absent_deduction' THEN ln.amount END) AS absent_deduction
        FROM [pay].[payslip_line] ln JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
        WHERE ln.payslip_id = p.id) x
    ORDER BY e.first_name, e.last_name, p.id;

    SELECT ln.payslip_id, ln.pay_item_id, pi.name AS pay_item_name, pi.item_type, ln.amount
    FROM #ids i
    JOIN [pay].[payslip_line] ln ON ln.payslip_id = i.id
    JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
    ORDER BY pi.id;
END
