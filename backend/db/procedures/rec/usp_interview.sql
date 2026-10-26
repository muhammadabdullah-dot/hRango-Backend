-- Interviews: schedule (with a panel of interviewers, who are notified), reschedule, cancel, complete,
-- and each interviewer's evaluation. Scope: rec.fn_visible_interviews (the opening's reach, plus the
-- interviews the caller sits on) with the permission the endpoint required.

-- Internal: tells the given interviewers (JSON array of employee ids) about an interview. No result set.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_notify]
    @company_id BIGINT,
    @id         BIGINT,
    @employees  NVARCHAR(MAX),
    @heading    NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @title NVARCHAR(200), @body NVARCHAR(MAX), @link NVARCHAR(500) = CONCAT(N'/recruitment/interviews/', @id);
    SELECT @title = LEFT(CONCAT(@heading, N': ', p.first_name, N' ', p.last_name), 200),
           @body = CONCAT(i.title, N' (round ', i.round_no, N') for ', o.title, N' on ',
                          FORMAT(i.scheduled_at, N'dd MMM yyyy, hh:mm tt'), N', ', i.duration_minutes, N' minutes',
                          CASE WHEN i.venue IS NOT NULL THEN CONCAT(N', ', i.venue) END, N'.')
    FROM [rec].[interview] i
    JOIN [rec].[application] a ON a.id = i.application_id
    JOIN [rec].[applicant] p ON p.id = a.applicant_id
    JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
    WHERE i.id = @id;

    DECLARE @emp BIGINT = (SELECT MIN(CAST(value AS BIGINT)) FROM OPENJSON(@employees));
    WHILE @emp IS NOT NULL
    BEGIN
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
             @title = @title, @body = @body, @notification_type = N'recruitment', @link = @link,
             @entity_type = N'rec.interview', @entity_id = @id;
        SET @emp = (SELECT MIN(CAST(value AS BIGINT)) FROM OPENJSON(@employees) WHERE CAST(value AS BIGINT) > @emp);
    END
END
GO

-- Internal: publishes an interview event. No result set.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_event]
    @company_id BIGINT,
    @id         BIGINT,
    @event_type NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), i.id) AS interviewId, CONVERT(NVARCHAR(30), i.application_id) AS applicationId,
               CONVERT(NVARCHAR(30), a.job_opening_id) AS jobOpeningId, o.title AS jobOpeningTitle,
               CONVERT(NVARCHAR(30), a.applicant_id) AS applicantId, CONCAT(p.first_name, N' ', p.last_name) AS applicantName,
               p.email AS applicantEmail, i.round_no AS roundNo, i.title, i.mode, i.scheduled_at AS scheduledAt,
               i.duration_minutes AS durationMinutes, i.venue, i.status, i.result,
               JSON_QUERY(ISNULL((SELECT CONVERT(NVARCHAR(30), ii.employee_id) AS employeeId,
                                         CONCAT(e.first_name, N' ', e.last_name) AS name
                                  FROM [rec].[interview_interviewer] ii JOIN [hr].[employee] e ON e.id = ii.employee_id
                                  WHERE ii.interview_id = i.id FOR JSON PATH), N'[]')) AS interviewers
        FROM [rec].[interview] i
        JOIN [rec].[application] a ON a.id = i.application_id
        JOIN [rec].[applicant] p ON p.id = a.applicant_id
        JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
        WHERE i.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event_type,
         @entity_type = N'rec.interview', @entity_id = @id, @payload = @payload;
END
GO

