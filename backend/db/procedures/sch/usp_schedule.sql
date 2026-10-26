-- One scheduled shift. Every procedure takes the permission code the endpoint required and only
-- reaches employees auth.fn_visible_employees gives for it.
-- Result set 1: the shift. Result set 2: its breaks.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[schedule] s
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
                   WHERE s.id = @id AND s.company_id = @company_id)
        THROW 50404, N'Schedule not found', 1;

    SELECT s.id, s.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           s.work_date, s.start_at, s.end_at, s.time_slot_id, ts.code AS time_slot_code, ts.name AS time_slot_name,
           ts.color AS time_slot_color, ts.is_flexible, CAST(CASE WHEN CAST(s.end_at AS DATE) > s.work_date THEN 1 ELSE 0 END AS BIT) AS is_overnight,
           ts.full_overtime, ts.short_overtime, s.schedule_batch_id, s.geo_fence_id, gf.name AS geo_fence_name, s.is_wfh,
           s.planned_minutes,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [sch].[rest_day] r WHERE r.employee_id = s.employee_id AND r.rest_date = s.work_date) THEN 1 ELSE 0 END AS BIT) AS is_rest_day,
           s.created_at, s.updated_at, s.row_version
    FROM [sch].[schedule] s
    JOIN [hr].[employee] e ON e.id = s.employee_id
    JOIN [sch].[time_slot] ts ON ts.id = s.time_slot_id
    LEFT JOIN [att].[geo_fence] gf ON gf.id = s.geo_fence_id
    WHERE s.id = @id AND s.company_id = @company_id;

    SELECT b.id, b.break_type_id, bt.name AS break_type_name, b.start_at, b.end_at, b.is_inclusive
    FROM [sch].[schedule_break] b
    JOIN [sch].[break_type] bt ON bt.id = b.break_type_id
    WHERE b.schedule_id = @id
    ORDER BY b.start_at, b.id;
END
GO

