-- Approval effect for the resignation request kind (comparison/04-requests.md). The requests engine
-- calls it on final approval, inside the approval's transaction; a THROW blocks the approval.
-- It starts the leaving chain (Mini SRS WF4; Open Question E8 decided "yes"): a pending end of
-- employment with Final Settlement and Asset Clearance ticked, and a pending final settlement.
-- If HR already started a pending end of employment for the employee, the request is linked to it.
-- Returns no result set.
CREATE OR ALTER PROCEDURE [sep].[usp_request_apply_resignation]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @reason NVARCHAR(MAX), @resignation_date DATE, @lwd DATE, @notice_days INT,
            @serve_notice BIT, @found BIT = 0;
    SELECT @found = 1, @employee_id = r.employee_id, @reason = r.reason, @resignation_date = rr.resignation_date,
           @lwd = rr.last_working_date, @notice_days = rr.notice_period_days, @serve_notice = rr.serve_notice
    FROM [req].[request] r
    JOIN [req].[req_resignation] rr ON rr.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF @found = 0
        THROW 50404, N'Resignation request not found', 1;
    IF EXISTS (SELECT 1 FROM [sep].[end_of_employment] WHERE resignation_request_id = @request_id)
        RETURN;  -- already applied

    DECLARE @emp_status NVARCHAR(30) = (SELECT status FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id);
    IF @emp_status IS NULL
        THROW 50404, N'Employee not found', 1;
    IF @emp_status = N'left'
        THROW 50409, N'This employee has already left.', 1;

    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME();
    SET @serve_notice = COALESCE(@serve_notice, CASE WHEN @notice_days > 0 THEN 1 ELSE 0 END);
    SET @lwd = COALESCE(@lwd,
                        CASE WHEN @serve_notice = 1 AND @notice_days > 0 THEN DATEADD(DAY, @notice_days, @resignation_date) END,
                        @resignation_date, @today);

    DECLARE @existing BIGINT, @existing_request BIGINT;
    SELECT TOP 1 @existing = id, @existing_request = resignation_request_id
    FROM [sep].[end_of_employment]
    WHERE company_id = @company_id AND employee_id = @employee_id AND status = N'pending'
    ORDER BY id DESC;

    IF @existing IS NOT NULL AND @existing_request IS NOT NULL
        THROW 50409, N'This employee already has a pending end of employment from another resignation.', 1;

    BEGIN TRAN;
        IF @existing IS NOT NULL
        BEGIN
            UPDATE [sep].[end_of_employment]
            SET resignation_request_id = @request_id, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @existing;
        END
        ELSE
        BEGIN
            INSERT [sep].[end_of_employment] (company_id, employee_id, reason, resignation_request_id, serve_notice,
                notice_period_days, last_working_date, needs_final_settlement, needs_asset_clearance, description,
                status, created_by)
            VALUES (@company_id, @employee_id, N'resignation', @request_id, @serve_notice, @notice_days, @lwd, 1, 1,
                    @reason, N'pending', @actor_user_id);
            SET @existing = SCOPE_IDENTITY();

            INSERT [sep].[final_settlement] (company_id, end_of_employment_id, status, created_by)
            VALUES (@company_id, @existing, N'pending', @actor_user_id);

            EXEC [sep].[usp_end_of_employment_announce] @company_id = @company_id, @id = @existing,
                 @event_type = N'offboarding.started';
        END

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.end_of_employment', @existing, N'resignation_request_id', CONVERT(NVARCHAR(30), @request_id),
                N'resignation approved', @actor_user_id, @now);
    COMMIT;
END
GO

-- Cancellation effect: an approved resignation was cancelled. The end of employment it started is
-- removed while nobody has worked on it (no clearance form, no checklist answers, settlement untouched);
-- otherwise it stays with HR, unlinked from the request. A completed one stops the cancellation.
CREATE OR ALTER PROCEDURE [sep].[usp_request_revert_resignation]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id BIGINT, @status NVARCHAR(30);
    SELECT @id = id, @status = status FROM [sep].[end_of_employment]
    WHERE resignation_request_id = @request_id AND company_id = @company_id;
    IF @id IS NULL
        RETURN;
    IF @status = N'completed'
        THROW 50409, N'The employee has already left under this resignation. It cannot be cancelled.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM [sep].[asset_clearance] WHERE end_of_employment_id = @id)
           AND NOT EXISTS (SELECT 1 FROM [sep].[checklist_answer] WHERE end_of_employment_id = @id)
           AND NOT EXISTS (SELECT 1 FROM [sep].[final_settlement] WHERE end_of_employment_id = @id
                           AND (status <> N'pending' OR payslip_id IS NOT NULL))
        BEGIN
            DELETE [sep].[final_settlement] WHERE end_of_employment_id = @id;
            DELETE [sep].[end_of_employment] WHERE id = @id;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'sep.end_of_employment', @id, N'resignation cancelled', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [sep].[end_of_employment]
            SET resignation_request_id = NULL, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'sep.end_of_employment', @id, N'resignation_request_id', CONVERT(NVARCHAR(30), @request_id),
                    N'resignation cancelled', @actor_user_id, @now);
        END
    COMMIT;
END