-- Result set 1: the interview. 2: the panel. 3: the evaluations.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [rec].[fn_visible_interviews](@company_id, @actor_user_id, @permission_code) v
                   WHERE v.interview_id = @id)
        THROW 50404, N'Interview not found', 1;

    SELECT * FROM [rec].[fn_interview_rows](@company_id) WHERE id = @id;

    SELECT ii.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           jt.name AS job_title_name, e.email,
           CAST(CASE WHEN ev.id IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS has_evaluated
    FROM [rec].[interview_interviewer] ii
    JOIN [hr].[employee] e ON e.id = ii.employee_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    LEFT JOIN [rec].[interview_evaluation] ev ON ev.interview_id = ii.interview_id AND ev.employee_id = ii.employee_id
    WHERE ii.interview_id = @id
    ORDER BY e.first_name, e.last_name;

    SELECT x.id, x.interview_id, x.employee_id, CONCAT(e.first_name, N' ', e.last_name) AS employee_name, x.rating,
           x.recommendation, x.strengths, x.concerns, x.comments, x.evaluated_at, x.evaluated_by_user_id,
           n.name AS evaluated_by_name, x.row_version
    FROM [rec].[interview_evaluation] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    OUTER APPLY [rec].[fn_user_name](x.evaluated_by_user_id) n
    WHERE x.interview_id = @id
    ORDER BY x.evaluated_at, x.id;
END
GO

-- Result set 1: total. Result set 2: the page, by time (upcoming first when listing scheduled ones).
-- @mine = 1 keeps the interviews the caller sits on.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @job_opening_id  BIGINT = NULL,
    @application_id  BIGINT = NULL,
    @interviewer_id  BIGINT = NULL,
    @status          NVARCHAR(30) = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @mine            BIT = 0,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF ISNULL(@mine, 0) = 1
        SET @interviewer_id = ISNULL(@me, -1);
    DECLARE @v TABLE (id BIGINT PRIMARY KEY);
    INSERT @v SELECT interview_id FROM [rec].[fn_visible_interviews](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [rec].[fn_interview_rows](@company_id) x JOIN @v v ON v.id = x.id
    WHERE (@pattern IS NULL OR x.applicant_name LIKE @pattern OR x.job_opening_title LIKE @pattern OR x.title LIKE @pattern)
      AND (@job_opening_id IS NULL OR x.job_opening_id = @job_opening_id)
      AND (@application_id IS NULL OR x.application_id = @application_id)
      AND (@interviewer_id IS NULL OR EXISTS (SELECT 1 FROM [rec].[interview_interviewer] ii
                                             WHERE ii.interview_id = x.id AND ii.employee_id = @interviewer_id))
      AND (@status IS NULL OR x.status = @status)
      AND (@from_date IS NULL OR x.scheduled_at >= @from_date)
      AND (@to_date IS NULL OR x.scheduled_at < DATEADD(DAY, 1, CAST(@to_date AS DATETIME2(0))))
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [rec].[fn_interview_rows](@company_id) x JOIN @v v ON v.id = x.id
    WHERE (@pattern IS NULL OR x.applicant_name LIKE @pattern OR x.job_opening_title LIKE @pattern OR x.title LIKE @pattern)
      AND (@job_opening_id IS NULL OR x.job_opening_id = @job_opening_id)
      AND (@application_id IS NULL OR x.application_id = @application_id)
      AND (@interviewer_id IS NULL OR EXISTS (SELECT 1 FROM [rec].[interview_interviewer] ii
                                             WHERE ii.interview_id = x.id AND ii.employee_id = @interviewer_id))
      AND (@status IS NULL OR x.status = @status)
      AND (@from_date IS NULL OR x.scheduled_at >= @from_date)
      AND (@to_date IS NULL OR x.scheduled_at < DATEADD(DAY, 1, CAST(@to_date AS DATETIME2(0))))
    ORDER BY x.scheduled_at DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Schedules (@id NULL) or reschedules an interview. @interviewers is a JSON array of employee ids (the
-- panel, at least one). Scheduling moves an application still before the interview stage to it. The
-- panel is told in the inbox: everyone on a new interview; on a change, everyone when the time or place
-- moved, otherwise only those added. An interviewer who has evaluated cannot be taken off the panel.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @id               BIGINT = NULL,
    @application_id   BIGINT = NULL,
    @title            NVARCHAR(200) = NULL,
    @mode             NVARCHAR(30) = N'in_person',
    @scheduled_at     DATETIME2(0),
    @duration_minutes INT = 60,
    @venue            NVARCHAR(500) = NULL,
    @remarks          NVARCHAR(MAX) = NULL,
    @interviewers     NVARCHAR(MAX),
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    SET @venue = NULLIF(LTRIM(RTRIM(@venue)), N'');

    DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30), @old_at DATETIME2(0), @old_venue NVARCHAR(500),
            @old_minutes INT, @stage NVARCHAR(30);
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_rv = i.row_version, @old_status = i.status, @old_at = i.scheduled_at, @old_venue = i.venue,
               @old_minutes = i.duration_minutes, @application_id = i.application_id
        FROM [rec].[interview] i
        JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v
          ON v.job_opening_id = (SELECT a.job_opening_id FROM [rec].[application] a WHERE a.id = i.application_id)
        WHERE i.id = @id AND i.company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Interview not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to change an interview.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this interview. Reload it and try again', 1;
        IF @old_status <> N'scheduled'
            THROW 50409, N'status|INTERVIEW_CLOSED|Only a scheduled interview can be changed.', 1;
    END
    ELSE
    BEGIN
        SELECT @stage = a.stage
        FROM [rec].[application] a
        JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
        WHERE a.id = @application_id AND a.company_id = @company_id;
        IF @stage IS NULL
            THROW 50400, N'applicationId|Application not found.', 1;
        IF @stage IN (N'hired', N'rejected', N'withdrawn')
            THROW 50409, N'applicationId|APPLICATION_CLOSED|This application is closed; interviews cannot be scheduled.', 1;
    END

    IF @scheduled_at IS NULL
        THROW 50400, N'scheduledAt|Choose the date and time.', 1;
    IF @mode IS NULL OR @mode NOT IN (N'in_person', N'phone', N'video')
        THROW 50400, N'mode|Choose in person, phone or video.', 1;
    IF @duration_minutes IS NULL OR @duration_minutes < 5 OR @duration_minutes > 600
        THROW 50400, N'durationMinutes|The duration is 5 to 600 minutes.', 1;
    IF ISJSON(@interviewers) = 0
        THROW 50400, N'interviewers|Choose at least one interviewer.', 1;
    DECLARE @panel TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @panel SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@interviewers) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @panel)
        THROW 50400, N'interviewers|Choose at least one interviewer.', 1;
    IF EXISTS (SELECT 1 FROM @panel p WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = p.employee_id
                                                        AND e.company_id = @company_id AND e.status NOT IN (N'left', N'inactive')))
        THROW 50400, N'interviewers|An interviewer was not found among the current employees.', 1;
    IF @id IS NOT NULL AND EXISTS (SELECT 1 FROM [rec].[interview_evaluation] x WHERE x.interview_id = @id
                                   AND x.employee_id NOT IN (SELECT employee_id FROM @panel))
        THROW 50409, N'interviewers|INTERVIEWER_EVALUATED|An interviewer who has already evaluated cannot be taken off the panel.', 1;
    -- No interviewer may be in two scheduled interviews at once.
    DECLARE @ends DATETIME2(0) = DATEADD(MINUTE, @duration_minutes, @scheduled_at);
    IF EXISTS (SELECT 1 FROM [rec].[interview] i
               JOIN [rec].[interview_interviewer] ii ON ii.interview_id = i.id
               JOIN @panel p ON p.employee_id = ii.employee_id
               WHERE i.company_id = @company_id AND i.status = N'scheduled' AND (@id IS NULL OR i.id <> @id)
                 AND i.scheduled_at < @ends AND DATEADD(MINUTE, i.duration_minutes, i.scheduled_at) > @scheduled_at)
        THROW 50409, N'interviewers|INTERVIEWER_BUSY|An interviewer already has an interview at that time.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @notify NVARCHAR(MAX), @event NVARCHAR(100);
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        DECLARE @round INT = 1 + ISNULL((SELECT MAX(round_no) FROM [rec].[interview] WITH (UPDLOCK, HOLDLOCK)
                                         WHERE application_id = @application_id), 0);
        INSERT [rec].[interview] (company_id, application_id, round_no, title, mode, scheduled_at, duration_minutes, venue,
                                  status, remarks, created_by)
        VALUES (@company_id, @application_id, @round, ISNULL(@title, CONCAT(N'Interview round ', @round)), @mode,
                @scheduled_at, @duration_minutes, @venue, N'scheduled', NULLIF(LTRIM(RTRIM(@remarks)), N''), @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [rec].[interview_interviewer] (interview_id, employee_id, created_by)
        SELECT @id, employee_id, @actor_user_id FROM @panel;
        IF @stage IN (N'applied', N'screening', N'shortlisted')
            EXEC [rec].[usp_application_stage_write] @company_id = @company_id, @actor_user_id = @actor_user_id,
                 @id = @application_id, @to_stage = N'interview', @remarks = N'Interview scheduled.';
        SET @notify = (SELECT employee_id AS [value] FROM @panel FOR JSON PATH);
        SET @event = N'recruitment.interview_scheduled';
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.interview', @id, N'create', CONVERT(NVARCHAR(30), @scheduled_at, 120), @actor_user_id, @now);
    END
    ELSE
    BEGIN
        DECLARE @moved BIT = CASE WHEN @old_at <> @scheduled_at OR @old_minutes <> @duration_minutes
                                       OR ISNULL(@old_venue, N'') <> ISNULL(@venue, N'') THEN 1 ELSE 0 END;
        UPDATE [rec].[interview]
        SET title = ISNULL(@title, title), mode = @mode, scheduled_at = @scheduled_at, duration_minutes = @duration_minutes,
            venue = @venue, remarks = NULLIF(LTRIM(RTRIM(@remarks)), N''), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this interview. Reload it and try again', 1;
        SET @notify = CASE WHEN @moved = 1 THEN (SELECT employee_id AS [value] FROM @panel FOR JSON PATH)
                           ELSE (SELECT p.employee_id AS [value] FROM @panel p
                                 WHERE NOT EXISTS (SELECT 1 FROM [rec].[interview_interviewer] ii
                                                   WHERE ii.interview_id = @id AND ii.employee_id = p.employee_id)
                                 FOR JSON PATH) END;
        DELETE FROM [rec].[interview_interviewer]
        WHERE interview_id = @id AND employee_id NOT IN (SELECT employee_id FROM @panel);
        INSERT [rec].[interview_interviewer] (interview_id, employee_id, created_by)
        SELECT @id, p.employee_id, @actor_user_id FROM @panel p
        WHERE NOT EXISTS (SELECT 1 FROM [rec].[interview_interviewer] ii WHERE ii.interview_id = @id AND ii.employee_id = p.employee_id);
        IF @moved = 1
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'rec.interview', @id, N'scheduled_at', CONVERT(NVARCHAR(30), @old_at, 120),
                    CONVERT(NVARCHAR(30), @scheduled_at, 120), N'update', @actor_user_id, @now);
        SET @event = N'recruitment.interview_rescheduled';
    END

    -- The JSON above is [{"value": id}, ...]; flatten it for the notifier.
    IF @notify IS NOT NULL
    BEGIN
        DECLARE @ids NVARCHAR(MAX) = (SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(30), JSON_VALUE(j.value, N'$.value')), N',') + N']'
                                      FROM OPENJSON(@notify) j);
        DECLARE @heading NVARCHAR(100) = CASE WHEN @event = N'recruitment.interview_scheduled' THEN N'Interview scheduled'
                                              ELSE N'Interview updated' END;
        EXEC [rec].[usp_interview_notify] @company_id = @company_id, @id = @id, @employees = @ids, @heading = @heading;
    END
    EXEC [rec].[usp_interview_event] @company_id = @company_id, @id = @id, @event_type = @event;
    COMMIT;

    EXEC [rec].[usp_interview_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Cancels a scheduled interview; the panel is told.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_cancel]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = i.row_version, @status = i.status
    FROM [rec].[interview] i
    JOIN [rec].[application] a ON a.id = i.application_id
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE i.id = @id AND i.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Interview not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this interview. Reload it and try again', 1;
    IF @status <> N'scheduled'
        THROW 50409, N'status|INTERVIEW_CLOSED|Only a scheduled interview can be cancelled.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [rec].[interview]
        SET status = N'cancelled', remarks = ISNULL(NULLIF(LTRIM(RTRIM(@remarks)), N''), remarks),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this interview. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.interview', @id, N'status', @status, N'cancelled', N'cancel', @actor_user_id, @now);
        DECLARE @ids NVARCHAR(MAX) = (SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(30), employee_id), N',') + N']'
                                      FROM [rec].[interview_interviewer] WHERE interview_id = @id);
        EXEC [rec].[usp_interview_notify] @company_id = @company_id, @id = @id, @employees = @ids, @heading = N'Interview cancelled';
        EXEC [rec].[usp_interview_event] @company_id = @company_id, @id = @id, @event_type = N'recruitment.interview_cancelled';
    COMMIT;

    EXEC [rec].[usp_interview_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Marks a scheduled interview completed (with a result: passed, failed, on_hold) or no_show.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_complete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @status          NVARCHAR(30) = N'completed',
    @result          NVARCHAR(30) = NULL,
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @old NVARCHAR(30);
    SELECT @rv = i.row_version, @old = i.status
    FROM [rec].[interview] i
    JOIN [rec].[application] a ON a.id = i.application_id
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE i.id = @id AND i.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Interview not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @status NOT IN (N'completed', N'no_show')
        THROW 50400, N'status|Choose completed or no show.', 1;
    IF @result IS NOT NULL AND (@result NOT IN (N'passed', N'failed', N'on_hold') OR @status = N'no_show')
        THROW 50400, N'result|Choose passed, failed or on hold (no result for a no show).', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this interview. Reload it and try again', 1;
    IF @old <> N'scheduled'
        THROW 50409, N'status|INTERVIEW_CLOSED|Only a scheduled interview can be completed.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [rec].[interview]
        SET status = @status, result = @result, remarks = ISNULL(NULLIF(LTRIM(RTRIM(@remarks)), N''), remarks),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this interview. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.interview', @id, N'status', @old, @status, N'complete', @actor_user_id, @now);
    COMMIT;

    EXEC [rec].[usp_interview_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- An interviewer's evaluation (one per interviewer; saving again replaces it). @employee_id blank = the
-- caller as interviewer; naming another panel member (HR entering feedback for them) needs the
-- permission over the opening, not only a seat on the panel.
CREATE OR ALTER PROCEDURE [rec].[usp_interview_evaluate]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @employee_id     BIGINT = NULL,
    @rating          INT,
    @recommendation  NVARCHAR(30),
    @strengths       NVARCHAR(MAX) = NULL,
    @concerns        NVARCHAR(MAX) = NULL,
    @comments        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @opening BIGINT;
    SELECT @status = i.status, @opening = a.job_opening_id
    FROM [rec].[interview] i
    JOIN [rec].[application] a ON a.id = i.application_id
    JOIN [rec].[fn_visible_interviews](@company_id, @actor_user_id, @permission_code) v ON v.interview_id = i.id
    WHERE i.id = @id;
    IF @status IS NULL
        THROW 50404, N'Interview not found', 1;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @employee_id IS NULL
        SET @employee_id = @me;
    IF @employee_id IS NULL
        THROW 50400, N'employeeId|Choose the interviewer this evaluation is from.', 1;
    IF @employee_id <> ISNULL(@me, -1)
       AND NOT EXISTS (SELECT 1 FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v WHERE v.job_opening_id = @opening)
        THROW 50403, N'You can only record your own evaluation.', 1;
    IF NOT EXISTS (SELECT 1 FROM [rec].[interview_interviewer] WHERE interview_id = @id AND employee_id = @employee_id)
        THROW 50400, N'employeeId|NOT_ON_PANEL|This person is not on the interview panel.', 1;
    IF @status = N'cancelled'
        THROW 50409, N'status|INTERVIEW_CANCELLED|A cancelled interview cannot be evaluated.', 1;
    IF @rating IS NULL OR @rating NOT BETWEEN 1 AND 5
        THROW 50400, N'rating|Rate from 1 to 5.', 1;
    IF @recommendation IS NULL OR @recommendation NOT IN (N'strong_hire', N'hire', N'no_hire', N'strong_no_hire')
        THROW 50400, N'recommendation|Choose strong hire, hire, no hire or strong no hire.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [rec].[interview_evaluation]
        SET rating = @rating, recommendation = @recommendation, strengths = NULLIF(LTRIM(RTRIM(@strengths)), N''),
            concerns = NULLIF(LTRIM(RTRIM(@concerns)), N''), comments = NULLIF(LTRIM(RTRIM(@comments)), N''),
            evaluated_at = @now, evaluated_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE interview_id = @id AND employee_id = @employee_id;
        IF @@ROWCOUNT = 0
            INSERT [rec].[interview_evaluation] (interview_id, employee_id, rating, recommendation, strengths, concerns, comments,
                                                 evaluated_at, evaluated_by_user_id, created_by)
            VALUES (@id, @employee_id, @rating, @recommendation, NULLIF(LTRIM(RTRIM(@strengths)), N''),
                    NULLIF(LTRIM(RTRIM(@concerns)), N''), NULLIF(LTRIM(RTRIM(@comments)), N''), @now, @actor_user_id, @actor_user_id);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), i.id) AS interviewId, CONVERT(NVARCHAR(30), i.application_id) AS applicationId,
                   CONVERT(NVARCHAR(30), a.applicant_id) AS applicantId, CONCAT(p.first_name, N' ', p.last_name) AS applicantName,
                   i.round_no AS roundNo, CONVERT(NVARCHAR(30), @employee_id) AS interviewerId,
                   @rating AS rating, @recommendation AS recommendation
            FROM [rec].[interview] i
            JOIN [rec].[application] a ON a.id = i.application_id
            JOIN [rec].[applicant] p ON p.id = a.applicant_id
            WHERE i.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'recruitment.interview_evaluated',
             @entity_type = N'rec.interview', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [rec].[usp_interview_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO
