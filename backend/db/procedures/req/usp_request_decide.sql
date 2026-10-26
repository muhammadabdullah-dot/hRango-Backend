-- An approver's decision on the current step (WF2 step 3; ACC-13: the flow and delegations decide
-- who may act, not a permission).
--   approve / reject   on an approval step. Reject ends the request (rejected), or ends a
--                      cancellation (the request stays approved).
--   consent / disagree on a consent step (Can Disagree node, or the colleague of a shift swap);
--                      either answer is recorded and the flow goes on.
-- @details carries what the approver enters on approval: loans (approved_amount, payment_method,
-- repayment_date, currency), overtime (approved_minutes), resignation (last_working_date,
-- serve_notice, notice_period_days), expense (lines: [{id, approved_amount}]), air tickets
-- (approved_amount). On the last step the owning module's effect runs in this transaction; its
-- THROW stops the approval. @prefill (bulk approve, which has no approval form) fills what the form
-- would prefill and nobody entered: a loan's approved amount (the amount asked), payment method (bank
-- when the employee has a bank account, else cash) and repayment date (the first of the month after
-- the required date, or after today when that is later). Publishes the outcome (requests.step_decided / approved / rejected /
-- cancelled / cancellation_rejected) and tells the next approver or the requester.
CREATE OR ALTER PROCEDURE [req].[usp_request_decide]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @action        NVARCHAR(20),
    @remarks       NVARCHAR(MAX) = NULL,
    @details       NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8),
    @prefill       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT, @kind NVARCHAR(30), @type_code NVARCHAR(30),
            @currency CHAR(3);
    SELECT @rv = r.row_version, @status = r.status, @employee_id = r.employee_id, @kind = t.kind, @type_code = t.code,
           @currency = c.currency
    FROM [req].[request] r
    JOIN [req].[request_type] t ON t.id = r.request_type_id
    JOIN [org].[company] c ON c.id = r.company_id
    WHERE r.id = @id AND r.company_id = @company_id AND r.is_deleted = 0;
    IF @rv IS NULL
        THROW 50404, N'Request not found', 1;
    IF @action NOT IN (N'approve', N'reject', N'consent', N'disagree')
        THROW 50400, N'action|Unknown decision.', 1;

    DECLARE @step BIGINT, @is_delegate BIT, @is_consent BIT, @node BIGINT, @approver BIGINT, @purpose NVARCHAR(30);
    SELECT TOP (1) @step = s.id, @is_delegate = a.is_delegate, @is_consent = s.is_consent, @node = s.approval_node_id,
           @approver = s.approver_id, @purpose = s.purpose
    FROM [req].[fn_actor_steps](@company_id, @me) a
    JOIN [req].[request_step] s ON s.id = a.step_id AND s.action_taken = N'pending'
    WHERE a.request_id = @id
    ORDER BY a.is_delegate, s.id;
    IF @step IS NULL
        THROW 50403, N'You are not the approver of this request at its current step.', 1;
    IF @employee_id = @me
        THROW 50403, N'You cannot decide your own request.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    IF @status NOT IN (N'pending', N'cancelling')
        THROW 50409, N'This request is no longer waiting for a decision.', 1;
    IF @is_consent = 1 AND @action IN (N'approve', N'reject')
        THROW 50400, N'action|This step asks for consent: agree or disagree.', 1;
    IF @is_consent = 0 AND @action IN (N'consent', N'disagree')
        THROW 50400, N'action|This step asks for a decision: approve or reject.', 1;

    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');
    IF @remarks IS NULL AND @action IN (N'reject', N'disagree')
        THROW 50400, N'remarks|Give a reason.', 1;
    IF @remarks IS NULL AND @action = N'approve' AND @purpose = N'request' AND @type_code IN (N'promotion', N'relaxation')
        THROW 50400, N'remarks|Approval remarks are required for this request type.', 1;

    DECLARE @d NVARCHAR(MAX) = ISNULL(NULLIF(LTRIM(RTRIM(@details)), N''), N'{}');
    IF ISJSON(@d) = 0
        THROW 50400, N'details|The approval details are not valid JSON.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    DECLARE @since BIGINT = (SELECT MAX(id) FROM [req].[request_step] WHERE request_id = @id);

    BEGIN TRAN;
        UPDATE [req].[request] SET updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this request. Reload it and try again', 1;

        -- What the approver enters (any step of the request flow may fill it; the last one must).
        IF @action = N'approve' AND @purpose = N'request'
        BEGIN
            IF @kind = N'loan'
            BEGIN
                DECLARE @la DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@d, N'$.approved_amount') AS DECIMAL(18,2)),
                        @lm NVARCHAR(30) = JSON_VALUE(@d, N'$.payment_method'),
                        @lr DATE = TRY_CAST(JSON_VALUE(@d, N'$.repayment_date') AS DATE),
                        @lc CHAR(3) = JSON_VALUE(@d, N'$.currency'), @asked DECIMAL(18,2);
                SET @asked = (SELECT amount_requested FROM [req].[req_loan] WHERE request_id = @id);
                IF @la IS NOT NULL AND (@la <= 0 OR @la > @asked)
                    THROW 50400, N'approvedAmount|The approved amount must be more than zero and no more than the amount asked.', 1;
                IF @lm IS NOT NULL AND @lm NOT IN (N'bank', N'cash', N'pay_order', N'cheque')
                    THROW 50400, N'paymentMethod|Payment method is not valid.', 1;
                UPDATE [req].[req_loan]
                SET approved_amount = COALESCE(@la, approved_amount), payment_method = COALESCE(@lm, payment_method),
                    repayment_date = COALESCE(@lr, repayment_date), currency = COALESCE(@lc, currency, @currency),
                    updated_at = @now, updated_by = @actor_user_id
                WHERE request_id = @id;
                IF @prefill = 1
                BEGIN
                    DECLARE @lfrom DATE = (SELECT CASE WHEN required_date > CAST(@now AS DATE) THEN required_date
                                                       ELSE CAST(@now AS DATE) END
                                           FROM [req].[req_loan] WHERE request_id = @id);
                    UPDATE [req].[req_loan]
                    SET approved_amount = COALESCE(approved_amount, amount_requested),
                        payment_method = COALESCE(payment_method,
                            CASE WHEN EXISTS (SELECT 1 FROM [hr].[employee_bank_account] b WHERE b.employee_id = @employee_id)
                                 THEN N'bank' ELSE N'cash' END),
                        repayment_date = COALESCE(repayment_date, DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@lfrom), MONTH(@lfrom), 1)))
                    WHERE request_id = @id;
                END
            END
            ELSE IF @kind = N'overtime'
            BEGIN
                DECLARE @om INT = TRY_CAST(JSON_VALUE(@d, N'$.approved_minutes') AS INT);
                IF @om IS NOT NULL AND (@om < 0 OR @om > (SELECT applied_minutes FROM [req].[req_overtime] WHERE request_id = @id))
                    THROW 50400, N'approvedMinutes|Approved minutes cannot be more than the minutes applied for.', 1;
                IF @om IS NOT NULL
                    UPDATE [req].[req_overtime] SET approved_minutes = @om, updated_at = @now, updated_by = @actor_user_id
                    WHERE request_id = @id;
            END
            ELSE IF @kind = N'resignation'
            BEGIN
                DECLARE @lwd DATE = TRY_CAST(JSON_VALUE(@d, N'$.last_working_date') AS DATE),
                        @serve BIT = TRY_CAST(JSON_VALUE(@d, N'$.serve_notice') AS BIT),
                        @notice INT = TRY_CAST(JSON_VALUE(@d, N'$.notice_period_days') AS INT);
                IF @lwd IS NOT NULL AND @lwd < (SELECT resignation_date FROM [req].[req_resignation] WHERE request_id = @id)
                    THROW 50400, N'lastWorkingDate|The last working date cannot be before the resignation date.', 1;
                UPDATE [req].[req_resignation]
                SET last_working_date = COALESCE(@lwd, last_working_date), serve_notice = COALESCE(@serve, serve_notice),
                    notice_period_days = COALESCE(@notice, notice_period_days,
                                                  DATEDIFF(DAY, resignation_date, COALESCE(@lwd, last_working_date))),
                    updated_at = @now, updated_by = @actor_user_id
                WHERE request_id = @id;
                UPDATE [req].[request] SET to_date = COALESCE(@lwd, to_date) WHERE id = @id;
            END
            ELSE IF @kind = N'expense' AND JSON_QUERY(@d, N'$.lines') IS NOT NULL
            BEGIN
                -- The approver may lower a claim (0: not reimbursed), never raise it.
                DECLARE @ex TABLE (id BIGINT, approved_amount DECIMAL(18,2));
                INSERT @ex (id, approved_amount)
                SELECT x.id, x.approved_amount
                FROM OPENJSON(@d, N'$.lines') WITH (id BIGINT N'$.id', approved_amount DECIMAL(18,2) N'$.approved_amount') x;
                IF EXISTS (SELECT 1 FROM @ex x WHERE NOT EXISTS (SELECT 1 FROM [req].[expense_line] l
                                                                 WHERE l.id = x.id AND l.request_id = @id))
                    THROW 50400, N'lines|A claim line does not belong to this request.', 1;
                IF EXISTS (SELECT 1 FROM @ex x JOIN [req].[expense_line] l ON l.id = x.id
                           WHERE x.approved_amount IS NOT NULL AND (x.approved_amount < 0 OR x.approved_amount > l.amount))
                    THROW 50400, N'lines|An approved amount cannot be below zero or above the amount claimed.', 1;
                UPDATE l SET approved_amount = x.approved_amount, updated_at = @now, updated_by = @actor_user_id
                FROM [req].[expense_line] l JOIN @ex x ON x.id = l.id
                WHERE x.approved_amount IS NOT NULL;
                UPDATE [req].[req_expense]
                SET approved_amount = (SELECT SUM(ISNULL(approved_amount, amount)) FROM [req].[expense_line] WHERE request_id = @id),
                    updated_at = @now, updated_by = @actor_user_id
                WHERE request_id = @id;
            END
            ELSE IF @kind = N'air_ticket'
            BEGIN
                DECLARE @ta DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@d, N'$.approved_amount') AS DECIMAL(18,2));
                IF @ta IS NOT NULL AND (@ta <= 0 OR @ta > (SELECT amount FROM [req].[req_air_ticket] WHERE request_id = @id))
                    THROW 50400, N'approvedAmount|The approved amount must be more than zero and no more than the amount claimed.', 1;
                IF @ta IS NOT NULL
                    UPDATE [req].[req_air_ticket] SET approved_amount = @ta, updated_at = @now, updated_by = @actor_user_id
                    WHERE request_id = @id;
            END
        END

        UPDATE [req].[request_step]
        SET action_taken = CASE @action WHEN N'approve' THEN N'approved' WHEN N'reject' THEN N'rejected'
                                        WHEN N'consent' THEN N'consented' ELSE N'disagreed' END,
            acted_by_id = @me, is_delegate = @is_delegate, remarks = @remarks, acted_at = @now,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @step;

        IF @action = N'reject'
        BEGIN
            UPDATE [req].[request]
            SET status = CASE WHEN @purpose = N'cancellation' THEN N'approved' ELSE N'rejected' END,
                decided_at = CASE WHEN @purpose = N'cancellation' THEN decided_at ELSE @now END,
                current_node_id = NULL, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id;
        END
        ELSE
        BEGIN
            -- The same person holding the next step too decides once; a consent is not a decision.
            DECLARE @last BIGINT = CASE WHEN @action = N'approve' THEN @approver END;
            EXEC [req].[usp_request_advance] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id,
                 @from_node_id = @node, @last_approver_id = @last;
        END

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'status', (SELECT status FROM [req].[request] WHERE id = @id), @action, @actor_user_id, @now);

        DECLARE @new_status NVARCHAR(30) = (SELECT status FROM [req].[request] WHERE id = @id);
        DECLARE @event NVARCHAR(100) = CASE
            WHEN @action = N'reject' AND @purpose = N'cancellation' THEN N'requests.cancellation_rejected'
            WHEN @action = N'reject' THEN N'requests.rejected'
            WHEN @new_status = N'approved' AND @purpose = N'request' THEN N'requests.approved'
            WHEN @new_status = N'cancelled' THEN N'requests.cancelled'
            ELSE N'requests.step_decided' END;
        DECLARE @did NVARCHAR(30) = CASE WHEN @event = N'requests.cancelled' THEN N'cancellation_approved'
                                         ELSE CASE @action WHEN N'approve' THEN N'approved' WHEN N'reject' THEN N'rejected'
                                                           WHEN N'consent' THEN N'consented' ELSE N'disagreed' END END;
        EXEC [req].[usp_request_publish] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id,
             @event_type = @event, @action = @did, @since_step_id = @since, @remarks = @remarks;
    COMMIT;
END
