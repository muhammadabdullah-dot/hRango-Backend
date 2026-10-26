CREATE OR ALTER PROCEDURE [org].[usp_cost_center_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [org].[cost_center] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Cost center not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this cost center. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE cost_center_id = @id)
        THROW 50409, N'Employees are assigned to this cost center. Move them first', 1;

    BEGIN TRAN;
        -- Anything else still pointing here (requests, plans, history) stops the delete with error 547.
        DELETE [org].[cost_center] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.cost_center', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