-- Adds one shift (@id NULL) or edits one. Times default to the time slot's; @start_time and
-- @end_time (both or neither) set other times for this day. @breaks (JSON {"break_type_id",
-- "start_time", "end_time", "is_inclusive"}) are this shift's breaks; NULL takes the slot's breaks.
-- Refused on a rest day, over another shift of the employee, or on a day that already has a shift
-- when "Allow Multi Shift on single day" is off. The employee of a shift does not change (use swap).
-- Internal callers (request effects) pass @permission_code NULL to skip the reach check, and
-- @return_row 0 to get no result set.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT = NULL,
    @work_date       DATE,
    @time_slot_id    BIGINT,
    @start_time      TIME(0) = NULL,
    @end_time        TIME(0) = NULL,
    @geo_fence_id    BIGINT = NULL,
    @is_wfh          BIT = 0,
    @breaks          NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL,
    @return_row      BIT = 1,
    @new_id          BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @old_rv BINARY(8), @old_date DATE, @old_start DATETIME2(0), @old_end DATETIME2(0), @old_slot BIGINT,
            @old_geo BIGINT, @old_wfh BIT;
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_rv = s.row_version, @employee_id = s.employee_id, @old_date = s.work_date, @old_start = s.start_at,
               @old_end = s.end_at, @old_slot = s.time_slot_id, @old_geo = s.geo_fence_id, @old_wfh = s.is_wfh
        FROM [sch].[schedule] s
        WHERE s.id = @id AND s.company_id = @company_id
          AND (@permission_code IS NULL OR EXISTS (
                SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                WHERE v.employee_id = s.employee_id));
        IF @old_rv IS NULL
            THROW 50404, N'Schedule not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a schedule.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this schedule. Reload it and try again', 1;
    END
    ELSE
    BEGIN
        IF @employee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
            THROW 50400, N'employeeId|Employee not found.', 1;
        IF @permission_code IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
            THROW 50403, N'You cannot schedule this employee.', 1;
    END

    IF @work_date IS NULL
        THROW 50400, N'workDate|Date is required.', 1;
    DECLARE @slot_start TIME(0), @slot_minutes INT, @flexible BIT, @workable INT;
    SELECT @slot_start = start_time, @slot_minutes = duration_minutes, @flexible = is_flexible, @workable = workable_minutes
    FROM [sch].[time_slot] WHERE id = @time_slot_id AND company_id = @company_id;
    IF @slot_start IS NULL
        THROW 50400, N'timeSlotId|Time slot not found.', 1;
    IF (@start_time IS NULL AND @end_time IS NOT NULL) OR (@start_time IS NOT NULL AND @end_time IS NULL)
        THROW 50400, N'endTime|Give both the start and the end time, or neither.', 1;
    IF @geo_fence_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [att].[geo_fence] WHERE id = @geo_fence_id AND company_id = @company_id)
        THROW 50400, N'geoFenceId|Geo fence not found.', 1;
    IF @breaks IS NOT NULL AND ISJSON(@breaks) = 0
        THROW 50400, N'breaks|Breaks are not valid.', 1;

    DECLARE @start_at DATETIME2(0), @end_at DATETIME2(0);
    IF @start_time IS NULL
    BEGIN
        SET @start_at = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @slot_start), CAST(@work_date AS DATETIME2(0)));
        SET @end_at = DATEADD(MINUTE, @slot_minutes, @start_at);
    END
    ELSE
    BEGIN
        SET @start_at = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @start_time), CAST(@work_date AS DATETIME2(0)));
        SET @end_at = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @end_time), CAST(@work_date AS DATETIME2(0)));
        IF @end_at <= @start_at
            SET @end_at = DATEADD(DAY, 1, @end_at);
    END

    DECLARE @b TABLE (n INT IDENTITY(1,1), break_type_id BIGINT, start_time TIME(0), end_time TIME(0), is_inclusive BIT,
                      start_at DATETIME2(0), end_at DATETIME2(0));
    IF @breaks IS NULL
        INSERT @b (break_type_id, start_time, end_time, is_inclusive)
        SELECT break_type_id, start_time, end_time, is_inclusive FROM [sch].[time_slot_break] WHERE time_slot_id = @time_slot_id;
    ELSE
        INSERT @b (break_type_id, start_time, end_time, is_inclusive)
        SELECT j.break_type_id, j.start_time, j.end_time, ISNULL(j.is_inclusive, 0)
        FROM OPENJSON(@breaks) WITH (break_type_id BIGINT, start_time TIME(0), end_time TIME(0), is_inclusive BIT) j;
    IF EXISTS (SELECT 1 FROM @b WHERE break_type_id IS NULL OR start_time IS NULL OR end_time IS NULL)
        THROW 50400, N'breaks|Each break needs a break type, a start time and an end time.', 1;
    IF EXISTS (SELECT 1 FROM @b x WHERE NOT EXISTS (SELECT 1 FROM [sch].[break_type] bt WHERE bt.id = x.break_type_id AND bt.company_id = @company_id))
        THROW 50400, N'breaks|Break type not found.', 1;
    UPDATE @b SET start_at = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), start_time), CAST(@work_date AS DATETIME2(0)));
    UPDATE @b SET start_at = DATEADD(DAY, 1, start_at) WHERE start_at < @start_at;
    UPDATE @b SET end_at = DATEADD(MINUTE, (DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), end_time)
                                            - DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), start_time) + 1440) % 1440, start_at);
    IF EXISTS (SELECT 1 FROM @b WHERE end_at <= start_at OR end_at > @end_at)
        THROW 50400, N'breaks|BREAK_OUTSIDE_SHIFT|Each break must end after it starts and sit inside the shift.', 1;
    IF EXISTS (SELECT 1 FROM @b x JOIN @b y ON x.n < y.n AND x.start_at < y.end_at AND y.start_at < x.end_at)
        THROW 50400, N'breaks|BREAK_OVERLAP|Two breaks overlap.', 1;

    IF EXISTS (SELECT 1 FROM [sch].[rest_day] WHERE employee_id = @employee_id AND rest_date = @work_date)
        THROW 50409, N'workDate|REST_DAY|This date is a rest day for the employee. Remove the rest day first.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[schedule] s WHERE s.employee_id = @employee_id AND (@id IS NULL OR s.id <> @id)
               AND s.start_at < @end_at AND @start_at < s.end_at)
        THROW 50409, N'startTime|SCHEDULE_OVERLAP|The employee already has a shift at these times.', 1;
    IF NOT EXISTS (SELECT 1 FROM [core].[company_setting]
                   WHERE company_id = @company_id AND module = N'attendance' AND setting_key = N'allow_multi_shift'
                     AND LOWER(LTRIM(RTRIM(CAST(setting_value AS NVARCHAR(10))))) IN (N'1', N'true'))
       AND EXISTS (SELECT 1 FROM [sch].[schedule] s WHERE s.employee_id = @employee_id AND (@id IS NULL OR s.id <> @id)
                   AND s.work_date = @work_date)
        THROW 50409, N'workDate|SCHEDULE_DAY_TAKEN|The employee already has a shift on this date.', 1;

    DECLARE @planned INT = CASE WHEN @flexible = 1 THEN @workable
        ELSE DATEDIFF(MINUTE, @start_at, @end_at) - ISNULL((SELECT SUM(DATEDIFF(MINUTE, start_at, end_at)) FROM @b WHERE is_inclusive = 0), 0) END;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [sch].[schedule] (company_id, employee_id, work_date, start_at, end_at, time_slot_id, geo_fence_id, is_wfh,
                                     planned_minutes, created_by)
            VALUES (@company_id, @employee_id, @work_date, @start_at, @end_at, @time_slot_id, @geo_fence_id, ISNULL(@is_wfh, 0),
                    @planned, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.schedule', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [sch].[schedule]
            SET work_date = @work_date, start_at = @start_at, end_at = @end_at, time_slot_id = @time_slot_id,
                geo_fence_id = @geo_fence_id, is_wfh = ISNULL(@is_wfh, 0), planned_minutes = @planned,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this schedule. Reload it and try again', 1;
            DELETE [sch].[schedule_break] WHERE schedule_id = @id;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'sch.schedule', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'work_date', CONVERT(NVARCHAR(30), @old_date, 23), CONVERT(NVARCHAR(30), @work_date, 23)),
                (N'start_at', CONVERT(NVARCHAR(30), @old_start, 120), CONVERT(NVARCHAR(30), @start_at, 120)),
                (N'end_at', CONVERT(NVARCHAR(30), @old_end, 120), CONVERT(NVARCHAR(30), @end_at, 120)),
                (N'time_slot_id', CONVERT(NVARCHAR(30), @old_slot), CONVERT(NVARCHAR(30), @time_slot_id)),
                (N'geo_fence_id', CONVERT(NVARCHAR(30), @old_geo), CONVERT(NVARCHAR(30), @geo_fence_id)),
                (N'is_wfh', CONVERT(NVARCHAR(30), @old_wfh), CONVERT(NVARCHAR(30), ISNULL(@is_wfh, 0)))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        END

        INSERT [sch].[schedule_break] (schedule_id, break_type_id, start_at, end_at, is_inclusive, created_by)
        SELECT @id, break_type_id, start_at, end_at, is_inclusive, @actor_user_id FROM @b ORDER BY start_at;
    COMMIT;

    SET @new_id = @id;
    IF ISNULL(@return_row, 1) = 1
        EXEC [sch].[usp_schedule_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @permission_code = @permission_code, @id = @id;
END
GO

-- Deletes one shift. A time sheet day or a request that points at it stops the delete (error 547).
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (
        SELECT s.row_version FROM [sch].[schedule] s
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
        WHERE s.id = @id AND s.company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Schedule not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this schedule. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [sch].[schedule_break] WHERE schedule_id = @id;
        DELETE [sch].[schedule] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.schedule', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Multi Delete and Delete Scheduling. Either @ids (JSON array of schedule ids; each must be
-- reachable) or a date range for @employee_ids (JSON array) or, with @all_employees = 1, everyone
-- the caller reaches. Rest days in the range go too only with @delete_rest_days = 1; with
-- @delete_schedules = 0 only rest days go (Rest Days tab, Delete for a date range).
-- Returns the numbers deleted.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_bulk_delete]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @ids              NVARCHAR(MAX) = NULL,
    @start_date       DATE = NULL,
    @end_date         DATE = NULL,
    @employee_ids     NVARCHAR(MAX) = NULL,
    @all_employees    BIT = 0,
    @delete_rest_days BIT = 0,
    @delete_schedules BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @visible TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @visible SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code);
    DECLARE @del TABLE (id BIGINT PRIMARY KEY);
    DECLARE @emps TABLE (employee_id BIGINT PRIMARY KEY);

    IF @ids IS NOT NULL
    BEGIN
        IF ISJSON(@ids) = 0
            THROW 50400, N'ids|Schedules are not valid.', 1;
        INSERT @del SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM @del)
            THROW 50400, N'ids|Select at least one shift.', 1;
        IF EXISTS (SELECT 1 FROM @del d WHERE NOT EXISTS (
                       SELECT 1 FROM [sch].[schedule] s JOIN @visible v ON v.employee_id = s.employee_id
                       WHERE s.id = d.id AND s.company_id = @company_id))
            THROW 50404, N'One or more of these shifts were not found', 1;
        SET @delete_rest_days = 0;
    END
    ELSE
    BEGIN
        IF @start_date IS NULL
            THROW 50400, N'startDate|Start date is required.', 1;
        IF @end_date IS NULL
            THROW 50400, N'endDate|End date is required.', 1;
        IF @end_date < @start_date
            THROW 50400, N'endDate|End date cannot be before the start date.', 1;
        IF ISNULL(@all_employees, 0) = 1
            INSERT @emps SELECT v.employee_id FROM @visible v;
        ELSE
        BEGIN
            IF @employee_ids IS NULL OR ISJSON(@employee_ids) = 0
                THROW 50400, N'employeeIds|Select at least one employee.', 1;
            INSERT @emps SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@employee_ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
            IF NOT EXISTS (SELECT 1 FROM @emps)
                THROW 50400, N'employeeIds|Select at least one employee.', 1;
            IF EXISTS (SELECT 1 FROM @emps i WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = i.employee_id AND e.company_id = @company_id))
                THROW 50400, N'employeeIds|Employee not found.', 1;
            IF EXISTS (SELECT 1 FROM @emps i WHERE NOT EXISTS (SELECT 1 FROM @visible v WHERE v.employee_id = i.employee_id))
                THROW 50403, N'You cannot change the schedule of one or more of these employees.', 1;
        END
        IF ISNULL(@delete_schedules, 1) = 1
            INSERT @del SELECT s.id FROM [sch].[schedule] s JOIN @emps e ON e.employee_id = s.employee_id
            WHERE s.company_id = @company_id AND s.work_date BETWEEN @start_date AND @end_date;
    END

    DECLARE @deleted INT, @rest_deleted INT = 0, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE b FROM [sch].[schedule_break] b JOIN @del d ON d.id = b.schedule_id;
        DELETE s FROM [sch].[schedule] s JOIN @del d ON d.id = s.id;
        SET @deleted = @@ROWCOUNT;
        IF ISNULL(@delete_rest_days, 0) = 1
        BEGIN
            DELETE r FROM [sch].[rest_day] r JOIN @emps e ON e.employee_id = r.employee_id
            WHERE r.company_id = @company_id AND r.rest_date BETWEEN @start_date AND @end_date;
            SET @rest_deleted = @@ROWCOUNT;
        END

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'sch.schedule', id, N'delete', @actor_user_id, @now FROM @del;
    COMMIT;

    SELECT @deleted AS deleted_schedules, @rest_deleted AS deleted_rest_days;
