-- Air ticket claims (requests of kind air_ticket) reach payroll the same way as expense claims
-- (see usp_request_apply_expense.sql): one opening balance under the air ticket reimbursement pay
-- item of Request Settings -> Reimbursement, in the first month payroll has not closed for the
-- employee. Written by the requests module for the request engine; run inside the request's
-- transaction.

CREATE OR ALTER PROCEDURE [pay].[usp_request_validate_air_ticket]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [req].[reimbursement_setting]
                   WHERE company_id = @company_id AND air_ticket_pay_item_id IS NOT NULL)
        THROW 50400, N'amount|AIR_TICKET_NOT_PAYABLE|Air tickets cannot be claimed yet: no reimbursement pay item is set for them under Request Settings, Reimbursement.', 1;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_request_apply_air_ticket]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @code NVARCHAR(30), @title NVARCHAR(200), @amount DECIMAL(18,2), @existing BIGINT;
    SELECT @employee_id = r.employee_id, @code = r.code, @title = a.title, @amount = ISNULL(a.approved_amount, a.amount),
           @existing = a.opening_balance_id
    FROM [req].[request] r
    JOIN [req].[req_air_ticket] a ON a.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Air ticket request not found', 1;
    IF @existing IS NOT NULL
        THROW 50409, N'This air ticket has already been passed to payroll.', 1;
    EXEC [pay].[usp_request_validate_air_ticket] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @request_id = @request_id;

    DECLARE @month DATE = DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1), @guard INT = 0;
    WHILE [pay].[fn_month_locked](@employee_id, @month) = 1 AND @guard < 120
        SELECT @month = DATEADD(MONTH, 1, @month), @guard += 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @ob BIGINT,
            @item BIGINT = (SELECT air_ticket_pay_item_id FROM [req].[reimbursement_setting] WHERE company_id = @company_id);
    INSERT [pay].[opening_balance] (employee_id, balance_month, pay_item_id, amount, is_taxable, kind, description, created_by)
    VALUES (@employee_id, @month, @item, @amount, 0, N'reimbursement', @code + N' air ticket: ' + @title, @actor_user_id);
    SET @ob = SCOPE_IDENTITY();

    UPDATE [req].[req_air_ticket] SET opening_balance_id = @ob, updated_at = @now, updated_by = @actor_user_id
    WHERE request_id = @request_id;
    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id,
                               performed_at)
    VALUES (@company_id, N'pay.opening_balance', @ob, N'request_id', CONVERT(NVARCHAR(30), @request_id), N'create',
            @actor_user_id, @now);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_request_revert_air_ticket]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ob BIGINT, @employee_id BIGINT, @month DATE;
    SELECT @ob = o.id, @employee_id = o.employee_id, @month = o.balance_month
    FROM [req].[request] r
    JOIN [req].[req_air_ticket] a ON a.request_id = r.id
    JOIN [pay].[opening_balance] o ON o.id = a.opening_balance_id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @ob IS NULL
        RETURN;
    IF [pay].[fn_month_locked](@employee_id, @month) = 1
        THROW 50409, N'This air ticket has already been paid through payroll, so the request cannot be cancelled.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    UPDATE [req].[req_air_ticket] SET opening_balance_id = NULL, updated_at = @now, updated_by = @actor_user_id
    WHERE request_id = @request_id;
    DELETE [pay].[opening_balance] WHERE id = @ob;
    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id,
                               performed_at)
    VALUES (@company_id, N'pay.opening_balance', @ob, N'request_id', CONVERT(NVARCHAR(30), @request_id), N'delete',
            @actor_user_id, @now);
END
