-- Next code from core.number_sequence for a prefix: PR-00008, TXS-0004, VCH-00012. Call inside the
-- caller's transaction so the number and the row that uses it commit together.
CREATE OR ALTER PROCEDURE [pay].[usp_sequence_next]
    @company_id BIGINT,
    @prefix     NVARCHAR(10),
    @digits     INT,
    @code       NVARCHAR(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n BIGINT;
    UPDATE [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK)
    SET @n = next_number, next_number = next_number + 1, updated_at = SYSUTCDATETIME()
    WHERE company_id = @company_id AND prefix = @prefix;
    IF @n IS NULL
    BEGIN
        INSERT [core].[number_sequence] (company_id, prefix, next_number) VALUES (@company_id, @prefix, 2);
        SET @n = 1;
    END
    SET @code = @prefix + RIGHT(REPLICATE(N'0', @digits) + CONVERT(NVARCHAR(20), @n), @digits);
END
GO

-- Recomputes payslip totals from their lines: earnings, deductions and reimbursements, leaving out
-- display-only items and items the run marks "calculate only". Gross is the salary line, tax the tax line.
-- One payslip (@payslip_id) or every payslip of a run (@payroll_id).
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_totals_refresh]
    @payslip_id BIGINT = NULL,
    @payroll_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE s
    SET total_earnings = ISNULL(x.earnings, 0), total_deductions = ISNULL(x.deductions, 0),
        total_reimbursements = ISNULL(x.reimbursements, 0),
        net_payable = ISNULL(x.earnings, 0) + ISNULL(x.reimbursements, 0) - ISNULL(x.deductions, 0),
        gross = ISNULL(x.salary, 0), tax_amount = ISNULL(x.tax, 0), updated_at = SYSUTCDATETIME()
    FROM [pay].[payslip] s
    OUTER APPLY (
        SELECT SUM(CASE WHEN pi.item_type = N'earning' THEN ln.amount END) AS earnings,
               SUM(CASE WHEN pi.item_type = N'deduction' THEN ln.amount END) AS deductions,
               SUM(CASE WHEN pi.item_type = N'reimbursement' THEN ln.amount END) AS reimbursements,
               SUM(CASE WHEN pi.system_code = N'salary' THEN ln.amount END) AS salary,
               SUM(CASE WHEN pi.system_code = N'tax' THEN ln.amount END) AS tax
        FROM [pay].[payslip_line] ln
        JOIN [pay].[pay_item] pi ON pi.id = ln.pay_item_id
        LEFT JOIN [pay].[payroll_pay_item] ppi ON ppi.payroll_id = s.payroll_id AND ppi.pay_item_id = ln.pay_item_id
        WHERE ln.payslip_id = s.id AND pi.is_display_only = 0 AND ISNULL(ppi.calculate_only, 0) = 0) x
    WHERE s.is_manually_updated = 0
      AND ((@payslip_id IS NOT NULL AND s.id = @payslip_id) OR (@payroll_id IS NOT NULL AND s.payroll_id = @payroll_id));
END
