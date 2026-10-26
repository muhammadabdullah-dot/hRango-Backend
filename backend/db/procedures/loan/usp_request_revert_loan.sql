-- Undoes the loan request's effect when its approved cancellation is decided: removes the loan and
-- its schedule. Refused once payroll has recovered any installment.
CREATE OR ALTER PROCEDURE [loan].[usp_request_revert_loan]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @loan_id BIGINT = (SELECT id FROM [loan].[loan] WHERE request_id = @request_id AND company_id = @company_id);
    IF @loan_id IS NULL
        RETURN;
    IF EXISTS (SELECT 1 FROM [loan].[loan_installment] WHERE loan_id = @loan_id
               AND (ISNULL(paid_amount, 0) > 0 OR payslip_id IS NOT NULL OR status = N'paid'))
        THROW 50409, N'Installments of this loan have already been recovered through payroll, so it cannot be cancelled.', 1;

    DELETE [loan].[loan_installment] WHERE loan_id = @loan_id;
    DELETE [loan].[loan] WHERE id = @loan_id;
    INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
    VALUES (N'loan.loan', @loan_id, N'delete', @actor_user_id, SYSUTCDATETIME());
END
