-- Whether a closed payroll (or a released final settlement) has already paid a person for a month.
CREATE OR ALTER FUNCTION [pay].[fn_month_locked] (@employee_id BIGINT, @month DATE)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1 FROM [pay].[payslip] p LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
        WHERE p.employee_id = @employee_id AND p.payslip_month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1)
          AND (pr.status = N'closed' OR (p.payroll_id IS NULL AND p.status = N'released'))) THEN 1 ELSE 0 END;
END
GO

-- True when a closed payroll (or released settlement) already paid this person for the month of @date or later.
CREATE OR ALTER FUNCTION [pay].[fn_month_locked_since] (@employee_id BIGINT, @date DATE)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1 FROM [pay].[payslip] p LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id
        WHERE p.employee_id = @employee_id AND p.payslip_month >= DATEFROMPARTS(YEAR(@date), MONTH(@date), 1)
          AND (pr.status = N'closed' OR (p.payroll_id IS NULL AND p.status = N'released'))) THEN 1 ELSE 0 END;
END
