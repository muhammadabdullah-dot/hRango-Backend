-- Closes a run (monthly or daily wages). Cannot be reverted: amounts are locked, ready payslips are
-- released, the time sheet days it used are frozen, and what it deducted is marked as taken: loan
-- installments paid, warning penalties linked to the payslip, leave encashments linked, rule postings
-- processed. Logged with user and time. Publishes payroll.closed and tells each employee whose payslip
-- was released.
-- Monthly runs also record the close e-mail (pay.payroll_close_email): 'disabled' while mail is not set
-- up (@mail_enabled 0, nothing is sent), else 'queued'; one pay.mail_outbox row per person with a
-- released payslip and an e-mail address (status 'queued' for the mail sender, or 'disabled').
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_close]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @kind          NVARCHAR(30),
    @row_version   BINARY(8),
    @mail_enabled  BIT = 0,
    @mail_subject  NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @month DATE, @work_date DATE;
    SELECT @rv = row_version, @status = status, @month = payroll_month, @work_date = work_date
    FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = @kind;
    IF @rv IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is already closed', 1;
    IF @status = N'open' OR NOT EXISTS (SELECT 1 FROM [pay].[payslip] WHERE payroll_id = @id)
        THROW 50409, N'status|PAYROLL_NOT_RUN|Run the payroll before closing it', 1;

    DECLARE @from DATE = ISNULL(@month, @work_date), @to DATE = ISNULL(EOMONTH(@month), @work_date);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @released TABLE (id BIGINT PRIMARY KEY);

    BEGIN TRAN;
        UPDATE [pay].[payroll]
        SET status = N'closed', closed_at = @now, closed_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;

        UPDATE [pay].[payslip] SET status = N'released', released_at = @now, updated_at = @now, updated_by = @actor_user_id
        OUTPUT inserted.id INTO @released
        WHERE payroll_id = @id AND status = N'ready';

        UPDATE t SET is_frozen = 1
        FROM [att].[timesheet_day] t
        JOIN [pay].[payslip] p ON p.payroll_id = @id AND p.employee_id = t.employee_id
        WHERE t.work_date BETWEEN @from AND @to;

        IF @kind = N'monthly'
        BEGIN
            -- Loan installments due this month, for people whose slip deducted them.
            UPDATE i
            SET status = N'paid', paid_amount = i.amount, paid_at = @now, payslip_id = p.id, updated_at = @now, updated_by = @actor_user_id
            FROM [loan].[loan_installment] i
            JOIN [loan].[loan] l ON l.id = i.loan_id AND l.status = N'active'
            JOIN [loan].[loan_type] lt ON lt.id = l.loan_type_id
            JOIN [pay].[payslip] p ON p.payroll_id = @id AND p.employee_id = l.employee_id
            WHERE ISNULL(i.status, N'') <> N'paid'
              AND DATEFROMPARTS(YEAR(i.due_month), MONTH(i.due_month), 1) = @month
              AND EXISTS (SELECT 1 FROM [pay].[payslip_line] ln
                          JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
                          WHERE ln.payslip_id = p.id AND ln.amount > 0
                            AND (ln.pay_item_id = lt.deduction_pay_item_id OR (lt.deduction_pay_item_id IS NULL AND pi.system_code = N'loan_deduction')));

            UPDATE l SET status = N'settled', settled_at = @now, updated_at = @now, updated_by = @actor_user_id
            FROM [loan].[loan] l
            WHERE l.status = N'active'
              AND l.employee_id IN (SELECT employee_id FROM [pay].[payslip] WHERE payroll_id = @id)
              AND EXISTS (SELECT 1 FROM [loan].[loan_installment] i WHERE i.loan_id = l.id)
              AND NOT EXISTS (SELECT 1 FROM [loan].[loan_installment] i WHERE i.loan_id = l.id AND ISNULL(i.status, N'') <> N'paid');

            UPDATE w SET payslip_id = p.id
            FROM [att].[warning] w
            JOIN [pay].[payslip] p ON p.payroll_id = @id AND p.employee_id = w.employee_id
            WHERE w.payslip_id IS NULL AND w.work_date BETWEEN @from AND @to
              AND ISNULL(w.deduction, N'payroll') IN (N'payroll', N'both');

            UPDATE r SET payslip_id = p.id
            FROM [lv].[leave_encashment_employee] r
            JOIN [lv].[leave_encashment] h ON h.id = r.leave_encashment_id AND h.mode = N'payroll' AND h.encashment_date <= @to
            JOIN [pay].[payslip] p ON p.payroll_id = @id AND p.employee_id = r.employee_id
            WHERE r.payslip_id IS NULL
              AND EXISTS (SELECT 1 FROM [pay].[payslip_line] ln JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
                          WHERE ln.payslip_id = p.id AND pi.system_code = N'leave_encashment');

            UPDATE a SET is_processed = 1, updated_at = @now, updated_by = @actor_user_id
            FROM [pay].[employee_account_entry] a
            JOIN [pay].[payslip] p ON p.id = a.payslip_id AND p.payroll_id = @id;

            -- Close e-mail: who would get it (released payslips with an address).
            DECLARE @mail TABLE (employee_id BIGINT PRIMARY KEY, to_address NVARCHAR(254));
            INSERT @mail (employee_id, to_address)
            SELECT p.employee_id, a.address
            FROM [pay].[payslip] p
            JOIN @released r ON r.id = p.id
            CROSS APPLY (SELECT [pay].[fn_employee_email](p.employee_id) AS address) a
            WHERE a.address IS NOT NULL;

            INSERT [pay].[payroll_close_email] (payroll_id, status, recipient_count, queued_at, created_by)
            VALUES (@id, CASE WHEN @mail_enabled = 1 THEN N'queued' ELSE N'disabled' END, (SELECT COUNT(*) FROM @mail),
                    CASE WHEN @mail_enabled = 1 THEN @now END, @actor_user_id);
            -- One row per person either way, so the run shows who it was (or would have been) sent to.
            INSERT [pay].[mail_outbox] (company_id, entity_type, entity_id, employee_id, to_address, subject, status, queued_at, created_by)
            SELECT @company_id, N'pay.payroll', @id, employee_id, to_address, @mail_subject,
                   CASE WHEN @mail_enabled = 1 THEN N'queued' ELSE N'disabled' END, CASE WHEN @mail_enabled = 1 THEN @now END,
                   @actor_user_id
            FROM @mail;
        END

        INSERT [pay].[payroll_run_log] (payroll_id, kind, started_at, finished_at, status, run_by_user_id, processed_count, error_count, created_by)
        VALUES (@id, N'close', @now, @now, N'completed', @actor_user_id, (SELECT COUNT(*) FROM [pay].[payslip] WHERE payroll_id = @id), 0, @actor_user_id);
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.payroll', @id, N'status', @status, N'closed', N'close', @actor_user_id, @now);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), p.id) AS payrollId, p.code, p.name, p.kind,
                   CONVERT(NVARCHAR(10), p.payroll_month, 23) AS payrollMonth, CONVERT(NVARCHAR(10), p.work_date, 23) AS workDate,
                   p.currency, s.payslips, (SELECT COUNT(*) FROM @released) AS payslipsReleased,
                   s.on_hold AS payslipsOnHold, s.total_earnings AS totalEarnings, s.total_deductions AS totalDeductions,
                   s.net_payable AS netPayable, p.closed_at AS closedAt, CONVERT(NVARCHAR(30), @actor_user_id) AS closedBy
            FROM [pay].[payroll] p
            CROSS APPLY (SELECT COUNT(*) AS payslips, SUM(CASE WHEN ps.status = N'on_hold' THEN 1 ELSE 0 END) AS on_hold,
                                ISNULL(SUM(ps.total_earnings), 0) AS total_earnings,
                                ISNULL(SUM(ps.total_deductions), 0) AS total_deductions,
                                ISNULL(SUM(ps.net_payable), 0) AS net_payable
                         FROM [pay].[payslip] ps WHERE ps.payroll_id = p.id) s
            WHERE p.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'payroll.closed',
             @entity_type = N'pay.payroll', @entity_id = @id, @payload = @payload;

        DECLARE @ids NVARCHAR(MAX) = (SELECT CONCAT(N'[', STRING_AGG(CONVERT(NVARCHAR(MAX), id), N','), N']') FROM @released);
        EXEC [pay].[usp_payslip_notify_released] @company_id = @company_id, @payslip_ids = @ids;
    COMMIT;

    EXEC [pay].[usp_payroll_get] @company_id = @company_id, @id = @id;
END
