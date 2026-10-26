-- Payroll reports and the payroll dashboard. Figures cover only the employees the caller may see.
-- "Paid out" figures count released payslips of closed runs and closed settlements.

-- Employee Account Report (the one report designed): per person, tax paid and tax rebates in the period,
-- and the balance of each employee account. Result sets: total, the page, the account balances of the page.
CREATE OR ALTER PROCEDURE [pay].[usp_report_employee_accounts]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @from_date       DATE,
    @to_date         DATE,
    @search          NVARCHAR(200) = NULL,
    @department_id   BIGINT = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name,
           ISNULL((SELECT SUM(p.tax_amount) FROM [pay].[payslip] p WHERE p.employee_id = e.id AND p.status = N'released'
                   AND p.payslip_month BETWEEN @from_date AND @to_date), 0) AS tax_paid,
           ISNULL((SELECT SUM(r.amount) FROM [pay].[tax_rebate] r WHERE r.employee_id = e.id
                   AND r.rebate_date BETWEEN @from_date AND @to_date), 0) AS tax_rebate
    INTO #r
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    WHERE e.company_id = @company_id
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (EXISTS (SELECT 1 FROM [pay].[payslip] p WHERE p.employee_id = e.id)
           OR EXISTS (SELECT 1 FROM [pay].[employee_account_entry] a WHERE a.employee_id = e.id)
           OR EXISTS (SELECT 1 FROM [pay].[tax_rebate] r WHERE r.employee_id = e.id))
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #r;

    SELECT * INTO #page FROM #r ORDER BY employee_name, employee_id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
    SELECT * FROM #page ORDER BY employee_name, employee_id;

    SELECT a.employee_id, a.account_type_id, t.name AS account_name, SUM(a.credit) AS credit, SUM(a.debit) AS debit,
           SUM(a.credit) - SUM(a.debit) AS balance
    FROM [pay].[employee_account_entry] a
    JOIN #page pg ON pg.employee_id = a.employee_id
    JOIN [pay].[account_type] t ON t.id = a.account_type_id
    WHERE a.entry_month <= @to_date
    GROUP BY a.employee_id, a.account_type_id, t.name
    ORDER BY a.employee_id, t.name;
END
GO

