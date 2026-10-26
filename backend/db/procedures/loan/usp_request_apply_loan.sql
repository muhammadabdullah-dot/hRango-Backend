-- The loan request's effect, run by the request engine inside the final approval's transaction:
-- creates the loan from the approved amount and the type's terms, and its installment schedule
-- (No. of Installments, every Gap Between Installments months from the repayment date's month).
-- A Non-Payable type makes a loan without installments.
CREATE OR ALTER PROCEDURE [loan].[usp_request_apply_loan]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @type_id BIGINT, @category_id BIGINT, @amount DECIMAL(18,2), @currency CHAR(3),
            @method NVARCHAR(30), @repay DATE, @n INT, @gap INT, @non_payable BIT;
    SELECT @employee_id = r.employee_id, @type_id = q.loan_type_id, @category_id = q.loan_category_id,
           @amount = q.approved_amount, @currency = q.currency, @method = q.payment_method, @repay = q.repayment_date,
           @n = t.installments, @gap = t.gap_between_installments_months, @non_payable = t.non_payable
    FROM [req].[request] r
    JOIN [req].[req_loan] q ON q.request_id = r.id
    JOIN [loan].[loan_type] t ON t.id = q.loan_type_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF @employee_id IS NULL
        THROW 50404, N'Loan request not found', 1;
    IF @amount IS NULL OR @repay IS NULL
        THROW 50400, N'approvedAmount|Approved amount and repayment date are required to approve a loan.', 1;
    IF EXISTS (SELECT 1 FROM [loan].[loan] WHERE request_id = @request_id)
        THROW 50409, N'A loan already exists for this request.', 1;

    SET @n = CASE WHEN @non_payable = 1 THEN 0 ELSE ISNULL(NULLIF(@n, 0), 1) END;
    SET @gap = ISNULL(NULLIF(@gap, 0), 1);
    DECLARE @start DATE = DATEFROMPARTS(YEAR(@repay), MONTH(@repay), 1), @loan_id BIGINT,
            @each DECIMAL(18,2) = CASE WHEN @n > 0 THEN ROUND(@amount / @n, 2, 1) END;

    INSERT [loan].[loan] (company_id, employee_id, request_id, loan_type_id, loan_category_id, principal, installment_amount,
                          installments, gap_between_installments_months, currency, payment_method, start_month, status, created_by)
    VALUES (@company_id, @employee_id, @request_id, @type_id, @category_id, @amount, @each, @n, @gap, @currency, @method,
            @start, CASE WHEN @n = 0 THEN N'non_payable' ELSE N'active' END, @actor_user_id);
    SET @loan_id = SCOPE_IDENTITY();

    IF @n > 0
    BEGIN
        WITH k AS (SELECT TOP (@n) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS no FROM sys.all_objects)
        INSERT [loan].[loan_installment] (loan_id, installment_no, due_month, amount, paid_amount, status, created_by)
        SELECT @loan_id, k.no, DATEADD(MONTH, (k.no - 1) * @gap, @start),
               CASE WHEN k.no = @n THEN @amount - @each * (@n - 1) ELSE @each END, 0, N'due', @actor_user_id
        FROM k;
    END

    INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
    VALUES (N'loan.loan', @loan_id, N'create', @actor_user_id, SYSUTCDATETIME());
END
