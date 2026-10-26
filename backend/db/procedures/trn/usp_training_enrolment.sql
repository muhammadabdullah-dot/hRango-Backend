-- Training -> Nominations and enrolments. Employee-owned: filtered on auth.fn_visible_employees with the
-- code the endpoint required. Statuses: requested (a nomination waiting for approval) -> enrolled (a seat)
-- -> completed | not_completed; or rejected / withdrawn / cancelled (the session was cancelled).
-- A seat is only given while the session has room (capacity counts enrolled, completed and not completed).

CREATE OR ALTER PROCEDURE [trn].[usp_training_enrolment_list]
    @company_id          BIGINT,
    @actor_user_id       BIGINT,
    @permission_code     NVARCHAR(150),
    @tab                 NVARCHAR(20) = N'all',
    @training_session_id BIGINT = NULL,
    @training_program_id BIGINT = NULL,
    @status              NVARCHAR(30) = NULL,
    @employee_id         BIGINT = NULL,
    @search              NVARCHAR(200) = NULL,
    @page                INT = 1,
    @page_size           INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SELECT r.id INTO #ids
    FROM [trn].[fn_enrolment_rows](@company_id) r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    WHERE (@tab = N'all' OR r.employee_id IN (SELECT employee_id FROM [trn].[fn_tab_employees](@actor_user_id, @tab)))
      AND (@training_session_id IS NULL OR r.training_session_id = @training_session_id)
      AND (@training_program_id IS NULL OR r.training_program_id = @training_program_id)
      AND (@status IS NULL OR r.status = @status)
      AND (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@pattern IS NULL OR r.employee_name LIKE @pattern OR r.employee_code LIKE @pattern OR r.session_title LIKE @pattern)
    OPTION (RECOMPILE, MAXRECURSION 100);
    SELECT COUNT(*) AS total FROM #ids;
    SELECT r.* FROM #ids i JOIN [trn].[fn_enrolment_rows](@company_id) r ON r.id = i.id
    ORDER BY r.start_date DESC, r.employee_name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Result sets: 1 the enrolment; 2 its attendance days; 3 its feedback (if given).
CREATE OR ALTER PROCEDURE [trn].[usp_training_enrolment_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [trn].[training_enrolment] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
                   WHERE e.id = @id AND e.company_id = @company_id)
        THROW 50404, N'Enrolment not found', 1;
    SELECT r.* FROM [trn].[fn_enrolment_rows](@company_id) r WHERE r.id = @id;
    SELECT a.attendance_date, a.status, a.remarks FROM [trn].[training_attendance] a WHERE a.training_enrolment_id = @id ORDER BY a.attendance_date;
    SELECT f.overall_rating, f.trainer_rating, f.content_rating, f.comments, f.created_at, f.updated_at
    FROM [trn].[training_feedback] f WHERE f.training_enrolment_id = @id;
END
GO

