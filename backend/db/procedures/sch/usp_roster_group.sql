-- Roster groups: a named weekly pattern (a time slot or a day off per weekday) for a period.
-- Result set 1: the group. Result set 2: its seven days (1 = Monday), with the slot's times.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_group_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[roster_group] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Roster group not found', 1;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    SELECT g.id, g.title, g.from_date, g.to_date, g.description, g.is_active,
           (SELECT COUNT(*) FROM [sch].[roster_group_member] m
            WHERE m.roster_group_id = g.id AND (m.end_date IS NULL OR m.end_date >= @today)) AS enrolled_count,
           g.created_at, g.updated_at, g.row_version
    FROM [sch].[roster_group] g
    WHERE g.id = @id AND g.company_id = @company_id;

    SELECT w.weekday, CAST(ISNULL(d.is_day_off, 1) AS BIT) AS is_day_off, d.time_slot_id,
           t.code AS time_slot_code, t.name AS time_slot_name, t.start_time, t.end_time, t.is_overnight,
           t.duration_minutes, t.workable_minutes
    FROM (VALUES (1), (2), (3), (4), (5), (6), (7)) w (weekday)
    LEFT JOIN [sch].[roster_group_day] d ON d.roster_group_id = @id AND d.weekday = w.weekday
    LEFT JOIN [sch].[time_slot] t ON t.id = d.time_slot_id
    ORDER BY w.weekday;
END
GO

