-- Days of a leave type already encashed for a person in a leave year: the ledger's 'encashed' debits (every leave
-- encashment, here or in the leave module, and a closed final settlement), leaving out @except_encashment_id (the
-- encashment being redone). A type's Encashment Max Limit is days per person a year, so what is left of it after
-- these is all a new encashment may pay (pay.usp_leave_encashment_save / _preview, the final settlement).
CREATE OR ALTER FUNCTION [pay].[fn_encashed_days] (@employee_id BIGINT, @leave_type_id BIGINT, @fiscal_year INT,
                                                   @except_encashment_id BIGINT = NULL)
RETURNS DECIMAL(6,2)
AS
BEGIN
    RETURN ISNULL((SELECT -SUM(l.days) FROM [lv].[leave_ledger] l
                   WHERE l.employee_id = @employee_id AND l.leave_type_id = @leave_type_id AND l.fiscal_year = @fiscal_year
                     AND l.reason = N'encashed'
                     AND (@except_encashment_id IS NULL OR ISNULL(l.leave_encashment_id, 0) <> @except_encashment_id)), 0);
END
GO
