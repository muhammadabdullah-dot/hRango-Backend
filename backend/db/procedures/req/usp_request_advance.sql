-- Walks a request's flow from a node (or from the start) to the next step someone must take, and
-- records it as a pending step. Internal: called inside the submit, decide and cancel transactions.
--   Condition nodes pick If True / If False (empty: the next node by number).
--   Observer ("On Looker") nodes are recorded as informed and the walk goes on.
--   A node nobody holds, a node that would make the requester decide their own request, and a node
--   held by the person who decided the step before are recorded as skipped.
-- At the end of the flow: a request becomes approved and the owning module's effect runs; a
-- cancellation becomes cancelled and the effect is reverted.
CREATE OR ALTER PROCEDURE [req].[usp_request_advance]
    @company_id       BIGINT,
    @actor_user_id    BIGINT = NULL,
    @request_id       BIGINT,
    @from_node_id     BIGINT = NULL,
    @last_approver_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @flow_id BIGINT, @status NVARCHAR(30), @employee_id BIGINT, @type_id BIGINT, @kind NVARCHAR(30),
            @department_id BIGINT, @branch_id BIGINT, @purpose NVARCHAR(30), @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @flow_id = r.approval_flow_id, @status = r.status, @employee_id = r.employee_id, @type_id = r.request_type_id,
           @kind = t.kind, @department_id = e.department_id, @branch_id = e.branch_id
    FROM [req].[request] r
    JOIN [req].[request_type] t ON t.id = r.request_type_id
    JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    SET @purpose = CASE WHEN @status = N'cancelling' THEN N'cancellation' ELSE N'request' END;

    DECLARE @node BIGINT, @guard INT = 0, @done BIT = 0,
            @step_no INT, @akind NVARCHAR(30), @aemp BIGINT, @role_id BIGINT, @is_cond BIT, @field NVARCHAR(200),
            @op NVARCHAR(2), @val DECIMAL(18,4), @next BIGINT, @if_true BIGINT, @if_false BIGINT, @can_disagree BIT,
            @observer BIT, @following BIGINT, @x DECIMAL(18,4), @ok BIT, @appr BIGINT, @appr_role BIGINT,
            @why NVARCHAR(300);

    IF @from_node_id IS NULL
        SELECT TOP (1) @node = id FROM [req].[approval_node] WHERE approval_flow_id = @flow_id ORDER BY step_no;
    ELSE
        SELECT @node = COALESCE(n.next_node_id,
                                (SELECT TOP (1) m.id FROM [req].[approval_node] m
                                 WHERE m.approval_flow_id = n.approval_flow_id AND m.step_no > n.step_no ORDER BY m.step_no))
        FROM [req].[approval_node] n WHERE n.id = @from_node_id;

    WHILE @node IS NOT NULL AND @done = 0
    BEGIN
        SET @guard += 1;
        IF @guard > 100
            THROW 50409, N'The approval flow goes round in a loop. Correct it under Request Settings.', 1;

        SELECT @step_no = step_no, @akind = approver_kind, @aemp = approver_employee_id, @role_id = role_id,
               @is_cond = is_condition, @field = condition_field, @op = condition_operator, @val = condition_value,
               @next = next_node_id, @if_true = true_node_id, @if_false = false_node_id,
               @can_disagree = can_disagree, @observer = is_observer
        FROM [req].[approval_node] WHERE id = @node;

        SET @following = (SELECT TOP (1) id FROM [req].[approval_node]
                          WHERE approval_flow_id = @flow_id AND step_no > @step_no ORDER BY step_no);

        IF @is_cond = 1
        BEGIN
            SET @x = [req].[fn_request_condition_value](@request_id, @field);
            SET @ok = CASE WHEN @x IS NULL OR @val IS NULL THEN 0
                           WHEN @op = N'=' AND @x = @val THEN 1
                           WHEN @op = N'<>' AND @x <> @val THEN 1
                           WHEN @op = N'>' AND @x > @val THEN 1
                           WHEN @op = N'>=' AND @x >= @val THEN 1
                           WHEN @op = N'<' AND @x < @val THEN 1
                           WHEN @op = N'<=' AND @x <= @val THEN 1
                           ELSE 0 END;
            SET @node = CASE WHEN @ok = 1 THEN COALESCE(@if_true, @following) ELSE COALESCE(@if_false, @following) END;
            CONTINUE;
        END

        SET @appr = NULL;
        SET @appr_role = NULL;
        SET @why = NULL;

        IF @akind = N'employee'
            SET @appr = @aemp;
        ELSE IF @akind = N'line_manager'
            SET @appr = (SELECT line_manager_id FROM [hr].[employee] WHERE id = @employee_id);
        ELSE IF @akind = N'hod'
        BEGIN
            -- The head of the employee's department; when that is the employee, the parent department's head.
            SELECT @appr = CASE WHEN d.head_id = @employee_id THEN p.head_id ELSE d.head_id END
            FROM [org].[department] d LEFT JOIN [org].[department] p ON p.id = d.parent_id
            WHERE d.id = @department_id;
        END
        ELSE IF @akind = N'branch_manager'
            SET @appr = (SELECT manager_id FROM [org].[branch] WHERE id = @branch_id);
        ELSE IF @akind = N'final_authority'
            SET @appr = COALESCE((SELECT final_authority_id FROM [req].[req_transfer] WHERE request_id = @request_id),
                                 (SELECT final_authority_id FROM [hr].[employee] WHERE id = @employee_id));
        ELSE IF @akind = N'role'
            SET @appr_role = @role_id;
        ELSE
            SELECT TOP (1) @appr = a.employee_id
            FROM [req].[approval_authority] a
            JOIN [hr].[employee] ae ON ae.id = a.employee_id AND ae.status <> N'left'
            WHERE a.company_id = @company_id AND a.authority = @akind AND a.is_active = 1
              AND (a.request_type_id IS NULL OR a.request_type_id = @type_id)
              AND (a.branch_id IS NULL OR a.branch_id = @branch_id)
              AND (a.department_id IS NULL OR a.department_id = @department_id)
            ORDER BY CASE WHEN a.request_type_id IS NULL THEN 1 ELSE 0 END,
                     CASE WHEN a.department_id IS NULL THEN 1 ELSE 0 END,
                     CASE WHEN a.branch_id IS NULL THEN 1 ELSE 0 END, a.id;

        IF @observer = 1
        BEGIN
            IF @appr IS NOT NULL OR @appr_role IS NOT NULL
                INSERT [req].[request_step] (request_id, approval_node_id, purpose, approver_kind, approver_id,
                                             approver_role_id, action_taken, acted_at, created_by)
                VALUES (@request_id, @node, @purpose, @akind, @appr, @appr_role, N'informed', @now, @actor_user_id);
            SET @node = COALESCE(@next, @following);
            CONTINUE;
        END

        IF @appr IS NULL AND @appr_role IS NULL
            SET @why = N'Nobody holds ' + REPLACE(ISNULL(@akind, N'this step'), N'_', N' ') + N' for this employee.';
        ELSE IF @appr = @employee_id
            SET @why = N'The employee cannot decide their own request.';
        ELSE IF @appr = @last_approver_id AND @can_disagree = 0
            SET @why = N'Already decided by the same person at the step before.';

        IF @why IS NOT NULL
        BEGIN
            INSERT [req].[request_step] (request_id, approval_node_id, purpose, approver_kind, approver_id,
                                         approver_role_id, action_taken, remarks, acted_at, created_by)
            VALUES (@request_id, @node, @purpose, @akind, @appr, @appr_role, N'skipped', @why, @now, @actor_user_id);
            SET @node = COALESCE(@next, @following);
            CONTINUE;
        END

        INSERT [req].[request_step] (request_id, approval_node_id, purpose, approver_kind, approver_id, approver_role_id,
                                     is_consent, action_taken, created_by)
        VALUES (@request_id, @node, @purpose, @akind, @appr, @appr_role, @can_disagree, N'pending', @actor_user_id);

        UPDATE [req].[request] SET current_node_id = @node, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @request_id;
        SET @done = 1;
    END

    IF @done = 1
        RETURN;

    IF @purpose = N'request'
    BEGIN
        -- What the final approver must have entered before the request takes effect.
        IF @kind = N'loan' AND EXISTS (SELECT 1 FROM [req].[req_loan] WHERE request_id = @request_id
                                       AND (approved_amount IS NULL OR payment_method IS NULL OR repayment_date IS NULL))
            THROW 50400, N'approvedAmount|Approved amount, payment method and repayment date are required to approve a loan.', 1;
        IF @kind = N'resignation' AND EXISTS (SELECT 1 FROM [req].[req_resignation] WHERE request_id = @request_id
                                              AND last_working_date IS NULL)
            THROW 50400, N'lastWorkingDate|The last working date is required to approve a resignation.', 1;
        IF @kind = N'overtime'
            UPDATE [req].[req_overtime] SET approved_minutes = applied_minutes, updated_at = @now
            WHERE request_id = @request_id AND approved_minutes IS NULL;
        -- Claims nobody lowered are approved as claimed.
        IF @kind = N'expense'
        BEGIN
            UPDATE [req].[expense_line] SET approved_amount = amount, updated_at = @now
            WHERE request_id = @request_id AND approved_amount IS NULL;
            UPDATE [req].[req_expense]
            SET approved_amount = (SELECT SUM(approved_amount) FROM [req].[expense_line] WHERE request_id = @request_id),
                updated_at = @now
            WHERE request_id = @request_id;
        END
        IF @kind = N'air_ticket'
            UPDATE [req].[req_air_ticket] SET approved_amount = amount, updated_at = @now
            WHERE request_id = @request_id AND approved_amount IS NULL;

        UPDATE [req].[request]
        SET status = N'approved', decided_at = @now, current_node_id = NULL, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @request_id;

        EXEC [req].[usp_request_effect_run] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @request_id, @verb = N'apply';
    END
    ELSE
    BEGIN
        UPDATE [req].[request]
        SET status = N'cancelled', decided_at = @now, current_node_id = NULL, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @request_id;

        EXEC [req].[usp_request_effect_run] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @request_id, @verb = N'revert';
    END
END