END
GO

-- Multi Edit: the same change on several shifts. A new @time_slot_id moves each shift to that slot's
-- times on its own date and takes the slot's breaks. @geo_fence_id sets the geo fence,
-- @clear_geo_fence = 1 removes it; @is_wfh sets work from home. NULL leaves a field as it is.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_bulk_edit]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @ids             NVARCHAR(MAX),
    @time_slot_id    BIGINT = NULL,
    @geo_fence_id    BIGINT = NULL,
    @clear_geo_fence BIT = 0,
    @is_wfh          BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ids IS NULL OR ISJSON(@ids) = 0
        THROW 50400, N'ids|Select at least one shift.', 1;
    DECLARE @set TABLE (id BIGINT PRIMARY KEY, employee_id BIGINT, work_date DATE, start_at DATETIME2(0), end_at DATETIME2(0));
    INSERT @set (id) SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @set)
        THROW 50400, N'ids|Select at least one shift.', 1;
    UPDATE x SET employee_id = s.employee_id, work_date = s.work_date, start_at = s.start_at, end_at = s.end_at
    FROM @set x
    JOIN [sch].[schedule] s ON s.id = x.id AND s.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id;
    IF EXISTS (SELECT 1 FROM @set WHERE employee_id IS NULL)
        THROW 50404, N'One or more of these shifts were not found', 1;
    IF @time_slot_id IS NULL AND @geo_fence_id IS NULL AND ISNULL(@clear_geo_fence, 0) = 0 AND @is_wfh IS NULL
        THROW 50400, N'timeSlotId|Nothing to change.', 1;
    IF @geo_fence_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [att].[geo_fence] WHERE id = @geo_fence_id AND company_id = @company_id)
        THROW 50400, N'geoFenceId|Geo fence not found.', 1;

    DECLARE @slot_start TIME(0), @slot_minutes INT, @flexible BIT, @workable INT, @breakless INT;
    IF @time_slot_id IS NOT NULL
    BEGIN
        SELECT @slot_start = start_time, @slot_minutes = duration_minutes, @flexible = is_flexible, @workable = workable_minutes
        FROM [sch].[time_slot] WHERE id = @time_slot_id AND company_id = @company_id;
        IF @slot_start IS NULL
            THROW 50400, N'timeSlotId|Time slot not found.', 1;
        UPDATE @set SET start_at = DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), @slot_start), CAST(work_date AS DATETIME2(0)));
        UPDATE @set SET end_at = DATEADD(MINUTE, @slot_minutes, start_at);

        IF EXISTS (SELECT 1 FROM @set a JOIN @set b ON a.employee_id = b.employee_id AND a.id < b.id
                   AND a.start_at < b.end_at AND b.start_at < a.end_at)
            THROW 50409, N'timeSlotId|SCHEDULE_OVERLAP|With this time slot two of the shifts would overlap.', 1;
        IF EXISTS (SELECT 1 FROM @set a JOIN [sch].[schedule] s ON s.employee_id = a.employee_id
                   AND NOT EXISTS (SELECT 1 FROM @set x WHERE x.id = s.id)
                   AND s.start_at < a.end_at AND a.start_at < s.end_at)
            THROW 50409, N'timeSlotId|SCHEDULE_OVERLAP|With this time slot some shifts would overlap other shifts.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @updated INT;
    BEGIN TRAN;
        UPDATE s
        SET time_slot_id = ISNULL(@time_slot_id, s.time_slot_id),
            start_at = x.start_at, end_at = x.end_at,
            geo_fence_id = CASE WHEN @clear_geo_fence = 1 THEN NULL ELSE ISNULL(@geo_fence_id, s.geo_fence_id) END,
            is_wfh = ISNULL(@is_wfh, s.is_wfh), updated_at = @now, updated_by = @actor_user_id
        FROM [sch].[schedule] s JOIN @set x ON x.id = s.id;
        SET @updated = @@ROWCOUNT;

        IF @time_slot_id IS NOT NULL
        BEGIN
            DELETE b FROM [sch].[schedule_break] b JOIN @set x ON x.id = b.schedule_id;
            INSERT [sch].[schedule_break] (schedule_id, break_type_id, start_at, end_at, is_inclusive, created_by)
            SELECT x.id, tb.break_type_id, bs.start_at,
                   DATEADD(MINUTE, (DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), tb.end_time)
                                    - DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), tb.start_time) + 1440) % 1440, bs.start_at),
                   tb.is_inclusive, @actor_user_id
            FROM @set x
            JOIN [sch].[time_slot_break] tb ON tb.time_slot_id = @time_slot_id
            CROSS APPLY (SELECT DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS TIME(0)), tb.start_time), CAST(x.work_date AS DATETIME2(0))) AS raw) r
            CROSS APPLY (SELECT CASE WHEN r.raw < x.start_at THEN DATEADD(DAY, 1, r.raw) ELSE r.raw END AS start_at) bs;

            UPDATE s SET planned_minutes = CASE WHEN @flexible = 1 THEN @workable
                ELSE DATEDIFF(MINUTE, s.start_at, s.end_at)
                     - ISNULL((SELECT SUM(DATEDIFF(MINUTE, b.start_at, b.end_at)) FROM [sch].[schedule_break] b
                               WHERE b.schedule_id = s.id AND b.is_inclusive = 0), 0) END
            FROM [sch].[schedule] s JOIN @set x ON x.id = s.id;
        END

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'sch.schedule', id, N'update', @actor_user_id, @now FROM @set;
    COMMIT;

    SELECT @updated AS updated_schedules;
