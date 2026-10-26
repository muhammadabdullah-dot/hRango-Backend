-- Approval effects the requests engine runs inside its final-approval transaction (comparison/04-requests.md):
--   <schema>.usp_request_apply_<kind>  @company_id, @actor_user_id, @request_id   on final approval
--   <schema>.usp_request_revert_<kind> @company_id, @actor_user_id, @request_id   when an approved request is cancelled
-- They return no result set. A THROW blocks the approval and its message goes to the approver.
-- A day already used by payroll (is_frozen) cannot be changed: the approval is refused (open question C9).
-- The time sheet reads approved requests itself (usp_timesheet_process), so most effects only re-process
-- the days; @include_request_id / @exclude_request_id count the request whatever its status is at that moment.

-- Shared: refuses frozen days, then re-processes an employee's days (a year at a time).
CREATE OR ALTER PROCEDURE [att].[usp_request_reprocess]
    @company_id         BIGINT,
    @actor_user_id      BIGINT = NULL,
    @employee_id        BIGINT,
    @from_date          DATE,
    @to_date            DATE,
    @include_request_id BIGINT = NULL,
    @exclude_request_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @from_date IS NULL OR @to_date IS NULL OR @to_date < @from_date
        THROW 50400, N'The request has no valid dates', 1;
    IF EXISTS (SELECT 1 FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND is_frozen = 1
               AND work_date BETWEEN @from_date AND @to_date)
        THROW 50409, N'workDate|ATTENDANCE_FROZEN|Attendance for these dates is locked: payroll has used it.', 1;

    DECLARE @ids NVARCHAR(50) = N'[' + CONVERT(NVARCHAR(30), @employee_id) + N']';
    DECLARE @lo DATE = DATEADD(DAY, -1, @from_date), @hi DATE = DATEADD(DAY, 1, @to_date), @chunk_to DATE;
    WHILE @lo <= @hi
    BEGIN
        SET @chunk_to = CASE WHEN DATEADD(DAY, 365, @lo) < @hi THEN DATEADD(DAY, 365, @lo) ELSE @hi END;
        EXEC [att].[usp_timesheet_process] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @from_date = @lo, @to_date = @chunk_to, @employee_ids = @ids,
             @include_request_id = @include_request_id, @exclude_request_id = @exclude_request_id, @quiet = 1;
        SET @lo = DATEADD(DAY, 1, @chunk_to);
    END
END
GO

-- Punch request (req_punch): adds the punch (source punch_request) and re-processes the day.
CREATE OR ALTER PROCEDURE [att].[usp_request_apply_punch]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @date DATE, @time TIME(0), @type_text NVARCHAR(100);
    SELECT @employee_id = r.employee_id, @date = ISNULL(p.punch_date, r.from_date), @time = p.punch_time, @type_text = p.punch_type
    FROM [req].[request] r
    JOIN [req].[req_punch] p ON p.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF @employee_id IS NULL
        THROW 50404, N'Punch request not found', 1;
    IF @date IS NULL OR @time IS NULL
        THROW 50400, N'punchTime|The punch request has no date or time.', 1;

    DECLARE @type NVARCHAR(30), @break_type_id BIGINT;
    SELECT @type = punch_type, @break_type_id = break_type_id FROM [att].[fn_punch_type_parse](@company_id, @type_text);
    IF @type IS NULL
        THROW 50400, N'punchType|The punch request has an unknown punch type.', 1;

    DECLARE @at DATETIME2(0) = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @time), CAST(@date AS DATETIME2(0)));
    IF EXISTS (SELECT 1 FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND is_frozen = 1
               AND work_date BETWEEN DATEADD(DAY, -1, @date) AND @date)
        THROW 50409, N'punchDate|ATTENDANCE_FROZEN|Attendance for this date is locked: payroll has used it.', 1;

    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM [att].[punch] WHERE employee_id = @employee_id AND punched_at = @at AND punch_type = @type)
            UPDATE [att].[punch]
            SET is_ignored = 0, request_id = ISNULL(request_id, @request_id), updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
            WHERE employee_id = @employee_id AND punched_at = @at AND punch_type = @type;
        ELSE
            INSERT [att].[punch] (company_id, employee_id, punched_at, punch_type, break_type_id, source, request_id, created_by)
            VALUES (@company_id, @employee_id, @at, @type, @break_type_id, N'punch_request', @request_id, @actor_user_id);

        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @at;
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_request_revert_punch]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @at DATETIME2(0);
    SELECT TOP 1 @employee_id = employee_id, @at = punched_at
    FROM [att].[punch] WHERE request_id = @request_id AND company_id = @company_id;
    IF @employee_id IS NULL
        RETURN;
    IF EXISTS (SELECT 1 FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND is_frozen = 1
               AND work_date BETWEEN DATEADD(DAY, -1, CAST(@at AS DATE)) AND CAST(@at AS DATE))
        THROW 50409, N'punchDate|ATTENDANCE_FROZEN|Attendance for this date is locked: payroll has used it.', 1;

    BEGIN TRAN;
        DELETE [att].[punch] WHERE request_id = @request_id AND source = N'punch_request';
        UPDATE [att].[punch] SET request_id = NULL WHERE request_id = @request_id;
        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @at;
    COMMIT;
