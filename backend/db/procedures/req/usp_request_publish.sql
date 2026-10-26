-- Tells the world what just happened to a request (internal; called at the end of submit, decide,
-- forward, cancel and delete, inside their transaction, after the change):
--   1. publishes @event_type (requests.submitted, requests.step_decided, requests.forwarded,
--      requests.approved, requests.rejected, requests.cancellation_requested,
--      requests.cancellation_rejected, requests.cancelled) with the request, its status and the
--      step now waiting;
--   2. notifies whoever must act on a step that became pending in this action (steps with an id
--      above @since_step_id): the named approver and their active delegatees for the type, or every
--      active holder of the step's role;
--   3. on a decision (approved, rejected, cancelled, cancellation rejected) notifies the employee
--      the request is for, unless they did it themselves.
-- Returns no result set (the notification procedures' results are captured).
CREATE OR ALTER PROCEDURE [req].[usp_request_publish]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT,
    @event_type    NVARCHAR(100),
    @action        NVARCHAR(30) = NULL,
    @since_step_id BIGINT = 0,
    @remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @code NVARCHAR(30), @type_id BIGINT, @type_code NVARCHAR(30), @type_name NVARCHAR(200),
            @employee_id BIGINT, @employee_name NVARCHAR(400), @status NVARCHAR(30);
    SELECT @code = r.code, @type_id = r.request_type_id, @type_code = t.code, @type_name = t.name,
           @employee_id = r.employee_id, @employee_name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '),
           @status = r.status
    FROM [req].[request] r
    JOIN [req].[request_type] t ON t.id = r.request_type_id
    JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @code IS NULL
        RETURN;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @slug NVARCHAR(40) = REPLACE(@type_code, N'_', N'-');

    -- 1. The event.
    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), r.id) AS requestId, r.code, t.code AS [type], t.name AS typeName, t.kind,
               @action AS [action], r.status,
               CONVERT(NVARCHAR(30), r.employee_id) AS employeeId, e.code AS employeeCode, @employee_name AS employeeName,
               CONVERT(NVARCHAR(30), e.department_id) AS departmentId, CONVERT(NVARCHAR(30), e.branch_id) AS branchId,
               r.from_date AS fromDate, r.to_date AS toDate, r.days,
               [req].[fn_request_condition_value](r.id, N'amount') AS amount,
               r.submitted_at AS submittedAt, r.decided_at AS decidedAt,
               CONVERT(NVARCHAR(30), @actor_user_id) AS actorUserId,
               CONVERT(NVARCHAR(30), @actor_employee_id) AS actorEmployeeId,
               @remarks AS remarks,
               JSON_QUERY((SELECT TOP (1) CONVERT(NVARCHAR(30), s.id) AS stepId, s.purpose, n.step_no AS stepNo,
                                  s.approver_kind AS approverKind, CONVERT(NVARCHAR(30), s.approver_id) AS approverId,
                                  COALESCE(NULLIF(CONCAT(ap.first_name, N' ', ap.last_name), N' '), ro.name) AS approverName,
                                  CONVERT(NVARCHAR(30), s.approver_role_id) AS approverRoleId, s.is_consent AS isConsent
                           FROM [req].[request_step] s
                           LEFT JOIN [req].[approval_node] n ON n.id = s.approval_node_id
                           LEFT JOIN [hr].[employee] ap ON ap.id = s.approver_id
                           LEFT JOIN [auth].[role] ro ON ro.id = s.approver_role_id
                           WHERE s.request_id = r.id AND s.action_taken = N'pending'
                           ORDER BY s.id
                           FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS currentStep
        FROM [req].[request] r
        JOIN [req].[request_type] t ON t.id = r.request_type_id
        JOIN [hr].[employee] e ON e.id = r.employee_id
        WHERE r.id = @request_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event_type,
         @entity_type = N'req.request', @entity_id = @request_id, @payload = @payload;

    -- 2. Whoever must act now.
    DECLARE @to TABLE (employee_id BIGINT NULL, user_id BIGINT NULL);
    DECLARE @title NVARCHAR(200), @body NVARCHAR(MAX), @link NVARCHAR(500) = N'/requests/approvals/' + CONVERT(NVARCHAR(30), @request_id),
            @sid BIGINT, @appr BIGINT, @role BIGINT, @consent BIT, @purpose NVARCHAR(30), @who BIGINT;

    SET @sid = (SELECT MIN(id) FROM [req].[request_step]
                WHERE request_id = @request_id AND id > ISNULL(@since_step_id, 0) AND action_taken = N'pending');
    WHILE @sid IS NOT NULL
    BEGIN
        SELECT @appr = approver_id, @role = approver_role_id, @consent = is_consent, @purpose = purpose
        FROM [req].[request_step] WHERE id = @sid;

        SET @title = LEFT(@type_name + N' request ' + @code
                          + CASE WHEN @consent = 1 THEN N' asks for your consent'
                                 WHEN @purpose = N'cancellation' THEN N': cancellation waiting for your approval'
                                 ELSE N' is waiting for your approval' END, 200);
        SET @body = ISNULL(@employee_name, N'An employee') + CASE WHEN @purpose = N'cancellation'
                        THEN N' asks to cancel an approved ' ELSE N' sent a ' END + LOWER(@type_name) + N' request.';

        DELETE @to;
        IF @appr IS NOT NULL
        BEGIN
            INSERT @to (employee_id) VALUES (@appr);
            INSERT @to (employee_id)
            SELECT DISTINCT d.delegatee_id FROM [req].[delegation] d
            WHERE d.company_id = @company_id AND d.delegator_id = @appr AND d.request_type_id = @type_id AND d.is_active = 1
              AND d.delegatee_id <> @appr;
        END
        ELSE IF @role IS NOT NULL
            INSERT @to (user_id)
            SELECT DISTINCT u.id
            FROM [auth].[user_role] ur
            JOIN [auth].[user_account] u ON u.id = ur.user_account_id AND u.is_active = 1
            JOIN [auth].[role] ro ON ro.id = ur.role_id AND ro.company_id = @company_id AND ro.is_active = 1
            WHERE ur.role_id = @role AND ISNULL(u.employee_id, 0) <> @employee_id;

        SET @who = (SELECT MIN(employee_id) FROM @to WHERE employee_id IS NOT NULL);
        WHILE @who IS NOT NULL
        BEGIN
            EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @who,
                 @title = @title, @body = @body, @notification_type = N'request_approval', @link = @link,
                 @entity_type = N'req.request', @entity_id = @request_id;
            SET @who = (SELECT MIN(employee_id) FROM @to WHERE employee_id > @who);
        END
        SET @who = (SELECT MIN(user_id) FROM @to WHERE user_id IS NOT NULL);
        WHILE @who IS NOT NULL
        BEGIN
            EXEC [core].[usp_notification_add] @quiet = 1, @company_id = @company_id, @user_account_id = @who,
                 @title = @title, @body = @body, @notification_type = N'request_approval', @link = @link,
                 @entity_type = N'req.request', @entity_id = @request_id;
            SET @who = (SELECT MIN(user_id) FROM @to WHERE user_id > @who);
        END

        SET @sid = (SELECT MIN(id) FROM [req].[request_step]
                    WHERE request_id = @request_id AND id > @sid AND action_taken = N'pending');
    END

    -- 3. The requester, when their request is decided.
    IF @event_type IN (N'requests.approved', N'requests.rejected', N'requests.cancelled', N'requests.cancellation_rejected')
       AND @employee_id <> ISNULL(@actor_employee_id, 0)
    BEGIN
        SET @title = LEFT(@type_name + N' request ' + @code + CASE @event_type
                         WHEN N'requests.approved' THEN N' was approved'
                         WHEN N'requests.rejected' THEN N' was rejected'
                         WHEN N'requests.cancelled' THEN N' was cancelled'
                         ELSE N': the cancellation was rejected' END, 200);
        SET @link = N'/requests/' + @slug + N'/' + CONVERT(NVARCHAR(30), @request_id);
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
             @title = @title, @body = @remarks, @notification_type = N'request_update',
             @link = @link, @entity_type = N'req.request', @entity_id = @request_id;
    END
END
