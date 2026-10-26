-- Builds att.timesheet_day (+ timesheet_flag, timesheet_break) for a company, an employee set and a date range,
-- set-based. Reads the planned day from scheduling (sch.fn_employee_day_schedule: shifts, rest days, holidays),
-- punches (att.punch), approved requests (leave, work from home, relaxation / official visit windows, overtime)
-- and the settings (core.company_setting modules 'attendance' and 'overtime').
--
-- Rules (comparison/03-attendance.md, "Time-sheet processing"):
--   * A day's punches are those between the midpoint to the neighbouring shifts (4 hours either side of a shift
--     when the neighbour has none), so overnight shifts work. Several shifts on a day are one span.
--   * Status, first match wins: HR mark, holiday (attendance exempt, rules match), rest day, full-day leave,
--     no shift (weekend), work from home, official visit without punches, no punches (yet to start / absent),
--     half-day leave (half day), worked below the short-day threshold (short day), present.
--   * Late = check-in after the expected start, less a relaxation window; up to the grace minutes it is grace,
--     not late. Early = check-out before the expected end, less a relaxation window. Flexible slots have neither.
--   * Overtime per the overtime settings; approved overtime = approved requests when approval is required.
--   * Days that are is_frozen are never written. Days that are is_manually_updated keep HR's times, mark and
--     breaks (only the minutes and flags are recomputed) unless @overwrite_manual = 1.
-- @include_request_id / @exclude_request_id let an approval effect count its request before (or a revert
-- after) the requests engine changes its status.
CREATE OR ALTER PROCEDURE [att].[usp_timesheet_process]
    @company_id         BIGINT,
    @actor_user_id      BIGINT = NULL,
    @from_date          DATE,
    @to_date            DATE,
    @employee_ids       NVARCHAR(MAX) = NULL,    -- JSON array of ids; NULL = every employee not left
    @permission_code    NVARCHAR(150) = NULL,    -- when given, only employees the actor reaches with it
    @overwrite_manual   BIT = 0,
    @include_request_id BIGINT = NULL,
    @exclude_request_id BIGINT = NULL,
    @quiet              BIT = 0,                 -- 1: no result set (when called from another procedure)
    @processed_days     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @from_date IS NULL
        THROW 50400, N'fromDate|From date is required.', 1;
    IF @to_date IS NULL
        THROW 50400, N'toDate|To date is required.', 1;
    IF @to_date < @from_date
        THROW 50400, N'toDate|The end date is before the start date.', 1;
    IF DATEDIFF(DAY, @from_date, @to_date) > 366
        THROW 50400, N'toDate|Process at most one year at a time.', 1;
    IF @employee_ids IS NOT NULL AND ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Employee ids are not valid.', 1;

    -- Settings; never saved = off / 0.
    DECLARE @ignore_type BIT, @cio_breaks BIT, @short_non_flex BIT, @min_workable INT, @grace INT,
            @ot_in BIT, @ot_out BIT, @ot_approval BIT, @ot_holiday BIT, @ot_after_duty BIT;
    SELECT
        @ignore_type    = ISNULL(MAX(CASE WHEN module = N'attendance' AND setting_key = N'ignore_punch_type' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @cio_breaks     = ISNULL(MAX(CASE WHEN module = N'attendance' AND setting_key = N'use_check_in_out_for_breaks' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @short_non_flex = ISNULL(MAX(CASE WHEN module = N'attendance' AND setting_key = N'short_duration_on_non_flexible' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @min_workable   = ISNULL(MAX(CASE WHEN module = N'attendance' AND setting_key = N'minimum_workable_minutes' THEN TRY_CONVERT(INT, setting_value) END), 0),
        @grace          = ISNULL(MAX(CASE WHEN module = N'attendance' AND setting_key = N'late_grace_minutes' THEN TRY_CONVERT(INT, setting_value) END), 0),
        @ot_in          = ISNULL(MAX(CASE WHEN module = N'overtime' AND setting_key = N'overtime_on_check_in' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @ot_out         = ISNULL(MAX(CASE WHEN module = N'overtime' AND setting_key = N'overtime_on_check_out' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @ot_approval    = ISNULL(MAX(CASE WHEN module = N'overtime' AND setting_key = N'overtime_approval_required' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @ot_holiday     = ISNULL(MAX(CASE WHEN module = N'overtime' AND setting_key = N'overtime_on_holidays' AND setting_value IN (N'true', N'1') THEN 1 END), 0),
        @ot_after_duty  = ISNULL(MAX(CASE WHEN module = N'overtime' AND setting_key = N'overtime_after_duty_duration' AND setting_value IN (N'true', N'1') THEN 1 END), 0)
    FROM [core].[company_setting]
    WHERE company_id = @company_id AND module IN (N'attendance', N'overtime');

    DECLARE @now DATETIME2(0) = [att].[fn_company_now](@company_id);
    DECLARE @today DATE = CAST(@now AS DATE);
    -- A week either side gives the punch windows their neighbours and the sandwich rule its context.
    DECLARE @ctx_from DATE = DATEADD(DAY, -7, @from_date), @ctx_to DATE = DATEADD(DAY, 7, @to_date);
    DECLARE @midnight TIME(0) = '00:00';

    CREATE TABLE #tsp_emp (
        employee_id BIGINT NOT NULL PRIMARY KEY, location_id BIGINT NULL, branch_id BIGINT NULL,
        religion NVARCHAR(200) NULL, country_id BIGINT NULL, state_id BIGINT NULL, city_id BIGINT NULL, has_period BIT NOT NULL);

    INSERT #tsp_emp (employee_id, location_id, branch_id, religion, country_id, state_id, city_id, has_period)
    SELECT e.id, e.location_id, e.branch_id, e.religion, b.country_id, b.state_id, b.city_id,
           CASE WHEN EXISTS (SELECT 1 FROM [hr].[employment_period] p WHERE p.employee_id = e.id) THEN 1 ELSE 0 END
    FROM [hr].[employee] e
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    WHERE e.company_id = @company_id
      AND (@employee_ids IS NULL OR e.id IN (SELECT TRY_CONVERT(BIGINT, value) FROM OPENJSON(@employee_ids)))
      AND (@employee_ids IS NOT NULL OR ISNULL(e.status, N'active') <> N'left')
      AND (@permission_code IS NULL
           OR e.id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code)));

    CREATE TABLE #tsp_day (
        employee_id BIGINT NOT NULL, work_date DATE NOT NULL, in_range BIT NOT NULL, employed BIT NOT NULL,
        schedule_id BIGINT NULL, sched_in DATETIME2(0) NULL, sched_out DATETIME2(0) NULL, planned INT NULL,
        is_flexible BIT NOT NULL DEFAULT 0, sched_wfh BIT NOT NULL DEFAULT 0,
        rest_day BIT NOT NULL DEFAULT 0, holiday BIT NOT NULL DEFAULT 0,
        leave_request_id BIGINT NULL, leave_type_id BIGINT NULL, leave_kind NVARCHAR(10) NULL,
        leave_start DATETIME2(0) NULL, leave_end DATETIME2(0) NULL,
        wfh BIT NOT NULL DEFAULT 0, ot_requested INT NULL,
        rx_start DATETIME2(0) NULL, rx_end DATETIME2(0) NULL, ov_start DATETIME2(0) NULL, ov_end DATETIME2(0) NULL,
        existing_id BIGINT NULL, existing_status NVARCHAR(30) NULL, frozen BIT NOT NULL DEFAULT 0,
        manual BIT NOT NULL DEFAULT 0, marked_status NVARCHAR(30) NULL,
        exp_in DATETIME2(0) NULL, exp_out DATETIME2(0) NULL, exp_minutes INT NULL,
        win_start DATETIME2(0) NULL, win_end DATETIME2(0) NULL,
        act_in DATETIME2(0) NULL, act_out DATETIME2(0) NULL, punch_count INT NOT NULL DEFAULT 0,
        c_in DATETIME2(0) NULL, c_out DATETIME2(0) NULL,
        break_minutes INT NOT NULL DEFAULT 0, worked INT NULL, shift_worked INT NULL,
        late INT NOT NULL DEFAULT 0, early INT NOT NULL DEFAULT 0, grace_used INT NOT NULL DEFAULT 0,
        waived INT NOT NULL DEFAULT 0, ot_before INT NOT NULL DEFAULT 0, ot_after INT NOT NULL DEFAULT 0,
        ot_approved INT NULL, missing_punch BIT NOT NULL DEFAULT 0, day_status NVARCHAR(30) NULL,
        write_row BIT NOT NULL DEFAULT 0, day_id BIGINT NULL,
        PRIMARY KEY (employee_id, work_date));

    ;WITH n AS (
        SELECT TOP (DATEDIFF(DAY, @ctx_from, @ctx_to) + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
        FROM sys.all_columns a CROSS JOIN sys.all_columns b
    )
    INSERT #tsp_day (employee_id, work_date, in_range, employed)
    SELECT e.employee_id, x.d,
           CASE WHEN x.d BETWEEN @from_date AND @to_date THEN 1 ELSE 0 END,
           CASE WHEN e.has_period = 0 OR EXISTS (
                    SELECT 1 FROM [hr].[employment_period] p
                    WHERE p.employee_id = e.employee_id AND (p.joining_date IS NULL OR p.joining_date <= x.d)
                      AND (p.end_date IS NULL OR p.end_date >= x.d)) THEN 1 ELSE 0 END
    FROM #tsp_emp e
    CROSS JOIN n
    CROSS APPLY (SELECT DATEADD(DAY, n.i, @ctx_from) AS d) x;

    -- The planned day from scheduling (sch.fn_employee_day_schedule): shifts, rest days, holidays.
    -- Several shifts on a day are one span from the first start to the last end.
    DECLARE @one_employee BIGINT = CASE WHEN (SELECT COUNT(*) FROM #tsp_emp) = 1 THEN (SELECT MIN(employee_id) FROM #tsp_emp) END;
    SELECT f.employee_id, f.work_date, f.schedule_id, f.start_at, f.end_at, f.planned_minutes, f.is_flexible, f.is_wfh,
           f.is_rest_day, f.holiday_exempt
    INTO #tsp_plan
    FROM [sch].[fn_employee_day_schedule](@company_id, @one_employee, @ctx_from, @ctx_to) f
    JOIN #tsp_emp e ON e.employee_id = f.employee_id;

    UPDATE d
    SET sched_in = s.s_in, sched_out = s.s_out, planned = s.planned, is_flexible = ISNULL(s.flex, 0),
        sched_wfh = ISNULL(s.wfh, 0), rest_day = s.rest, holiday = s.hol,
        schedule_id = (SELECT TOP 1 p.schedule_id FROM #tsp_plan p
                       WHERE p.employee_id = d.employee_id AND p.work_date = d.work_date AND p.schedule_id IS NOT NULL
                       ORDER BY p.start_at)
    FROM #tsp_day d
    CROSS APPLY (SELECT MIN(p.start_at) AS s_in, MAX(p.end_at) AS s_out, SUM(p.planned_minutes) AS planned,
                        MAX(CAST(p.is_flexible AS INT)) AS flex, MIN(CAST(p.is_wfh AS INT)) AS wfh,
                        MAX(CAST(p.is_rest_day AS INT)) AS rest,
                        MAX(CASE WHEN p.holiday_exempt = 1 THEN 1 ELSE 0 END) AS hol, COUNT(*) AS cnt
                 FROM #tsp_plan p
                 WHERE p.employee_id = d.employee_id AND p.work_date = d.work_date) s
    WHERE s.cnt > 0;

    -- Approved requests of these employees (cancelling ones still count until the cancellation is approved).
    CREATE TABLE #tsp_req (request_id BIGINT NOT NULL PRIMARY KEY, employee_id BIGINT NOT NULL, from_date DATE NULL,
                           to_date DATE NULL, type_code NVARCHAR(30) NULL);
    INSERT #tsp_req (request_id, employee_id, from_date, to_date, type_code)
    SELECT r.id, r.employee_id, r.from_date, ISNULL(r.to_date, r.from_date), rt.code
    FROM [req].[request] r
    JOIN #tsp_emp e ON e.employee_id = r.employee_id
    LEFT JOIN [req].[request_type] rt ON rt.id = r.request_type_id
    WHERE r.company_id = @company_id AND r.is_deleted = 0
      AND (r.status IN (N'approved', N'cancelling') OR r.id = @include_request_id)
      AND (@exclude_request_id IS NULL OR r.id <> @exclude_request_id);

    -- Leave: full day, half day (one date, under a day), short (is_short, with times).
    UPDATE d
    SET leave_request_id = x.request_id, leave_type_id = x.leave_type_id, leave_kind = x.kind,
        leave_start = CASE WHEN x.start_time IS NOT NULL
                           THEN DATEADD(SECOND, DATEDIFF(SECOND, @midnight, x.start_time), CAST(d.work_date AS DATETIME2(0))) END,
        leave_end = CASE WHEN x.end_time IS NOT NULL
                         THEN DATEADD(DAY, CASE WHEN x.end_time <= x.start_time THEN 1 ELSE 0 END,
                              DATEADD(SECOND, DATEDIFF(SECOND, @midnight, x.end_time), CAST(d.work_date AS DATETIME2(0)))) END
    FROM #tsp_day d
    CROSS APPLY (
        SELECT TOP 1 r.request_id, l.leave_type_id, l.start_time, l.end_time,
               CASE WHEN l.is_short = 1 THEN N'short'
                    WHEN r.from_date = r.to_date AND ISNULL(l.days, 1) < 1 THEN N'half' ELSE N'full' END AS kind
        FROM #tsp_req r
        JOIN [req].[req_leave] l ON l.request_id = r.request_id
        WHERE r.employee_id = d.employee_id AND d.work_date BETWEEN r.from_date AND r.to_date
        ORDER BY CASE WHEN l.is_short = 0 AND NOT (r.from_date = r.to_date AND ISNULL(l.days, 1) < 1) THEN 0 ELSE 1 END,
                 r.request_id) x;

    UPDATE d SET wfh = 1
    FROM #tsp_day d
    WHERE d.sched_wfh = 1
       OR EXISTS (SELECT 1 FROM #tsp_req r
                  JOIN [req].[request_day] rd ON rd.request_id = r.request_id AND rd.request_date = d.work_date
                  WHERE r.employee_id = d.employee_id AND r.type_code IN (N'work_from_home', N'wfh'));

    UPDATE d SET ot_requested = x.minutes
    FROM #tsp_day d
    CROSS APPLY (SELECT SUM(COALESCE(o.approved_minutes, o.applied_minutes)) AS minutes
                 FROM #tsp_req r JOIN [req].[req_overtime] o ON o.request_id = r.request_id
                 WHERE r.employee_id = d.employee_id AND o.overtime_date = d.work_date) x
    WHERE x.minutes IS NOT NULL;

    -- What is already stored: frozen days stay as they are; manual days keep HR's inputs.
    UPDATE d
    SET existing_id = t.id, existing_status = t.day_status, frozen = t.is_frozen,
        manual = CASE WHEN t.is_manually_updated = 1 AND @overwrite_manual = 0 THEN 1 ELSE 0 END,
        marked_status = CASE WHEN t.is_manually_updated = 1 AND @overwrite_manual = 0 THEN t.marked_status END,
        exp_in = CASE WHEN t.is_manually_updated = 1 AND @overwrite_manual = 0 THEN t.expected_in END,
        exp_out = CASE WHEN t.is_manually_updated = 1 AND @overwrite_manual = 0 THEN t.expected_out END,
        act_in = CASE WHEN t.is_manually_updated = 1 AND @overwrite_manual = 0 THEN t.first_in END,
        act_out = CASE WHEN t.is_manually_updated = 1 AND @overwrite_manual = 0 THEN t.last_out END
    FROM #tsp_day d
    JOIN [att].[timesheet_day] t ON t.employee_id = d.employee_id AND t.work_date = d.work_date;

    -- Expected times: the shift, moved by a half or short leave that covers its start or its end.
    UPDATE #tsp_day SET exp_in = sched_in, exp_out = sched_out WHERE manual = 0;
    UPDATE #tsp_day
    SET exp_in = CASE WHEN leave_start <= exp_in AND leave_end > exp_in
                      THEN CASE WHEN leave_end < exp_out THEN leave_end ELSE exp_out END ELSE exp_in END,
        exp_out = CASE WHEN NOT (leave_start <= exp_in AND leave_end > exp_in) AND leave_start < exp_out AND leave_end >= exp_out
                       THEN CASE WHEN leave_start > exp_in THEN leave_start ELSE exp_in END ELSE exp_out END
    WHERE manual = 0 AND leave_kind IN (N'half', N'short') AND leave_start IS NOT NULL AND exp_in IS NOT NULL;
    UPDATE #tsp_day SET exp_in = NULL, exp_out = NULL WHERE exp_in IS NULL OR exp_out IS NULL;

    UPDATE #tsp_day
    SET exp_minutes = CASE
            WHEN exp_in IS NULL THEN NULL
            WHEN is_flexible = 1 THEN planned
            WHEN sched_in IS NOT NULL THEN DATEDIFF(MINUTE, exp_in, exp_out) - (DATEDIFF(MINUTE, sched_in, sched_out) - ISNULL(planned, DATEDIFF(MINUTE, sched_in, sched_out)))
            ELSE DATEDIFF(MINUTE, exp_in, exp_out) END;
    UPDATE #tsp_day SET exp_minutes = 0 WHERE exp_minutes < 0;
    UPDATE #tsp_day SET exp_minutes = exp_minutes / 2 WHERE leave_kind = N'half' AND leave_start IS NULL AND exp_minutes IS NOT NULL;

    -- Relaxation and official-visit windows; a window without times covers the whole expected span.
    UPDATE d
    SET rx_start = x.rx_s, rx_end = x.rx_e, ov_start = x.ov_s, ov_end = x.ov_e
    FROM #tsp_day d
    CROSS APPLY (
        SELECT MIN(CASE WHEN w.kind = N'relaxation' THEN v.s END) AS rx_s, MAX(CASE WHEN w.kind = N'relaxation' THEN v.e END) AS rx_e,
               MIN(CASE WHEN w.kind = N'official_visit' THEN v.s END) AS ov_s, MAX(CASE WHEN w.kind = N'official_visit' THEN v.e END) AS ov_e
        FROM #tsp_req r
        JOIN [req].[req_time_window] w ON w.request_id = r.request_id
        CROSS APPLY (SELECT CASE WHEN w.start_time IS NULL THEN d.exp_in
                                 ELSE DATEADD(SECOND, DATEDIFF(SECOND, @midnight, w.start_time), CAST(d.work_date AS DATETIME2(0))) END AS s) s0
        CROSS APPLY (SELECT s0.s,
                            CASE WHEN w.end_time IS NULL THEN d.exp_out
                                 ELSE DATEADD(DAY, CASE WHEN w.start_time IS NOT NULL AND w.end_time <= w.start_time THEN 1 ELSE 0 END,
                                      DATEADD(SECOND, DATEDIFF(SECOND, @midnight, w.end_time), CAST(d.work_date AS DATETIME2(0)))) END AS e) v
        WHERE r.employee_id = d.employee_id AND ISNULL(w.window_date, r.from_date) = d.work_date) x;

    -- Punch windows: the boundary between two days is the midpoint between their shifts; next to a day
    -- without a shift it is 4 hours from the shift (or midnight, whichever is further from the shift).
    ;WITH w AS (
        SELECT employee_id, work_date, exp_in, exp_out,
               LAG(exp_out) OVER (PARTITION BY employee_id ORDER BY work_date) AS p_out,
               LEAD(exp_in) OVER (PARTITION BY employee_id ORDER BY work_date) AS n_in,
               CAST(work_date AS DATETIME2(0)) AS day_start,
               CAST(DATEADD(DAY, 1, work_date) AS DATETIME2(0)) AS next_start,
               win_start, win_end
        FROM #tsp_day
    )
    UPDATE w
    SET win_start = CASE
            WHEN exp_in IS NOT NULL AND p_out IS NOT NULL THEN DATEADD(SECOND, DATEDIFF(SECOND, p_out, exp_in) / 2, p_out)
            WHEN exp_in IS NOT NULL THEN CASE WHEN DATEADD(HOUR, -4, exp_in) < day_start THEN DATEADD(HOUR, -4, exp_in) ELSE day_start END
            WHEN p_out IS NOT NULL THEN CASE WHEN DATEADD(HOUR, 4, p_out) > day_start THEN DATEADD(HOUR, 4, p_out) ELSE day_start END
            ELSE day_start END,
        win_end = CASE
            WHEN exp_out IS NOT NULL AND n_in IS NOT NULL THEN DATEADD(SECOND, DATEDIFF(SECOND, exp_out, n_in) / 2, exp_out)
            WHEN n_in IS NOT NULL THEN CASE WHEN DATEADD(HOUR, -4, n_in) < next_start THEN DATEADD(HOUR, -4, n_in) ELSE next_start END
            WHEN exp_out IS NOT NULL THEN CASE WHEN DATEADD(HOUR, 4, exp_out) > next_start THEN DATEADD(HOUR, 4, exp_out) ELSE next_start END
            ELSE next_start END;

    -- The day's punches (not for manual days: they keep HR's times).
    CREATE TABLE #tsp_punch (employee_id BIGINT NOT NULL, work_date DATE NOT NULL, punched_at DATETIME2(0) NOT NULL,
                             punch_type NVARCHAR(30) NOT NULL, break_type_id BIGINT NULL, rn INT NULL, cnt INT NULL,
                             nxt_at DATETIME2(0) NULL, nxt_type NVARCHAR(30) NULL);
    INSERT #tsp_punch (employee_id, work_date, punched_at, punch_type, break_type_id)
    SELECT d.employee_id, d.work_date, p.punched_at, p.punch_type, p.break_type_id
    FROM #tsp_day d
    JOIN [att].[punch] p ON p.employee_id = d.employee_id AND p.punched_at >= d.win_start AND p.punched_at < d.win_end
    WHERE p.company_id = @company_id AND p.is_ignored = 0 AND d.manual = 0;

    ;WITH o AS (
        SELECT rn, cnt, nxt_at, nxt_type,
               ROW_NUMBER() OVER (PARTITION BY employee_id, work_date ORDER BY punched_at, punch_type) AS rn2,
               COUNT(*) OVER (PARTITION BY employee_id, work_date) AS cnt2,
               LEAD(punched_at) OVER (PARTITION BY employee_id, work_date ORDER BY punched_at, punch_type) AS nxt_at2,
               LEAD(punch_type) OVER (PARTITION BY employee_id, work_date ORDER BY punched_at, punch_type) AS nxt_type2
        FROM #tsp_punch
    )
    UPDATE o SET rn = rn2, cnt = cnt2, nxt_at = nxt_at2, nxt_type = nxt_type2;

    UPDATE d
    SET punch_count = x.cnt,
        act_in = CASE WHEN @ignore_type = 1 THEN x.first_any ELSE x.first_in END,
        act_out = CASE WHEN @ignore_type = 1 THEN CASE WHEN x.cnt > 1 THEN x.last_any END ELSE x.last_out END
    FROM #tsp_day d
    CROSS APPLY (SELECT COUNT(*) AS cnt, MIN(punched_at) AS first_any, MAX(punched_at) AS last_any,
                        MIN(CASE WHEN punch_type = N'check_in' THEN punched_at END) AS first_in,
                        MAX(CASE WHEN punch_type = N'check_out' THEN punched_at END) AS last_out
                 FROM #tsp_punch p WHERE p.employee_id = d.employee_id AND p.work_date = d.work_date) x
    WHERE d.manual = 0;
    UPDATE #tsp_day SET act_out = NULL WHERE act_out <= act_in;
    UPDATE #tsp_day
    SET punch_count = CASE WHEN act_in IS NULL THEN 0 ELSE 1 END + CASE WHEN act_out IS NULL THEN 0 ELSE 1 END
    WHERE manual = 1;

    -- Breaks: break-out followed by break-in; with "Use Check IN/Check OUT for computing breaks" also a
    -- check-out followed by a check-in inside the day (or, ignoring punch types, every inner pair).
    CREATE TABLE #tsp_break (employee_id BIGINT NOT NULL, work_date DATE NOT NULL, break_type_id BIGINT NULL,
                             out_at DATETIME2(0) NOT NULL, in_at DATETIME2(0) NULL, minutes INT NULL);
    INSERT #tsp_break (employee_id, work_date, break_type_id, out_at, in_at, minutes)
    SELECT p.employee_id, p.work_date, p.break_type_id, p.punched_at, p.nxt_at, DATEDIFF(MINUTE, p.punched_at, p.nxt_at)
    FROM #tsp_punch p
    JOIN #tsp_day d ON d.employee_id = p.employee_id AND d.work_date = p.work_date
    WHERE p.nxt_at IS NOT NULL
      AND (   (@ignore_type = 0 AND p.punch_type = N'break_out' AND p.nxt_type = N'break_in')
           OR (@ignore_type = 0 AND @cio_breaks = 1 AND p.punch_type = N'check_out' AND p.nxt_type = N'check_in')
           OR (@ignore_type = 1 AND @cio_breaks = 1 AND p.rn % 2 = 0 AND p.rn < p.cnt))
      AND (d.act_in IS NULL OR p.punched_at >= d.act_in)
      AND (d.act_out IS NULL OR p.nxt_at <= d.act_out);

    INSERT #tsp_break (employee_id, work_date, break_type_id, out_at, in_at, minutes)
    SELECT d.employee_id, d.work_date, b.break_type_id, b.out_at, b.in_at, b.minutes
    FROM #tsp_day d
    JOIN [att].[timesheet_break] b ON b.timesheet_day_id = d.existing_id
    WHERE d.manual = 1;

    UPDATE d SET break_minutes = x.minutes
    FROM #tsp_day d
    CROSS APPLY (SELECT SUM(ISNULL(b.minutes, 0)) AS minutes FROM #tsp_break b
                 WHERE b.employee_id = d.employee_id AND b.work_date = d.work_date) x
    WHERE x.minutes IS NOT NULL;

    -- Times used for the minutes: the punches, widened by an official visit window.
    UPDATE #tsp_day
    SET c_in = CASE WHEN ov_start IS NOT NULL AND (act_in IS NULL OR ov_start < act_in) THEN ov_start ELSE act_in END,
        c_out = CASE WHEN ov_end IS NOT NULL AND (act_out IS NULL OR ov_end > act_out) THEN ov_end ELSE act_out END;

    UPDATE #tsp_day
    SET worked = CASE WHEN c_in IS NOT NULL AND c_out IS NOT NULL AND c_out > c_in
                      THEN DATEDIFF(MINUTE, c_in, c_out) - break_minutes END;
    UPDATE #tsp_day SET worked = 0 WHERE worked < 0;
    UPDATE #tsp_day
    SET shift_worked = CASE WHEN worked IS NULL OR exp_in IS NULL THEN NULL ELSE
            DATEDIFF(MINUTE, CASE WHEN c_in > exp_in THEN c_in ELSE exp_in END,
                             CASE WHEN c_out < exp_out THEN c_out ELSE exp_out END) - break_minutes END;
    UPDATE #tsp_day SET shift_worked = 0 WHERE shift_worked < 0;

    -- Late and early on working days with a fixed shift.
    UPDATE d
    SET late = CASE WHEN l.net > @grace THEN l.net ELSE 0 END,
        grace_used = CASE WHEN l.net > 0 AND l.net <= @grace THEN l.net ELSE 0 END,
        early = e.net,
        waived = l.waived + e.waived
    FROM #tsp_day d
    CROSS APPLY (SELECT CASE WHEN d.c_in > d.exp_in THEN DATEDIFF(MINUTE, d.exp_in, d.c_in) ELSE 0 END AS raw_late,
                        CASE WHEN d.c_out < d.exp_out THEN DATEDIFF(MINUTE, d.c_out, d.exp_out) ELSE 0 END AS raw_early) r
    CROSS APPLY (SELECT CASE WHEN d.rx_start <= d.exp_in AND d.rx_end > d.exp_in
                             THEN CASE WHEN DATEDIFF(MINUTE, d.exp_in, d.rx_end) < r.raw_late THEN DATEDIFF(MINUTE, d.exp_in, d.rx_end) ELSE r.raw_late END
                             ELSE 0 END AS waived) lw
    CROSS APPLY (SELECT r.raw_late - lw.waived AS net, lw.waived) l
    CROSS APPLY (SELECT CASE WHEN d.rx_start < d.exp_out AND d.rx_end >= d.exp_out
                             THEN CASE WHEN DATEDIFF(MINUTE, d.rx_start, d.exp_out) < r.raw_early THEN DATEDIFF(MINUTE, d.rx_start, d.exp_out) ELSE r.raw_early END
                             ELSE 0 END AS waived) ew
    CROSS APPLY (SELECT r.raw_early - ew.waived AS net, ew.waived) e
    WHERE d.exp_in IS NOT NULL AND d.is_flexible = 0 AND d.holiday = 0 AND d.rest_day = 0
      AND ISNULL(d.leave_kind, N'') <> N'full' AND NOT (ISNULL(d.leave_kind, N'') = N'half' AND d.leave_start IS NULL)
      AND d.wfh = 0 AND d.c_in IS NOT NULL;

    -- Overtime.
    UPDATE #tsp_day
    SET ot_before = CASE WHEN @ot_in = 1 AND is_flexible = 0 AND c_in < exp_in THEN DATEDIFF(MINUTE, c_in, exp_in) ELSE 0 END,
        ot_after = CASE WHEN @ot_out = 0 THEN 0
                        WHEN is_flexible = 1 THEN CASE WHEN worked > exp_minutes THEN worked - exp_minutes ELSE 0 END
                        WHEN c_out > exp_out THEN DATEDIFF(MINUTE, exp_out, c_out) ELSE 0 END
    WHERE exp_in IS NOT NULL AND holiday = 0 AND rest_day = 0 AND worked IS NOT NULL;
    UPDATE #tsp_day SET ot_before = 0, ot_after = 0
    WHERE @ot_after_duty = 1 AND exp_in IS NOT NULL AND holiday = 0 AND rest_day = 0 AND ISNULL(worked, 0) < ISNULL(exp_minutes, 0);
    -- Work on a day off (holiday, rest day, no shift) is overtime when "Is Overtime Applicable on Holidays" is on.
    UPDATE #tsp_day SET ot_before = 0, ot_after = CASE WHEN @ot_holiday = 1 THEN ISNULL(worked, 0) ELSE 0 END
    WHERE holiday = 1 OR rest_day = 1 OR exp_in IS NULL;
    UPDATE #tsp_day
    SET ot_approved = CASE WHEN @ot_approval = 1 THEN ISNULL(ot_requested, 0) ELSE ISNULL(ot_requested, ot_before + ot_after) END;

    -- Status.
    UPDATE #tsp_day
    SET day_status = CASE
            WHEN marked_status IS NOT NULL THEN marked_status
            WHEN holiday = 1 THEN N'holiday'
            WHEN rest_day = 1 THEN N'rest_day'
            WHEN leave_kind = N'full' THEN N'leave'
            WHEN exp_in IS NULL THEN N'weekend'
            WHEN wfh = 1 THEN N'wfh'
            WHEN punch_count = 0 AND ov_start IS NOT NULL THEN N'official_visit'
            WHEN punch_count = 0 THEN CASE WHEN work_date > @today OR (work_date = @today AND @now < exp_out)
                                           THEN N'yet_to_start' ELSE N'absent' END
            WHEN leave_kind = N'half' THEN N'half_day'
            WHEN c_out IS NOT NULL AND (is_flexible = 1 OR @short_non_flex = 1)
                 AND worked < CASE WHEN @min_workable > 0 THEN @min_workable ELSE ISNULL(exp_minutes, 0) END THEN N'short_day'
            ELSE N'present' END,
        missing_punch = CASE WHEN punch_count > 0 AND (act_in IS NULL OR act_out IS NULL) AND @now >= win_end
                             AND ov_start IS NULL THEN 1 ELSE 0 END;

    -- Sandwich: a day off between two leave days of sandwich leave types (the same type, or both across types).
    UPDATE d SET day_status = N'sandwich'
    FROM #tsp_day d
    CROSS APPLY (SELECT TOP 1 p.day_status, p.leave_type_id FROM #tsp_day p
                 WHERE p.employee_id = d.employee_id AND p.work_date < d.work_date
                   AND ISNULL(p.day_status, N'') NOT IN (N'weekend', N'rest_day', N'holiday', N'sandwich')
                 ORDER BY p.work_date DESC) prv
    CROSS APPLY (SELECT TOP 1 n.day_status, n.leave_type_id FROM #tsp_day n
                 WHERE n.employee_id = d.employee_id AND n.work_date > d.work_date
                   AND ISNULL(n.day_status, N'') NOT IN (N'weekend', N'rest_day', N'holiday', N'sandwich')
                 ORDER BY n.work_date) nxt
    JOIN [lv].[leave_type] lp ON lp.id = prv.leave_type_id
    JOIN [lv].[leave_type] ln ON ln.id = nxt.leave_type_id
    WHERE d.day_status IN (N'weekend', N'rest_day', N'holiday') AND d.marked_status IS NULL
      AND prv.day_status = N'leave' AND nxt.day_status = N'leave'
      AND lp.is_sandwich = 1 AND ln.is_sandwich = 1
      AND (lp.id = ln.id OR (lp.sandwich_across_types = 1 AND ln.sandwich_across_types = 1));

    -- Which rows are written: the range, plus stored neighbours whose sandwich state changed.
    UPDATE #tsp_day
    SET write_row = 1
    WHERE employed = 1 AND frozen = 0
      AND (in_range = 1
           OR (existing_id IS NOT NULL AND manual = 0 AND existing_status <> day_status
               AND (day_status = N'sandwich' OR existing_status = N'sandwich')));

    DECLARE @at DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        MERGE [att].[timesheet_day] WITH (HOLDLOCK) AS t
        USING (SELECT * FROM #tsp_day WHERE write_row = 1) AS s
            ON t.employee_id = s.employee_id AND t.work_date = s.work_date
        WHEN MATCHED AND t.is_frozen = 0 THEN UPDATE SET
            schedule_id = s.schedule_id, expected_in = s.exp_in, expected_out = s.exp_out, expected_minutes = s.exp_minutes,
            first_in = s.act_in, last_out = s.act_out, worked_minutes = s.worked, break_minutes = s.break_minutes,
            shift_worked_minutes = s.shift_worked, late_minutes = s.late, early_left_minutes = s.early,
            overtime_before_minutes = s.ot_before, overtime_after_minutes = s.ot_after,
            approved_overtime_minutes = s.ot_approved, grace_consumed_minutes = s.grace_used,
            day_status = s.day_status, marked_status = s.marked_status, leave_request_id = s.leave_request_id,
            is_manually_updated = s.manual, processed_at = @at, updated_at = @at, updated_by = @actor_user_id
        WHEN NOT MATCHED BY TARGET THEN INSERT
            (company_id, employee_id, work_date, schedule_id, expected_in, expected_out, expected_minutes, first_in, last_out,
             worked_minutes, break_minutes, shift_worked_minutes, late_minutes, early_left_minutes, overtime_before_minutes,
             overtime_after_minutes, approved_overtime_minutes, grace_consumed_minutes, day_status, marked_status,
             leave_request_id, is_manually_updated, processed_at, created_by)
        VALUES
            (@company_id, s.employee_id, s.work_date, s.schedule_id, s.exp_in, s.exp_out, s.exp_minutes, s.act_in, s.act_out,
             s.worked, s.break_minutes, s.shift_worked, s.late, s.early, s.ot_before, s.ot_after, s.ot_approved, s.grace_used,
             s.day_status, s.marked_status, s.leave_request_id, s.manual, @at, @actor_user_id);

        UPDATE d SET day_id = t.id
        FROM #tsp_day d
        JOIN [att].[timesheet_day] t ON t.employee_id = d.employee_id AND t.work_date = d.work_date
        WHERE d.write_row = 1;

        DELETE f FROM [att].[timesheet_flag] f JOIN #tsp_day d ON d.day_id = f.timesheet_day_id;

        INSERT [att].[timesheet_flag] (timesheet_day_id, flag, minutes, created_by)
        SELECT d.day_id, v.flag, v.minutes, @actor_user_id
        FROM #tsp_day d
        CROSS APPLY (VALUES
            (N'late', d.late, CASE WHEN d.late > 0 THEN 1 ELSE 0 END),
            (N'early', d.early, CASE WHEN d.early > 0 THEN 1 ELSE 0 END),
            (N'grace', d.grace_used, CASE WHEN d.grace_used > 0 THEN 1 ELSE 0 END),
            (N'overtime', d.ot_before + d.ot_after, CASE WHEN d.ot_before + d.ot_after > 0 THEN 1 ELSE 0 END),
            (N'missing_punch', NULL, CAST(d.missing_punch AS INT)),
            (N'relaxation', d.waived, CASE WHEN d.waived > 0 THEN 1 ELSE 0 END),
            (N'official_visit', DATEDIFF(MINUTE, d.ov_start, d.ov_end), CASE WHEN d.ov_start IS NOT NULL THEN 1 ELSE 0 END),
            (N'half_leave', NULL, CASE WHEN d.leave_kind = N'half' THEN 1 ELSE 0 END),
            (N'short_leave', DATEDIFF(MINUTE, d.leave_start, d.leave_end), CASE WHEN d.leave_kind = N'short' THEN 1 ELSE 0 END)
        ) v (flag, minutes, keep)
        WHERE d.day_id IS NOT NULL AND v.keep = 1;

        DELETE b FROM [att].[timesheet_break] b JOIN #tsp_day d ON d.day_id = b.timesheet_day_id WHERE d.manual = 0;

        INSERT [att].[timesheet_break] (timesheet_day_id, break_type_id, out_at, in_at, minutes, created_by)
        SELECT d.day_id, b.break_type_id, b.out_at, b.in_at, b.minutes, @actor_user_id
        FROM #tsp_break b
        JOIN #tsp_day d ON d.employee_id = b.employee_id AND d.work_date = b.work_date
        WHERE d.day_id IS NOT NULL AND d.manual = 0;

        SET @processed_days = (SELECT COUNT(*) FROM #tsp_day WHERE day_id IS NOT NULL);

        -- One summary event per run someone asked for (the Process button, @quiet = 0) or the nightly job
        -- (no actor). Re-processing after a punch, a day edit or a request is not announced.
        IF @quiet = 0 OR (@actor_user_id IS NULL AND @processed_days > 0)
        BEGIN
            DECLARE @ev_payload NVARCHAR(MAX) = (
                SELECT CONVERT(NVARCHAR(10), @from_date, 23) AS fromDate, CONVERT(NVARCHAR(10), @to_date, 23) AS toDate,
                       @processed_days AS processedDays, (SELECT COUNT(*) FROM #tsp_emp) AS employees,
                       CAST(ISNULL(@overwrite_manual, 0) AS BIT) AS overwriteManual,
                       CONVERT(NVARCHAR(30), @actor_user_id) AS processedBy,
                       CASE WHEN @actor_user_id IS NULL THEN N'scheduled' ELSE N'manual' END AS [trigger]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'attendance.timesheet_processed',
                 @entity_type = NULL, @entity_id = NULL, @payload = @ev_payload;
        END
    COMMIT;

    -- Warnings and penalties follow the new minutes (att.usp_warning_raise, owned by the warning module).
    -- @quiet keeps its result set out of this procedure's output (not INSERT ... EXEC: it notifies people).
    IF @processed_days > 0 AND OBJECT_ID(N'[att].[usp_warning_raise]', N'P') IS NOT NULL
       AND EXISTS (SELECT 1 FROM [att].[warning_policy] WHERE company_id = @company_id AND is_active = 1)
        EXEC [att].[usp_warning_raise] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @from_date = @from_date, @to_date = @to_date, @employee_id = @one_employee, @quiet = 1;
    IF @quiet = 0
        SELECT @processed_days AS processed_days, COUNT(*) AS employees FROM #tsp_emp;
END
