-- Running a monthly payroll and working out a final settlement.
--
-- The work is split three ways:
--   1. pay.usp_payroll_run_inputs / pay.usp_final_settlement_inputs gather everything set-based: salary,
--      time sheet days, approved leave, warning penalties, loan installments, fixed pay items, opening
--      balances, leave encashment, benefits, hand-edited lines and the year's tax so far.
--   2. The service (app/services/payroll_engine.py) works out each person's lines with the pay item
--      formulas (a whitelisted expression evaluator), then the tax.
--   3. pay.usp_payroll_run_save / pay.usp_final_settlement_save write the payslips set-based in one
--      transaction.

-- Shared by both input procedures. Reads #emp (who, which days) and #items (which pay items) made by the
-- caller and returns, in this order: pay items, formulas, rules, tax slabs, employees with their
-- variables, input amounts, benefits, hand-edited lines, tax so far this year.
CREATE OR ALTER PROCEDURE [pay].[usp_calc_inputs]
    @company_id       BIGINT,
    @tax_structure_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @tax_start DATE, @tax_end DATE, @loan_item BIGINT, @encash_item BIGINT;
    SELECT @tax_start = start_date, @tax_end = end_date FROM [pay].[tax_structure] WHERE id = @tax_structure_id;
    SELECT @loan_item = id FROM [pay].[pay_item] WHERE company_id = @company_id AND system_code = N'loan_deduction';
    SELECT @encash_item = id FROM [pay].[pay_item] WHERE company_id = @company_id AND system_code = N'leave_encashment';

    -- 1. Pay items of the run.
    SELECT p.id AS pay_item_id, p.name, p.item_type, p.calculation_type, p.system_code, p.tax_distribution,
           p.is_display_only, p.eligibility_expression, ef.expression AS employee_expression,
           rf.expression AS employer_expression, i.is_taxable, i.calculate_only,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [pay].[reward_benefit] b WHERE b.pay_item_id = p.id AND b.is_group = 1)
                     THEN 1 ELSE 0 END AS BIT) AS members_only
    FROM #items i
    JOIN [pay].[pay_item] p ON p.id = i.pay_item_id
    LEFT JOIN [pay].[formula] ef ON ef.id = p.employee_formula_id
    LEFT JOIN [pay].[formula] rf ON rf.id = p.employer_formula_id
    ORDER BY p.id;

    -- 2. Names an expression may refer to: formulas (with their expression) and every pay item.
    SELECT f.name, f.expression, N'formula' AS kind FROM [pay].[formula] f WHERE f.company_id = @company_id
    UNION ALL
    SELECT p.name, NULL, N'pay_item' FROM [pay].[pay_item] p WHERE p.company_id = @company_id;

    -- 3. Rules: posted to employee accounts on every run.
    SELECT r.id, r.name, r.expression, r.account_type_id FROM [pay].[pay_rule] r WHERE r.company_id = @company_id ORDER BY r.id;

    -- 4. Tax slabs.
    SELECT s.min_amount, s.max_amount, s.fixed_amount, s.percentage
    FROM [pay].[tax_slab] s WHERE s.tax_structure_id = @tax_structure_id ORDER BY s.min_amount;

    -- 5. Employees and their variables.
    SELECT e.employee_id, emp.code AS employee_code, CONCAT(emp.first_name, N' ', emp.last_name) AS employee_name,
           emp.status AS employee_status, emp.salary_frequency, emp.branch_id, emp.department_id, emp.designation_id,
           emp.grade_id, emp.employment_type_id, emp.employee_group_id, emp.location_id,
           sal.amount AS gross_salary, ep.joining_date, ep.end_date AS employment_end_date,
           eoe.last_working_date, e.period_start, e.period_end, e.month_start, e.month_end, e.include_salary,
           CASE WHEN EXISTS (SELECT 1 FROM [hr].[employee_bank_account] ba WHERE ba.employee_id = e.employee_id)
                THEN N'bank' ELSE N'cash' END AS payment_method,
           ISNULL(ts.present_days, 0) AS present_days, ISNULL(ts.absent_days, 0) AS absent_days,
           ISNULL(ts.half_days, 0) AS half_days, ISNULL(ts.short_days, 0) AS short_days,
           ISNULL(ts.holiday_days, 0) AS holiday_days, ISNULL(ts.late_days, 0) AS late_days,
           ISNULL(ts.late_minutes, 0) AS late_minutes, ISNULL(ts.early_left_days, 0) AS early_left_days,
           ISNULL(ts.early_left_minutes, 0) AS early_left_minutes, ISNULL(ts.overtime_minutes, 0) AS overtime_minutes,
           ISNULL(ts.worked_minutes, 0) AS worked_minutes, ISNULL(ts.expected_minutes, 0) AS expected_minutes,
           ts.day_minutes, ISNULL(lv.leave_days, 0) AS leave_days, ISNULL(lv.unpaid_leave_days, 0) AS unpaid_leave_days,
           ISNULL(pen.penalty_days, 0) AS penalty_days,
           CASE WHEN e.encash_balance = 1 THEN ISNULL(enc.days, 0) ELSE 0 END AS fs_encash_days
    FROM #emp e
    JOIN [hr].[employee] emp ON emp.id = e.employee_id
    OUTER APPLY (SELECT TOP 1 s.amount FROM [hr].[employee_salary] s
                 WHERE s.employee_id = e.employee_id AND s.effective_date <= e.period_end
                 ORDER BY s.effective_date DESC, s.id DESC) sal
    OUTER APPLY (SELECT TOP 1 p.joining_date, p.end_date FROM [hr].[employment_period] p
                 WHERE p.employee_id = e.employee_id AND p.joining_date <= e.period_end
                 ORDER BY p.joining_date DESC) ep
    OUTER APPLY (SELECT TOP 1 x.last_working_date FROM [sep].[end_of_employment] x
                 WHERE x.employee_id = e.employee_id AND x.last_working_date >= ISNULL(ep.joining_date, '19000101')
                 ORDER BY x.last_working_date DESC) eoe
    OUTER APPLY (
        SELECT SUM(CASE WHEN t.day_status IN (N'present', N'wfh', N'official_visit') THEN 1 ELSE 0 END) AS present_days,
               SUM(CASE WHEN t.day_status = N'absent' THEN 1 ELSE 0 END) AS absent_days,
               SUM(CASE WHEN t.day_status = N'half_day' THEN 1 ELSE 0 END) AS half_days,
               SUM(CASE WHEN t.day_status = N'short_day' THEN 1 ELSE 0 END) AS short_days,
               SUM(CASE WHEN t.day_status IN (N'holiday', N'weekend', N'rest_day') THEN 1 ELSE 0 END) AS holiday_days,
               SUM(CASE WHEN ISNULL(t.late_minutes, 0) > 0 THEN 1 ELSE 0 END) AS late_days,
               SUM(ISNULL(t.late_minutes, 0)) AS late_minutes,
               SUM(CASE WHEN ISNULL(t.early_left_minutes, 0) > 0 THEN 1 ELSE 0 END) AS early_left_days,
               SUM(ISNULL(t.early_left_minutes, 0)) AS early_left_minutes,
               SUM(COALESCE(t.approved_overtime_minutes,
                            ISNULL(t.overtime_before_minutes, 0) + ISNULL(t.overtime_after_minutes, 0))) AS overtime_minutes,
               SUM(ISNULL(t.worked_minutes, 0)) AS worked_minutes,
               SUM(COALESCE(t.expected_minutes, DATEDIFF(MINUTE, t.expected_in, t.expected_out), 0)) AS expected_minutes,
               AVG(COALESCE(NULLIF(t.expected_minutes, 0),
                            CASE WHEN t.expected_out > t.expected_in THEN DATEDIFF(MINUTE, t.expected_in, t.expected_out) END)) AS day_minutes
        FROM [att].[timesheet_day] t
        WHERE t.employee_id = e.employee_id AND t.work_date BETWEEN e.period_start AND e.period_end) ts
    OUTER APPLY (
        SELECT -SUM(l.days) AS leave_days, -SUM(CASE WHEN lt.is_deductible = 1 THEN l.days ELSE 0 END) AS unpaid_leave_days
        FROM [lv].[leave_ledger] l
        JOIN [lv].[leave_type] lt ON lt.id = l.leave_type_id
        WHERE l.employee_id = e.employee_id AND l.reason IN (N'availed', N'restored')
          AND l.entry_date BETWEEN e.period_start AND e.period_end) lv
    OUTER APPLY (
        SELECT SUM(ISNULL(w.penalty_percentage, 0)) / 100.0 AS penalty_days
        FROM [att].[warning] w
        WHERE w.employee_id = e.employee_id AND w.work_date BETWEEN e.period_start AND e.period_end
          AND ISNULL(w.deduction, N'payroll') IN (N'payroll', N'both')
          AND (w.payslip_id IS NULL OR w.payslip_id = e.payslip_id)) pen
    OUTER APPLY (
        SELECT SUM(CASE WHEN b.balance <= 0 THEN 0
                        WHEN lt.encashment_min IS NOT NULL AND b.balance < lt.encashment_min THEN 0
                        WHEN lt.encashment_max IS NOT NULL AND b.balance > lt.encashment_max THEN lt.encashment_max
                        ELSE b.balance END) AS days
        FROM [lv].[leave_type] lt
        CROSS APPLY (SELECT SUM(l.days) AS balance FROM [lv].[leave_ledger] l
                     WHERE l.employee_id = e.employee_id AND l.leave_type_id = lt.id
                       AND l.fiscal_year = (SELECT MAX(l2.fiscal_year) FROM [lv].[leave_ledger] l2
                                            WHERE l2.employee_id = e.employee_id AND l2.leave_type_id = lt.id)) b
        WHERE lt.company_id = @company_id AND lt.allow_encashment = 1) enc
    ORDER BY e.employee_id;

    -- 6. Amounts that feed pay items: fixed per-person amounts, opening balances, loan installments,
    --    leave encashments paid through payroll. is_oneoff = 1 for amounts that do not repeat every month.
    WITH fixed AS (
        SELECT epi.employee_id, epi.pay_item_id, epi.amount,
               ROW_NUMBER() OVER (PARTITION BY epi.employee_id, epi.pay_item_id ORDER BY epi.effective_date DESC, epi.id DESC) AS rn
        FROM [hr].[employee_pay_item] epi
        JOIN #emp e ON e.employee_id = epi.employee_id
        JOIN #items i ON i.pay_item_id = epi.pay_item_id
        WHERE epi.effective_date IS NULL OR epi.effective_date <= e.period_end
    )
    SELECT employee_id, pay_item_id, CAST(amount AS DECIMAL(18,2)) AS amount, CAST(0 AS BIT) AS is_oneoff,
           CAST(NULL AS BIT) AS is_taxable, N'fixed' AS source
    FROM fixed WHERE rn = 1
    UNION ALL
    SELECT o.employee_id, o.pay_item_id, o.amount, CAST(1 AS BIT), o.is_taxable, N'opening_balance'
    FROM [pay].[opening_balance] o
    JOIN #emp e ON e.employee_id = o.employee_id AND o.balance_month = e.month_start
    JOIN #items i ON i.pay_item_id = o.pay_item_id
    UNION ALL
    SELECT l.employee_id, ISNULL(lt.deduction_pay_item_id, @loan_item),
           SUM(i.amount - ISNULL(i.paid_amount, 0)), CAST(1 AS BIT), CAST(0 AS BIT), N'loan'
    FROM [loan].[loan_installment] i
    JOIN [loan].[loan] l ON l.id = i.loan_id AND l.status = N'active'
    JOIN [loan].[loan_type] lt ON lt.id = l.loan_type_id
    JOIN #emp e ON e.employee_id = l.employee_id
    WHERE ISNULL(i.status, N'') <> N'paid'
      AND (e.loans_all = 1 OR DATEFROMPARTS(YEAR(i.due_month), MONTH(i.due_month), 1) = e.month_start)
      AND ISNULL(lt.deduction_pay_item_id, @loan_item) IN (SELECT pay_item_id FROM #items)
    GROUP BY l.employee_id, ISNULL(lt.deduction_pay_item_id, @loan_item)
    UNION ALL
    SELECT r.employee_id, @encash_item, SUM(r.amount), CAST(1 AS BIT), CAST(NULL AS BIT), N'leave_encashment'
    FROM [lv].[leave_encashment_employee] r
    JOIN [lv].[leave_encashment] h ON h.id = r.leave_encashment_id AND h.company_id = @company_id AND h.mode = N'payroll'
    JOIN #emp e ON e.employee_id = r.employee_id
    WHERE (r.payslip_id IS NULL OR r.payslip_id = e.payslip_id) AND h.encashment_date <= e.period_end
      AND @encash_item IN (SELECT pay_item_id FROM #items)
    GROUP BY r.employee_id;

    -- 7. Benefits that reach each person (group benefits only reach their members).
    SELECT e.employee_id, b.pay_item_id, b.id AS benefit_id, b.is_group, f.expression
    FROM #emp e
    JOIN [hr].[employee] emp ON emp.id = e.employee_id
    JOIN [pay].[reward_benefit] b ON b.company_id = @company_id
    JOIN #items i ON i.pay_item_id = b.pay_item_id
    LEFT JOIN [pay].[formula] f ON f.id = b.formula_id
    WHERE b.is_group = 0
       OR EXISTS (SELECT 1 FROM [pay].[reward_benefit_member] m
                  WHERE m.reward_benefit_id = b.id
                    AND (m.employee_id = e.employee_id OR (m.employee_group_id IS NOT NULL AND m.employee_group_id = emp.employee_group_id)));

    -- 8. Lines someone edited by hand: kept as they are.
    SELECT e.employee_id, l.pay_item_id, l.amount, l.employer_contribution
    FROM #emp e
    JOIN [pay].[payslip_line] l ON l.payslip_id = e.payslip_id AND l.is_manually_updated = 1;

    -- 9. Taxable income and tax already taken this tax year (closed runs and released settlements), and rebates.
    SELECT e.employee_id, ISNULL(y.ytd_taxable, 0) AS ytd_taxable, ISNULL(y.ytd_tax, 0) AS ytd_tax, ISNULL(rb.rebates, 0) AS rebates
    FROM #emp e
    OUTER APPLY (
        SELECT SUM(p.taxable_income) AS ytd_taxable, SUM(p.tax_amount) AS ytd_tax
        FROM [pay].[payslip] p
        LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
        WHERE p.employee_id = e.employee_id AND p.company_id = @company_id
          AND p.payslip_month >= @tax_start AND p.payslip_month < e.month_start
          AND ((pr.id IS NOT NULL AND pr.kind = N'monthly' AND pr.status = N'closed')
               OR (p.payroll_id IS NULL AND p.status = N'released'))) y
    OUTER APPLY (
        SELECT SUM(r.amount) AS rebates FROM [pay].[tax_rebate] r
        WHERE r.employee_id = e.employee_id AND r.rebate_date BETWEEN @tax_start AND @tax_end) rb;
END
GO

-- Inputs for a monthly run, for everyone in it or for @employee_ids (JSON array; Recalculate).
-- Result sets: 1 the run, 2 people skipped and why, then the nine of pay.usp_calc_inputs.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_run_inputs]
    @company_id   BIGINT,
    @id           BIGINT,
    @employee_ids NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @kind NVARCHAR(30), @status NVARCHAR(30), @month DATE, @tax_structure_id BIGINT, @tax_applicable BIT;
    SELECT @kind = kind, @status = status, @month = payroll_month, @tax_structure_id = tax_structure_id, @tax_applicable = tax_applicable
    FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id;
    IF @kind IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @kind <> N'monthly'
        THROW 50400, N'Daily wages are processed from the time sheet, not from pay items.', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. It cannot be run again', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll_employee] WHERE payroll_id = @id)
        THROW 50400, N'employeeIds|Add employees to the payroll before running it.', 1;

    DECLARE @month_end DATE = EOMONTH(@month);
    DECLARE @exclude_fs BIT = CASE WHEN (SELECT setting_value FROM [core].[company_setting]
        WHERE company_id = @company_id AND module = N'payroll' AND setting_key = N'exclude_final_settlement') = N'true' THEN 1 ELSE 0 END;

    CREATE TABLE #emp (employee_id BIGINT PRIMARY KEY, period_start DATE, period_end DATE, month_start DATE, month_end DATE,
                       payslip_id BIGINT NULL, include_salary BIT, loans_all BIT, encash_balance BIT, skip_reason NVARCHAR(400) NULL);
    CREATE TABLE #items (pay_item_id BIGINT PRIMARY KEY, is_taxable BIT, calculate_only BIT);

    INSERT #emp (employee_id, period_start, period_end, month_start, month_end, payslip_id, include_salary, loans_all, encash_balance)
    SELECT pe.employee_id, @month, @month_end, @month, @month_end, ps.id, 1, 0, 0
    FROM [pay].[payroll_employee] pe
    LEFT JOIN [pay].[payslip] ps ON ps.payroll_id = @id AND ps.employee_id = pe.employee_id
    WHERE pe.payroll_id = @id
      AND (@employee_ids IS NULL OR pe.employee_id IN (SELECT TRY_CONVERT(BIGINT, [value]) FROM OPENJSON(@employee_ids)));

    UPDATE e SET skip_reason = N'The payslip was released; it is not worked out again.'
    FROM #emp e JOIN [pay].[payslip] ps ON ps.id = e.payslip_id WHERE ps.status = N'released';

    UPDATE e SET skip_reason = CONCAT(N'Leaves on ', CONVERT(NVARCHAR(10), x.last_working_date, 23),
                                      N'; paid through final settlement (Exclude Final Settlement from Payroll).')
    FROM #emp e
    JOIN [sep].[end_of_employment] x ON x.employee_id = e.employee_id AND x.needs_final_settlement = 1
         AND x.last_working_date BETWEEN @month AND @month_end
    WHERE @exclude_fs = 1 AND e.skip_reason IS NULL;

    UPDATE e SET skip_reason = N'Left before this month.'
    FROM #emp e
    WHERE e.skip_reason IS NULL AND EXISTS (
        SELECT 1 FROM [sep].[end_of_employment] x WHERE x.employee_id = e.employee_id AND x.last_working_date < @month
          AND NOT EXISTS (SELECT 1 FROM [hr].[employment_period] p WHERE p.employee_id = e.employee_id AND p.joining_date > x.last_working_date));

    INSERT #items SELECT pay_item_id, is_taxable, calculate_only FROM [pay].[payroll_pay_item] WHERE payroll_id = @id;

    -- 1. The run.
    SELECT p.id, p.code, p.name, p.kind, p.payroll_month, @month_end AS month_end, DAY(@month_end) AS month_days,
           p.applicable_days, p.fixed_days, p.tax_applicable, p.tax_structure_id, t.start_date AS tax_start_date,
           t.end_date AS tax_end_date, t.surcharge_type, t.surcharge_value, CAST(0 AS BIT) AS is_final_settlement, p.status
    FROM [pay].[payroll] p
    LEFT JOIN [pay].[tax_structure] t ON t.id = p.tax_structure_id
    WHERE p.id = @id;

    -- 2. People skipped.
    SELECT employee_id, skip_reason FROM #emp WHERE skip_reason IS NOT NULL;
    DELETE #emp WHERE skip_reason IS NOT NULL;

    DECLARE @tax_id BIGINT = CASE WHEN @tax_applicable = 1 THEN @tax_structure_id END;
    EXEC [pay].[usp_calc_inputs] @company_id = @company_id, @tax_structure_id = @tax_id;
