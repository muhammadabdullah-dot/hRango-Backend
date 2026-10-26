-- Deletes a pending request nobody has acted on yet ("Delete" on the requester's lists). The row
-- is kept, marked deleted, so the action stays traceable (Mini SRS NFR-4).
CREATE OR ALTER PROCEDURE [req].[usp_request_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @type_code       NVARCHAR(30),
    @permission_code NVARCHAR(150),
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT;
    SELECT @rv = r.row_version, @status = r.status, @employee_id = r.employee_id
    FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.id = @id AND r.company_id = @company_id AND r.is_deleted = 0 AND t.code = @type_code;
    IF @rv IS NULL OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                                  WHERE v.employee_id = @employee_id)
        THROW 50404, N'Request not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    IF @status <> N'pending' OR EXISTS (SELECT 1 FROM [req].[request_step] WHERE request_id = @id
                                         AND action_taken IN (N'approved', N'rejected', N'consented', N'disagreed', N'forwarded'))
        THROW 50409, N'Only a pending request nobody has acted on can be deleted. Cancel it instead.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [req].[request]
        SET is_deleted = 1, status = N'cancelled', current_node_id = NULL, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
        UPDATE [req].[request_step]
        SET action_taken = N'skipped', remarks = N'Request deleted.', acted_at = @now, updated_at = @now
        WHERE request_id = @id AND action_taken = N'pending';

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'delete', @actor_user_id, @now);

        EXEC [req].[usp_request_publish] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id,
             @event_type = N'requests.cancelled', @action = N'deleted', @since_step_id = NULL;
    COMMIT;
END
