-- Edits a pending request: by the requester side (the caller's create permission reaches the
-- employee) while nobody has acted on it, or by the approver of the current step when that node
-- allows editing (Can Edit). Re-validates the details. Takes the @row_version last read.
CREATE OR ALTER PROCEDURE [req].[usp_request_update]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @type_code       NVARCHAR(30),
    @permission_code NVARCHAR(150),
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @reason          NVARCHAR(MAX) = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @application     NVARCHAR(MAX) = NULL,
    @details         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT, @node BIGINT;
    SELECT @rv = r.row_version, @status = r.status, @employee_id = r.employee_id, @node = r.current_node_id
    FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.id = @id AND r.company_id = @company_id AND r.is_deleted = 0 AND t.code = @type_code;
    IF @rv IS NULL
        THROW 50404, N'Request not found', 1;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @as_requester BIT = CASE WHEN EXISTS (
                SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                WHERE v.employee_id = @employee_id) THEN 1 ELSE 0 END;
    DECLARE @as_approver BIT = CASE WHEN EXISTS (
                SELECT 1 FROM [req].[fn_actor_steps](@company_id, @actor_employee_id) a
                JOIN [req].[request_step] s ON s.id = a.step_id AND s.action_taken = N'pending'
                JOIN [req].[approval_node] n ON n.id = s.approval_node_id AND n.can_edit = 1
                WHERE a.request_id = @id) THEN 1 ELSE 0 END;
    IF @as_requester = 0 AND @as_approver = 0
        THROW 50403, N'You cannot edit this request.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    IF @status <> N'pending'
        THROW 50409, N'Only a pending request can be edited.', 1;
    IF @as_approver = 0 AND EXISTS (SELECT 1 FROM [req].[request_step] WHERE request_id = @id
                                    AND action_taken IN (N'approved', N'rejected', N'consented', N'disagreed', N'forwarded'))
        THROW 50409, N'An approver has already acted on this request, so it can no longer be edited.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @old TABLE (field_name NVARCHAR(100), old_value NVARCHAR(MAX));
    INSERT @old
    SELECT N'from_date', CONVERT(NVARCHAR(10), from_date, 23) FROM [req].[request] WHERE id = @id
    UNION ALL SELECT N'to_date', CONVERT(NVARCHAR(10), to_date, 23) FROM [req].[request] WHERE id = @id
    UNION ALL SELECT N'reason', reason FROM [req].[request] WHERE id = @id
    UNION ALL SELECT N'details', [req].[fn_request_details](@id);

    BEGIN TRAN;
        UPDATE [req].[request]
        SET from_date = @from_date, to_date = @to_date, reason = NULLIF(LTRIM(RTRIM(@reason)), N''),
            description = NULLIF(LTRIM(RTRIM(@description)), N''), application = NULLIF(@application, N''),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this request. Reload it and try again', 1;

        EXEC [req].[usp_request_detail_save] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @id, @details = @details;

        IF EXISTS (SELECT 1 FROM [req].[request_restriction] x JOIN [req].[request] r ON r.id = @id
                   WHERE x.company_id = @company_id AND x.request_type_id = r.request_type_id
                     AND x.start_date <= ISNULL(r.to_date, r.from_date) AND x.end_date >= r.from_date)
            THROW 50400, N'fromDate|REQUEST_RESTRICTED|Requests of this type are closed over these dates.', 1;

        EXEC [req].[usp_request_effect_run] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @id, @verb = N'validate';

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'req.request', @id, o.field_name, o.old_value, n.new_value, N'update', @actor_user_id, @now
        FROM @old o
        JOIN (SELECT N'from_date' AS field_name, CONVERT(NVARCHAR(10), from_date, 23) AS new_value FROM [req].[request] WHERE id = @id
              UNION ALL SELECT N'to_date', CONVERT(NVARCHAR(10), to_date, 23) FROM [req].[request] WHERE id = @id
              UNION ALL SELECT N'reason', reason FROM [req].[request] WHERE id = @id
              UNION ALL SELECT N'details', [req].[fn_request_details](@id)) n ON n.field_name = o.field_name
        WHERE EXISTS (SELECT o.old_value EXCEPT SELECT n.new_value);
    COMMIT;
END