-- Nominates people for a session. @source: 'self' (one's own nomination; the training setting may forbid
-- it), 'manager' (waits for approval) or 'hr' (a seat at once). Someone whose earlier nomination was rejected,
-- withdrawn or cancelled is nominated again on the same row. Returns the enrolments touched.
CREATE OR ALTER PROCEDURE [trn].[usp_training_enrolment_nominate]
    @company_id          BIGINT,
    @actor_user_id       BIGINT,
    @permission_code     NVARCHAR(150),
    @training_session_id BIGINT,
    @employee_ids        NVARCHAR(MAX),
    @source              NVARCHAR(30),
    @remarks             NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @capacity INT, @deadline DATE, @title NVARCHAR(200), @start DATE;
    SELECT @status = status, @capacity = capacity, @deadline = nomination_deadline, @title = title, @start = start_date
    FROM [trn].[training_session] WHERE id = @training_session_id AND company_id = @company_id;
    IF @status IS NULL
        THROW 50400, N'trainingSessionId|Session not found.', 1;
    IF @status <> N'scheduled'
        THROW 50409, N'trainingSessionId|SESSION_CLOSED|This session is completed or cancelled.', 1;
    IF @source <> N'hr' AND @deadline IS NOT NULL AND @deadline < CAST(SYSUTCDATETIME() AS DATE)
        THROW 50409, N'trainingSessionId|NOMINATION_CLOSED|Nominations for this session have closed.', 1;
    IF @source = N'self' AND (SELECT allow_self_nomination FROM [trn].[fn_settings](@company_id)) = 0
        THROW 50403, N'Self-nomination is switched off. Ask your manager or HR to nominate you.', 1;
    IF ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Employees are not valid.', 1;

    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @people SELECT DISTINCT TRY_CONVERT(BIGINT, j.[value]) FROM OPENJSON(@employee_ids) j WHERE TRY_CONVERT(BIGINT, j.[value]) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @people)
        THROW 50400, N'employeeIds|Choose at least one employee.', 1;
    IF EXISTS (SELECT 1 FROM @people p WHERE NOT EXISTS (
                   SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = p.employee_id))
        THROW 50400, N'employeeIds|Some of these employees were not found.', 1;
    IF EXISTS (SELECT 1 FROM @people p JOIN [trn].[training_enrolment] e ON e.employee_id = p.employee_id
               WHERE e.training_session_id = @training_session_id AND e.status IN (N'requested', N'enrolled', N'completed', N'not_completed'))
        THROW 50409, N'employeeIds|ALREADY_NOMINATED|Someone chosen is already nominated for this session.', 1;

    DECLARE @new_status NVARCHAR(30) = CASE WHEN @source = N'hr' THEN N'enrolled' ELSE N'requested' END;
    IF @new_status = N'enrolled' AND @capacity IS NOT NULL
       AND (SELECT COUNT(*) FROM [trn].[training_enrolment] WHERE training_session_id = @training_session_id
            AND status IN (N'enrolled', N'completed', N'not_completed')) + (SELECT COUNT(*) FROM @people) > @capacity
        THROW 50409, N'trainingSessionId|SESSION_FULL|The session does not have enough seats left.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @touched TABLE (id BIGINT, employee_id BIGINT);
    BEGIN TRAN;
        UPDATE e SET status = @new_status, nomination_source = @source, nominated_by_user_id = @actor_user_id,
                     decided_by_user_id = CASE WHEN @new_status = N'enrolled' THEN @actor_user_id END,
                     decided_at = CASE WHEN @new_status = N'enrolled' THEN @now END, decision_remarks = @remarks,
                     attendance_percent = NULL, score = NULL, result_remarks = NULL, completed_at = NULL,
                     updated_at = @now, updated_by = @actor_user_id
        OUTPUT inserted.id, inserted.employee_id INTO @touched
        FROM [trn].[training_enrolment] e JOIN @people p ON p.employee_id = e.employee_id
        WHERE e.training_session_id = @training_session_id;
        INSERT [trn].[training_enrolment] (company_id, training_session_id, employee_id, status, nomination_source, nominated_by_user_id,
                                           decided_by_user_id, decided_at, decision_remarks, created_by)
        OUTPUT inserted.id, inserted.employee_id INTO @touched
        SELECT @company_id, @training_session_id, p.employee_id, @new_status, @source, @actor_user_id,
               CASE WHEN @new_status = N'enrolled' THEN @actor_user_id END, CASE WHEN @new_status = N'enrolled' THEN @now END,
               @remarks, @actor_user_id
        FROM @people p
        WHERE NOT EXISTS (SELECT 1 FROM [trn].[training_enrolment] e WHERE e.training_session_id = @training_session_id AND e.employee_id = p.employee_id);

        DECLARE @eid BIGINT = (SELECT MIN(id) FROM @touched), @emp BIGINT, @payload NVARCHAR(MAX), @link NVARCHAR(500),
                @event NVARCHAR(100) = CASE WHEN @new_status = N'enrolled' THEN N'training.enrolled' ELSE N'training.nominated' END,
                @title_n NVARCHAR(200) = LEFT(N'You are enrolled: ' + @title, 200),
                @body NVARCHAR(MAX) = @title + N' starts on ' + CONVERT(NVARCHAR(10), @start, 23) + N'.';
        WHILE @eid IS NOT NULL
        BEGIN
            SELECT @emp = employee_id FROM @touched WHERE id = @eid;
            SET @payload = (SELECT CONVERT(NVARCHAR(20), @eid) AS enrolmentId, CONVERT(NVARCHAR(20), @training_session_id) AS sessionId,
                                   CONVERT(NVARCHAR(20), @emp) AS employeeId, @source AS source FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event,
                 @entity_type = N'trn.training_enrolment', @entity_id = @eid, @payload = @payload;
            IF @new_status = N'enrolled'
            BEGIN
                SET @link = N'/training/enrolments/' + CONVERT(NVARCHAR(20), @eid);
                EXEC [trn].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title_n, @body = @body,
                     @link = @link, @entity_type = N'trn.training_enrolment', @entity_id = @eid;
            END
            SET @eid = (SELECT MIN(id) FROM @touched WHERE id > @eid);
        END
    COMMIT;

    SELECT r.* FROM [trn].[fn_enrolment_rows](@company_id) r WHERE r.id IN (SELECT id FROM @touched) ORDER BY r.employee_name, r.id;
END
GO

-- Decides or ends one enrolment. @action: 'approve' (requested -> enrolled, needs a free seat), 'reject'
-- (requested -> rejected), 'withdraw' (requested or enrolled -> withdrawn, before the session closes).
CREATE OR ALTER PROCEDURE [trn].[usp_training_enrolment_decide]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @action          NVARCHAR(20),
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @emp BIGINT, @session BIGINT, @session_status NVARCHAR(30), @capacity INT,
            @title NVARCHAR(200), @start DATE;
    SELECT @rv = e.row_version, @status = e.status, @emp = e.employee_id, @session = s.id, @session_status = s.status,
           @capacity = s.capacity, @title = s.title, @start = s.start_date
    FROM [trn].[training_enrolment] e
    JOIN [trn].[training_session] s ON s.id = e.training_session_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
    WHERE e.id = @id AND e.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Enrolment not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;
    IF @session_status <> N'scheduled'
        THROW 50409, N'status|SESSION_CLOSED|This session is completed or cancelled.', 1;
    IF @action IN (N'approve', N'reject') AND @status <> N'requested'
        THROW 50409, N'status|NOT_REQUESTED|Only a nomination waiting for approval can be approved or rejected.', 1;
    IF @action = N'withdraw' AND @status NOT IN (N'requested', N'enrolled')
        THROW 50409, N'status|NOT_ACTIVE|Only a waiting nomination or a seat can be withdrawn.', 1;
    IF @action NOT IN (N'approve', N'reject', N'withdraw')
        THROW 50400, N'action|Unknown action.', 1;
    IF @action = N'approve' AND @capacity IS NOT NULL
       AND (SELECT COUNT(*) FROM [trn].[training_enrolment] WHERE training_session_id = @session
            AND status IN (N'enrolled', N'completed', N'not_completed')) >= @capacity
        THROW 50409, N'status|SESSION_FULL|The session has no seats left.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(),
            @new NVARCHAR(30) = CASE @action WHEN N'approve' THEN N'enrolled' WHEN N'reject' THEN N'rejected' ELSE N'withdrawn' END;
    BEGIN TRAN;
        UPDATE [trn].[training_enrolment]
        SET status = @new, decision_remarks = ISNULL(@remarks, decision_remarks), decided_at = @now, decided_by_user_id = @actor_user_id,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;
        DECLARE @event NVARCHAR(100) = CASE @action WHEN N'approve' THEN N'training.enrolled' WHEN N'reject' THEN N'training.nomination_rejected'
                                                    ELSE N'training.withdrawn' END,
                @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS enrolmentId, CONVERT(NVARCHAR(20), @session) AS sessionId,
                                                 CONVERT(NVARCHAR(20), @emp) AS employeeId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                @link NVARCHAR(500) = N'/training/enrolments/' + CONVERT(NVARCHAR(20), @id),
                @title_n NVARCHAR(200) = LEFT(CASE @action WHEN N'approve' THEN N'You are enrolled: ' WHEN N'reject' THEN N'Nomination not approved: '
                                              ELSE N'Training withdrawn: ' END + @title, 200),
                @body NVARCHAR(MAX) = CASE WHEN @action = N'approve' THEN @title + N' starts on ' + CONVERT(NVARCHAR(10), @start, 23) + N'.'
                                           ELSE @remarks END;
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event, @entity_type = N'trn.training_enrolment',
             @entity_id = @id, @payload = @payload;
        IF @emp <> ISNULL((SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id), 0)
            EXEC [trn].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title_n, @body = @body,
                 @link = @link, @entity_type = N'trn.training_enrolment', @entity_id = @id;
    COMMIT;
    EXEC [trn].[usp_training_enrolment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Records one participant's result: completed when their attendance reaches the minimum (training settings).
CREATE OR ALTER PROCEDURE [trn].[usp_training_enrolment_complete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @score           DECIMAL(5,2) = NULL,
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @emp BIGINT, @session BIGINT, @session_status NVARCHAR(30), @pct DECIMAL(5,2),
            @title NVARCHAR(200);
    SELECT @rv = r.row_version, @status = r.status, @emp = r.employee_id, @session = r.training_session_id,
           @session_status = r.session_status, @pct = r.attendance_to_date, @title = r.session_title
    FROM [trn].[fn_enrolment_rows](@company_id) r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    WHERE r.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Enrolment not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;
    IF @session_status = N'cancelled'
        THROW 50409, N'status|SESSION_CLOSED|This session was cancelled.', 1;
    IF @status <> N'enrolled'
        THROW 50409, N'status|NOT_ENROLLED|Only an enrolled participant can complete the training.', 1;
    DECLARE @min DECIMAL(5,2) = (SELECT min_attendance_percent FROM [trn].[fn_settings](@company_id));
    IF @pct < @min
        THROW 50409, N'status|ATTENDANCE_SHORT|Attendance is below the minimum needed to complete the training.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [trn].[training_enrolment]
        SET status = N'completed', attendance_percent = @pct, score = @score, result_remarks = @remarks, completed_at = @now,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS enrolmentId, CONVERT(NVARCHAR(20), @session) AS sessionId,
                                                 CONVERT(NVARCHAR(20), @emp) AS employeeId, @pct AS attendancePercent, @score AS score
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                @title_n NVARCHAR(200) = LEFT(N'Training completed: ' + @title, 200),
                @link NVARCHAR(500) = N'/training/enrolments/' + CONVERT(NVARCHAR(20), @id);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.completed',
             @entity_type = N'trn.training_enrolment', @entity_id = @id, @payload = @payload;
        EXEC [trn].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title_n, @link = @link,
             @entity_type = N'trn.training_enrolment', @entity_id = @id;
    COMMIT;
    EXEC [trn].[usp_training_enrolment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Attaches the certificate (an uploaded file) to a completed enrolment; it expires after the program's
-- validity months, when the program sets them.
CREATE OR ALTER PROCEDURE [trn].[usp_training_certificate_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @file_id         BIGINT,
    @certificate_no  NVARCHAR(100) = NULL,
    @issued_date     DATE,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @emp BIGINT, @validity INT, @title NVARCHAR(200);
    SELECT @rv = e.row_version, @status = e.status, @emp = e.employee_id, @validity = p.certificate_validity_months, @title = s.title
    FROM [trn].[training_enrolment] e
    JOIN [trn].[training_session] s ON s.id = e.training_session_id
    JOIN [trn].[training_program] p ON p.id = s.training_program_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
    WHERE e.id = @id AND e.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Enrolment not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;
    IF @status <> N'completed'
        THROW 50409, N'status|NOT_COMPLETED|A certificate is given only for a completed training.', 1;
    IF @file_id IS NULL OR NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [trn].[training_enrolment]
        SET certificate_file_id = @file_id, certificate_no = NULLIF(LTRIM(RTRIM(@certificate_no)), N''), certificate_issued_date = @issued_date,
            certificate_expiry_date = CASE WHEN @validity IS NOT NULL THEN DATEADD(MONTH, @validity, @issued_date) END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS enrolmentId, CONVERT(NVARCHAR(20), @emp) AS employeeId,
                                                 CONVERT(NVARCHAR(20), @file_id) AS fileId, @issued_date AS issuedDate
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                @title_n NVARCHAR(200) = LEFT(N'Certificate issued: ' + @title, 200),
                @link NVARCHAR(500) = N'/training/enrolments/' + CONVERT(NVARCHAR(20), @id);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.certificate_issued',
             @entity_type = N'trn.training_enrolment', @entity_id = @id, @payload = @payload;
        EXEC [trn].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title_n, @link = @link,
             @entity_type = N'trn.training_enrolment', @entity_id = @id;
    COMMIT;
    EXEC [trn].[usp_training_enrolment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- The participant's own feedback, once the training is over for them (completed or not completed).
CREATE OR ALTER PROCEDURE [trn].[usp_training_feedback_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @overall_rating  INT,
    @trainer_rating  INT = NULL,
    @content_rating  INT = NULL,
    @comments        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @emp BIGINT, @session BIGINT;
    SELECT @status = e.status, @emp = e.employee_id, @session = e.training_session_id
    FROM [trn].[training_enrolment] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
    WHERE e.id = @id AND e.company_id = @company_id;
    IF @status IS NULL
        THROW 50404, N'Enrolment not found', 1;
    IF @emp <> ISNULL((SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id), 0)
        THROW 50403, N'Only the participant gives feedback on their training.', 1;
    IF @status NOT IN (N'completed', N'not_completed')
        THROW 50409, N'status|FEEDBACK_EARLY|Feedback opens once the training is over.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [trn].[training_feedback]
        SET overall_rating = @overall_rating, trainer_rating = @trainer_rating, content_rating = @content_rating, comments = @comments,
            updated_at = @now, updated_by = @actor_user_id
        WHERE training_enrolment_id = @id;
        IF @@ROWCOUNT = 0
            INSERT [trn].[training_feedback] (training_enrolment_id, overall_rating, trainer_rating, content_rating, comments, created_by)
            VALUES (@id, @overall_rating, @trainer_rating, @content_rating, @comments, @actor_user_id);
        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS enrolmentId, CONVERT(NVARCHAR(20), @session) AS sessionId,
                                                 CONVERT(NVARCHAR(20), @emp) AS employeeId, @overall_rating AS overallRating
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.feedback_submitted',
             @entity_type = N'trn.training_enrolment', @entity_id = @id, @payload = @payload;
    COMMIT;
    EXEC [trn].[usp_training_enrolment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_feedback_list]
    @company_id          BIGINT,
    @actor_user_id       BIGINT,
    @permission_code     NVARCHAR(150),
    @training_session_id BIGINT = NULL,
    @training_program_id BIGINT = NULL,
    @page                INT = 1,
    @page_size           INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.id INTO #ids
    FROM [trn].[training_feedback] f
    JOIN [trn].[training_enrolment] e ON e.id = f.training_enrolment_id AND e.company_id = @company_id
    JOIN [trn].[training_session] s ON s.id = e.training_session_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
    WHERE (@training_session_id IS NULL OR e.training_session_id = @training_session_id)
      AND (@training_program_id IS NULL OR s.training_program_id = @training_program_id)
    OPTION (RECOMPILE);
    SELECT COUNT(*) AS total FROM #ids;
    SELECT f.id, f.training_enrolment_id AS enrolment_id, e.training_session_id, s.title AS session_title, e.employee_id,
           CONCAT(emp.first_name, N' ', emp.last_name) AS employee_name, f.overall_rating, f.trainer_rating, f.content_rating,
           f.comments, f.created_at, f.updated_at
    FROM #ids i
    JOIN [trn].[training_feedback] f ON f.id = i.id
    JOIN [trn].[training_enrolment] e ON e.id = f.training_enrolment_id
    JOIN [trn].[training_session] s ON s.id = e.training_session_id
    JOIN [hr].[employee] emp ON emp.id = e.employee_id
    ORDER BY f.created_at DESC, f.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
