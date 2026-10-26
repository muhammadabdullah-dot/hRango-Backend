-- Forwards the current approval step to another employee (Mini SRS MOB-2: "approves, rejects with
-- remarks, or forwards"). The step is recorded as forwarded and the same node waits for the new
-- approver; the flow then goes on as before.
CREATE OR ALTER PROCEDURE [req].[usp_request_forward]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @to_employee_id BIGINT,
    @remarks       NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT;
    SELECT @rv = row_version, @status = status, @employee_id = employee_id
    FROM [req].[request] WHERE id = @id AND company_id = @company_id AND is_deleted = 0;
    IF @rv IS NULL
        THROW 50404, N'Request not found', 1;

    DECLARE @step BIGINT, @is_delegate BIT, @is_consent BIT, @node BIGINT, @purpose NVARCHAR(30), @kind NVARCHAR(30);
    SELECT TOP (1) @step = s.id, @is_delegate = a.is_delegate, @is_consent = s.is_consent, @node = s.approval_node_id,
           @purpose = s.purpose, @kind = s.approver_kind
    FROM [req].[fn_actor_steps](@company_id, @me) a
    JOIN [req].[request_step] s ON s.id = a.step_id AND s.action_taken = N'pending'
    WHERE a.request_id = @id
    ORDER BY a.is_delegate, s.id;
    IF @step IS NULL OR @employee_id = @me
        THROW 50403, N'You are not the approver of this request at its current step.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    IF @is_consent = 1
        THROW 50400, N'action|A consent step cannot be forwarded.', 1;
    IF @to_employee_id IS NULL OR @to_employee_id IN (@me, @employee_id)
       OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @to_employee_id AND company_id = @company_id AND status <> N'left')
        THROW 50400, N'employeeId|Choose someone else to forward this request to.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [req].[request] SET updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this request. Reload it and try again', 1;

        UPDATE [req].[request_step]
        SET action_taken = N'forwarded', acted_by_id = @me, is_delegate = @is_delegate,
            remarks = NULLIF(LTRIM(RTRIM(@remarks)), N''), acted_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @step;

        DECLARE @since BIGINT = (SELECT MAX(id) FROM [req].[request_step] WHERE request_id = @id);
        INSERT [req].[request_step] (request_id, approval_node_id, purpose, approver_kind, approver_id, action_taken, created_by)
        VALUES (@id, @node, @purpose, @kind, @to_employee_id, N'pending', @actor_user_id);

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'approver_id', CONVERT(NVARCHAR(30), @to_employee_id), N'forward', @actor_user_id, @now);

        EXEC [req].[usp_request_publish] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id,
             @event_type = N'requests.forwarded', @action = N'forwarded', @since_step_id = @since, @remarks = @remarks;
    COMMIT;
END
