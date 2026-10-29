-- Validates and saves the kind-specific part of a request (internal; called by submit and edit
-- inside their transaction, after the header row exists). @details is the kind's JSON object with
-- snake_case keys; the API layer has already checked shapes and allowed values. Sets the header's
-- from_date, to_date and days (the Count) from the details. Rules come from the Functional
-- Requirements (pp. 1-97) per type; see comparison/04-requests.md.
CREATE OR ALTER PROCEDURE [req].[usp_request_detail_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT,
    @details       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @kind NVARCHAR(30), @type_code NVARCHAR(30), @type_id BIGINT, @employee_id BIGINT, @from DATE, @to DATE,
            @days DECIMAL(6,2), @today DATE = CAST(SYSDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME(),
            @d NVARCHAR(MAX) = ISNULL(NULLIF(LTRIM(RTRIM(@details)), N''), N'{}'), @msg NVARCHAR(400);
    SELECT @kind = t.kind, @type_code = t.code, @type_id = t.id, @employee_id = r.employee_id,
           @from = r.from_date, @to = r.to_date
    FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF ISJSON(@d) = 0
        THROW 50400, N'details|The request details are not valid JSON.', 1;

    -- Other requests of the same type that still count (not deleted, not rejected or cancelled).
    DECLARE @live TABLE (id BIGINT PRIMARY KEY, from_date DATE NULL, to_date DATE NULL, status NVARCHAR(30));
    INSERT @live (id, from_date, to_date, status)
    SELECT r.id, r.from_date, r.to_date, r.status
    FROM [req].[request] r
    WHERE r.company_id = @company_id AND r.employee_id = @employee_id AND r.request_type_id = @type_id
      AND r.id <> @request_id AND r.is_deleted = 0 AND r.status IN (N'pending', N'approved', N'cancelling');

    -- Dates of a multi-day request, with the employee's shift on each day (first one when several).
    DECLARE @dates TABLE (request_date DATE PRIMARY KEY, schedule_id BIGINT NULL);
    DECLARE @join DATE = (SELECT MAX(joining_date) FROM [hr].[employment_period] WHERE employee_id = @employee_id);

    -- ------------------------------------------------------------------ leave
    IF @kind = N'leave'
    BEGIN
        DECLARE @leave_type_id BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.leave_type_id') AS BIGINT),
                @is_short BIT = ISNULL(TRY_CAST(JSON_VALUE(@d, N'$.is_short') AS BIT), 0),
                @short_type NVARCHAR(30) = JSON_VALUE(@d, N'$.short_leave_type'),
                @l_start TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.start_time') AS TIME(0)),
                @l_end TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.end_time') AS TIME(0));
        DECLARE @lt_title NVARCHAR(200), @lt_active BIT, @lt_short BIT;
        SELECT @lt_title = title, @lt_active = is_active, @lt_short = is_short_leave
        FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id;

        IF @lt_title IS NULL
            THROW 50400, N'leaveTypeId|Leave type not found.', 1;
        IF @lt_active = 0
            THROW 50400, N'leaveTypeId|This leave type is not active.', 1;
        IF @from IS NULL
            THROW 50400, N'fromDate|Start date is required.', 1;

        IF @is_short = 1
        BEGIN
            IF @lt_short = 0
                THROW 50400, N'isShort|This leave type cannot be taken as a short leave.', 1;
            IF @short_type NOT IN (N'half_day', N'quarter_day') OR @short_type IS NULL
                THROW 50400, N'shortLeaveType|Short leave type is required.', 1;
            IF @l_start IS NULL OR @l_end IS NULL
                THROW 50400, N'startTime|Start time and end time are required for a short leave.', 1;
            IF @l_end <= @l_start
                THROW 50400, N'endTime|End time must be after the start time.', 1;
            IF @to IS NOT NULL AND @to <> @from
                THROW 50400, N'toDate|A short leave is for one day.', 1;
            SET @to = @from;
            SET @days = CASE @short_type WHEN N'half_day' THEN 0.5 ELSE 0.25 END;
            INSERT @dates (request_date, schedule_id)
            SELECT @from, (SELECT MIN(id) FROM [sch].[schedule] WHERE employee_id = @employee_id AND work_date = @from);
        END
        ELSE
        BEGIN
            SELECT @short_type = NULL, @l_start = NULL, @l_end = NULL;
            IF @to IS NULL
                THROW 50400, N'toDate|End date is required.', 1;
            IF @to < @from
                THROW 50400, N'toDate|End date must be on or after the start date.', 1;
            IF DATEDIFF(DAY, @from, @to) > 366
                THROW 50400, N'toDate|A request can cover at most a year.', 1;
            WITH n AS (SELECT TOP (DATEDIFF(DAY, @from, @to) + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
                       FROM sys.all_objects)
            INSERT @dates (request_date, schedule_id)
            SELECT DATEADD(DAY, n.i, @from),
                   (SELECT MIN(s.id) FROM [sch].[schedule] s WHERE s.employee_id = @employee_id AND s.work_date = DATEADD(DAY, n.i, @from))
            FROM n;
            -- Only shift days count when the employee has a schedule in the range; otherwise every day.
            IF EXISTS (SELECT 1 FROM @dates WHERE schedule_id IS NOT NULL)
                DELETE @dates WHERE schedule_id IS NULL;
            SET @days = (SELECT COUNT(*) FROM @dates);
        END

        IF EXISTS (SELECT 1 FROM @live v WHERE v.from_date <= @to AND v.to_date >= @from)
            THROW 50409, N'fromDate|LEAVE_OVERLAP|Another leave request already covers some of these dates.', 1;

        -- The leave module's check of every leave type rule (policy coverage, gender, marital status,
        -- probation, experience, back and future dates, attachment, half-day / short leave policy,
        -- applications, gap, balance). lv owns the rules; this request is left out of its counts.
        DECLARE @has_file BIT = CASE WHEN EXISTS (SELECT 1 FROM [core].[attachment] WHERE entity_type = N'req.request'
                                                 AND entity_id = @request_id) THEN 1 ELSE 0 END;
        EXEC [lv].[usp_leave_request_check] @company_id = @company_id, @employee_id = @employee_id,
             @leave_type_id = @leave_type_id, @from_date = @from, @to_date = @to, @days = @days, @is_short = @is_short,
             @short_leave_type = @short_type, @has_attachment = @has_file, @request_id = @request_id;

        IF EXISTS (SELECT 1 FROM [req].[req_leave] WHERE request_id = @request_id)
            UPDATE [req].[req_leave]
            SET leave_type_id = @leave_type_id, is_short = @is_short, short_leave_type = @short_type,
                start_time = @l_start, end_time = @l_end, days = @days, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_leave] (request_id, leave_type_id, is_short, short_leave_type, start_time, end_time, days, created_by)
            VALUES (@request_id, @leave_type_id, @is_short, @short_type, @l_start, @l_end, @days, @actor_user_id);
    END

    -- ------------------------------------------------------------------ punch
    ELSE IF @kind = N'punch'
    BEGIN
        DECLARE @p_date DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.punch_date') AS DATE), @from),
                @p_type NVARCHAR(30) = JSON_VALUE(@d, N'$.punch_type'),
                @p_time TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.punch_time') AS TIME(0)),
                @p_count INT, @p_start DATETIME2(0), @p_end DATETIME2(0), @p_at DATETIME2(0);
        IF @p_date IS NULL
            THROW 50400, N'punchDate|Date is required.', 1;
        IF @p_type IS NULL OR @p_type NOT IN (N'check_in', N'check_out', N'break_out', N'break_in')
            THROW 50400, N'punchType|Punch type is required.', 1;
        IF @p_time IS NULL
            THROW 50400, N'punchTime|Punch time is required.', 1;
        IF @p_date > @today
            THROW 50400, N'punchDate|A punch request is for today or an earlier date.', 1;

        SELECT @p_count = COUNT(*), @p_start = MIN(start_at), @p_end = MIN(end_at)
        FROM [sch].[schedule] WHERE employee_id = @employee_id AND work_date = @p_date;
        IF @p_count = 0
            THROW 50400, N'punchDate|NO_SHIFT|There is no shift on this date, so a punch cannot be requested.', 1;
        IF @p_count = 1
        BEGIN
            -- One shift: the punch must fall inside it. Several shifts: any time is accepted.
            SET @p_at = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @p_time), CAST(@p_date AS DATETIME2(0)));
            IF @p_at < @p_start AND CAST(@p_end AS DATE) > @p_date
                SET @p_at = DATEADD(DAY, 1, @p_at);
            IF @p_at < @p_start OR @p_at > @p_end
            BEGIN
                SET @msg = N'punchTime|The punch time must fall within the shift (' + CONVERT(NVARCHAR(5), CAST(@p_start AS TIME), 108)
                         + N' - ' + CONVERT(NVARCHAR(5), CAST(@p_end AS TIME), 108) + N').';
                THROW 50400, @msg, 1;
            END
        END
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[req_punch] p ON p.request_id = v.id
                   WHERE p.punch_date = @p_date AND p.punch_type = @p_type)
            THROW 50409, N'punchType|PUNCH_DUPLICATE|A request for this punch on this date already exists.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_punch] WHERE request_id = @request_id)
            UPDATE [req].[req_punch] SET punch_date = @p_date, punch_type = @p_type, punch_time = @p_time,
                   updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_punch] (request_id, punch_date, punch_type, punch_time, created_by)
            VALUES (@request_id, @p_date, @p_type, @p_time, @actor_user_id);
        SELECT @from = @p_date, @to = @p_date, @days = 1;
    END

    -- ------------------------------------------------------------------ relaxation, official visit
    ELSE IF @kind = N'time_window'
    BEGIN
        DECLARE @w_date DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.window_date') AS DATE), @from),
                @w_start TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.start_time') AS TIME(0)),
                @w_end TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.end_time') AS TIME(0)),
                @w_count INT, @w_slot BIGINT, @w_s DATETIME2(0), @w_e DATETIME2(0), @w_a DATETIME2(0), @w_b DATETIME2(0);
        IF @w_date IS NULL
            THROW 50400, N'windowDate|Date is required.', 1;
        IF @w_start IS NULL
            THROW 50400, N'startTime|Start time is required.', 1;
        IF @w_end IS NULL
            THROW 50400, N'endTime|End time is required.', 1;
        IF @w_end <= @w_start
            THROW 50400, N'endTime|End time must be after the start time.', 1;

        SELECT @w_count = COUNT(*), @w_slot = MIN(time_slot_id), @w_s = MIN(start_at), @w_e = MIN(end_at)
        FROM [sch].[schedule] WHERE employee_id = @employee_id AND work_date = @w_date;
        IF @type_code = N'relaxation' AND @w_count = 0
            THROW 50400, N'windowDate|NO_SHIFT|There is no shift on this date to relax.', 1;
        IF @type_code = N'relaxation' AND @w_count = 1
        BEGIN
            SET @w_a = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @w_start), CAST(@w_date AS DATETIME2(0)));
            SET @w_b = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @w_end), CAST(@w_date AS DATETIME2(0)));
            IF @w_a < @w_s AND CAST(@w_e AS DATE) > @w_date
                SELECT @w_a = DATEADD(DAY, 1, @w_a), @w_b = DATEADD(DAY, 1, @w_b);
            IF @w_a < @w_s OR @w_b > @w_e
            BEGIN
                SET @msg = N'startTime|The times must fall inside the shift (' + CONVERT(NVARCHAR(5), CAST(@w_s AS TIME), 108)
                         + N' - ' + CONVERT(NVARCHAR(5), CAST(@w_e AS TIME), 108) + N').';
                THROW 50400, @msg, 1;
            END
        END
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[req_time_window] w ON w.request_id = v.id
                   WHERE w.window_date = @w_date AND w.start_time < @w_end AND w.end_time > @w_start)
            THROW 50409, N'startTime|WINDOW_OVERLAP|Another request on this date overlaps these times.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_time_window] WHERE request_id = @request_id)
            UPDATE [req].[req_time_window]
            SET kind = @type_code, window_date = @w_date, start_time = @w_start, end_time = @w_end, time_slot_id = @w_slot,
                duration_minutes = DATEDIFF(MINUTE, @w_start, @w_end), updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_time_window] (request_id, kind, window_date, start_time, end_time, time_slot_id, duration_minutes, created_by)
            VALUES (@request_id, @type_code, @w_date, @w_start, @w_end, @w_slot, DATEDIFF(MINUTE, @w_start, @w_end), @actor_user_id);
        SELECT @from = @w_date, @to = @w_date, @days = 1;
    END

    -- ------------------------------------------------------------------ work from home
    ELSE IF @kind = N'work_from_home'
    BEGIN
        IF @from IS NULL
            THROW 50400, N'fromDate|Start date is required.', 1;
        IF @to IS NULL
            THROW 50400, N'toDate|End date is required.', 1;
        IF @to < @from
            THROW 50400, N'toDate|End date must be on or after the start date.', 1;
        IF DATEDIFF(DAY, @from, @to) > 366
            THROW 50400, N'toDate|A request can cover at most a year.', 1;
        WITH n AS (SELECT TOP (DATEDIFF(DAY, @from, @to) + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
                   FROM sys.all_objects)
        INSERT @dates (request_date, schedule_id)
        SELECT DATEADD(DAY, n.i, @from),
               (SELECT MIN(s.id) FROM [sch].[schedule] s WHERE s.employee_id = @employee_id AND s.work_date = DATEADD(DAY, n.i, @from))
        FROM n;
        -- Only shift days; and only the ticked days when the form sends them (FRD: the request keeps its
        -- From / To, the days are the shifts ticked inside it, "proceed only if one shift is applied").
        DELETE @dates WHERE schedule_id IS NULL;
        IF JSON_QUERY(@d, N'$.dates') IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.dates') j
                       WHERE TRY_CAST(j.value AS DATE) IS NULL OR TRY_CAST(j.value AS DATE) NOT BETWEEN @from AND @to)
                THROW 50400, N'dates|Each ticked day must be a date between the start and end dates.', 1;
            DELETE @dates WHERE request_date NOT IN (SELECT TRY_CAST(value AS DATE) FROM OPENJSON(@d, N'$.dates'));
        END
        IF NOT EXISTS (SELECT 1 FROM @dates)
            THROW 50400, N'fromDate|NO_SHIFT|Please select at least one shift: there is no shift on the chosen dates.', 1;
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[request_day] x ON x.request_id = v.id
                   WHERE x.request_date IN (SELECT request_date FROM @dates))
            THROW 50409, N'fromDate|WFH_OVERLAP|Some of these days are already requested from home.', 1;
        SET @days = (SELECT COUNT(*) FROM @dates);
    END

    -- ------------------------------------------------------------------ overtime
    ELSE IF @kind = N'overtime'
    BEGIN
        DECLARE @o_dept BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.department_id') AS BIGINT),
                @o_loc BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.location_id') AS BIGINT),
                @o_branch BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.branch_id') AS BIGINT),
                @o_date DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.overtime_date') AS DATE), @from),
                @o_start TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.start_time') AS TIME(0)),
                @o_end TIME(0) = TRY_CAST(JSON_VALUE(@d, N'$.end_time') AS TIME(0)),
                @o_applied INT = TRY_CAST(JSON_VALUE(@d, N'$.applied_minutes') AS INT), @o_span INT,
                @o_type NVARCHAR(30) = NULLIF(JSON_VALUE(@d, N'$.overtime_type'), N''),
                -- Set only by the bulk filing (the API never takes it from a form); kept on edit.
                @o_bulk BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.bulk_id') AS BIGINT);
        IF @o_type IS NOT NULL AND @o_type NOT IN (N'mandatory', N'voluntary')
            THROW 50400, N'overtimeType|Type must be mandatory or voluntary.', 1;
        IF @o_bulk IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [req].[request_bulk] WHERE id = @o_bulk AND company_id = @company_id)
            THROW 50400, N'bulkId|Bulk filing not found.', 1;
        IF @o_dept IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @o_dept AND company_id = @company_id)
            THROW 50400, N'departmentId|Department is required.', 1;
        IF @o_loc IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[location] WHERE id = @o_loc AND company_id = @company_id)
            THROW 50400, N'locationId|Location not found.', 1;
        IF @o_branch IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @o_branch AND company_id = @company_id)
            THROW 50400, N'branchId|Branch not found.', 1;
        IF @o_date IS NULL
            THROW 50400, N'overtimeDate|Date is required.', 1;
        IF @o_start IS NULL OR @o_end IS NULL
            THROW 50400, N'startTime|Start time and end time are required.', 1;
        SET @o_span = DATEDIFF(MINUTE, @o_start, @o_end);
        IF @o_span <= 0
            SET @o_span += 1440;
        SET @o_applied = ISNULL(@o_applied, @o_span);
        IF @o_applied <= 0 OR @o_applied > @o_span
            THROW 50400, N'appliedMinutes|Overtime must be more than zero and no longer than the time between start and end.', 1;
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[req_overtime] o ON o.request_id = v.id WHERE o.overtime_date = @o_date)
            THROW 50409, N'overtimeDate|OVERTIME_DUPLICATE|An overtime request for this date already exists.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_overtime] WHERE request_id = @request_id)
            UPDATE [req].[req_overtime]
            SET department_id = @o_dept, location_id = @o_loc, branch_id = @o_branch, overtime_date = @o_date,
                start_time = @o_start, end_time = @o_end, applied_minutes = @o_applied,
                overtime_type = COALESCE(@o_type, overtime_type), updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_overtime] (request_id, department_id, location_id, branch_id, overtime_date, start_time, end_time,
                                         applied_minutes, overtime_type, bulk_id, created_by)
            VALUES (@request_id, @o_dept, @o_loc, @o_branch, @o_date, @o_start, @o_end, @o_applied, @o_type, @o_bulk,
                    @actor_user_id);
        SELECT @from = @o_date, @to = @o_date, @days = 1;
    END

    -- ------------------------------------------------------------------ rest days
    ELSE IF @kind = N'rest_day'
    BEGIN
        DECLARE @r_dept BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.department_id') AS BIGINT),
                @r_group BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.roster_group_id') AS BIGINT),
                @r_payable BIT = ISNULL(TRY_CAST(JSON_VALUE(@d, N'$.is_payable') AS BIT), 0);
        IF @r_dept IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @r_dept AND company_id = @company_id)
            THROW 50400, N'departmentId|Department is required.', 1;
        IF @r_group IS NULL OR NOT EXISTS (SELECT 1 FROM [sch].[roster_group] WHERE id = @r_group AND company_id = @company_id)
            THROW 50400, N'rosterGroupId|Roster is required.', 1;
        IF @from IS NULL
            THROW 50400, N'fromDate|Date from is required.', 1;
        IF @to IS NULL
            THROW 50400, N'toDate|Date to is required.', 1;
        IF @to < @from
            THROW 50400, N'toDate|Date to must be on or after date from.', 1;
        IF DATEDIFF(DAY, @from, @to) > 366
            THROW 50400, N'toDate|A request can cover at most a year.', 1;
        WITH n AS (SELECT TOP (DATEDIFF(DAY, @from, @to) + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
                   FROM sys.all_objects)
        INSERT @dates (request_date, schedule_id)
        SELECT DATEADD(DAY, n.i, @from),
               (SELECT MIN(s.id) FROM [sch].[schedule] s WHERE s.employee_id = @employee_id AND s.work_date = DATEADD(DAY, n.i, @from))
        FROM n;
        IF EXISTS (SELECT 1 FROM @dates WHERE schedule_id IS NOT NULL)
            DELETE @dates WHERE schedule_id IS NULL;
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[request_day] x ON x.request_id = v.id
                   WHERE x.request_date IN (SELECT request_date FROM @dates))
            THROW 50409, N'fromDate|REST_DAY_OVERLAP|Some of these days are already requested as rest days.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_rest_day] WHERE request_id = @request_id)
            UPDATE [req].[req_rest_day] SET department_id = @r_dept, roster_group_id = @r_group, is_payable = @r_payable,
                   updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_rest_day] (request_id, department_id, roster_group_id, is_payable, created_by)
            VALUES (@request_id, @r_dept, @r_group, @r_payable, @actor_user_id);
        SET @days = (SELECT COUNT(*) FROM @dates);
    END

    -- ------------------------------------------------------------------ shift request (change or swap)
    ELSE IF @kind = N'shift_swap'
    BEGIN
        DECLARE @s_date DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.shift_date') AS DATE), @from),
                @s_slot BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.time_slot_id') AS BIGINT),
                @s_with BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.with_employee_id') AS BIGINT),
                @s_from BIGINT, @s_from_slot BIGINT, @s_to BIGINT, @s_from_start TIME(0), @s_from_end TIME(0);
        IF @s_date IS NULL
            THROW 50400, N'shiftDate|Date is required.', 1;
        IF @s_date < @today
            THROW 50400, N'shiftDate|A shift request is for today or a later date.', 1;
        IF (@s_slot IS NULL AND @s_with IS NULL) OR (@s_slot IS NOT NULL AND @s_with IS NOT NULL)
            THROW 50400, N'timeSlotId|Choose either a new shift or a colleague to swap with.', 1;
        SELECT TOP (1) @s_from = id, @s_from_slot = time_slot_id, @s_from_start = CAST(start_at AS TIME(0)),
               @s_from_end = CAST(end_at AS TIME(0))
        FROM [sch].[schedule] WHERE employee_id = @employee_id AND work_date = @s_date ORDER BY start_at;
        IF @s_from IS NULL
            THROW 50400, N'shiftDate|NO_SHIFT|There is no shift on this date to change.', 1;
        IF @s_slot IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [sch].[time_slot] WHERE id = @s_slot AND company_id = @company_id)
                THROW 50400, N'timeSlotId|Shift not found.', 1;
            -- A change to the slot the shift already has, or to another slot with the same hours, changes nothing.
            IF @s_slot = @s_from_slot
               OR EXISTS (SELECT 1 FROM [sch].[time_slot] WHERE id = @s_slot
                          AND CAST(start_time AS TIME(0)) = @s_from_start AND CAST(end_time AS TIME(0)) = @s_from_end)
                THROW 50400, N'timeSlotId|SHIFT_UNCHANGED|The new shift is the same as the current one.', 1;
        END
        IF @s_with IS NOT NULL
        BEGIN
            IF @s_with = @employee_id OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @s_with AND company_id = @company_id AND status <> N'left')
                THROW 50400, N'withEmployeeId|Choose a colleague to swap with.', 1;
            SELECT TOP (1) @s_to = id FROM [sch].[schedule] WHERE employee_id = @s_with AND work_date = @s_date ORDER BY start_at;
            IF @s_to IS NULL
                THROW 50400, N'withEmployeeId|The colleague has no shift on this date.', 1;
            -- Swapping for a shift with the same slot and hours changes nothing.
            IF EXISTS (SELECT 1 FROM [sch].[schedule] WHERE id = @s_to AND time_slot_id = @s_from_slot
                       AND CAST(start_at AS TIME(0)) = @s_from_start AND CAST(end_at AS TIME(0)) = @s_from_end)
                THROW 50400, N'withEmployeeId|SHIFT_UNCHANGED|The colleague works the same shift on this date.', 1;
        END
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[req_shift_swap] x ON x.request_id = v.id
                   WHERE x.shift_date = @s_date AND v.status IN (N'pending', N'cancelling'))
            THROW 50409, N'shiftDate|SHIFT_DUPLICATE|A shift request for this date is already waiting.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_shift_swap] WHERE request_id = @request_id)
            UPDATE [req].[req_shift_swap]
            SET shift_date = @s_date, from_schedule_id = @s_from, time_slot_id = @s_slot, with_employee_id = @s_with,
                to_schedule_id = @s_to, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_shift_swap] (request_id, shift_date, from_schedule_id, time_slot_id, with_employee_id, to_schedule_id, created_by)
            VALUES (@request_id, @s_date, @s_from, @s_slot, @s_with, @s_to, @actor_user_id);
        SELECT @from = @s_date, @to = @s_date, @days = 1;
    END

    -- ------------------------------------------------------------------ promotion or demotion
    ELSE IF @kind = N'promotion'
    BEGIN
        DECLARE @pr_demotion BIT = ISNULL(TRY_CAST(JSON_VALUE(@d, N'$.is_demotion') AS BIT), 0),
                @pr_grade BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.grade_id') AS BIGINT),
                @pr_level BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.job_level_id') AS BIGINT),
                @pr_desig BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.designation_id') AS BIGINT),
                @pr_title BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.job_title_id') AS BIGINT),
                @pr_salary DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@d, N'$.new_salary') AS DECIMAL(18,2)),
                @pr_eff DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.effective_date') AS DATE), @from),
                @pr_prev DECIMAL(18,2);
        IF @pr_grade IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[grade] WHERE id = @pr_grade AND company_id = @company_id)
            THROW 50400, N'gradeId|Grade is required.', 1;
        IF @pr_level IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_level] WHERE id = @pr_level AND company_id = @company_id)
            THROW 50400, N'jobLevelId|Level not found.', 1;
        IF @pr_desig IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[designation] WHERE id = @pr_desig AND company_id = @company_id)
            THROW 50400, N'designationId|Designation is required.', 1;
        IF @pr_title IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @pr_title AND company_id = @company_id)
            THROW 50400, N'jobTitleId|Job title is required.', 1;
        IF @pr_salary IS NULL OR @pr_salary <= 0
            THROW 50400, N'newSalary|Revised salary is required.', 1;
        IF @pr_eff IS NULL
            THROW 50400, N'effectiveDate|Effective date is required.', 1;
        SELECT TOP (1) @pr_prev = amount FROM [hr].[employee_salary]
        WHERE employee_id = @employee_id AND effective_date <= @pr_eff ORDER BY effective_date DESC, id DESC;
        IF @pr_demotion = 0 AND @pr_prev IS NOT NULL AND @pr_salary < @pr_prev
            THROW 50400, N'newSalary|A promotion cannot lower the salary.', 1;
        IF @pr_demotion = 1 AND @pr_prev IS NOT NULL AND @pr_salary > @pr_prev
            THROW 50400, N'newSalary|A demotion cannot raise the salary.', 1;
        IF EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.benefit_pay_item_ids') j
                   WHERE NOT EXISTS (SELECT 1 FROM [pay].[pay_item] p WHERE p.id = TRY_CAST(j.value AS BIGINT) AND p.company_id = @company_id))
            THROW 50400, N'benefitPayItemIds|A benefit was not found.', 1;
        IF EXISTS (SELECT 1 FROM @live WHERE status IN (N'pending', N'cancelling'))
            THROW 50409, N'employeeId|PROMOTION_OPEN|This employee already has a promotion request waiting.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_promotion] WHERE request_id = @request_id)
            UPDATE [req].[req_promotion]
            SET is_demotion = @pr_demotion, grade_id = @pr_grade, job_level_id = @pr_level, designation_id = @pr_desig,
                job_title_id = @pr_title, previous_salary = @pr_prev, new_salary = @pr_salary, effective_date = @pr_eff,
                updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_promotion] (request_id, is_demotion, grade_id, job_level_id, designation_id, job_title_id,
                                          previous_salary, new_salary, effective_date, created_by)
            VALUES (@request_id, @pr_demotion, @pr_grade, @pr_level, @pr_desig, @pr_title, @pr_prev, @pr_salary, @pr_eff, @actor_user_id);
        DELETE [req].[req_promotion_benefit] WHERE request_id = @request_id;
        INSERT [req].[req_promotion_benefit] (request_id, pay_item_id, created_by)
        SELECT DISTINCT @request_id, TRY_CAST(j.value AS BIGINT), @actor_user_id FROM OPENJSON(@d, N'$.benefit_pay_item_ids') j;
        SELECT @from = @pr_eff, @to = @pr_eff, @days = NULL;
    END

    -- ------------------------------------------------------------------ transfer
    ELSE IF @kind = N'transfer'
    BEGIN
        DECLARE @t_loc BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.location_id') AS BIGINT),
                @t_branch BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.branch_id') AS BIGINT),
                @t_dept BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.department_id') AS BIGINT),
                @t_lm BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.line_manager_id') AS BIGINT),
                @t_fa BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.final_authority_id') AS BIGINT),
                @t_eff DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.effective_date') AS DATE), @from);
        IF @t_loc IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[location] WHERE id = @t_loc AND company_id = @company_id)
            THROW 50400, N'locationId|Location is required.', 1;
        IF @t_branch IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @t_branch AND company_id = @company_id)
            THROW 50400, N'branchId|Branch is required.', 1;
        IF NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @t_branch AND location_id = @t_loc)
            THROW 50400, N'branchId|This branch is not in the chosen location.', 1;
        IF @t_dept IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @t_dept AND company_id = @company_id)
            THROW 50400, N'departmentId|Department is required.', 1;
        IF @t_lm IS NULL OR @t_lm = @employee_id
           OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @t_lm AND company_id = @company_id AND status <> N'left')
            THROW 50400, N'lineManagerId|Choose a line manager other than the employee.', 1;
        IF @t_fa IS NULL OR @t_fa = @employee_id
           OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @t_fa AND company_id = @company_id AND status <> N'left')
            THROW 50400, N'finalAuthorityId|Choose a final authority other than the employee.', 1;
        IF @t_eff IS NULL
            THROW 50400, N'effectiveDate|Effective date is required.', 1;
        IF EXISTS (SELECT 1 FROM @live WHERE status IN (N'pending', N'cancelling'))
            THROW 50409, N'employeeId|TRANSFER_OPEN|This employee already has a transfer request waiting.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_transfer] WHERE request_id = @request_id)
            UPDATE [req].[req_transfer]
            SET location_id = @t_loc, branch_id = @t_branch, department_id = @t_dept, line_manager_id = @t_lm,
                final_authority_id = @t_fa, effective_date = @t_eff, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_transfer] (request_id, location_id, branch_id, department_id, line_manager_id, final_authority_id,
                                         effective_date, created_by)
            VALUES (@request_id, @t_loc, @t_branch, @t_dept, @t_lm, @t_fa, @t_eff, @actor_user_id);
        SELECT @from = @t_eff, @to = @t_eff, @days = NULL;
    END

    -- ------------------------------------------------------------------ resignation
    ELSE IF @kind = N'resignation'
    BEGIN
        DECLARE @rs_type NVARCHAR(30) = JSON_VALUE(@d, N'$.resignation_type'),
                @rs_date DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.resignation_date') AS DATE), @from),
                @rs_lwd DATE = TRY_CAST(JSON_VALUE(@d, N'$.last_working_date') AS DATE),
                @rs_notice INT = TRY_CAST(JSON_VALUE(@d, N'$.notice_period_days') AS INT),
                @rs_serve BIT = ISNULL(TRY_CAST(JSON_VALUE(@d, N'$.serve_notice') AS BIT), 0);
        IF NULLIF(@rs_type, N'') IS NULL
            THROW 50400, N'resignationType|Type is required.', 1;
        IF @rs_date IS NULL
            THROW 50400, N'resignationDate|Resignation date is required.', 1;
        IF @rs_lwd IS NOT NULL AND @rs_lwd < @rs_date
            THROW 50400, N'lastWorkingDate|The last working date cannot be before the resignation date.', 1;
        IF @rs_notice IS NULL AND @rs_lwd IS NOT NULL
            SET @rs_notice = DATEDIFF(DAY, @rs_date, @rs_lwd);
        IF @rs_notice < 0
            THROW 50400, N'noticePeriodDays|Notice period cannot be negative.', 1;
        IF EXISTS (SELECT 1 FROM @live)
            THROW 50409, N'employeeId|RESIGNATION_OPEN|This employee already has a resignation in progress.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_resignation] WHERE request_id = @request_id)
            UPDATE [req].[req_resignation]
            SET resignation_type = @rs_type, resignation_date = @rs_date, last_working_date = @rs_lwd,
                notice_period_days = @rs_notice, serve_notice = @rs_serve, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_resignation] (request_id, resignation_type, resignation_date, last_working_date,
                                            notice_period_days, serve_notice, created_by)
            VALUES (@request_id, @rs_type, @rs_date, @rs_lwd, @rs_notice, @rs_serve, @actor_user_id);
        SELECT @from = @rs_date, @to = COALESCE(@rs_lwd, @rs_date), @days = NULL;
    END

    -- ------------------------------------------------------------------ loan and advance
    ELSE IF @kind = N'loan'
    BEGIN
        DECLARE @ln_type BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.loan_type_id') AS BIGINT),
                @ln_cat BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.loan_category_id') AS BIGINT),
                @ln_amount DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@d, N'$.amount_requested') AS DECIMAL(18,2)),
                @ln_required DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.required_date') AS DATE), @from),
                @ln_ext NVARCHAR(20) = JSON_VALUE(@d, N'$.extension_no'),
                @ln_active BIT, @ln_name NVARCHAR(200), @ln_guarantor BIT, @ln_min_exp INT, @ln_gap INT,
                @ln_emp_type BIGINT;
        SELECT @ln_name = name, @ln_active = is_active, @ln_guarantor = guarantor_required,
               @ln_min_exp = min_experience_months, @ln_gap = gap_between_requests_months
        FROM [loan].[loan_type] WHERE id = @ln_type AND company_id = @company_id;
        IF @ln_name IS NULL
            THROW 50400, N'loanTypeId|Loan & advance type is required.', 1;
        IF @ln_active = 0
            THROW 50400, N'loanTypeId|This loan & advance type is not active.', 1;
        IF @ln_cat IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [loan].[loan_category] WHERE id = @ln_cat AND company_id = @company_id AND is_active = 1)
            THROW 50400, N'loanCategoryId|Category not found or not active.', 1;
        IF @ln_amount IS NULL OR @ln_amount <= 0
            THROW 50400, N'amountRequested|Required amount must be more than zero.', 1;
        IF @ln_required IS NULL
            THROW 50400, N'requiredDate|Required date is required.', 1;

        SET @ln_emp_type = (SELECT employment_type_id FROM [hr].[employee] WHERE id = @employee_id);
        IF EXISTS (SELECT 1 FROM [loan].[loan_type_employment_type] WHERE loan_type_id = @ln_type)
           AND NOT EXISTS (SELECT 1 FROM [loan].[loan_type_employment_type] WHERE loan_type_id = @ln_type AND employment_type_id = @ln_emp_type)
            THROW 50400, N'loanTypeId|LOAN_NOT_ELIGIBLE|This loan & advance type is not offered for the employee''s contract type.', 1;
        IF ISNULL(@ln_min_exp, 0) > 0 AND (@join IS NULL OR DATEDIFF(MONTH, @join, @today) < @ln_min_exp)
        BEGIN
            SET @msg = N'loanTypeId|LOAN_NOT_ELIGIBLE|This loan & advance type needs ' + CONVERT(NVARCHAR(10), @ln_min_exp) + N' months of service.';
            THROW 50400, @msg, 1;
        END
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[req_loan] l ON l.request_id = v.id
                   WHERE l.loan_type_id = @ln_type AND v.status IN (N'pending', N'cancelling'))
            THROW 50409, N'loanTypeId|LOAN_PENDING|A request for this loan & advance type is already waiting.', 1;
        IF ISNULL(@ln_gap, 0) > 0 AND EXISTS (SELECT 1 FROM @live v JOIN [req].[request] r ON r.id = v.id
                                             JOIN [req].[req_loan] l ON l.request_id = v.id
                                             WHERE l.loan_type_id = @ln_type AND r.submitted_at > DATEADD(MONTH, -@ln_gap, @now))
        BEGIN
            SET @msg = N'loanTypeId|LOAN_GAP|Requests for this type must be ' + CONVERT(NVARCHAR(10), @ln_gap) + N' months apart.';
            THROW 50409, @msg, 1;
        END
        IF @ln_guarantor = 1 AND NOT EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.guarantors'))
            THROW 50400, N'guarantors|A guarantor is required for this loan & advance type.', 1;
        IF EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.guarantors') WITH (file_id BIGINT N'$.file_id') g
                   WHERE g.file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, g.file_id)))
            THROW 50400, N'guarantors|A guarantor''s file was not found. Upload it again.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_loan] WHERE request_id = @request_id)
            UPDATE [req].[req_loan]
            SET loan_type_id = @ln_type, loan_category_id = @ln_cat, amount_requested = @ln_amount,
                required_date = @ln_required, extension_no = @ln_ext, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_loan] (request_id, loan_type_id, loan_category_id, amount_requested, required_date, extension_no, created_by)
            VALUES (@request_id, @ln_type, @ln_cat, @ln_amount, @ln_required, @ln_ext, @actor_user_id);

        DELETE [req].[loan_guarantor] WHERE request_id = @request_id;
        INSERT [req].[loan_guarantor] (request_id, name, cnic, known_since, relationship, extension_no, description, file_id,
                                       created_by)
        SELECT @request_id, g.name, g.cnic, g.known_since, g.relationship, g.extension_no, g.description, g.file_id, @actor_user_id
        FROM OPENJSON(@d, N'$.guarantors') WITH (
            name NVARCHAR(200) N'$.name', cnic NVARCHAR(15) N'$.cnic', known_since DATE N'$.known_since',
            relationship NVARCHAR(200) N'$.relationship', extension_no NVARCHAR(20) N'$.extension_no',
            description NVARCHAR(MAX) N'$.description', file_id BIGINT N'$.file_id') g;
        SELECT @from = @ln_required, @to = @ln_required, @days = NULL;
    END

    -- ------------------------------------------------------------------ travel
    ELSE IF @kind = N'travel'
    BEGIN
        DECLARE @tr_purpose NVARCHAR(500) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.purpose'))), N''),
                @tr_advance BIT = ISNULL(TRY_CAST(JSON_VALUE(@d, N'$.advance_required') AS BIT), 0),
                @tr_from DATE, @tr_to DATE;
        IF @tr_purpose IS NULL
            THROW 50400, N'purpose|Purpose is required.', 1;
        IF @tr_advance = 1 AND NOT EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.advances'))
            THROW 50400, N'advances|Add the advance amount, or untick Advance Required.', 1;
        IF NOT EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.legs'))
            THROW 50400, N'legs|Add at least one travel detail.', 1;

        DECLARE @legs TABLE (travel_type NVARCHAR(30), from_place NVARCHAR(200), to_place NVARCHAR(200), travel_mode NVARCHAR(30),
                             distance_km DECIMAL(9,2), depart_at DATETIME2(0), arrive_at DATETIME2(0), stay_required BIT);
        INSERT @legs
        SELECT travel_type, from_place, to_place, travel_mode, distance_km, depart_at, arrive_at, ISNULL(stay_required, 0)
        FROM OPENJSON(@d, N'$.legs') WITH (
            travel_type NVARCHAR(30) N'$.travel_type', from_place NVARCHAR(200) N'$.from_place', to_place NVARCHAR(200) N'$.to_place',
            travel_mode NVARCHAR(30) N'$.travel_mode', distance_km DECIMAL(9,2) N'$.distance_km', depart_at DATETIME2(0) N'$.depart_at',
            arrive_at DATETIME2(0) N'$.arrive_at', stay_required BIT N'$.stay_required');
        IF EXISTS (SELECT 1 FROM @legs WHERE depart_at IS NULL OR arrive_at IS NULL OR arrive_at <= depart_at)
            THROW 50400, N'legs|Each travel detail needs a departure before its arrival.', 1;
        IF EXISTS (SELECT 1 FROM @legs a JOIN @legs b ON a.depart_at < b.depart_at AND a.arrive_at > b.depart_at)
            THROW 50400, N'legs|Travel details overlap each other.', 1;
        IF EXISTS (SELECT 1 FROM @legs WHERE stay_required = 1) AND NOT EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.stays'))
            THROW 50400, N'stays|A stay is required: add the hotel booking.', 1;
        SELECT @tr_from = MIN(CAST(depart_at AS DATE)), @tr_to = MAX(CAST(arrive_at AS DATE)) FROM @legs;
        IF EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.stays') WITH (from_date DATE N'$.from_date', to_date DATE N'$.to_date') s
                   WHERE s.from_date IS NULL OR s.to_date IS NULL OR s.to_date < s.from_date
                      OR s.from_date < @tr_from OR s.to_date > @tr_to)
            THROW 50400, N'stays|Each stay must fall inside the trip.', 1;
        IF EXISTS (SELECT 1 FROM @live v WHERE v.from_date <= @tr_to AND v.to_date >= @tr_from)
            THROW 50409, N'legs|TRAVEL_OVERLAP|Another travel request already covers these dates.', 1;
        IF EXISTS (SELECT 1 FROM OPENJSON(@d, N'$.tickets') WITH (file_id BIGINT N'$.file_id') k
                   WHERE k.file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, k.file_id)))
            THROW 50400, N'tickets|A ticket file was not found. Upload it again.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_travel] WHERE request_id = @request_id)
            UPDATE [req].[req_travel]
            SET purpose = @tr_purpose, extension_no = JSON_VALUE(@d, N'$.extension_no'), alt_phone = JSON_VALUE(@d, N'$.alt_phone'),
                advance_required = @tr_advance, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_travel] (request_id, purpose, extension_no, alt_phone, advance_required, created_by)
            VALUES (@request_id, @tr_purpose, JSON_VALUE(@d, N'$.extension_no'), JSON_VALUE(@d, N'$.alt_phone'), @tr_advance, @actor_user_id);

        DELETE [req].[travel_advance] WHERE request_id = @request_id;
        DELETE [req].[travel_leg] WHERE request_id = @request_id;
        DELETE [req].[travel_stay] WHERE request_id = @request_id;
        DELETE [req].[travel_ticket] WHERE request_id = @request_id;
        IF @tr_advance = 1
            INSERT [req].[travel_advance] (request_id, amount, currency, created_by)
            SELECT @request_id, a.amount, a.currency, @actor_user_id
            FROM OPENJSON(@d, N'$.advances') WITH (amount DECIMAL(18,2) N'$.amount', currency CHAR(3) N'$.currency') a;
        INSERT [req].[travel_leg] (request_id, travel_type, from_place, to_place, travel_mode, distance_km, depart_at, arrive_at,
                                   stay_required, created_by)
        SELECT @request_id, travel_type, from_place, to_place, travel_mode, distance_km, depart_at, arrive_at, stay_required, @actor_user_id
        FROM @legs;
        INSERT [req].[travel_stay] (request_id, stay_type, address, city, from_date, to_date, nights, phone, email, created_by)
        SELECT @request_id, s.stay_type, s.address, s.city, s.from_date, s.to_date,
               ISNULL(s.nights, DATEDIFF(DAY, s.from_date, s.to_date)), s.phone, s.email, @actor_user_id
        FROM OPENJSON(@d, N'$.stays') WITH (
            stay_type NVARCHAR(30) N'$.stay_type', address NVARCHAR(500) N'$.address', city NVARCHAR(200) N'$.city',
            from_date DATE N'$.from_date', to_date DATE N'$.to_date', nights INT N'$.nights', phone NVARCHAR(30) N'$.phone',
            email NVARCHAR(254) N'$.email') s;
        INSERT [req].[travel_ticket] (request_id, ticket_no, travel_class, from_place, to_place, travel_at, description, file_id,
                                      created_by)
        SELECT @request_id, k.ticket_no, k.travel_class, k.from_place, k.to_place, k.travel_at, k.description, k.file_id, @actor_user_id
        FROM OPENJSON(@d, N'$.tickets') WITH (
            ticket_no NVARCHAR(50) N'$.ticket_no', travel_class NVARCHAR(30) N'$.travel_class', from_place NVARCHAR(200) N'$.from_place',
            to_place NVARCHAR(200) N'$.to_place', travel_at DATETIME2(0) N'$.travel_at', description NVARCHAR(MAX) N'$.description',
            file_id BIGINT N'$.file_id') k;
        SELECT @from = @tr_from, @to = @tr_to, @days = DATEDIFF(DAY, @tr_from, @tr_to) + 1;
    END

    -- ------------------------------------------------------------------ expense (Work Expense / Claim Expense)
    -- One request carries the claims prepared together ("Generate Claim", then "Submit All").
    ELSE IF @kind = N'expense'
    BEGIN
        DECLARE @ex_lines TABLE (line_no INT PRIMARY KEY, title NVARCHAR(200), claim_date DATE, expense_category_id BIGINT,
                                 amount DECIMAL(18,2), description NVARCHAR(MAX), file_id BIGINT);
        DECLARE @ex_msg NVARCHAR(400), @ex_currency CHAR(3) = (SELECT currency FROM [org].[company] WHERE id = @company_id),
                @ex_total DECIMAL(18,2);
        INSERT @ex_lines (line_no, title, claim_date, expense_category_id, amount, description, file_id)
        SELECT CAST(j.[key] AS INT) + 1, NULLIF(LTRIM(RTRIM(x.title)), N''), COALESCE(x.claim_date, @today),
               x.expense_category_id, x.amount, NULLIF(LTRIM(RTRIM(x.description)), N''), x.file_id
        FROM OPENJSON(@d, N'$.lines') j
        CROSS APPLY OPENJSON(j.[value]) WITH (
            title NVARCHAR(200) N'$.title', claim_date DATE N'$.claim_date', expense_category_id BIGINT N'$.expense_category_id',
            amount DECIMAL(18,2) N'$.amount', description NVARCHAR(MAX) N'$.description', file_id BIGINT N'$.file_id') x;

        IF NOT EXISTS (SELECT 1 FROM @ex_lines)
            THROW 50400, N'lines|Add at least one claim.', 1;
        IF EXISTS (SELECT 1 FROM @ex_lines WHERE title IS NULL)
            THROW 50400, N'lines|Each claim needs a title.', 1;
        IF EXISTS (SELECT 1 FROM @ex_lines WHERE description IS NULL)
            THROW 50400, N'lines|Each claim needs a description.', 1;
        IF EXISTS (SELECT 1 FROM @ex_lines WHERE amount IS NULL OR amount <= 0)
            THROW 50400, N'lines|Each claim needs an amount more than zero.', 1;
        IF EXISTS (SELECT 1 FROM @ex_lines WHERE claim_date > @today)
            THROW 50400, N'lines|A claim date cannot be in the future.', 1;
        IF EXISTS (SELECT 1 FROM @ex_lines x WHERE NOT EXISTS (
                       SELECT 1 FROM [req].[expense_category] c
                       WHERE c.id = x.expense_category_id AND c.company_id = @company_id AND c.is_active = 1))
            THROW 50400, N'lines|Choose an active expense category for each claim.', 1;
        SELECT TOP (1) @ex_msg = N'lines|EXPENSE_OVER_LIMIT|' + x.title + N': ' + c.name + N' claims may be at most '
                                 + CONVERT(NVARCHAR(30), c.max_amount) + N'.'
        FROM @ex_lines x JOIN [req].[expense_category] c ON c.id = x.expense_category_id
        WHERE c.max_amount IS NOT NULL AND x.amount > c.max_amount
        ORDER BY x.line_no;
        IF @ex_msg IS NOT NULL
            THROW 50400, @ex_msg, 1;
        SELECT TOP (1) @ex_msg = N'lines|EXPENSE_RECEIPT_REQUIRED|' + x.title + N': attach the receipt (' + c.name
                                 + N' claims need one).'
        FROM @ex_lines x JOIN [req].[expense_category] c ON c.id = x.expense_category_id
        WHERE c.receipt_required = 1 AND x.file_id IS NULL
        ORDER BY x.line_no;
        IF @ex_msg IS NOT NULL
            THROW 50400, @ex_msg, 1;
        IF EXISTS (SELECT 1 FROM @ex_lines x WHERE x.file_id IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, x.file_id)))
            THROW 50400, N'lines|A receipt file was not found. Upload it again.', 1;
        -- The same claim twice: same category, date and amount in another live expense request.
        IF EXISTS (SELECT 1 FROM @ex_lines x
                   JOIN [req].[expense_line] l ON l.expense_category_id = x.expense_category_id
                                              AND l.claim_date = x.claim_date AND l.amount = x.amount
                   JOIN @live v ON v.id = l.request_id)
            THROW 50409, N'lines|EXPENSE_DUPLICATE|A claim with the same category, date and amount is already in another expense request.', 1;

        SET @ex_total = (SELECT SUM(amount) FROM @ex_lines);
        IF EXISTS (SELECT 1 FROM [req].[req_expense] WHERE request_id = @request_id)
            UPDATE [req].[req_expense]
            SET total_amount = @ex_total, approved_amount = NULL, currency = ISNULL(currency, @ex_currency),
                updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_expense] (request_id, currency, total_amount, created_by)
            VALUES (@request_id, @ex_currency, @ex_total, @actor_user_id);

        DELETE [req].[expense_line] WHERE request_id = @request_id;
        INSERT [req].[expense_line] (request_id, line_no, title, claim_date, expense_category_id, amount, description, file_id,
                                     created_by)
        SELECT @request_id, line_no, title, claim_date, expense_category_id, amount, description, file_id, @actor_user_id
        FROM @ex_lines;
        SELECT @from = MIN(claim_date), @to = MAX(claim_date), @days = NULL FROM @ex_lines;
    END

    -- ------------------------------------------------------------------ air ticket
    ELSE IF @kind = N'air_ticket'
    BEGIN
        DECLARE @at_title NVARCHAR(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.title'))), N''),
                @at_claim DATE = COALESCE(TRY_CAST(JSON_VALUE(@d, N'$.claim_date') AS DATE), @today),
                @at_travel DATE = TRY_CAST(JSON_VALUE(@d, N'$.travel_date') AS DATE),
                @at_amount DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@d, N'$.amount') AS DECIMAL(18,2)),
                @at_file BIGINT = TRY_CAST(JSON_VALUE(@d, N'$.file_id') AS BIGINT),
                @at_from NVARCHAR(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.from_place'))), N''),
                @at_to NVARCHAR(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.to_place'))), N''),
                @at_desc NVARCHAR(MAX) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.description'))), N''),
                @at_currency CHAR(3) = (SELECT currency FROM [org].[company] WHERE id = @company_id);
        IF @at_title IS NULL
            THROW 50400, N'title|Title is required.', 1;
        IF @at_travel IS NULL
            THROW 50400, N'travelDate|Travel date is required.', 1;
        IF @at_claim > @today
            THROW 50400, N'claimDate|The claim date cannot be in the future.', 1;
        IF @at_amount IS NULL OR @at_amount <= 0
            THROW 50400, N'amount|The ticket amount must be more than zero.', 1;
        IF @at_file IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @at_file))
            THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
        IF EXISTS (SELECT 1 FROM @live v JOIN [req].[req_air_ticket] a ON a.request_id = v.id WHERE a.travel_date = @at_travel)
            THROW 50409, N'travelDate|AIR_TICKET_DUPLICATE|Another air ticket claim already covers this travel date.', 1;

        IF EXISTS (SELECT 1 FROM [req].[req_air_ticket] WHERE request_id = @request_id)
            UPDATE [req].[req_air_ticket]
            SET title = @at_title, claim_date = @at_claim, travel_date = @at_travel, from_place = @at_from, to_place = @at_to,
                amount = @at_amount, approved_amount = NULL, currency = ISNULL(currency, @at_currency), description = @at_desc,
                file_id = @at_file, updated_at = @now, updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_air_ticket] (request_id, title, claim_date, travel_date, from_place, to_place, amount, currency,
                                           description, file_id, created_by)
            VALUES (@request_id, @at_title, @at_claim, @at_travel, @at_from, @at_to, @at_amount, @at_currency, @at_desc,
                    @at_file, @actor_user_id);
        SELECT @from = @at_travel, @to = @at_travel, @days = NULL;
    END

    -- ------------------------------------------------------------------ requisition
    ELSE IF @kind = N'requisition'
    BEGIN
        DECLARE @rq_title NVARCHAR(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.title'))), N''),
                @rq_type NVARCHAR(30) = JSON_VALUE(@d, N'$.requisition_type'),
                @rq_needed DATE = TRY_CAST(JSON_VALUE(@d, N'$.needed_by_date') AS DATE),
                @rq_place NVARCHAR(200) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@d, N'$.delivery_location'))), N''),
                @rq_currency CHAR(3) = (SELECT currency FROM [org].[company] WHERE id = @company_id),
                @rq_submitted DATE = (SELECT CAST(submitted_at AS DATE) FROM [req].[request] WHERE id = @request_id),
                @rq_total DECIMAL(18,2);
        DECLARE @rq_lines TABLE (line_no INT PRIMARY KEY, item_name NVARCHAR(200), quantity DECIMAL(18,2), unit NVARCHAR(200),
                                 estimated_unit_cost DECIMAL(18,2), description NVARCHAR(MAX));
        INSERT @rq_lines (line_no, item_name, quantity, unit, estimated_unit_cost, description)
        SELECT CAST(j.[key] AS INT) + 1, NULLIF(LTRIM(RTRIM(x.item_name)), N''), x.quantity, NULLIF(LTRIM(RTRIM(x.unit)), N''),
               x.estimated_unit_cost, NULLIF(LTRIM(RTRIM(x.description)), N'')
        FROM OPENJSON(@d, N'$.lines') j
        CROSS APPLY OPENJSON(j.[value]) WITH (
            item_name NVARCHAR(200) N'$.item_name', quantity DECIMAL(18,2) N'$.quantity', unit NVARCHAR(200) N'$.unit',
            estimated_unit_cost DECIMAL(18,2) N'$.estimated_unit_cost', description NVARCHAR(MAX) N'$.description') x;

        IF @rq_title IS NULL
            THROW 50400, N'title|Title is required.', 1;
        IF @rq_type IS NULL OR @rq_type NOT IN (N'stationery', N'it_equipment', N'furniture', N'asset', N'consumable',
                                                 N'service', N'other')
            THROW 50400, N'requisitionType|Choose what kind of requisition this is.', 1;
        IF @rq_needed IS NULL
            THROW 50400, N'neededByDate|Needed-by date is required.', 1;
        IF @rq_needed < ISNULL(@rq_submitted, @today)
            THROW 50400, N'neededByDate|The needed-by date cannot be before the request date.', 1;
        IF NOT EXISTS (SELECT 1 FROM @rq_lines)
            THROW 50400, N'lines|Add at least one item.', 1;
        IF EXISTS (SELECT 1 FROM @rq_lines WHERE item_name IS NULL OR quantity IS NULL OR quantity <= 0)
            THROW 50400, N'lines|Each item needs a name and a quantity more than zero.', 1;
        IF EXISTS (SELECT 1 FROM @rq_lines WHERE estimated_unit_cost < 0)
            THROW 50400, N'lines|An estimated cost cannot be below zero.', 1;

        SET @rq_total = (SELECT SUM(quantity * estimated_unit_cost) FROM @rq_lines WHERE estimated_unit_cost IS NOT NULL);
        IF EXISTS (SELECT 1 FROM [req].[req_requisition] WHERE request_id = @request_id)
            UPDATE [req].[req_requisition]
            SET title = @rq_title, requisition_type = @rq_type, needed_by_date = @rq_needed, delivery_location = @rq_place,
                estimated_amount = @rq_total, currency = ISNULL(currency, @rq_currency), updated_at = @now,
                updated_by = @actor_user_id
            WHERE request_id = @request_id;
        ELSE
            INSERT [req].[req_requisition] (request_id, title, requisition_type, needed_by_date, delivery_location,
                                            estimated_amount, currency, created_by)
            VALUES (@request_id, @rq_title, @rq_type, @rq_needed, @rq_place, @rq_total, @rq_currency, @actor_user_id);

        DELETE [req].[requisition_line] WHERE request_id = @request_id;
        INSERT [req].[requisition_line] (request_id, line_no, item_name, quantity, unit, estimated_unit_cost, description,
                                         created_by)
        SELECT @request_id, line_no, item_name, quantity, unit, estimated_unit_cost, description, @actor_user_id
        FROM @rq_lines;
        SELECT @from = @rq_needed, @to = @rq_needed, @days = NULL;
    END

    -- Days of a multi-day request.
    IF @kind IN (N'leave', N'work_from_home', N'rest_day')
    BEGIN
        DELETE [req].[request_day] WHERE request_id = @request_id;
        INSERT [req].[request_day] (request_id, request_date, schedule_id, created_by)
        SELECT @request_id, request_date, schedule_id, @actor_user_id FROM @dates;
    END

    UPDATE [req].[request]
    SET from_date = @from, to_date = @to, days = @days, updated_at = @now, updated_by = @actor_user_id
    WHERE id = @request_id;
END
