-- Time slots (Attendance settings -> Time Slots): a shift template with its planned breaks.
-- Result set 1: the slot. Result set 2: its breaks.
CREATE OR ALTER PROCEDURE [sch].[usp_time_slot_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[time_slot] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Time slot not found', 1;

    SELECT t.id, t.code, t.name, t.color, t.start_time, t.end_time, t.duration_minutes, t.workable_minutes,
           t.is_flexible, t.is_overnight, t.full_overtime, t.short_overtime,
           t.created_at, t.updated_at, t.row_version
    FROM [sch].[time_slot] t
    WHERE t.id = @id AND t.company_id = @company_id;

    SELECT b.id, b.break_type_id, bt.name AS break_type_name, b.start_time, b.end_time, b.is_inclusive
    FROM [sch].[time_slot_break] b
    JOIN [sch].[break_type] bt ON bt.id = b.break_type_id
    WHERE b.time_slot_id = @id
    ORDER BY (DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), b.start_time)
              - (SELECT DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), start_time) FROM [sch].[time_slot] WHERE id = @id) + 1440) % 1440, b.id;
END
GO

-- Time slot list. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [sch].[usp_time_slot_list]
    @company_id  BIGINT,
    @search      NVARCHAR(200) = NULL,
    @is_flexible BIT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sch].[time_slot] t
    WHERE t.company_id = @company_id
      AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
      AND (@is_flexible IS NULL OR t.is_flexible = @is_flexible)
    OPTION (RECOMPILE);

    SELECT t.id, t.code, t.name, t.color, t.start_time, t.end_time, t.duration_minutes, t.workable_minutes,
           t.is_flexible, t.is_overnight, t.full_overtime, t.short_overtime,
           (SELECT COUNT(*) FROM [sch].[time_slot_break] b WHERE b.time_slot_id = t.id) AS break_count,
           t.created_at, t.updated_at, t.row_version
    FROM [sch].[time_slot] t
    WHERE t.company_id = @company_id
      AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
      AND (@is_flexible IS NULL OR t.is_flexible = @is_flexible)
    ORDER BY t.start_time, t.name, t.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a time slot (@id NULL) or edits one. @breaks is a JSON array of
