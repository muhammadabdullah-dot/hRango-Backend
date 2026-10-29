-- Bank transfer file of a closed run (monthly or daily wages): net pay per person paid by bank transfer
-- through the chosen disbursement bank. A run is paid through its own disbursement bank, so the bank must
-- be the run's (any of the company's banks when the run names none, as daily-wage runs do). People whose
-- payslip is on hold or pays nothing are left out; the account is the person's primary bank account (else
-- the first one). The API writes the file (CSV, fixed-width TXT) from these rows.
-- TODO(payroll): a per-person disbursement bank (split a run across several company banks) is not in the
-- design; every bank-paid payslip of the run goes through the run's bank.
-- Result set 1: the run and the bank. Result set 2: the transfers.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_bank_file]
    @company_id           BIGINT,
    @actor_user_id        BIGINT,
    @permission_code      NVARCHAR(150),
    @id                   BIGINT,
    @kind                 NVARCHAR(30),
    @disbursement_bank_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @status NVARCHAR(30), @run_bank BIGINT, @found BIT = 0;
    SELECT @found = 1, @status = status, @run_bank = disbursement_bank_id
    FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = @kind;
    IF @found = 0
        THROW 50404, N'Payroll not found', 1;
    IF @status <> N'closed'
        THROW 50409, N'status|PAYROLL_NOT_CLOSED|Close the payroll before downloading its bank transfer file', 1;

    SET @disbursement_bank_id = ISNULL(@disbursement_bank_id, @run_bank);
    IF @disbursement_bank_id IS NULL
        THROW 50400, N'disbursementBankId|Choose the disbursement bank.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[disbursement_bank] WHERE id = @disbursement_bank_id AND company_id = @company_id)
        THROW 50400, N'disbursementBankId|Disbursement bank not found.', 1;
    IF @run_bank IS NOT NULL AND @run_bank <> @disbursement_bank_id
        THROW 50400, N'disbursementBankId|This payroll is paid through another disbursement bank.', 1;

    SELECT p.id, p.code, p.name, p.kind, p.payroll_month, p.work_date, ISNULL(p.currency, c.currency) AS currency,
           b.id AS bank_id, b.bank_name, b.account_holder AS bank_account_holder, b.account_number AS bank_account_number,
           b.branch_code AS bank_branch_code
    FROM [pay].[payroll] p
    JOIN [org].[company] c ON c.id = p.company_id
    JOIN [pay].[disbursement_bank] b ON b.id = @disbursement_bank_id
    WHERE p.id = @id;

    SELECT ps.employee_id, e.code AS employee_code, NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N'') AS employee_name,
           ISNULL(a.account_holder, NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N'')) AS account_holder,
           a.account_number, a.bank_name, a.branch_code, ps.net_payable AS amount
    FROM [pay].[payslip] ps
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = ps.employee_id
    JOIN [hr].[employee] e ON e.id = ps.employee_id
    CROSS APPLY (SELECT TOP 1 x.account_holder, x.account_number, x.bank_name, x.branch_code
                 FROM [hr].[employee_bank_account] x WHERE x.employee_id = ps.employee_id
                 ORDER BY x.is_primary DESC, x.id) a
    WHERE ps.payroll_id = @id AND ps.payment_method = N'bank' AND ps.status <> N'on_hold' AND ps.net_payable > 0
    ORDER BY e.code;
END