-- Roster group list. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_group_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sch].[roster_group] g
    WHERE g.company_id = @company_id
      AND (@pattern IS NULL OR g.title LIKE @pattern)
      AND (@is_active IS NULL OR g.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT g.id, g.title, g.from_date, g.to_date, g.description, g.is_active,
           (SELECT COUNT(*) FROM [sch].[roster_group_member] m
            WHERE m.roster_group_id = g.id AND (m.end_date IS NULL OR m.end_date >= @today)) AS enrolled_count,
           (SELECT COUNT(*) FROM [sch].[roster_group_day] d WHERE d.roster_group_id = g.id AND d.is_day_off = 0) AS working_days,
           g.created_at, g.updated_at, g.row_version
    FROM [sch].[roster_group] g
    WHERE g.company_id = @company_id
      AND (@pattern IS NULL OR g.title LIKE @pattern)
      AND (@is_active IS NULL OR g.is_active = @is_active)
    ORDER BY g.title, g.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds or edits a roster group with its week. @days is a JSON array of
-- {"weekday": 1..7, "is_day_off": bool, "time_slot_id": id}; a weekday left out is a day off.
-- At least one working day. Shortening the period is refused while enrolments fall outside it.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_group_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @title         NVARCHAR(200),
    @from_date     DATE,
    @to_date       DATE = NULL,
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @days          NVARCHAR(MAX),
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Group title is required.', 1;
    IF @from_date IS NULL
        THROW 50400, N'fromDate|From date is required.', 1;
    IF @to_date IS NOT NULL AND @to_date < @from_date
        THROW 50400, N'toDate|To date cannot be before the from date.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[roster_group] WHERE company_id = @company_id AND title = @title AND (@id IS NULL OR id <> @id))
        THROW 50409, N'title|ROSTER_GROUP_DUPLICATE|A roster group with this title already exists.', 1;
    IF @days IS NULL OR ISJSON(@days) = 0
        THROW 50400, N'days|The week is required.', 1;

    DECLARE @d TABLE (weekday INT, is_day_off BIT, time_slot_id BIGINT);
    INSERT @d (weekday, is_day_off, time_slot_id)
    SELECT j.weekday, ISNULL(j.is_day_off, 0), CASE WHEN ISNULL(j.is_day_off, 0) = 1 THEN NULL ELSE j.time_slot_id END
    FROM OPENJSON(@days) WITH (weekday INT, is_day_off BIT, time_slot_id BIGINT) j;

    IF EXISTS (SELECT 1 FROM @d WHERE weekday IS NULL OR weekday NOT BETWEEN 1 AND 7)
        THROW 50400, N'days|Weekdays are 1 (Monday) to 7 (Sunday).', 1;
    IF EXISTS (SELECT weekday FROM @d GROUP BY weekday HAVING COUNT(*) > 1)
        THROW 50400, N'days|A weekday is listed twice.', 1;
    IF EXISTS (SELECT 1 FROM @d WHERE is_day_off = 0 AND time_slot_id IS NULL)
        THROW 50400, N'days|Pick a time slot for each working day.', 1;
    IF EXISTS (SELECT 1 FROM @d x WHERE x.time_slot_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [sch].[time_slot] t WHERE t.id = x.time_slot_id AND t.company_id = @company_id))
        THROW 50400, N'days|Time slot not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM @d WHERE is_day_off = 0)
        THROW 50400, N'days|At least one day must be a working day.', 1;

    INSERT @d (weekday, is_day_off, time_slot_id)
    SELECT w.weekday, 1, NULL FROM (VALUES (1), (2), (3), (4), (5), (6), (7)) w (weekday)
    WHERE NOT EXISTS (SELECT 1 FROM @d x WHERE x.weekday = w.weekday);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [sch].[roster_group] (company_id, title, from_date, to_date, description, is_active, created_by)
            VALUES (@company_id, @title, @from_date, @to_date, @description, ISNULL(@is_active, 1), @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [sch].[roster_group_day] (roster_group_id, weekday, is_day_off, time_slot_id, created_by)
            SELECT @id, weekday, is_day_off, time_slot_id, @actor_user_id FROM @d;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.roster_group', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a roster group.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sch].[roster_group] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Roster group not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this roster group. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [sch].[roster_group_member] m WHERE m.roster_group_id = @id
                   AND (m.start_date < @from_date OR (@to_date IS NOT NULL AND (m.end_date IS NULL OR m.end_date > @to_date))))
            THROW 50409, N'fromDate|ENROLMENT_OUTSIDE_PERIOD|Some enrolments fall outside these dates. Change them first.', 1;

        BEGIN TRAN;
            UPDATE [sch].[roster_group]
            SET title = @title, from_date = @from_date, to_date = @to_date, description = @description,
                is_active = ISNULL(@is_active, 1), updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this roster group. Reload it and try again', 1;

            UPDATE rd SET is_day_off = x.is_day_off, time_slot_id = x.time_slot_id, updated_at = @now, updated_by = @actor_user_id
            FROM [sch].[roster_group_day] rd JOIN @d x ON x.weekday = rd.weekday
            WHERE rd.roster_group_id = @id
              AND (rd.is_day_off <> x.is_day_off OR EXISTS (SELECT rd.time_slot_id EXCEPT SELECT x.time_slot_id));
            INSERT [sch].[roster_group_day] (roster_group_id, weekday, is_day_off, time_slot_id, created_by)
            SELECT @id, x.weekday, x.is_day_off, x.time_slot_id, @actor_user_id FROM @d x
            WHERE NOT EXISTS (SELECT 1 FROM [sch].[roster_group_day] rd WHERE rd.roster_group_id = @id AND rd.weekday = x.weekday);

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.roster_group', @id, N'update', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [sch].[usp_roster_group_get] @company_id = @company_id, @id = @id;
END
GO

-- Refused while employees are enrolled (current or past); a batch or request that used the group
-- stops it with error 547.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_group_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sch].[roster_group] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Roster group not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this roster group. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sch].[roster_group_member] WHERE roster_group_id = @id)
        THROW 50409, N'Employees are enrolled in this roster group. Remove them first', 1;

    BEGIN TRAN;
        DELETE [sch].[roster_group_day] WHERE roster_group_id = @id;
        DELETE [sch].[roster_group] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.roster_group', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