-- {"break_type_id", "start_time", "end_time", "is_inclusive"}; the slot's breaks are replaced by it.
-- An end time at or before the start time ends the next day (overnight). Breaks must sit inside the
-- slot and not overlap. Workable minutes: given for a flexible slot (the hours to work in the
-- window); for a fixed slot the duration minus the breaks that are not inclusive.
-- Editing a slot does not move shifts already scheduled from it.
CREATE OR ALTER PROCEDURE [sch].[usp_time_slot_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT = NULL,
    @id               BIGINT = NULL,
    @name             NVARCHAR(200),
    @color            NVARCHAR(20) = NULL,
    @start_time       TIME(0),
    @end_time         TIME(0),
    @workable_minutes INT = NULL,
    @is_flexible      BIT = 0,
    @full_overtime    BIT = 0,
    @short_overtime   BIT = 0,
    @breaks           NVARCHAR(MAX) = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @color = NULLIF(LTRIM(RTRIM(@color)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Time slot name is required.', 1;
    IF @start_time IS NULL
        THROW 50400, N'startTime|Start time is required.', 1;
    IF @end_time IS NULL
        THROW 50400, N'endTime|End time is required.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[time_slot] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|TIME_SLOT_DUPLICATE|A time slot with this name already exists.', 1;

    DECLARE @start_min INT = DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), @start_time);
    DECLARE @end_min INT = DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), @end_time);
    DECLARE @is_overnight BIT = CASE WHEN @end_min <= @start_min THEN 1 ELSE 0 END;
    DECLARE @duration INT = CASE WHEN @end_min > @start_min THEN @end_min - @start_min ELSE @end_min + 1440 - @start_min END;

    -- Breaks, as minutes from the slot's start.
    DECLARE @b TABLE (n INT IDENTITY(1,1), break_type_id BIGINT, start_time TIME(0), end_time TIME(0), is_inclusive BIT,
                      s INT NULL, e INT NULL);
    IF @breaks IS NOT NULL AND ISJSON(@breaks) = 0
        THROW 50400, N'breaks|Breaks are not valid.', 1;
    INSERT @b (break_type_id, start_time, end_time, is_inclusive)
    SELECT j.break_type_id, j.start_time, j.end_time, ISNULL(j.is_inclusive, 0)
    FROM OPENJSON(ISNULL(@breaks, N'[]')) WITH (break_type_id BIGINT, start_time TIME(0), end_time TIME(0), is_inclusive BIT) j;

    IF EXISTS (SELECT 1 FROM @b WHERE break_type_id IS NULL OR start_time IS NULL OR end_time IS NULL)
        THROW 50400, N'breaks|Each break needs a break type, a start time and an end time.', 1;
    IF EXISTS (SELECT 1 FROM @b x WHERE NOT EXISTS (SELECT 1 FROM [sch].[break_type] bt WHERE bt.id = x.break_type_id AND bt.company_id = @company_id))
        THROW 50400, N'breaks|Break type not found.', 1;

    UPDATE @b SET s = (DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), start_time) - @start_min + 1440) % 1440;
    UPDATE @b SET e = s + (DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), end_time) - DATEDIFF(MINUTE, CAST('00:00' AS TIME(0)), start_time) + 1440) % 1440;
    IF EXISTS (SELECT 1 FROM @b WHERE e <= s OR e > @duration)
        THROW 50400, N'breaks|BREAK_OUTSIDE_SLOT|Each break must end after it starts and sit inside the slot''s times.', 1;
    IF EXISTS (SELECT 1 FROM @b x JOIN @b y ON x.n < y.n AND x.s < y.e AND y.s < x.e)
        THROW 50400, N'breaks|BREAK_OVERLAP|Two breaks overlap.', 1;

    DECLARE @break_minutes INT = ISNULL((SELECT SUM(e - s) FROM @b WHERE is_inclusive = 0), 0);
    IF @is_flexible = 1
    BEGIN
        IF @workable_minutes IS NULL OR @workable_minutes <= 0
            THROW 50400, N'workableMinutes|Workable minutes are required for a flexible slot.', 1;
        IF @workable_minutes > @duration
            THROW 50400, N'workableMinutes|Workable minutes cannot be more than the slot''s duration.', 1;
    END
    ELSE
        SET @workable_minutes = @duration - @break_minutes;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            DECLARE @n INT;
            UPDATE [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK)
            SET @n = next_number, next_number = next_number + 1, updated_at = @now
            WHERE company_id = @company_id AND prefix = N'TS-';
            IF @n IS NULL
            BEGIN
                SET @n = ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(code, 4, 20) AS INT)) FROM [sch].[time_slot] WHERE company_id = @company_id), 0) + 1;
                INSERT [core].[number_sequence] (company_id, prefix, next_number, created_by) VALUES (@company_id, N'TS-', @n + 1, @actor_user_id);
            END

            INSERT [sch].[time_slot] (company_id, code, name, color, start_time, end_time, duration_minutes, workable_minutes,
                                      is_flexible, is_overnight, full_overtime, short_overtime, created_by)
            VALUES (@company_id, N'TS-' + CASE WHEN @n > 99999 THEN CAST(@n AS NVARCHAR(10)) ELSE RIGHT(N'0000' + CAST(@n AS NVARCHAR(10)), 5) END, @name, @color,
                    @start_time, @end_time, @duration, @workable_minutes, @is_flexible, @is_overnight, @full_overtime, @short_overtime, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [sch].[time_slot_break] (time_slot_id, break_type_id, start_time, end_time, is_inclusive, created_by)
            SELECT @id, break_type_id, start_time, end_time, is_inclusive, @actor_user_id FROM @b ORDER BY n;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.time_slot', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a time slot.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sch].[time_slot] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Time slot not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this time slot. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [sch].[time_slot]
            SET name = @name, color = @color, start_time = @start_time, end_time = @end_time, duration_minutes = @duration,
                workable_minutes = @workable_minutes, is_flexible = @is_flexible, is_overnight = @is_overnight,
                full_overtime = @full_overtime, short_overtime = @short_overtime, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this time slot. Reload it and try again', 1;

            DELETE [sch].[time_slot_break] WHERE time_slot_id = @id;
            INSERT [sch].[time_slot_break] (time_slot_id, break_type_id, start_time, end_time, is_inclusive, created_by)
            SELECT @id, break_type_id, start_time, end_time, is_inclusive, @actor_user_id FROM @b ORDER BY n;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.time_slot', @id, N'update', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [sch].[usp_time_slot_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a time slot that nothing uses yet.
CREATE OR ALTER PROCEDURE [sch].[usp_time_slot_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sch].[time_slot] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Time slot not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this time slot. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sch].[schedule] WHERE time_slot_id = @id)
        THROW 50409, N'Shifts are scheduled with this time slot. Delete them first', 1;
    IF EXISTS (SELECT 1 FROM [sch].[roster_group_day] WHERE time_slot_id = @id)
        THROW 50409, N'A roster group uses this time slot. Change the roster first', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE default_time_slot_id = @id)
        THROW 50409, N'Employees have this time slot as their default shift', 1;

    BEGIN TRAN;
        DELETE [sch].[time_slot_break] WHERE time_slot_id = @id;
        -- Anything else still pointing here (batches, payroll) stops the delete with error 547.
        DELETE [sch].[time_slot] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.time_slot', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