-- Payroll Summary: totals of one run, and the total of each pay item. Result sets: totals, pay items.
CREATE OR ALTER PROCEDURE [pay].[usp_report_payroll_summary]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @payroll_id      BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @payroll_id AND company_id = @company_id)
        THROW 50404, N'Payroll not found', 1;

    SELECT p.id INTO #ids FROM [pay].[payslip] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE p.payroll_id = @payroll_id;

    SELECT pr.id AS payroll_id, pr.code, pr.name, pr.kind, pr.payroll_month, pr.work_date, pr.status,
           COUNT(p.id) AS employee_count, ISNULL(SUM(p.gross), 0) AS gross, ISNULL(SUM(p.total_earnings), 0) AS total_earnings,
           ISNULL(SUM(p.total_deductions), 0) AS total_deductions, ISNULL(SUM(p.total_reimbursements), 0) AS total_reimbursements,
           ISNULL(SUM(p.tax_amount), 0) AS tax, ISNULL(SUM(p.net_payable), 0) AS net_payable,
           ISNULL(SUM(CASE WHEN p.status = N'on_hold' THEN 1 ELSE 0 END), 0) AS on_hold_count,
           ISNULL(SUM(CASE WHEN p.status = N'on_hold' THEN p.net_payable ELSE 0 END), 0) AS on_hold_amount,
           ISNULL(SUM(CASE WHEN p.paid_at IS NOT NULL THEN p.net_payable ELSE 0 END), 0) AS paid_amount
    FROM [pay].[payroll] pr
    LEFT JOIN [pay].[payslip] p ON p.id IN (SELECT id FROM #ids)
    WHERE pr.id = @payroll_id
    GROUP BY pr.id, pr.code, pr.name, pr.kind, pr.payroll_month, pr.work_date, pr.status;

    SELECT pi.id AS pay_item_id, pi.name AS pay_item_name, pi.item_type, SUM(ln.amount) AS amount,
           SUM(ISNULL(ln.employer_contribution, 0)) AS employer_contribution, COUNT(*) AS employee_count
    FROM [pay].[payslip_line] ln
    JOIN #ids i ON i.id = ln.payslip_id
    JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
    GROUP BY pi.id, pi.name, pi.item_type
    ORDER BY CASE pi.item_type WHEN N'earning' THEN 1 WHEN N'reimbursement' THEN 2 WHEN N'deduction' THEN 3 ELSE 4 END, pi.id;
END
GO

-- Employee-wise Report: one row per payslip in the period.
CREATE OR ALTER PROCEDURE [pay].[usp_report_employee_wise]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @from_month      DATE,
    @to_month        DATE,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SET @from_month = DATEFROMPARTS(YEAR(@from_month), MONTH(@from_month), 1);

    SELECT p.id INTO #ids
    FROM [pay].[payslip] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    WHERE p.company_id = @company_id AND p.payslip_month BETWEEN @from_month AND @to_month
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT p.id AS payslip_id, p.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, p.payslip_month, pr.name AS payroll_name, p.is_final_settlement, p.gross, p.total_earnings,
           p.total_reimbursements, p.total_deductions, p.tax_amount, p.net_payable, p.status
    FROM #ids i
    JOIN [pay].[payslip] p ON p.id = i.id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    ORDER BY p.payslip_month DESC, e.first_name, e.last_name, p.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Daily Wages Summary: one row per daily-wage run in the period, with its vouchers.
CREATE OR ALTER PROCEDURE [pay].[usp_report_daily_wages]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @from_date       DATE,
    @to_date         DATE,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS total FROM [pay].[payroll]
    WHERE company_id = @company_id AND kind = N'daily_wage' AND work_date BETWEEN @from_date AND @to_date;

    -- employee_count: the people in the run the caller may see (processed or not, like the run's own count);
    -- worked minutes and net payable come from their payslips (0 until the run is processed).
    SELECT employee_id INTO #vis FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code);

    SELECT pr.id AS payroll_id, pr.code, pr.name, pr.work_date, ts.name AS time_slot_name, pr.status,
           (SELECT COUNT(*) FROM [pay].[payroll_employee] pe JOIN #vis x ON x.employee_id = pe.employee_id
            WHERE pe.payroll_id = pr.id) AS employee_count,
           ISNULL(ps.worked_minutes, 0) AS worked_minutes, ISNULL(ps.net_payable, 0) AS net_payable,
           (SELECT COUNT(*) FROM [pay].[voucher] v WHERE v.payroll_id = pr.id) AS voucher_count,
           (SELECT COUNT(*) FROM [pay].[voucher] v WHERE v.payroll_id = pr.id AND v.status = N'processed') AS vouchers_processed
    FROM [pay].[payroll] pr
    LEFT JOIN [sch].[time_slot] ts ON ts.id = pr.time_slot_id
    OUTER APPLY (SELECT SUM(p.worked_minutes) AS worked_minutes, SUM(p.net_payable) AS net_payable
                 FROM [pay].[payslip] p JOIN #vis x ON x.employee_id = p.employee_id
                 WHERE p.payroll_id = pr.id) ps
    WHERE pr.company_id = @company_id AND pr.kind = N'daily_wage' AND pr.work_date BETWEEN @from_date AND @to_date
    ORDER BY pr.work_date DESC, pr.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Payroll Dashboard for a year: result set 1 the tiles (payrolls, paid, on hold, unpaid), 2 Salary
-- Statistics per month (gross, tax, deductions, net), 3 Salary Breakup by pay item for @month (or the
-- latest month with payslips).
CREATE OR ALTER PROCEDURE [pay].[usp_dashboard]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @year            INT,
    @month           DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @from DATE = DATEFROMPARTS(@year, 1, 1), @to DATE = DATEFROMPARTS(@year, 12, 31);

    SELECT p.id, p.payslip_month, p.status, p.paid_at, p.gross, p.tax_amount, p.total_deductions, p.net_payable
    INTO #p
    FROM [pay].[payslip] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE p.company_id = @company_id AND p.payslip_month BETWEEN @from AND @to;

    SELECT (SELECT COUNT(*) FROM [pay].[payroll] WHERE company_id = @company_id
            AND ISNULL(payroll_month, work_date) BETWEEN @from AND @to) AS total_payrolls,
           (SELECT COUNT(*) FROM [pay].[payroll] WHERE company_id = @company_id AND status = N'closed'
            AND ISNULL(payroll_month, work_date) BETWEEN @from AND @to) AS closed_payrolls,
           COUNT(*) AS total_payslips,
           SUM(CASE WHEN status = N'released' THEN 1 ELSE 0 END) AS released_payslips,
           SUM(CASE WHEN paid_at IS NOT NULL THEN 1 ELSE 0 END) AS paid_payslips,
           SUM(CASE WHEN status = N'on_hold' THEN 1 ELSE 0 END) AS on_hold_payslips,
           SUM(CASE WHEN paid_at IS NULL AND status <> N'on_hold' THEN 1 ELSE 0 END) AS unpaid_payslips,
           ISNULL(SUM(net_payable), 0) AS net_payable, ISNULL(SUM(CASE WHEN paid_at IS NOT NULL THEN net_payable END), 0) AS paid_amount
    FROM #p;

    SELECT payslip_month AS month, ISNULL(SUM(gross), 0) AS gross, ISNULL(SUM(tax_amount), 0) AS tax,
           ISNULL(SUM(total_deductions), 0) AS deductions, ISNULL(SUM(net_payable), 0) AS net_payable, COUNT(*) AS payslip_count
    FROM #p GROUP BY payslip_month ORDER BY payslip_month;

    IF @month IS NULL SET @month = (SELECT MAX(payslip_month) FROM #p);
    ELSE SET @month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1);
    SELECT @month AS month, pi.id AS pay_item_id, pi.name AS pay_item_name, pi.item_type, SUM(ln.amount) AS amount
    FROM #p p
    JOIN [pay].[payslip_line] ln ON ln.payslip_id = p.id
    JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
    WHERE p.payslip_month = @month AND pi.item_type IN (N'earning', N'deduction', N'reimbursement')
    GROUP BY pi.id, pi.name, pi.item_type
    HAVING SUM(ln.amount) <> 0
    ORDER BY SUM(ln.amount) DESC;
END
