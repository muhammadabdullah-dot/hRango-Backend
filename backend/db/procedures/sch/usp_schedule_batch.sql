-- Internal: writes the shifts a caller has put in #cand, inside the caller's transaction.
--   #cand  (n INT IDENTITY, employee_id, work_date, time_slot_id, start_at, end_at, geo_fence_id, is_wfh,
--           custom_breaks BIT, schedule_batch_id)
--   #cbrk  (break_type_id, start_time, end_time, is_inclusive): the breaks for rows with custom_breaks = 1;
--          other rows get their time slot's breaks.
-- Rules: a date that is a rest day for the employee is skipped (a rest day wins). Shifts of one
-- employee must not overlap. Without "Allow Multi Shift on single day" (core.company_setting,
-- module attendance, key allow_multi_shift) an employee has one shift per date. Existing shifts on
-- the same dates, or overlapping, are replaced when @replace_existing = 1; otherwise they are a 409.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_apply_candidates]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @replace_existing BIT = 0,
    @created          INT = NULL OUTPUT,
    @replaced         INT = NULL OUTPUT,
    @skipped_rest     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @multi BIT = CASE WHEN EXISTS (
        SELECT 1 FROM [core].[company_setting]
        WHERE company_id = @company_id AND module = N'attendance' AND setting_key = N'allow_multi_shift'
          AND LOWER(LTRIM(RTRIM(CAST(setting_value AS NVARCHAR(10))))) IN (N'1', N'true')) THEN 1 ELSE 0 END;

    DELETE c FROM #cand c
    WHERE EXISTS (SELECT 1 FROM [sch].[rest_day] r WHERE r.employee_id = c.employee_id AND r.rest_date = c.work_date);
    SET @skipped_rest = @@ROWCOUNT;

    -- Breaks of every candidate, as date-times inside its shift.
    CREATE TABLE #cb (n INT, break_type_id BIGINT, start_at DATETIME2(0), end_at DATETIME2(0), is_inclusive BIT);
    INSERT #cb (n, break_type_id, start_at, end_at, is_inclusive)
    SELECT c.n, x.break_type_id, x.bs, DATEADD(MINUTE, x.len, x.bs), x.is_inclusive
    FROM #cand c
    CROSS APPLY (
        SELECT b.break_type_id, b.is_inclusive, b.start_time, b.end_time
        FROM [sch].[time_slot_break] b WHERE c.custom_breaks = 0 AND b.time_slot_id = c.time_slot_id
        UNION ALL
        SELECT b.break_type_id, b.is_inclusive, b.start_time, b.end_time
        FROM #cbrk b WHERE c.custom_breaks = 1
    ) b
    CROSS APPLY (SELECT DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), b.start_time), CAST(c.work_date AS DATETIME2(0))) AS raw_bs) r
    CROSS APPLY (SELECT b.break_type_id, b.is_inclusive,
                        CASE WHEN r.raw_bs < c.start_at THEN DATEADD(DAY, 1, r.raw_bs) ELSE r.raw_bs END AS bs,
                        (DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), b.end_time)
                         - DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), b.start_time) + 1440) % 1440 AS len) x;

    IF EXISTS (SELECT 1 FROM #cb b JOIN #cand c ON c.n = b.n WHERE b.end_at <= b.start_at OR b.end_at > c.end_at)
        THROW 50400, N'breaks|BREAK_OUTSIDE_SHIFT|Each break must end after it starts and sit inside the shift.', 1;
    IF EXISTS (SELECT 1 FROM #cb x JOIN #cb y ON x.n = y.n AND x.start_at < y.start_at AND y.start_at < x.end_at)
        THROW 50400, N'breaks|BREAK_OVERLAP|Two breaks overlap.', 1;

    IF EXISTS (SELECT 1 FROM #cand a JOIN #cand b ON a.employee_id = b.employee_id AND a.n < b.n
               AND (a.start_at < b.end_at AND b.start_at < a.end_at OR (@multi = 0 AND a.work_date = b.work_date)))
        THROW 50409, N'employeeIds|SCHEDULE_OVERLAP|Two of the new shifts for the same employee overlap or fall on the same day.', 1;

    -- Existing shifts in the way: on the same date, or overlapping.
    DECLARE @clash TABLE (id BIGINT PRIMARY KEY, same_day BIT);
    INSERT @clash (id, same_day)
    SELECT s.id, MAX(CASE WHEN s.work_date = c.work_date THEN 1 ELSE 0 END)
    FROM #cand c
    JOIN [sch].[schedule] s ON s.employee_id = c.employee_id
     AND s.start_at < DATEADD(DAY, 2, CAST(c.work_date AS DATETIME2(0)))
     AND s.end_at > DATEADD(DAY, -2, CAST(c.work_date AS DATETIME2(0)))
    WHERE s.work_date = c.work_date OR (s.start_at < c.end_at AND c.start_at < s.end_at)
    GROUP BY s.id;

    SET @replaced = 0;
    IF EXISTS (SELECT 1 FROM @clash)
    BEGIN
        IF ISNULL(@replace_existing, 0) = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM @clash c JOIN [sch].[schedule] s ON s.id = c.id
                       JOIN #cand n ON n.employee_id = s.employee_id AND s.start_at < n.end_at AND n.start_at < s.end_at)
                THROW 50409, N'employeeIds|SCHEDULE_OVERLAP|Some employees already have a shift at these times. Replace them or pick other dates.', 1;
            IF @multi = 0 AND EXISTS (SELECT 1 FROM @clash WHERE same_day = 1)
                THROW 50409, N'employeeIds|SCHEDULE_DAY_TAKEN|Some employees already have a shift on these dates. Replace them or pick other dates.', 1;
        END
        ELSE
        BEGIN
            DELETE b FROM [sch].[schedule_break] b JOIN @clash c ON c.id = b.schedule_id;
            DELETE s FROM [sch].[schedule] s JOIN @clash c ON c.id = s.id;
            SET @replaced = @@ROWCOUNT;
        END
    END

    DECLARE @map TABLE (n INT, id BIGINT);
    MERGE [sch].[schedule] AS t
    USING (
        SELECT c.n, c.employee_id, c.work_date, c.start_at, c.end_at, c.time_slot_id, c.schedule_batch_id, c.geo_fence_id, c.is_wfh,
               CASE WHEN ts.is_flexible = 1 THEN ts.workable_minutes
                    ELSE DATEDIFF(MINUTE, c.start_at, c.end_at)
                         - ISNULL((SELECT SUM(DATEDIFF(MINUTE, b.start_at, b.end_at)) FROM #cb b WHERE b.n = c.n AND b.is_inclusive = 0), 0)
               END AS planned_minutes
        FROM #cand c JOIN [sch].[time_slot] ts ON ts.id = c.time_slot_id
    ) AS src ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (company_id, employee_id, work_date, start_at, end_at, time_slot_id, schedule_batch_id, geo_fence_id, is_wfh,
                planned_minutes, created_by)
        VALUES (@company_id, src.employee_id, src.work_date, src.start_at, src.end_at, src.time_slot_id, src.schedule_batch_id,
                src.geo_fence_id, ISNULL(src.is_wfh, 0), src.planned_minutes, @actor_user_id)
    OUTPUT src.n, INSERTED.id INTO @map (n, id);
    SET @created = @@ROWCOUNT;

    INSERT [sch].[schedule_break] (schedule_id, break_type_id, start_at, end_at, is_inclusive, created_by)
    SELECT m.id, b.break_type_id, b.start_at, b.end_at, b.is_inclusive, @actor_user_id
    FROM #cb b JOIN @map m ON m.n = b.n;
END
GO

-- "Create Scheduling" (@batch_kind create) and "Apply Default Shift" (@batch_kind default_shift)
-- over a date range for many employees, as one batch.
--   create: one time slot for every picked day, or a roster group's slot for each weekday (its days
--           off are skipped, and so are dates outside the group's period). The days are those
--           sch.fn_pattern_dates picks from @weekdays, @repeat_every_weeks and @step. Employees are
--           @employee_ids; with a roster group and no employees, its members enrolled on each date.
--   default_shift: every date in the range; each employee gets the roster they are enrolled in on
--           that date, otherwise their default time slot (hr.employee.default_time_slot_id).
-- @breaks (JSON {"break_type_id", "start_time", "end_time", "is_inclusive"}) replaces the slots'
-- breaks when given. Returns the batch with the numbers created, replaced and skipped.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_batch_create]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @batch_kind         NVARCHAR(30) = N'create',
    @start_date         DATE,
    @end_date           DATE,
    @time_slot_id       BIGINT = NULL,
    @roster_group_id    BIGINT = NULL,
    @weekdays           NVARCHAR(30) = NULL,
    @repeat_every_weeks INT = 0,
    @step               INT = 1,
    @geo_fence_id       BIGINT = NULL,
    @is_wfh             BIT = 0,
    @employee_ids       NVARCHAR(MAX) = NULL,
    @breaks             NVARCHAR(MAX) = NULL,
    @replace_existing   BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @repeat_every_weeks = ISNULL(@repeat_every_weeks, 0);
    SET @step = CASE WHEN @repeat_every_weeks = 0 THEN 1 ELSE ISNULL(@step, 1) END;
    SET @weekdays = NULLIF(REPLACE(LTRIM(RTRIM(@weekdays)), N' ', N''), N'');

    IF @batch_kind NOT IN (N'create', N'default_shift')
        THROW 50400, N'batchKind|Unknown kind of scheduling.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Start date is required.', 1;
    IF @end_date IS NULL
        THROW 50400, N'endDate|End date is required.', 1;
    IF @end_date < @start_date
        THROW 50400, N'endDate|End date cannot be before the start date.', 1;
    IF DATEDIFF(DAY, @start_date, @end_date) > 366
        THROW 50400, N'endDate|Schedule at most a year at a time.', 1;
    IF @repeat_every_weeks NOT BETWEEN 0 AND 8
        THROW 50400, N'repeatEveryWeeks|Repeat is never or every 1 to 8 weeks.', 1;
    IF @step < 1 OR (@repeat_every_weeks > 0 AND @step > @repeat_every_weeks)
        THROW 50400, N'step|Step is between 1 and the number of weeks in the repeat.', 1;
    IF @weekdays IS NOT NULL AND EXISTS (SELECT 1 FROM STRING_SPLIT(@weekdays, N',') WHERE ISNULL(TRY_CAST(value AS INT), 0) NOT BETWEEN 1 AND 7)
        THROW 50400, N'weekdays|Weekdays are 1 (Monday) to 7 (Sunday).', 1;
    IF @batch_kind = N'create' AND (@time_slot_id IS NULL AND @roster_group_id IS NULL OR @time_slot_id IS NOT NULL AND @roster_group_id IS NOT NULL)
        THROW 50400, N'timeSlotId|Pick either a time slot or a roster group.', 1;
    IF @time_slot_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [sch].[time_slot] WHERE id = @time_slot_id AND company_id = @company_id)
        THROW 50400, N'timeSlotId|Time slot not found.', 1;
    IF @roster_group_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [sch].[roster_group] WHERE id = @roster_group_id AND company_id = @company_id)
        THROW 50400, N'rosterGroupId|Roster group not found.', 1;
    IF @geo_fence_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [att].[geo_fence] WHERE id = @geo_fence_id AND company_id = @company_id)
        THROW 50400, N'geoFenceId|Geo fence not found.', 1;
    IF @employee_ids IS NOT NULL AND ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Employees are not valid.', 1;
    IF @breaks IS NOT NULL AND ISJSON(@breaks) = 0
        THROW 50400, N'breaks|Breaks are not valid.', 1;

    DECLARE @ids TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @ids SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(ISNULL(@employee_ids, N'[]')) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @ids) AND NOT (@batch_kind = N'create' AND @roster_group_id IS NOT NULL)
        THROW 50400, N'employeeIds|Select at least one employee.', 1;
    IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = i.employee_id AND e.company_id = @company_id))
        THROW 50400, N'employeeIds|Employee not found.', 1;

    DECLARE @visible TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @visible SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code);
    IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (SELECT 1 FROM @visible v WHERE v.employee_id = i.employee_id))
        THROW 50403, N'You cannot schedule one or more of these employees.', 1;

    CREATE TABLE #cbrk (break_type_id BIGINT, start_time TIME(0), end_time TIME(0), is_inclusive BIT);
    IF @breaks IS NOT NULL
    BEGIN
        INSERT #cbrk (break_type_id, start_time, end_time, is_inclusive)
        SELECT j.break_type_id, j.start_time, j.end_time, ISNULL(j.is_inclusive, 0)
        FROM OPENJSON(@breaks) WITH (break_type_id BIGINT, start_time TIME(0), end_time TIME(0), is_inclusive BIT) j;
        IF EXISTS (SELECT 1 FROM #cbrk WHERE break_type_id IS NULL OR start_time IS NULL OR end_time IS NULL)
            THROW 50400, N'breaks|Each break needs a break type, a start time and an end time.', 1;
        IF EXISTS (SELECT 1 FROM #cbrk x WHERE NOT EXISTS (SELECT 1 FROM [sch].[break_type] bt WHERE bt.id = x.break_type_id AND bt.company_id = @company_id))
            THROW 50400, N'breaks|Break type not found.', 1;
    END

    -- The slot each employee works on each date.
    CREATE TABLE #pick (employee_id BIGINT, work_date DATE, time_slot_id BIGINT);
    IF @batch_kind = N'create' AND @time_slot_id IS NOT NULL
        INSERT #pick (employee_id, work_date, time_slot_id)
        SELECT i.employee_id, d.d, @time_slot_id
        FROM @ids i CROSS JOIN [sch].[fn_pattern_dates](@start_date, @end_date, @weekdays, @repeat_every_weeks, @step) d;
    ELSE IF @batch_kind = N'create'
        INSERT #pick (employee_id, work_date, time_slot_id)
        SELECT emp.employee_id, d.d, rd.time_slot_id
        FROM [sch].[fn_pattern_dates](@start_date, @end_date, @weekdays, @repeat_every_weeks, @step) d
        JOIN [sch].[roster_group] g ON g.id = @roster_group_id AND d.d >= g.from_date AND (g.to_date IS NULL OR d.d <= g.to_date)
        JOIN [sch].[roster_group_day] rd ON rd.roster_group_id = g.id AND rd.weekday = d.weekday AND rd.is_day_off = 0
        CROSS APPLY (
            SELECT i.employee_id FROM @ids i
            UNION ALL
            SELECT m.employee_id FROM [sch].[roster_group_member] m
            JOIN @visible v ON v.employee_id = m.employee_id
            WHERE NOT EXISTS (SELECT 1 FROM @ids) AND m.roster_group_id = g.id
              AND m.start_date <= d.d AND (m.end_date IS NULL OR m.end_date >= d.d)
        ) emp;
    ELSE
        INSERT #pick (employee_id, work_date, time_slot_id)
        SELECT i.employee_id, d.d, COALESCE(rr.time_slot_id, CASE WHEN rr.found IS NULL THEN e.default_time_slot_id END)
        FROM @ids i
        JOIN [hr].[employee] e ON e.id = i.employee_id
        CROSS JOIN [sch].[fn_dates](@start_date, @end_date) d
        OUTER APPLY (
            SELECT TOP (1) 1 AS found, CASE WHEN rd.is_day_off = 0 THEN rd.time_slot_id END AS time_slot_id
            FROM [sch].[roster_group_member] m
            JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
            JOIN [sch].[roster_group_day] rd ON rd.roster_group_id = g.id AND rd.weekday = d.weekday
            WHERE m.employee_id = i.employee_id AND m.start_date <= d.d AND (m.end_date IS NULL OR m.end_date >= d.d)
            ORDER BY m.start_date DESC
        ) rr;

    DECLARE @skipped_no_shift INT = (SELECT COUNT(*) FROM #pick WHERE time_slot_id IS NULL);
    DELETE #pick WHERE time_slot_id IS NULL;
    IF NOT EXISTS (SELECT 1 FROM #pick)
        THROW 50400, N'startDate|NOTHING_TO_SCHEDULE|These dates, days and employees give no shift to schedule.', 1;

    CREATE TABLE #cand (n INT IDENTITY(1,1), employee_id BIGINT, work_date DATE, time_slot_id BIGINT, start_at DATETIME2(0),
                        end_at DATETIME2(0), geo_fence_id BIGINT, is_wfh BIT, custom_breaks BIT, schedule_batch_id BIGINT);
    INSERT #cand (employee_id, work_date, time_slot_id, start_at, end_at, geo_fence_id, is_wfh, custom_breaks)
    SELECT p.employee_id, p.work_date, p.time_slot_id, x.start_at, DATEADD(MINUTE, ts.duration_minutes, x.start_at),
           @geo_fence_id, ISNULL(@is_wfh, 0), CASE WHEN @breaks IS NULL THEN 0 ELSE 1 END
    FROM #pick p
    JOIN [sch].[time_slot] ts ON ts.id = p.time_slot_id
    CROSS APPLY (SELECT DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), ts.start_time), CAST(p.work_date AS DATETIME2(0))) AS start_at) x
    ORDER BY p.employee_id, p.work_date;

    DECLARE @batch_id BIGINT, @created INT, @replaced INT, @skipped_rest INT, @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        INSERT [sch].[schedule_batch] (company_id, batch_kind, start_date, end_date, time_slot_id, roster_group_id, weekdays,
                                       repeat_every_weeks, step, geo_fence_id, is_wfh, created_by)
        VALUES (@company_id, @batch_kind, @start_date, @end_date, @time_slot_id, @roster_group_id, @weekdays,
                @repeat_every_weeks, @step, @geo_fence_id, ISNULL(@is_wfh, 0), @actor_user_id);
        SET @batch_id = SCOPE_IDENTITY();
        UPDATE #cand SET schedule_batch_id = @batch_id;

        EXEC [sch].[usp_schedule_apply_candidates] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @replace_existing = @replace_existing, @created = @created OUTPUT, @replaced = @replaced OUTPUT,
             @skipped_rest = @skipped_rest OUTPUT;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.schedule_batch', @batch_id, N'create',
                CONCAT(N'created ', @created, N', replaced ', @replaced), @actor_user_id, @now);
    COMMIT;

    SELECT b.id, b.batch_kind, b.start_date, b.end_date, b.time_slot_id, t.name AS time_slot_name,
           b.roster_group_id, g.title AS roster_group_title, b.weekdays, b.repeat_every_weeks, b.step,
           b.geo_fence_id, b.is_wfh, @created AS created_count, @replaced AS replaced_count,
           @skipped_rest AS skipped_rest_days, @skipped_no_shift AS skipped_no_shift, b.created_at
    FROM [sch].[schedule_batch] b
    LEFT JOIN [sch].[time_slot] t ON t.id = b.time_slot_id
    LEFT JOIN [sch].[roster_group] g ON g.id = b.roster_group_id
    WHERE b.id = @batch_id;
END
