-- Expense claims (requests of kind expense) reach payroll as opening balances: payroll adds a
-- person's opening balances of a month to that pay item in the month's run (pay.usp_payroll_run_inputs),
-- so an approved claim is paid with the next salary and shows under Reimbursements on the payslip.
-- Written by the requests module for the request engine (README "How modules hand work to each
-- other"); all three run inside the request's transaction.
--   validate  on submit and edit: every claim's category resolves to a reimbursement pay item
--             (the category's own, else Request Settings -> Reimbursement's default).
--   apply     on final approval: one opening balance (kind 'reimbursement', not taxable) per claim
--             with an approved amount above zero, in the first month payroll has not closed for the
--             employee; the claim keeps its id (req.expense_line.opening_balance_id).
--   revert    when the approved request's cancellation is approved: removes those opening balances;
--             refused once a closed payroll has paid them.
-- The pay item must also be ticked on the payroll (Payroll -> pay items) for the run to pay it.

CREATE OR ALTER PROCEDURE [pay].[usp_request_validate_expense]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @default BIGINT = (SELECT expense_pay_item_id FROM [req].[reimbursement_setting] WHERE company_id = @company_id),
            @msg NVARCHAR(400);
    SELECT TOP (1) @msg = N'lines|EXPENSE_NOT_PAYABLE|' + c.name + N' claims cannot be paid yet: no reimbursement pay item '
                        + N'is set for them under Request Settings, Reimbursement.'
    FROM [req].[expense_line] l
    JOIN [req].[expense_category] c ON c.id = l.expense_category_id
    WHERE l.request_id = @request_id AND COALESCE(c.pay_item_id, @default) IS NULL
    ORDER BY l.line_no;
    IF @msg IS NOT NULL
        THROW 50400, @msg, 1;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_request_apply_expense]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @code NVARCHAR(30);
    SELECT @employee_id = r.employee_id, @code = r.code
    FROM [req].[request] r WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Expense request not found', 1;
    IF EXISTS (SELECT 1 FROM [req].[expense_line] WHERE request_id = @request_id AND opening_balance_id IS NOT NULL)
        THROW 50409, N'These claims have already been passed to payroll.', 1;
    EXEC [pay].[usp_request_validate_expense] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @request_id = @request_id;

    -- The first month payroll has not closed for this person, from this month on.
    DECLARE @month DATE = DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1), @guard INT = 0;
    WHILE [pay].[fn_month_locked](@employee_id, @month) = 1 AND @guard < 120
        SELECT @month = DATEADD(MONTH, 1, @month), @guard += 1;

    DECLARE @default BIGINT = (SELECT expense_pay_item_id FROM [req].[reimbursement_setting] WHERE company_id = @company_id),
            @now DATETIME2(0) = SYSUTCDATETIME(), @ob BIGINT,
            @line BIGINT = (SELECT MIN(id) FROM [req].[expense_line] WHERE request_id = @request_id AND approved_amount > 0);
    WHILE @line IS NOT NULL
    BEGIN
        INSERT [pay].[opening_balance] (employee_id, balance_month, pay_item_id, amount, is_taxable, kind, description, created_by)
        SELECT @employee_id, @month, COALESCE(c.pay_item_id, @default), l.approved_amount, 0, N'reimbursement',
               @code + N' expense claim: ' + l.title, @actor_user_id
        FROM [req].[expense_line] l
        JOIN [req].[expense_category] c ON c.id = l.expense_category_id
        WHERE l.id = @line;
        SET @ob = SCOPE_IDENTITY();

        UPDATE [req].[expense_line] SET opening_balance_id = @ob, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @line;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name,
                                   performed_by_user_id, performed_at)
        VALUES (@company_id, N'pay.opening_balance', @ob, N'request_id', CONVERT(NVARCHAR(30), @request_id), N'create',
                @actor_user_id, @now);

        SET @line = (SELECT MIN(id) FROM [req].[expense_line] WHERE request_id = @request_id AND approved_amount > 0 AND id > @line);
    END
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_request_revert_expense]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [req].[request] WHERE id = @request_id AND company_id = @company_id)
        RETURN;
    IF EXISTS (SELECT 1 FROM [req].[expense_line] l
               JOIN [pay].[opening_balance] o ON o.id = l.opening_balance_id
               WHERE l.request_id = @request_id AND [pay].[fn_month_locked](o.employee_id, o.balance_month) = 1)
        THROW 50409, N'These claims have already been paid through payroll, so the request cannot be cancelled.', 1;

    DECLARE @gone TABLE (id BIGINT PRIMARY KEY);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    UPDATE [req].[expense_line]
    SET opening_balance_id = NULL, updated_at = @now, updated_by = @actor_user_id
    OUTPUT deleted.opening_balance_id INTO @gone
    WHERE request_id = @request_id AND opening_balance_id IS NOT NULL;

    DELETE [pay].[opening_balance] WHERE id IN (SELECT id FROM @gone);
    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id,
                               performed_at)
    SELECT @company_id, N'pay.opening_balance', id, N'request_id', CONVERT(NVARCHAR(30), @request_id), N'delete',
           @actor_user_id, @now
    FROM @gone;
END
