-- Tells each employee that their payslip is out. Called inside the caller's transaction when payslips
-- become released (closing a run, taking a slip off hold after the close, paying a slip, closing a final
-- settlement). @payslip_ids: JSON array of payslip ids. One notification per payslip; no result set.
CREATE OR ALTER PROCEDURE [pay].[usp_payslip_notify_released]
    @company_id  BIGINT,
    @payslip_ids NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @slips TABLE (id BIGINT PRIMARY KEY, employee_id BIGINT, title NVARCHAR(200));
    INSERT @slips (id, employee_id, title)
    SELECT p.id, p.employee_id,
           CASE WHEN p.is_final_settlement = 1 OR p.payroll_id IS NULL THEN N'Your final settlement payslip is ready'
                WHEN pr.kind = N'daily_wage' THEN CONCAT(N'Your daily wage slip for ', CONVERT(NVARCHAR(10), ISNULL(pr.work_date, p.payslip_month), 23), N' is ready')
                ELSE CONCAT(N'Your payslip for ', DATENAME(MONTH, p.payslip_month), N' ', YEAR(p.payslip_month), N' is ready') END
    FROM (SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) AS id FROM OPENJSON(ISNULL(@payslip_ids, N'[]'))) j
    JOIN [pay].[payslip] p ON p.id = j.id AND p.company_id = @company_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = p.payroll_id;

    DECLARE @id BIGINT = (SELECT MIN(id) FROM @slips), @employee_id BIGINT, @title NVARCHAR(200);
    WHILE @id IS NOT NULL
    BEGIN
        SELECT @employee_id = employee_id, @title = title FROM @slips WHERE id = @id;
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
             @title = @title, @notification_type = N'payslip', @link = N'/payroll/pay-slips/my',
             @entity_type = N'pay.payslip', @entity_id = @id;
        SET @id = (SELECT MIN(id) FROM @slips WHERE id > @id);
    END
END
