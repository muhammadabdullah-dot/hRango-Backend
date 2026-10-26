-- Time sheet (My / Subordinates / All), one day's detail, HR's edit of a day and its history.

-- Result set 1: total; result set 2: the page of days.
CREATE OR ALTER PROCEDURE [att].[usp_timesheet_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @tab             NVARCHAR(20) = N'all',      -- my, subordinates, all
    @from_date       DATE,
    @to_date         DATE,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @day_status      NVARCHAR(30) = NULL,
    @flag            NVARCHAR(30) = NULL,
    @time_slot_id    BIGINT = NULL,
    @employee_status NVARCHAR(30) = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    CREATE TABLE #tsl_emp (employee_id BIGINT PRIMARY KEY);
    INSERT #tsl_emp (employee_id)
    SELECT v.employee_id
    FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
    JOIN [hr].[employee] e ON e.id = v.employee_id
    WHERE (@tab <> N'my' OR v.employee_id = @me)
      AND (@tab <> N'subordinates' OR v.employee_id IN (SELECT employee_id FROM [att].[fn_team](@company_id, @actor_user_id)))
      AND (@employee_id IS NULL OR v.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@employee_status IS NULL OR e.status = @employee_status)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total
    FROM [att].[timesheet_day] t
    JOIN #tsl_emp x ON x.employee_id = t.employee_id
    LEFT JOIN [sch].[schedule] s ON s.id = t.schedule_id
    WHERE t.company_id = @company_id AND t.work_date BETWEEN @from_date AND @to_date
      AND (@day_status IS NULL OR t.day_status = @day_status)
      AND (@flag IS NULL OR EXISTS (SELECT 1 FROM [att].[timesheet_flag] f WHERE f.timesheet_day_id = t.id AND f.flag = @flag))
      AND (@time_slot_id IS NULL OR s.time_slot_id = @time_slot_id)
    OPTION (RECOMPILE);

    SELECT t.id, t.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, t.work_date, t.schedule_id, s.time_slot_id, ts.name AS time_slot_name,
           t.expected_in, t.expected_out, t.expected_minutes, t.first_in, t.last_out, t.worked_minutes, t.break_minutes,
           t.shift_worked_minutes, t.late_minutes, t.early_left_minutes, t.overtime_before_minutes, t.overtime_after_minutes,
           t.approved_overtime_minutes, t.grace_consumed_minutes, t.day_status, t.marked_status, t.leave_request_id,
           t.is_manually_updated, t.is_frozen, t.comments, t.processed_at,
           (SELECT STRING_AGG(f.flag, N',') FROM [att].[timesheet_flag] f WHERE f.timesheet_day_id = t.id) AS flags,
           (SELECT COUNT(*) FROM [att].[warning] w WHERE w.timesheet_day_id = t.id) AS warning_count,
           pen.penalty_type, pen.penalty_percentage,
           t.row_version
    FROM [att].[timesheet_day] t
    JOIN #tsl_emp x ON x.employee_id = t.employee_id
    JOIN [hr].[employee] e ON e.id = t.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [sch].[schedule] s ON s.id = t.schedule_id
    LEFT JOIN [sch].[time_slot] ts ON ts.id = s.time_slot_id
    OUTER APPLY (SELECT TOP 1 w.penalty_type, w.penalty_percentage FROM [att].[warning] w
                 WHERE w.timesheet_day_id = t.id AND w.penalty_type IS NOT NULL
                 ORDER BY w.penalty_percentage DESC) pen
    WHERE t.company_id = @company_id AND t.work_date BETWEEN @from_date AND @to_date
      AND (@day_status IS NULL OR t.day_status = @day_status)
      AND (@flag IS NULL OR EXISTS (SELECT 1 FROM [att].[timesheet_flag] f WHERE f.timesheet_day_id = t.id AND f.flag = @flag))
      AND (@time_slot_id IS NULL OR s.time_slot_id = @time_slot_id)
    ORDER BY t.work_date DESC, e.code, t.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One day. Processes it first when it has never been processed. Result sets: the day, its flags, its
-- breaks, and the punches around it (the "Logs" popup).
CREATE OR ALTER PROCEDURE [att].[usp_timesheet_day_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT,
    @work_date       DATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;

    IF NOT EXISTS (SELECT 1 FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND work_date = @work_date)
    BEGIN
        DECLARE @ids NVARCHAR(50) = N'[' + CONVERT(NVARCHAR(30), @employee_id) + N']';
        EXEC [att].[usp_timesheet_process] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @from_date = @work_date, @to_date = @work_date, @employee_ids = @ids, @quiet = 1;
    END

    DECLARE @id BIGINT = (SELECT id FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND work_date = @work_date
                          AND company_id = @company_id);
    IF @id IS NULL
        THROW 50404, N'No time sheet for this day (the employee was not employed then)', 1;

    SELECT t.id, t.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, t.work_date, t.schedule_id, s.time_slot_id, ts.name AS time_slot_name,
           t.expected_in, t.expected_out, t.expected_minutes, t.first_in, t.last_out, t.worked_minutes, t.break_minutes,
           t.shift_worked_minutes, t.late_minutes, t.early_left_minutes, t.overtime_before_minutes, t.overtime_after_minutes,
           t.approved_overtime_minutes, t.grace_consumed_minutes, t.day_status, t.marked_status, t.leave_request_id,
           t.is_manually_updated, t.is_frozen, t.comments, t.processed_at,
           (SELECT STRING_AGG(f.flag, N',') FROM [att].[timesheet_flag] f WHERE f.timesheet_day_id = t.id) AS flags,
           (SELECT COUNT(*) FROM [att].[warning] w WHERE w.timesheet_day_id = t.id) AS warning_count,
           pen.penalty_type, pen.penalty_percentage,
           t.row_version
    FROM [att].[timesheet_day] t
    JOIN [hr].[employee] e ON e.id = t.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [sch].[schedule] s ON s.id = t.schedule_id
    LEFT JOIN [sch].[time_slot] ts ON ts.id = s.time_slot_id
    OUTER APPLY (SELECT TOP 1 w.penalty_type, w.penalty_percentage FROM [att].[warning] w
                 WHERE w.timesheet_day_id = t.id AND w.penalty_type IS NOT NULL
                 ORDER BY w.penalty_percentage DESC) pen
    WHERE t.id = @id;

    SELECT flag, minutes FROM [att].[timesheet_flag] WHERE timesheet_day_id = @id ORDER BY flag;

    SELECT b.id, b.break_type_id, bt.name AS break_type_name, b.out_at, b.in_at, b.minutes
    FROM [att].[timesheet_break] b
    LEFT JOIN [sch].[break_type] bt ON bt.id = b.break_type_id
    WHERE b.timesheet_day_id = @id
    ORDER BY b.out_at;

    DECLARE @lo DATETIME2(0), @hi DATETIME2(0);
    SELECT @lo = DATEADD(HOUR, -4, COALESCE(CASE WHEN first_in < expected_in THEN first_in ELSE expected_in END, first_in, CAST(work_date AS DATETIME2(0)))),
           @hi = DATEADD(HOUR, 4, COALESCE(CASE WHEN last_out > expected_out THEN last_out ELSE expected_out END, last_out, CAST(DATEADD(DAY, 1, work_date) AS DATETIME2(0))))
    FROM [att].[timesheet_day] WHERE id = @id;

    SELECT p.id, p.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           p.punched_at, p.punch_type, p.break_type_id, bt.name AS break_type_name, p.source,
           p.device_id, dv.code AS device_code, dv.name AS device_name, p.latitude, p.longitude, p.ip_address,
           p.photo_file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = p.photo_file_id) AS photo_file_name,
           p.request_id, p.remarks, p.is_manually_updated, p.is_ignored,
           p.created_at, p.updated_at, p.row_version
    FROM [att].[punch] p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [sch].[break_type] bt ON bt.id = p.break_type_id
    LEFT JOIN [att].[device] dv ON dv.id = p.device_id
    WHERE p.employee_id = @employee_id AND p.punched_at >= @lo AND p.punched_at < @hi
    ORDER BY p.punched_at, p.id;
END
GO

-- HR's edit of a day: expected and actual times, a mark (absent, half day, short day), breaks and comments.
-- The day becomes "Manually Updated": processing keeps these inputs and only recomputes minutes and flags.
-- @breaks = [{"breakTypeId": 1, "outAt": "2026-01-05T13:00:00", "inAt": "2026-01-05T13:30:00"}]
CREATE OR ALTER PROCEDURE [att].[usp_timesheet_day_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT,
    @work_date       DATE,
    @expected_in     DATETIME2(0) = NULL,
    @expected_out    DATETIME2(0) = NULL,
    @first_in        DATETIME2(0) = NULL,
    @last_out        DATETIME2(0) = NULL,
    @marked_status   NVARCHAR(30) = NULL,
    @comments        NVARCHAR(MAX) = NULL,
    @breaks          NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8),
    @sent            NVARCHAR(400) = NULL   -- fields the client sent (comma separated, snake_case); NULL = all.
                                            -- A field not sent keeps its value; a field sent as null is cleared.
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;

    DECLARE @id BIGINT, @rv BINARY(8), @frozen BIT, @o_exp_in DATETIME2(0), @o_exp_out DATETIME2(0), @o_in DATETIME2(0),
            @o_out DATETIME2(0), @o_mark NVARCHAR(30), @o_comments NVARCHAR(MAX);
    SELECT @id = id, @rv = row_version, @frozen = is_frozen, @o_exp_in = expected_in, @o_exp_out = expected_out,
           @o_in = first_in, @o_out = last_out, @o_mark = marked_status, @o_comments = comments
    FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND work_date = @work_date AND company_id = @company_id;

    IF @id IS NULL
        THROW 50404, N'Time sheet day not found', 1;
    IF @sent IS NOT NULL
    BEGIN
        DECLARE @s TABLE (f NVARCHAR(50));
        INSERT @s SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@sent, N',');
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'expected_in') SET @expected_in = @o_exp_in;
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'expected_out') SET @expected_out = @o_exp_out;
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'first_in') SET @first_in = @o_in;
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'last_out') SET @last_out = @o_out;
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'marked_status') SET @marked_status = @o_mark;
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'comments') SET @comments = @o_comments;
        IF NOT EXISTS (SELECT 1 FROM @s WHERE f = N'breaks')
            SET @breaks = (SELECT break_type_id AS breakTypeId, out_at AS outAt, in_at AS inAt
                           FROM [att].[timesheet_break] WHERE timesheet_day_id = @id ORDER BY out_at
                           FOR JSON PATH, INCLUDE_NULL_VALUES);
    END
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this day. Reload it and try again', 1;
    IF @frozen = 1
        THROW 50409, N'workDate|DAY_FROZEN|This day is locked: payroll has used it.', 1;
    IF @marked_status IS NOT NULL AND @marked_status NOT IN (N'absent', N'half_day', N'short_day')
        THROW 50400, N'markedStatus|Mark must be absent, half day or short day.', 1;
    IF (@expected_in IS NULL AND @expected_out IS NOT NULL) OR (@expected_in IS NOT NULL AND @expected_out IS NULL)
       OR @expected_out <= @expected_in
        THROW 50400, N'expectedOut|Give both expected times, the end after the start.', 1;
    IF @last_out <= @first_in
        THROW 50400, N'lastOut|Check out must be after check in.', 1;
    IF (@first_in IS NOT NULL AND ABS(DATEDIFF(HOUR, CAST(@work_date AS DATETIME2(0)), @first_in)) > 36)
       OR (@last_out IS NOT NULL AND ABS(DATEDIFF(HOUR, CAST(@work_date AS DATETIME2(0)), @last_out)) > 48)
        THROW 50400, N'firstIn|The times must be on or next to the day being edited.', 1;
    IF @breaks IS NOT NULL AND ISJSON(@breaks) = 0
        THROW 50400, N'breaks|Breaks are not valid.', 1;

    DECLARE @b TABLE (break_type_id BIGINT, out_at DATETIME2(0), in_at DATETIME2(0));
    INSERT @b (break_type_id, out_at, in_at)
    SELECT break_type_id, out_at, in_at
    FROM OPENJSON(ISNULL(@breaks, N'[]')) WITH (break_type_id BIGINT '$.breakTypeId', out_at DATETIME2(0) '$.outAt', in_at DATETIME2(0) '$.inAt');
    IF EXISTS (SELECT 1 FROM @b WHERE out_at IS NULL OR in_at <= out_at)
        THROW 50400, N'breaks|Each break needs a break-out time, and its break-in after it.', 1;
    IF EXISTS (SELECT 1 FROM @b b WHERE b.break_type_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [sch].[break_type] t WHERE t.id = b.break_type_id AND t.company_id = @company_id))
        THROW 50400, N'breaks|Break type not found.', 1;

    DECLARE @o_breaks NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(break_type_id, N' ', CONVERT(NVARCHAR(16), out_at, 126), N'-', CONVERT(NVARCHAR(16), in_at, 126)), N'; ')
                                                 WITHIN GROUP (ORDER BY out_at)
                                       FROM [att].[timesheet_break] WHERE timesheet_day_id = @id);
    DECLARE @n_breaks NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(break_type_id, N' ', CONVERT(NVARCHAR(16), out_at, 126), N'-', CONVERT(NVARCHAR(16), in_at, 126)), N'; ')
                                                 WITHIN GROUP (ORDER BY out_at)
                                       FROM @b);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    DECLARE @changes TABLE (field_name NVARCHAR(100), old_value NVARCHAR(MAX), new_value NVARCHAR(MAX), is_time BIT);
    INSERT @changes
    SELECT f.field_name, f.old_value, f.new_value, f.is_time
    FROM (VALUES
        (N'expected_in', CONVERT(NVARCHAR(30), @o_exp_in, 126), CONVERT(NVARCHAR(30), @expected_in, 126), 1),
        (N'expected_out', CONVERT(NVARCHAR(30), @o_exp_out, 126), CONVERT(NVARCHAR(30), @expected_out, 126), 1),
        (N'first_in', CONVERT(NVARCHAR(30), @o_in, 126), CONVERT(NVARCHAR(30), @first_in, 126), 1),
        (N'last_out', CONVERT(NVARCHAR(30), @o_out, 126), CONVERT(NVARCHAR(30), @last_out, 126), 1),
        (N'marked_status', @o_mark, @marked_status, 1),
        (N'breaks', @o_breaks, @n_breaks, 1),
        (N'comments', @o_comments, @comments, 0)
    ) f (field_name, old_value, new_value, is_time)
    WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);

    BEGIN TRAN;
        UPDATE [att].[timesheet_day]
        SET expected_in = @expected_in, expected_out = @expected_out, first_in = @first_in, last_out = @last_out,
            marked_status = @marked_status, comments = @comments,
            is_manually_updated = CASE WHEN EXISTS (SELECT 1 FROM @changes WHERE is_time = 1) THEN 1 ELSE is_manually_updated END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this day. Reload it and try again', 1;

        IF EXISTS (SELECT 1 FROM @changes WHERE field_name = N'breaks')
        BEGIN
            DELETE [att].[timesheet_break] WHERE timesheet_day_id = @id;
            INSERT [att].[timesheet_break] (timesheet_day_id, break_type_id, out_at, in_at, minutes, created_by)
            SELECT @id, break_type_id, out_at, in_at, DATEDIFF(MINUTE, out_at, in_at), @actor_user_id FROM @b;
        END

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'att.timesheet_day', @id, field_name, old_value, new_value, N'update', @actor_user_id, @now FROM @changes;

        DECLARE @ids NVARCHAR(50) = N'[' + CONVERT(NVARCHAR(30), @employee_id) + N']';
        EXEC [att].[usp_timesheet_process] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @from_date = @work_date, @to_date = @work_date, @employee_ids = @ids, @quiet = 1;
    COMMIT;

    EXEC [att].[usp_timesheet_day_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @employee_id = @employee_id, @work_date = @work_date;
END
GO

-- The History popup of a day: one row per changed field. Result set 1: total; 2: the page.
CREATE OR ALTER PROCEDURE [att].[usp_timesheet_day_history]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT,
    @work_date       DATE,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;
    DECLARE @id BIGINT = (SELECT id FROM [att].[timesheet_day] WHERE employee_id = @employee_id AND work_date = @work_date
                          AND company_id = @company_id);
    IF @id IS NULL
        THROW 50404, N'Time sheet day not found', 1;

    SELECT COUNT(*) AS total FROM [core].[audit_log] WHERE entity_type = N'att.timesheet_day' AND entity_id = @id;

    SELECT a.id, a.field_name, a.old_value, a.new_value, a.action_name, a.performed_at, a.performed_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS performed_by_name
    FROM [core].[audit_log] a
    LEFT JOIN [auth].[user_account] u ON u.id = a.performed_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE a.entity_type = N'att.timesheet_day' AND a.entity_id = @id
    ORDER BY a.performed_at DESC, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Counts per day status and flag over a period (Days Overview tiles, Attendance Overview counts).
CREATE OR ALTER PROCEDURE [att].[usp_timesheet_summary]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @tab             NVARCHAR(20) = N'all',
    @from_date       DATE,
    @to_date         DATE,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    SELECT COUNT(*) AS total_days,
           COUNT(DISTINCT t.employee_id) AS employees,
           SUM(CASE WHEN t.day_status = N'present' THEN 1 ELSE 0 END) AS present,
           SUM(CASE WHEN t.day_status = N'absent' THEN 1 ELSE 0 END) AS absent,
           SUM(CASE WHEN t.day_status = N'holiday' THEN 1 ELSE 0 END) AS holiday,
           SUM(CASE WHEN t.day_status = N'weekend' THEN 1 ELSE 0 END) AS weekend,
           SUM(CASE WHEN t.day_status = N'rest_day' THEN 1 ELSE 0 END) AS rest_day,
           SUM(CASE WHEN t.day_status = N'leave' THEN 1 ELSE 0 END) AS leave,
           SUM(CASE WHEN t.day_status = N'half_day' THEN 1 ELSE 0 END) AS half_day,
           SUM(CASE WHEN t.day_status = N'short_day' THEN 1 ELSE 0 END) AS short_day,
           SUM(CASE WHEN t.day_status = N'wfh' THEN 1 ELSE 0 END) AS wfh,
           SUM(CASE WHEN t.day_status = N'official_visit' THEN 1 ELSE 0 END) AS official_visit,
           SUM(CASE WHEN t.day_status = N'sandwich' THEN 1 ELSE 0 END) AS sandwich,
           SUM(CASE WHEN t.day_status = N'yet_to_start' THEN 1 ELSE 0 END) AS yet_to_start,
           SUM(CASE WHEN t.late_minutes > 0 THEN 1 ELSE 0 END) AS late_arrival,
           SUM(CASE WHEN t.early_left_minutes > 0 THEN 1 ELSE 0 END) AS early_left,
           SUM(ISNULL(mp.missing, 0)) AS missing_punch,
           SUM(ISNULL(t.worked_minutes, 0)) AS worked_minutes,
           SUM(ISNULL(t.overtime_before_minutes, 0) + ISNULL(t.overtime_after_minutes, 0)) AS overtime_minutes,
           SUM(ISNULL(t.approved_overtime_minutes, 0)) AS approved_overtime_minutes
    FROM [att].[timesheet_day] t
    JOIN [hr].[employee] e ON e.id = t.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = t.employee_id
    OUTER APPLY (SELECT TOP 1 1 AS missing FROM [att].[timesheet_flag] f
                 WHERE f.timesheet_day_id = t.id AND f.flag = N'missing_punch') mp
    WHERE t.company_id = @company_id AND t.work_date BETWEEN @from_date AND @to_date
      AND (@tab <> N'my' OR t.employee_id = @me)
      AND (@tab <> N'subordinates' OR t.employee_id IN (SELECT employee_id FROM [att].[fn_team](@company_id, @actor_user_id)))
      AND (@employee_id IS NULL OR t.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
    OPTION (RECOMPILE);
END
GO

-- Attendance Overview: one row per employee for a month with counts, and each day's status.
-- Result set 1: total employees; 2: the page of employees with counts; 3: their days.
CREATE OR ALTER PROCEDURE [att].[usp_overview_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @tab             NVARCHAR(20) = N'all',
    @from_date       DATE,
    @to_date         DATE,
    @department_id   BIGINT = NULL,
    @branch_id       BIGINT = NULL,
    @employee_status NVARCHAR(30) = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    CREATE TABLE #ovl_emp (employee_id BIGINT PRIMARY KEY, code NVARCHAR(30), name NVARCHAR(500), department_name NVARCHAR(200),
                           designation_name NVARCHAR(200), status NVARCHAR(30));
    INSERT #ovl_emp
    SELECT e.id, e.code, CONCAT(e.first_name, N' ', e.last_name), dp.name, dg.name, e.status
    FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
    JOIN [hr].[employee] e ON e.id = v.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[designation] dg ON dg.id = e.designation_id
    WHERE (@tab <> N'my' OR e.id = @me)
      AND (@tab <> N'subordinates' OR e.id IN (SELECT employee_id FROM [att].[fn_team](@company_id, @actor_user_id)))
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@employee_status IS NULL OR e.status = @employee_status)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ovl_emp;

    CREATE TABLE #ovl_page (employee_id BIGINT PRIMARY KEY, code NVARCHAR(30), name NVARCHAR(500), department_name NVARCHAR(200),
                            designation_name NVARCHAR(200), status NVARCHAR(30), sort_no INT);
    INSERT #ovl_page
    SELECT employee_id, code, name, department_name, designation_name, status,
           ROW_NUMBER() OVER (ORDER BY name, employee_id)
    FROM #ovl_emp
    ORDER BY name, employee_id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;

    SELECT p.employee_id, p.code AS employee_code, p.name AS employee_name, p.department_name, p.designation_name,
           p.status AS employee_status,
           COUNT(t.id) AS total_days,
           SUM(CASE WHEN t.day_status = N'present' THEN 1 ELSE 0 END) AS present,
           SUM(CASE WHEN t.day_status = N'absent' THEN 1 ELSE 0 END) AS absent,
           SUM(CASE WHEN t.day_status = N'holiday' THEN 1 ELSE 0 END) AS holiday,
           SUM(CASE WHEN t.day_status IN (N'weekend', N'rest_day') THEN 1 ELSE 0 END) AS days_off,
           SUM(CASE WHEN t.day_status = N'leave' THEN 1 ELSE 0 END) AS leave,
           SUM(CASE WHEN t.late_minutes > 0 THEN 1 ELSE 0 END) AS late_arrival,
           SUM(CASE WHEN t.early_left_minutes > 0 THEN 1 ELSE 0 END) AS early_left
    FROM #ovl_page p
    LEFT JOIN [att].[timesheet_day] t ON t.employee_id = p.employee_id AND t.work_date BETWEEN @from_date AND @to_date
    GROUP BY p.employee_id, p.code, p.name, p.department_name, p.designation_name, p.status, p.sort_no
    ORDER BY p.sort_no;

    SELECT t.employee_id, t.work_date, t.day_status, t.late_minutes, t.early_left_minutes, t.is_manually_updated
    FROM #ovl_page p
    JOIN [att].[timesheet_day] t ON t.employee_id = p.employee_id
    WHERE t.work_date BETWEEN @from_date AND @to_date
    ORDER BY t.employee_id, t.work_date;
END
