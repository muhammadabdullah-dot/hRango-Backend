-- The leave effects the requests engine runs (see comparison/04-requests.md and 05-leaves-and-warning.md).

-- Final approval of a leave request: posts the days as 'availed' in the leave year the leave starts
-- in. Runs inside the approval's transaction. For deductible types the balance is checked again:
-- other pending requests stay reserved, this request's own days do not count twice.
-- Running it twice for the same request posts once.
CREATE OR ALTER PROCEDURE [lv].[usp_request_apply_leave]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @leave_type_id BIGINT, @from_date DATE, @to_date DATE, @days DECIMAL(6,2),
            @status NVARCHAR(30), @deductible BIT;
    SELECT @employee_id = r.employee_id, @leave_type_id = rl.leave_type_id, @from_date = r.from_date,
           @to_date = ISNULL(r.to_date, r.from_date),
           @days = ISNULL(rl.days, r.days), @status = r.status, @deductible = t.is_deductible
    FROM [req].[request] r
    JOIN [req].[req_leave] rl ON rl.request_id = r.id
    JOIN [lv].[leave_type] t ON t.id = rl.leave_type_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF @employee_id IS NULL
        THROW 50404, N'Leave request not found', 1;
    IF @days IS NULL OR @days <= 0
        THROW 50400, N'days|The leave request has no days.', 1;

    BEGIN TRAN;
        DECLARE @res NVARCHAR(100) = CONCAT(N'lv.balance.', @employee_id);
        EXEC sp_getapplock @Resource = @res, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;

        IF NOT EXISTS (SELECT 1 FROM [lv].[leave_ledger] WHERE request_id = @request_id AND reason = N'availed')
        BEGIN
            IF @deductible = 1
            BEGIN
                DECLARE @available DECIMAL(6,2) = (
                    SELECT b.available + CASE WHEN @status = N'pending' THEN @days ELSE 0 END
                    FROM [lv].[fn_leave_balance](@company_id, @employee_id, @leave_type_id, @from_date) b);
                IF ISNULL(@available, 0) < @days
                    THROW 50409, N'leaveTypeId|LEAVE_BALANCE_EXCEEDED|The leave balance is no longer enough for this request.', 1;
            END

            INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, request_id, created_by)
            SELECT @employee_id, @leave_type_id, y.fiscal_year, @from_date, -@days, N'availed', @request_id, @actor_user_id
            FROM [lv].[fn_leave_year](@company_id, @from_date) y;
        END

        -- The time sheet shows the leave on those days (refused when payroll has already used them).
        EXEC [att].[usp_request_reprocess] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @employee_id = @employee_id, @from_date = @from_date, @to_date = @to_date, @include_request_id = @request_id;
    COMMIT;
END
GO

-- An approved leave request was cancelled: gives the days back ('restored'). Once per request.
CREATE OR ALTER PROCEDURE [lv].[usp_request_revert_leave]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @from_date DATE, @to_date DATE;
    SELECT @employee_id = employee_id, @from_date = from_date, @to_date = ISNULL(to_date, from_date)
    FROM [req].[request] WHERE id = @request_id AND company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Leave request not found', 1;

    BEGIN TRAN;
        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, request_id, remarks, created_by)
        SELECT g.employee_id, g.leave_type_id, g.fiscal_year, g.entry_date, -g.days, N'restored', g.request_id,
               N'Leave cancelled', @actor_user_id
        FROM [lv].[leave_ledger] g
        WHERE g.request_id = @request_id AND g.reason = N'availed'
          AND NOT EXISTS (SELECT 1 FROM [lv].[leave_ledger] x WHERE x.request_id = @request_id AND x.reason = N'restored');

        EXEC [att].[usp_request_reprocess] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @employee_id = @employee_id, @from_date = @from_date, @to_date = @to_date, @exclude_request_id = @request_id;
    COMMIT;
END
GO

