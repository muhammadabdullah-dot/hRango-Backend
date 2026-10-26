-- Effects of approved requests, called by the requests engine inside its approval transaction
-- (see comparison/04-requests.md), and their reversal when an approved request is cancelled.
-- A THROW blocks the approval and its message goes to the approver.

-- Re-does the time sheet of days that have already happened, after a request changed an employee's
-- schedule or rest days (att.usp_request_reprocess; refused when payroll has used those days).
-- Future days are left to the regular processing run.
CREATE OR ALTER PROCEDURE [sch].[usp_attendance_refresh]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @from_date     DATE,
    @to_date       DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE);
    SET @to_date = ISNULL(@to_date, @from_date);
    IF @employee_id IS NULL OR @from_date IS NULL OR @from_date > @today
        RETURN;
    IF @to_date > @today
        SET @to_date = @today;
    EXEC [att].[usp_request_reprocess] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @employee_id = @employee_id, @from_date = @from_date, @to_date = @to_date;
END
GO

-- Rest day request approved: the requester gets a rest day on each selected day (req.request_day),
-- or on every day from request.from_date to request.to_date when no days were selected, paid as
-- req.req_rest_day.is_payable says. A date that is already a rest day is left as it is. A rest day
-- wins over a shift on the same date, so shifts are not deleted.
CREATE OR ALTER PROCEDURE [sch].[usp_request_apply_rest_day]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @from DATE, @to DATE, @payable BIT;
    SELECT @employee_id = r.employee_id, @from = r.from_date, @to = ISNULL(r.to_date, r.from_date), @payable = x.is_payable
    FROM [req].[request] r
    JOIN [req].[req_rest_day] x ON x.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Rest day request not found', 1;

    DECLARE @days TABLE (d DATE PRIMARY KEY);
    INSERT @days SELECT DISTINCT request_date FROM [req].[request_day] WHERE request_id = @request_id AND request_date IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @days)
    BEGIN
        IF @from IS NULL
            THROW 50400, N'The rest day request has no dates.', 1;
        IF DATEDIFF(DAY, @from, @to) > 366
            THROW 50400, N'The rest day request covers more than a year.', 1;
        INSERT @days SELECT d FROM [sch].[fn_dates](@from, @to);
    END

    INSERT [sch].[rest_day] (company_id, employee_id, rest_date, is_payable, request_id, created_by)
    SELECT @company_id, @employee_id, d.d, ISNULL(@payable, 0), @request_id, @actor_user_id
    FROM @days d
    WHERE NOT EXISTS (SELECT 1 FROM [sch].[rest_day] r WHERE r.employee_id = @employee_id AND r.rest_date = d.d);

    DECLARE @lo DATE = (SELECT MIN(d) FROM @days), @hi DATE = (SELECT MAX(d) FROM @days);
    EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @employee_id = @employee_id, @from_date = @lo, @to_date = @hi;

    INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
    VALUES (@company_id, N'sch.rest_day', @request_id, N'request_apply', CONCAT(N'request ', @request_id), @actor_user_id, SYSUTCDATETIME());
END
GO

-- Cancelling an approved rest day request: its rest days go.
CREATE OR ALTER PROCEDURE [sch].[usp_request_revert_rest_day]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @lo DATE, @hi DATE;
    SELECT @employee_id = MIN(employee_id), @lo = MIN(rest_date), @hi = MAX(rest_date)
    FROM [sch].[rest_day] WHERE company_id = @company_id AND request_id = @request_id;

    DELETE [sch].[rest_day] WHERE company_id = @company_id AND request_id = @request_id;
    EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @employee_id = @employee_id, @from_date = @lo, @to_date = @hi;

    INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
    VALUES (@company_id, N'sch.rest_day', @request_id, N'request_revert', CONCAT(N'request ', @request_id), @actor_user_id, SYSUTCDATETIME());
END
GO

