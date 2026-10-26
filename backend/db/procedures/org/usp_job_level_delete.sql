CREATE OR ALTER PROCEDURE [org].[usp_job_level_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [org].[job_level] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Job level not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this job level. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE job_level_id = @id)
        THROW 50409, N'Employees are assigned to this job level. Move them first', 1;

    BEGIN TRAN;
        -- Anything else still pointing here (requests, plans, history) stops the delete with error 547.
        DELETE [org].[job_level] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.job_level', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