-- The leave type's rules for a request about to be submitted (the requests engine calls it before
-- it saves). THROWs 50400 with the field at fault, or 50409 when the balance is not enough.
-- @request_id: the request being edited, left out of the counts.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_request_check]
    @company_id     BIGINT,
    @employee_id    BIGINT,
    @leave_type_id  BIGINT,
    @from_date      DATE,
    @to_date        DATE,
    @days           DECIMAL(6,2),
    @is_short       BIT = 0,
    @short_leave_type NVARCHAR(30) = NULL,
    @has_attachment BIT = 0,
    @request_id     BIGINT = NULL,
    @today          DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @today = ISNULL(@today, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @gender NVARCHAR(30), @marital NVARCHAR(30), @status NVARCHAR(30), @joined DATE;
    SELECT @gender = e.gender, @marital = e.marital_status, @status = e.status,
           @joined = (SELECT MAX(p.joining_date) FROM [hr].[employment_period] p WHERE p.employee_id = e.id)
    FROM [hr].[employee] e WHERE e.id = @employee_id AND e.company_id = @company_id;
    IF @status IS NULL
        THROW 50400, N'employeeId|Employee not found.', 1;

    DECLARE @t TABLE (is_active BIT, gender NVARCHAR(30), marital_status NVARCHAR(30), allowed_in_probation BIT,
                      is_probation_type BIT, allow_back_date BIT, back_date_limit_days INT, has_future_limit BIT,
                      future_limit_days INT, attachment_required BIT, attachment_rule NVARCHAR(30),
                      min_experience_months INT, max_applications INT, gap_months INT, is_deductible BIT, is_short_leave BIT);
    INSERT @t
    SELECT is_active, gender, marital_status, allowed_in_probation, is_probation_type, allow_back_date, back_date_limit_days,
           has_future_limit, future_limit_days, attachment_required, attachment_rule, min_experience_months,
           max_applications, gap_between_applications_months, is_deductible, is_short_leave
    FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id;

    IF NOT EXISTS (SELECT 1 FROM @t WHERE is_active = 1)
        THROW 50400, N'leaveTypeId|Leave type not found or not active.', 1;
    IF @from_date IS NULL OR @to_date IS NULL OR @to_date < @from_date
        THROW 50400, N'toDate|The end date must be on or after the start date.', 1;
    IF NOT EXISTS (SELECT 1 FROM [lv].[fn_leave_coverage](@company_id) c WHERE c.employee_id = @employee_id AND c.leave_type_id = @leave_type_id)
        THROW 50400, N'leaveTypeId|No leave policy gives this employee this leave type.', 1;
    IF EXISTS (SELECT 1 FROM @t WHERE gender <> N'any' AND (@gender IS NULL OR @gender <> gender))
        THROW 50400, N'leaveTypeId|This leave type is not for this employee''s gender.', 1;
    IF EXISTS (SELECT 1 FROM @t WHERE marital_status <> N'any' AND (@marital IS NULL OR @marital <> marital_status))
        THROW 50400, N'leaveTypeId|This leave type is not for this employee''s marital status.', 1;
    IF @status = N'probation' AND EXISTS (SELECT 1 FROM @t WHERE allowed_in_probation = 0 AND is_probation_type = 0)
        THROW 50400, N'leaveTypeId|This leave type cannot be taken during probation.', 1;
    IF EXISTS (SELECT 1 FROM @t WHERE ISNULL(min_experience_months, 0) > 0
               AND (@joined IS NULL OR DATEADD(month, min_experience_months, @joined) > @from_date))
        THROW 50400, N'leaveTypeId|The employee has not served long enough for this leave type.', 1;
    IF @from_date < @today AND EXISTS (SELECT 1 FROM @t WHERE allow_back_date = 0)
        THROW 50400, N'fromDate|This leave type cannot be applied for past dates.', 1;
    IF @from_date < @today AND EXISTS (SELECT 1 FROM @t WHERE allow_back_date = 1 AND back_date_limit_days IS NOT NULL
                                       AND DATEDIFF(day, @from_date, @today) > back_date_limit_days)
        THROW 50400, N'fromDate|The start date is further back than this leave type allows.', 1;
    IF EXISTS (SELECT 1 FROM @t WHERE has_future_limit = 1 AND future_limit_days IS NOT NULL
               AND DATEDIFF(day, @today, @from_date) > future_limit_days)
        THROW 50400, N'fromDate|The start date is further ahead than this leave type allows.', 1;
    IF ISNULL(@has_attachment, 0) = 0 AND EXISTS (SELECT 1 FROM @t WHERE attachment_required = 1 AND ISNULL(attachment_rule, N'refuse') = N'refuse')
        THROW 50400, N'attachment|This leave type needs an attachment.', 1;
    IF @is_short = 1
    BEGIN
        -- The leave type must allow a short leave at all; then a half day needs the employee's
        -- "Half leave & Short leave" policy to allow half days (allowHalfDay) and a quarter day to allow
        -- short leave (allowShortLeave). Without such a policy the type alone decides.
        IF EXISTS (SELECT 1 FROM @t WHERE ISNULL(is_short_leave, 0) = 0)
            THROW 50400, N'isShort|This leave type cannot be taken as a short leave.', 1;
        DECLARE @half BIT, @short BIT;
        SELECT @half = h.allow_half_day, @short = h.allow_short_leave
        FROM [lv].[fn_leave_half_short](@company_id, @employee_id) h;
        IF ISNULL(@short_leave_type, N'half_day') = N'half_day' AND ISNULL(@half, 1) = 0
            THROW 50400, N'shortLeaveType|HALF_DAY_NOT_ALLOWED|Half-day leave is not allowed for this employee.', 1;
        IF @short_leave_type = N'quarter_day' AND ISNULL(@short, 1) = 0
            THROW 50400, N'shortLeaveType|SHORT_LEAVE_NOT_ALLOWED|Short leave is not allowed for this employee.', 1;
    END

    DECLARE @count INT, @last DATE;
    SELECT @count = COUNT(*), @last = MAX(r.to_date)
    FROM [req].[request] r JOIN [req].[req_leave] rl ON rl.request_id = r.id
    WHERE r.company_id = @company_id AND r.employee_id = @employee_id AND rl.leave_type_id = @leave_type_id
      AND r.status IN (N'pending', N'approved', N'cancelling') AND r.is_deleted = 0
      AND (@request_id IS NULL OR r.id <> @request_id)
      AND (@joined IS NULL OR r.from_date >= @joined);
    IF EXISTS (SELECT 1 FROM @t WHERE max_applications IS NOT NULL AND @count >= max_applications)
        THROW 50400, N'leaveTypeId|The employee has used all the applications this leave type allows.', 1;
    IF @last IS NOT NULL AND EXISTS (SELECT 1 FROM @t WHERE ISNULL(gap_months, 0) > 0 AND DATEADD(month, gap_months, @last) > @from_date)
        THROW 50400, N'fromDate|Too soon after the last application of this leave type.', 1;

    IF EXISTS (SELECT 1 FROM @t WHERE is_deductible = 1)
    BEGIN
        DECLARE @available DECIMAL(6,2) = (
            SELECT b.available + ISNULL((SELECT ISNULL(rl.days, r.days) FROM [req].[request] r
                                         JOIN [req].[req_leave] rl ON rl.request_id = r.id
                                         WHERE r.id = @request_id AND r.status = N'pending' AND rl.leave_type_id = @leave_type_id), 0)
            FROM [lv].[fn_leave_balance](@company_id, @employee_id, @leave_type_id, @from_date) b);
        IF ISNULL(@available, 0) < @days
            THROW 50409, N'leaveTypeId|LEAVE_BALANCE_EXCEEDED|Not enough leave balance for this request.', 1;
    END
END