END
GO

-- Writes a run's results. @payslips: JSON [{employeeId, appliedDays..., lines: [...], postings: [...]}] as the
-- service builds them; @errors: JSON [{employeeId, message}]; @run_kind 'run' (everyone) or 'recalculate'.
-- Returns the run log row.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_run_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @run_kind      NVARCHAR(30),
    @started_at    DATETIME2(0),
    @payslips      NVARCHAR(MAX),
    @errors        NVARCHAR(MAX) = N'[]'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @month DATE;
    SELECT @status = status, @month = payroll_month FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = N'monthly';
    IF @status IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll was closed while it ran. Nothing was saved', 1;

    CREATE TABLE #ps (employee_id BIGINT PRIMARY KEY, applicable_days DECIMAL(6,2), worked_days DECIMAL(6,2), worked_minutes INT,
                      expected_minutes INT, leave_days DECIMAL(6,2), absent_days DECIMAL(6,2), overtime_minutes INT,
                      taxable_income DECIMAL(18,2), payment_method NVARCHAR(30), lines NVARCHAR(MAX), postings NVARCHAR(MAX),
                      payslip_id BIGINT NULL);
    INSERT #ps (employee_id, applicable_days, worked_days, worked_minutes, expected_minutes, leave_days, absent_days,
                overtime_minutes, taxable_income, payment_method, lines, postings)
    SELECT j.employee_id, j.applicable_days, j.worked_days, j.worked_minutes, j.expected_minutes, j.leave_days, j.absent_days,
           j.overtime_minutes, j.taxable_income, j.payment_method, j.lines, j.postings
    FROM OPENJSON(@payslips) WITH (
        employee_id BIGINT '$.employeeId', applicable_days DECIMAL(6,2) '$.applicableDays', worked_days DECIMAL(6,2) '$.workedDays',
        worked_minutes INT '$.workedMinutes', expected_minutes INT '$.expectedMinutes', leave_days DECIMAL(6,2) '$.leaveDays',
        absent_days DECIMAL(6,2) '$.absentDays', overtime_minutes INT '$.overtimeMinutes', taxable_income DECIMAL(18,2) '$.taxableIncome',
        payment_method NVARCHAR(30) '$.paymentMethod', lines NVARCHAR(MAX) '$.lines' AS JSON, postings NVARCHAR(MAX) '$.postings' AS JSON) j;

    IF EXISTS (SELECT 1 FROM #ps p WHERE NOT EXISTS (SELECT 1 FROM [pay].[payroll_employee] pe WHERE pe.payroll_id = @id AND pe.employee_id = p.employee_id))
        THROW 50409, N'The people in this payroll changed while it ran. Run it again', 1;
    IF EXISTS (SELECT 1 FROM #ps p JOIN [pay].[payslip] s ON s.payroll_id = @id AND s.employee_id = p.employee_id AND s.status = N'released')
        THROW 50409, N'A payslip was released while the payroll ran. Run it again', 1;

    DECLARE @err TABLE (employee_id BIGINT NULL, message NVARCHAR(MAX));
    INSERT @err SELECT employee_id, message FROM OPENJSON(ISNULL(@errors, N'[]')) WITH (employee_id BIGINT '$.employeeId', message NVARCHAR(MAX) '$.message');

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @log_id BIGINT;
    DECLARE @new_status NVARCHAR(30) = CASE WHEN @status = N'on_hold' THEN N'on_hold' ELSE N'ready' END;

    BEGIN TRAN;
        INSERT [pay].[payroll_run_log] (payroll_id, kind, started_at, finished_at, status, run_by_user_id, processed_count, error_count, created_by)
        VALUES (@id, @run_kind, @started_at, @now, CASE WHEN EXISTS (SELECT 1 FROM @err) THEN N'completed_with_errors' ELSE N'completed' END,
                @actor_user_id, (SELECT COUNT(*) FROM #ps), (SELECT COUNT(*) FROM @err), @actor_user_id);
        SET @log_id = SCOPE_IDENTITY();
        INSERT [pay].[payroll_run_error] (payroll_run_log_id, employee_id, message, created_by)
        SELECT @log_id, employee_id, message, @actor_user_id FROM @err;

        -- A person who errored loses a payslip that is no longer right (unless it was released).
        DECLARE @stale TABLE (payslip_id BIGINT);
        INSERT @stale SELECT s.id FROM [pay].[payslip] s
        WHERE s.payroll_id = @id AND s.status <> N'released' AND s.employee_id IN (SELECT employee_id FROM @err WHERE employee_id IS NOT NULL);
        DELETE [pay].[employee_account_entry] WHERE payslip_id IN (SELECT payslip_id FROM @stale) AND pay_rule_id IS NOT NULL;
        DELETE [pay].[payslip_line] WHERE payslip_id IN (SELECT payslip_id FROM @stale);
        DELETE [pay].[payslip] WHERE id IN (SELECT payslip_id FROM @stale);

        UPDATE s
        SET applicable_days = p.applicable_days, worked_days = p.worked_days, worked_minutes = p.worked_minutes,
            expected_minutes = p.expected_minutes, leave_days = p.leave_days, absent_days = p.absent_days,
            overtime_minutes = p.overtime_minutes, taxable_income = p.taxable_income, payment_method = p.payment_method,
            payslip_month = @month, updated_at = @now, updated_by = @actor_user_id
        FROM [pay].[payslip] s JOIN #ps p ON s.payroll_id = @id AND s.employee_id = p.employee_id;

        INSERT [pay].[payslip] (company_id, payroll_id, employee_id, payslip_month, applicable_days, worked_days, worked_minutes,
                                expected_minutes, leave_days, absent_days, overtime_minutes, taxable_income, status, payment_method, created_by)
        SELECT @company_id, @id, p.employee_id, @month, p.applicable_days, p.worked_days, p.worked_minutes, p.expected_minutes,
               p.leave_days, p.absent_days, p.overtime_minutes, p.taxable_income, @new_status, p.payment_method, @actor_user_id
        FROM #ps p
        WHERE NOT EXISTS (SELECT 1 FROM [pay].[payslip] s WHERE s.payroll_id = @id AND s.employee_id = p.employee_id);

        UPDATE p SET payslip_id = s.id FROM #ps p JOIN [pay].[payslip] s ON s.payroll_id = @id AND s.employee_id = p.employee_id;

        DELETE l FROM [pay].[payslip_line] l JOIN #ps p ON p.payslip_id = l.payslip_id;
        INSERT [pay].[payslip_line] (payslip_id, pay_item_id, amount, employer_contribution, is_taxable, is_manually_updated, created_by)
        SELECT p.payslip_id, j.pay_item_id, j.amount, j.employer_contribution, ISNULL(j.is_taxable, 0), ISNULL(j.is_manual, 0), @actor_user_id
        FROM #ps p
        CROSS APPLY OPENJSON(p.lines) WITH (pay_item_id BIGINT '$.payItemId', amount DECIMAL(18,2) '$.amount',
             employer_contribution DECIMAL(18,2) '$.employerContribution', is_taxable BIT '$.isTaxable', is_manual BIT '$.isManual') j;

        DELETE a FROM [pay].[employee_account_entry] a JOIN #ps p ON p.payslip_id = a.payslip_id WHERE a.pay_rule_id IS NOT NULL;
        INSERT [pay].[employee_account_entry] (employee_id, account_type_id, entry_month, credit, debit, is_processed, payslip_id,
                                               pay_rule_id, description, created_by)
        SELECT p.employee_id, j.account_type_id, @month, ISNULL(j.credit, 0), ISNULL(j.debit, 0), 0, p.payslip_id, j.pay_rule_id,
               j.description, @actor_user_id
        FROM #ps p
        CROSS APPLY OPENJSON(ISNULL(p.postings, N'[]')) WITH (pay_rule_id BIGINT '$.payRuleId', account_type_id BIGINT '$.accountTypeId',
             credit DECIMAL(18,2) '$.credit', debit DECIMAL(18,2) '$.debit', description NVARCHAR(MAX) '$.description') j;

        EXEC [pay].[usp_payslip_totals_refresh] @payroll_id = @id;

        UPDATE [pay].[payroll]
        SET status = CASE WHEN status = N'open' THEN N'running' ELSE status END, last_run_at = @now,
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