END
GO

-- Swap Shift. Exchanges the employees of two shifts (@with_schedule_id), or gives the shift to
-- another employee on the same date (@with_employee_id). With @permission_code the caller must reach
-- both employees; the requests engine calls it without one (sch.usp_request_apply_shift_swap).
-- Refused when a shift would land on a rest day or over another shift of its new employee.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_swap]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150) = NULL,
    @schedule_id      BIGINT,
    @with_schedule_id BIGINT = NULL,
    @with_employee_id BIGINT = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @a_emp BIGINT, @a_rv BINARY(8), @a_date DATE, @a_start DATETIME2(0), @a_end DATETIME2(0);
    DECLARE @b_emp BIGINT, @b_date DATE, @b_start DATETIME2(0), @b_end DATETIME2(0);
    SELECT @a_emp = employee_id, @a_rv = row_version, @a_date = work_date, @a_start = start_at, @a_end = end_at
    FROM [sch].[schedule] WHERE id = @schedule_id AND company_id = @company_id;
    IF @a_emp IS NULL
        THROW 50404, N'Schedule not found', 1;
    IF @permission_code IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @a_emp)
        THROW 50404, N'Schedule not found', 1;
    IF @row_version IS NOT NULL AND @row_version <> @a_rv
        THROW 50409, N'Someone else changed this schedule. Reload it and try again', 1;

    IF @with_schedule_id IS NOT NULL
    BEGIN
        SELECT @b_emp = employee_id, @b_date = work_date, @b_start = start_at, @b_end = end_at
        FROM [sch].[schedule] WHERE id = @with_schedule_id AND company_id = @company_id;
        IF @b_emp IS NULL
            THROW 50400, N'withScheduleId|The other shift was not found.', 1;
        IF @with_employee_id IS NOT NULL AND @with_employee_id <> @b_emp
            THROW 50400, N'withEmployeeId|The other shift belongs to someone else.', 1;
    END
    ELSE
    BEGIN
        IF @with_employee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @with_employee_id AND company_id = @company_id)
            THROW 50400, N'withEmployeeId|Pick the employee to swap with.', 1;
        SET @b_emp = @with_employee_id;
    END
    IF @b_emp = @a_emp
        THROW 50400, N'withEmployeeId|Swap with another employee.', 1;
    IF @permission_code IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @b_emp)
        THROW 50403, N'You cannot change the schedule of the other employee.', 1;

    DECLARE @multi BIT = CASE WHEN EXISTS (
        SELECT 1 FROM [core].[company_setting]
        WHERE company_id = @company_id AND module = N'attendance' AND setting_key = N'allow_multi_shift'
          AND LOWER(LTRIM(RTRIM(CAST(setting_value AS NVARCHAR(10))))) IN (N'1', N'true')) THEN 1 ELSE 0 END;

    -- Shift A goes to employee B.
    IF EXISTS (SELECT 1 FROM [sch].[rest_day] WHERE employee_id = @b_emp AND rest_date = @a_date)
        THROW 50409, N'withEmployeeId|REST_DAY|The shift falls on a rest day of the other employee.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[schedule] s WHERE s.employee_id = @b_emp AND s.id <> ISNULL(@with_schedule_id, 0)
               AND (s.start_at < @a_end AND @a_start < s.end_at OR (@multi = 0 AND s.work_date = @a_date)))
        THROW 50409, N'withEmployeeId|SCHEDULE_OVERLAP|The other employee already has a shift then.', 1;
    -- Shift B goes to employee A.
    IF @with_schedule_id IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM [sch].[rest_day] WHERE employee_id = @a_emp AND rest_date = @b_date)
            THROW 50409, N'withScheduleId|REST_DAY|The other shift falls on a rest day of this employee.', 1;
        IF EXISTS (SELECT 1 FROM [sch].[schedule] s WHERE s.employee_id = @a_emp AND s.id <> @schedule_id
                   AND (s.start_at < @b_end AND @b_start < s.end_at OR (@multi = 0 AND s.work_date = @b_date)))
            THROW 50409, N'withScheduleId|SCHEDULE_OVERLAP|This employee already has a shift at the other shift''s time.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [sch].[schedule]
        SET employee_id = CASE WHEN id = @schedule_id THEN @b_emp ELSE @a_emp END, updated_at = @now, updated_by = @actor_user_id
        WHERE company_id = @company_id AND id IN (@schedule_id, ISNULL(@with_schedule_id, @schedule_id));

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'sch.schedule', x.id, N'employee_id', CONVERT(NVARCHAR(30), x.old_emp), CONVERT(NVARCHAR(30), x.new_emp), N'swap', @actor_user_id, @now
        FROM (VALUES (@schedule_id, @a_emp, @b_emp), (@with_schedule_id, @b_emp, @a_emp)) x (id, old_emp, new_emp)
        WHERE x.id IS NOT NULL;
    COMMIT;
END