END
GO

-- Relaxation and official visit (req_time_window): the time sheet reads the window; re-process the day.
CREATE OR ALTER PROCEDURE [att].[usp_request_apply_time_window]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @date DATE;
    SELECT @employee_id = r.employee_id, @date = ISNULL(w.window_date, r.from_date)
    FROM [req].[request] r JOIN [req].[req_time_window] w ON w.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Request not found', 1;
    EXEC [att].[usp_request_reprocess] @company_id, @actor_user_id, @employee_id, @date, @date, @request_id, NULL;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_request_revert_time_window]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @date DATE;
    SELECT @employee_id = r.employee_id, @date = ISNULL(w.window_date, r.from_date)
    FROM [req].[request] r JOIN [req].[req_time_window] w ON w.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Request not found', 1;
    EXEC [att].[usp_request_reprocess] @company_id, @actor_user_id, @employee_id, @date, @date, NULL, @request_id;
END
GO

-- Overtime (req_overtime): approved minutes (or the applied ones) become the day's approved overtime.
CREATE OR ALTER PROCEDURE [att].[usp_request_apply_overtime]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @date DATE;
    SELECT @employee_id = r.employee_id, @date = ISNULL(o.overtime_date, r.from_date)
    FROM [req].[request] r JOIN [req].[req_overtime] o ON o.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Overtime request not found', 1;
    EXEC [att].[usp_request_reprocess] @company_id, @actor_user_id, @employee_id, @date, @date, @request_id, NULL;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_request_revert_overtime]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @date DATE;
    SELECT @employee_id = r.employee_id, @date = ISNULL(o.overtime_date, r.from_date)
    FROM [req].[request] r JOIN [req].[req_overtime] o ON o.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Overtime request not found', 1;
    EXEC [att].[usp_request_reprocess] @company_id, @actor_user_id, @employee_id, @date, @date, NULL, @request_id;
END
GO

-- Work from home (request type work_from_home, no detail table): the request's days (req.request_day:
-- the shift days ticked between from_date and to_date) become WFH. The employee's planned shifts on
-- those days get sch.schedule.is_wfh = 1, then the time sheet is re-processed.
CREATE OR ALTER PROCEDURE [att].[usp_request_apply_work_from_home]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @from DATE, @to DATE;
    SELECT @employee_id = r.employee_id, @from = r.from_date, @to = ISNULL(r.to_date, r.from_date)
    FROM [req].[request] r WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Request not found', 1;
    BEGIN TRAN;
        UPDATE s SET is_wfh = 1, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        FROM [sch].[schedule] s
        JOIN [req].[request_day] d ON d.request_id = @request_id AND d.request_date = s.work_date
        WHERE s.employee_id = @employee_id AND s.company_id = @company_id AND ISNULL(s.is_wfh, 0) = 0;
        EXEC [att].[usp_request_reprocess] @company_id, @actor_user_id, @employee_id, @from, @to, @request_id, NULL;
    COMMIT;
END
GO

-- Cancelling an approved WFH request: its days' shifts go back to office work (is_wfh = 0) unless
-- another approved WFH request still covers the day; then the time sheet is re-processed.
CREATE OR ALTER PROCEDURE [att].[usp_request_revert_work_from_home]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @employee_id BIGINT, @from DATE, @to DATE, @type_id BIGINT;
    SELECT @employee_id = r.employee_id, @from = r.from_date, @to = ISNULL(r.to_date, r.from_date),
           @type_id = r.request_type_id
    FROM [req].[request] r WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Request not found', 1;
    BEGIN TRAN;
        UPDATE s SET is_wfh = 0, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        FROM [sch].[schedule] s
        JOIN [req].[request_day] d ON d.request_id = @request_id AND d.request_date = s.work_date
        WHERE s.employee_id = @employee_id AND s.company_id = @company_id AND s.is_wfh = 1
          AND NOT EXISTS (SELECT 1 FROM [req].[request] o
                          JOIN [req].[request_day] od ON od.request_id = o.id AND od.request_date = s.work_date
                          WHERE o.employee_id = @employee_id AND o.request_type_id = @type_id AND o.id <> @request_id
                            AND o.is_deleted = 0 AND o.status IN (N'approved', N'cancelling'));
        EXEC [att].[usp_request_reprocess] @company_id, @actor_user_id, @employee_id, @from, @to, NULL, @request_id;
    COMMIT;
END
