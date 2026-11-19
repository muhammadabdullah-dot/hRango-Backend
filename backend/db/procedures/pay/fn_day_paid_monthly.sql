-- The monthly payroll that already pays a person for a day: a monthly run of that month with them in it, the day
-- within their employment (on or after their joining date, not after their last working date), as the run works
-- out employed days. Daily wages refuse such a day (it would be paid twice): pay.usp_payroll_employee_set,
-- usp_payroll_employee_add_filtered, usp_daily_wage_process and usp_payroll_close.
CREATE OR ALTER FUNCTION [pay].[fn_day_paid_monthly] (@employee_id BIGINT, @work_date DATE)
RETURNS TABLE
AS
RETURN (
    SELECT TOP (1) op.id AS payroll_id, op.code, op.name
    FROM [pay].[payroll_employee] o
    JOIN [pay].[payroll] op ON op.id = o.payroll_id AND op.kind = N'monthly'
         AND op.payroll_month = DATEFROMPARTS(YEAR(@work_date), MONTH(@work_date), 1)
    OUTER APPLY (SELECT TOP (1) p.joining_date FROM [hr].[employment_period] p
                 WHERE p.employee_id = @employee_id AND p.joining_date <= @work_date
                 ORDER BY p.joining_date DESC) ep
    WHERE o.employee_id = @employee_id
      AND (ep.joining_date IS NOT NULL
           OR NOT EXISTS (SELECT 1 FROM [hr].[employment_period] p WHERE p.employee_id = @employee_id))
      AND NOT EXISTS (SELECT 1 FROM [sep].[end_of_employment] x
                      WHERE x.employee_id = @employee_id AND x.last_working_date < @work_date
                        AND x.last_working_date >= ISNULL(ep.joining_date, '19000101'))
    ORDER BY op.id
);
GO