-- Shift request approved (req.req_shift_swap). Two forms:
--   swap    with_employee_id given: the requester's shift (from_schedule_id) goes to that colleague,
--           and the colleague's shift (to_schedule_id, when given) comes to the requester.
--   change  no colleague, time_slot_id given: the requester's shift (from_schedule_id, or a new
--           shift on shift_date when there is none) moves to that time slot.
-- Refused when the shifts no longer belong to those people, or the result would clash (rest day,
-- overlap, a second shift on a day without multi-shift). For a change, the previous slot and times
-- are kept in core.audit_log (field_name request:<id>) so a cancellation can put them back.
CREATE OR ALTER PROCEDURE [sch].[usp_request_apply_shift_swap]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @shift_date DATE, @from_schedule BIGINT, @time_slot BIGINT, @with_employee BIGINT,
            @to_schedule BIGINT;
    SELECT @employee_id = r.employee_id, @shift_date = x.shift_date, @from_schedule = x.from_schedule_id,
           @time_slot = x.time_slot_id, @with_employee = x.with_employee_id, @to_schedule = x.to_schedule_id
    FROM [req].[request] r
    JOIN [req].[req_shift_swap] x ON x.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Shift request not found', 1;
    IF @from_schedule IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [sch].[schedule] WHERE id = @from_schedule AND employee_id = @employee_id AND company_id = @company_id)
        THROW 50409, N'The requester''s shift has changed since the request was made.', 1;

    IF @with_employee IS NOT NULL
    BEGIN
        IF @from_schedule IS NULL
            THROW 50400, N'The shift request names no shift to swap.', 1;
        IF @to_schedule IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [sch].[schedule] WHERE id = @to_schedule AND employee_id = @with_employee AND company_id = @company_id)
            THROW 50409, N'The other employee''s shift has changed since the request was made.', 1;
        DECLARE @d1 DATE = (SELECT work_date FROM [sch].[schedule] WHERE id = @from_schedule),
                @d2 DATE = (SELECT work_date FROM [sch].[schedule] WHERE id = @to_schedule);
        EXEC [sch].[usp_schedule_swap] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = NULL,
             @schedule_id = @from_schedule, @with_schedule_id = @to_schedule, @with_employee_id = @with_employee;
        DECLARE @lo DATE = CASE WHEN @d2 IS NOT NULL AND @d2 < @d1 THEN @d2 ELSE @d1 END,
                @hi DATE = CASE WHEN @d2 IS NOT NULL AND @d2 > @d1 THEN @d2 ELSE @d1 END;
        EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @employee_id = @employee_id, @from_date = @lo, @to_date = @hi;
        EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @employee_id = @with_employee, @from_date = @lo, @to_date = @hi;
        RETURN;
    END

    IF @time_slot IS NULL
        THROW 50400, N'The shift request asks for neither a swap nor another time slot.', 1;

    DECLARE @old NVARCHAR(200), @rv BINARY(8), @work_date DATE, @geo BIGINT, @wfh BIT, @new_id BIGINT;
    IF @from_schedule IS NOT NULL
    BEGIN
        SELECT @old = CONCAT(time_slot_id, N'|', CONVERT(CHAR(8), CAST(start_at AS TIME(0)), 108), N'|',
                             CONVERT(CHAR(8), CAST(end_at AS TIME(0)), 108)),
               @rv = row_version, @work_date = work_date, @geo = geo_fence_id, @wfh = is_wfh
        FROM [sch].[schedule] WHERE id = @from_schedule;
        EXEC [sch].[usp_schedule_save] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = NULL,
             @id = @from_schedule, @work_date = @work_date, @time_slot_id = @time_slot, @geo_fence_id = @geo,
             @is_wfh = @wfh, @row_version = @rv, @return_row = 0;
        SET @new_id = @from_schedule;
    END
    ELSE
    BEGIN
        IF @shift_date IS NULL
            THROW 50400, N'The shift request has no date.', 1;
        EXEC [sch].[usp_schedule_save] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = NULL,
             @employee_id = @employee_id, @work_date = @shift_date, @time_slot_id = @time_slot, @return_row = 0,
             @new_id = @new_id OUTPUT;
    END

    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
    VALUES (@company_id, N'sch.schedule', @new_id, CONCAT(N'request:', @request_id), @old, CONVERT(NVARCHAR(30), @time_slot),
            N'request_apply', @actor_user_id, SYSUTCDATETIME());
    DECLARE @changed DATE = ISNULL(@work_date, @shift_date);
    EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @employee_id = @employee_id, @from_date = @changed, @to_date = @changed;
END
GO

