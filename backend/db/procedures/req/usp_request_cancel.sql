-- Cancels a request (WF2 steps 6 and 7), with a reason.
--   pending   withdrawn at once by the requester side (the caller's cancel permission reaches
--             the employee): status cancelled, nothing had taken effect.
--   approved  the cancellation walks the type's cancellation flow (or the request flow when there
--             is none): status cancelling. Its final approval cancels the request and reverts the
--             owning module's effect; a rejection leaves it approved.
-- Allowed when @permission_code reaches the employee, or when the caller took part in its approval
-- (approver, role holder or delegatee: "the delegatee can Approve, Reject or Cancel").
-- Work from home only: @cancel_dates (JSON list of yyyy-MM-dd within the request's dates), @cancel_start_time
-- and @cancel_end_time are stored with the cancellation (the approver's "WFH Cancel" form, R2). What
-- cancelling a day from-to a time means is an open product question: they change nothing yet.
-- TODO(R2): once answered, a partial cancellation keeps the other days / hours (revert only those).
CREATE OR ALTER PROCEDURE [req].[usp_request_cancel]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @reason          NVARCHAR(MAX),
    @row_version     BINARY(8),
    @type_code       NVARCHAR(30) = NULL,
    @permission_code NVARCHAR(150) = NULL,
    @cancel_dates      NVARCHAR(MAX) = NULL,
    @cancel_start_time TIME(0) = NULL,
    @cancel_end_time   TIME(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT, @code NVARCHAR(30), @r_from DATE, @r_to DATE;
    SELECT @rv = r.row_version, @status = r.status, @employee_id = r.employee_id, @code = t.code,
           @r_from = r.from_date, @r_to = ISNULL(r.to_date, r.from_date)
    FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.id = @id AND r.company_id = @company_id AND r.is_deleted = 0 AND (@type_code IS NULL OR t.code = @type_code);
    IF @rv IS NULL
        THROW 50404, N'Request not found', 1;

    DECLARE @as_requester BIT = CASE WHEN @permission_code IS NOT NULL AND EXISTS (
                SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                WHERE v.employee_id = @employee_id) THEN 1 ELSE 0 END;
    DECLARE @as_approver BIT = CASE WHEN EXISTS (
                SELECT 1 FROM [req].[fn_actor_steps](@company_id, @me) a WHERE a.request_id = @id) THEN 1 ELSE 0 END;
    IF @as_requester = 0 AND @as_approver = 0
        THROW 50404, N'Request not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF @reason IS NULL
        THROW 50400, N'reason|Reason for cancellation is required.', 1;
    IF @status = N'pending' AND @as_requester = 0
        THROW 50403, N'Only the requester side can withdraw a pending request; reject it instead.', 1;
    IF @status NOT IN (N'pending', N'approved')
        THROW 50409, N'Only a pending or approved request can be cancelled.', 1;

    SET @cancel_dates = NULLIF(LTRIM(RTRIM(@cancel_dates)), N'');
    IF (@cancel_dates IS NOT NULL OR @cancel_start_time IS NOT NULL OR @cancel_end_time IS NOT NULL)
       AND @code <> N'work_from_home'
        THROW 50400, N'dates|Dates and times can only be given when cancelling a work from home request.', 1;
    IF @cancel_dates IS NOT NULL AND ISJSON(@cancel_dates) = 0
        THROW 50400, N'dates|Dates are not valid.', 1;
    IF @cancel_dates IS NOT NULL AND EXISTS (
            SELECT 1 FROM OPENJSON(@cancel_dates) j
            WHERE TRY_CAST(j.value AS DATE) IS NULL OR TRY_CAST(j.value AS DATE) NOT BETWEEN @r_from AND @r_to)
        THROW 50400, N'dates|Choose dates within the request.', 1;
    IF @cancel_start_time IS NOT NULL AND @cancel_end_time IS NOT NULL AND @cancel_end_time <= @cancel_start_time
        THROW 50400, N'endTime|End time must be after the start time.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @since BIGINT = (SELECT MAX(id) FROM [req].[request_step] WHERE request_id = @id);
    BEGIN TRAN;
        UPDATE [req].[request]
        SET cancel_reason = @reason, cancel_requested_at = @now, updated_at = @now, updated_by = @actor_user_id,
            cancel_dates = @cancel_dates, cancel_start_time = @cancel_start_time, cancel_end_time = @cancel_end_time,
            status = CASE WHEN @status = N'pending' THEN N'cancelled' ELSE N'cancelling' END,
            decided_at = CASE WHEN @status = N'pending' THEN @now ELSE decided_at END,
            current_node_id = NULL
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this request. Reload it and try again', 1;

        IF @status = N'pending'
        BEGIN
            UPDATE [req].[request_step]
            SET action_taken = N'skipped', remarks = N'Withdrawn by the requester.', acted_at = @now, updated_at = @now
            WHERE request_id = @id AND action_taken = N'pending';
            INSERT [req].[request_step] (request_id, purpose, approver_kind, acted_by_id, action_taken, remarks, acted_at, created_by)
            VALUES (@id, N'request', N'requester', @me, N'withdrawn', @reason, @now, @actor_user_id);
        END
        ELSE
        BEGIN
            INSERT [req].[request_step] (request_id, purpose, approver_kind, acted_by_id, action_taken, remarks, acted_at, created_by)
            VALUES (@id, N'cancellation', CASE WHEN @as_requester = 1 THEN N'requester' ELSE N'approver' END, @me,
                    N'cancel_requested', @reason, @now, @actor_user_id);
            EXEC [req].[usp_request_flow_pick] @company_id = @company_id, @actor_user_id = @actor_user_id,
                 @request_id = @id, @purpose = N'cancellation';
            EXEC [req].[usp_request_advance] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id;
            IF NOT EXISTS (SELECT 1 FROM [req].[request] WHERE id = @id AND status = N'cancelling')
                THROW 50400, N'reason|NO_APPROVER|Nobody in the approval flow can decide this cancellation.', 1;
        END

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'status', @status, (SELECT status FROM [req].[request] WHERE id = @id), N'cancel', @actor_user_id, @now);

        DECLARE @cancel_event NVARCHAR(100) = CASE WHEN (SELECT status FROM [req].[request] WHERE id = @id) = N'cancelling'
                                                   THEN N'requests.cancellation_requested' ELSE N'requests.cancelled' END;
        DECLARE @cancel_action NVARCHAR(30) = CASE WHEN @status = N'pending' THEN N'withdrawn'
                                                   WHEN @cancel_event = N'requests.cancelled' THEN N'cancellation_approved'
                                                   ELSE N'cancel_requested' END;
        EXEC [req].[usp_request_publish] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id,
             @event_type = @cancel_event, @action = @cancel_action, @since_step_id = @since, @remarks = @reason;
    COMMIT;
END