-- Cancelling an approved shift request: a swap is swapped back; a changed shift gets its previous
-- time slot and times back; a shift the request created is deleted.
CREATE OR ALTER PROCEDURE [sch].[usp_request_revert_shift_swap]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @from_schedule BIGINT, @with_employee BIGINT, @to_schedule BIGINT;
    SELECT @employee_id = r.employee_id, @from_schedule = x.from_schedule_id, @with_employee = x.with_employee_id,
           @to_schedule = x.to_schedule_id
    FROM [req].[request] r
    JOIN [req].[req_shift_swap] x ON x.request_id = r.id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @employee_id IS NULL
        THROW 50404, N'Shift request not found', 1;

    IF @with_employee IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [sch].[schedule] WHERE id = @from_schedule AND employee_id = @with_employee AND company_id = @company_id)
            THROW 50409, N'The swapped shift has changed since the swap; it cannot be swapped back.', 1;
        IF @to_schedule IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [sch].[schedule] WHERE id = @to_schedule AND employee_id = @employee_id AND company_id = @company_id)
            THROW 50409, N'The swapped shift has changed since the swap; it cannot be swapped back.', 1;
        DECLARE @r1 DATE = (SELECT work_date FROM [sch].[schedule] WHERE id = @from_schedule),
                @r2 DATE = (SELECT work_date FROM [sch].[schedule] WHERE id = @to_schedule);
        EXEC [sch].[usp_schedule_swap] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = NULL,
             @schedule_id = @from_schedule, @with_schedule_id = @to_schedule, @with_employee_id = @employee_id;
        DECLARE @rlo DATE = CASE WHEN @r2 IS NOT NULL AND @r2 < @r1 THEN @r2 ELSE @r1 END,
                @rhi DATE = CASE WHEN @r2 IS NOT NULL AND @r2 > @r1 THEN @r2 ELSE @r1 END;
        EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @employee_id = @employee_id, @from_date = @rlo, @to_date = @rhi;
        EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @employee_id = @with_employee, @from_date = @rlo, @to_date = @rhi;
        RETURN;
    END

    DECLARE @tag NVARCHAR(100) = CONCAT(N'request:', @request_id), @schedule_id BIGINT, @old NVARCHAR(MAX);
    SELECT TOP (1) @schedule_id = entity_id, @old = old_value
    FROM [core].[audit_log]
    WHERE company_id = @company_id AND entity_type = N'sch.schedule' AND field_name = @tag AND action_name = N'request_apply'
    ORDER BY id DESC;
    IF @schedule_id IS NULL OR NOT EXISTS (SELECT 1 FROM [sch].[schedule] WHERE id = @schedule_id AND employee_id = @employee_id)
        RETURN;  -- nothing was applied, or the shift is gone already

    IF @old IS NULL
    BEGIN
        DELETE [sch].[schedule_break] WHERE schedule_id = @schedule_id;
        DELETE [sch].[schedule] WHERE id = @schedule_id;
    END
    ELSE
    BEGIN
        -- old_value is "<time slot id>|<start hh:mm:ss>|<end hh:mm:ss>".
        DECLARE @p1 INT = CHARINDEX(N'|', @old);
        DECLARE @p2 INT = CHARINDEX(N'|', @old, @p1 + 1);
        DECLARE @slot BIGINT = TRY_CAST(LEFT(@old, @p1 - 1) AS BIGINT);
        DECLARE @st TIME(0) = TRY_CAST(SUBSTRING(@old, @p1 + 1, @p2 - @p1 - 1) AS TIME(0));
        DECLARE @et TIME(0) = TRY_CAST(SUBSTRING(@old, @p2 + 1, 20) AS TIME(0));
        DECLARE @rv BINARY(8), @work_date DATE, @geo BIGINT, @wfh BIT;
        SELECT @rv = row_version, @work_date = work_date, @geo = geo_fence_id, @wfh = is_wfh
        FROM [sch].[schedule] WHERE id = @schedule_id;
        EXEC [sch].[usp_schedule_save] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = NULL,
             @id = @schedule_id, @work_date = @work_date, @time_slot_id = @slot, @start_time = @st, @end_time = @et,
             @geo_fence_id = @geo, @is_wfh = @wfh, @row_version = @rv, @return_row = 0;
    END

    DECLARE @reverted DATE = (SELECT work_date FROM [sch].[schedule] WHERE id = @schedule_id);
    IF @reverted IS NULL
        SET @reverted = (SELECT shift_date FROM [req].[req_shift_swap] WHERE request_id = @request_id);
    EXEC [sch].[usp_attendance_refresh] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @employee_id = @employee_id, @from_date = @reverted, @to_date = @reverted;

    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, action_name, performed_by_user_id, performed_at)
    VALUES (@company_id, N'sch.schedule', @schedule_id, @tag, N'request_revert', @actor_user_id, SYSUTCDATETIME());
END
