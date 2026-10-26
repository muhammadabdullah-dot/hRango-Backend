-- Training -> Sessions: scheduled runs of a program (scheduled -> completed | cancelled). Seats taken are
-- enrolments that are enrolled, completed or not completed. Moving a session tells its participants;
-- cancelling it cancels their seats; completing it settles every enrolled seat by attendance.

CREATE OR ALTER PROCEDURE [trn].[usp_training_session_list]
    @company_id          BIGINT,
    @training_program_id BIGINT = NULL,
    @status              NVARCHAR(30) = NULL,
    @from_date           DATE = NULL,
    @to_date             DATE = NULL,
    @search              NVARCHAR(200) = NULL,
    @page                INT = 1,
    @page_size           INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SELECT COUNT(*) AS total FROM [trn].[training_session] s
    JOIN [trn].[training_program] p ON p.id = s.training_program_id
    WHERE s.company_id = @company_id
      AND (@training_program_id IS NULL OR s.training_program_id = @training_program_id)
      AND (@status IS NULL OR s.status = @status)
      AND (@from_date IS NULL OR s.end_date >= @from_date) AND (@to_date IS NULL OR s.start_date <= @to_date)
      AND (@pattern IS NULL OR s.title LIKE @pattern OR p.title LIKE @pattern OR s.venue LIKE @pattern OR s.trainer_name LIKE @pattern)
    OPTION (RECOMPILE);
    SELECT r.* FROM [trn].[fn_session_rows](@company_id) r
    WHERE (@training_program_id IS NULL OR r.training_program_id = @training_program_id)
      AND (@status IS NULL OR r.status = @status)
      AND (@from_date IS NULL OR r.end_date >= @from_date) AND (@to_date IS NULL OR r.start_date <= @to_date)
      AND (@pattern IS NULL OR r.title LIKE @pattern OR r.program_title LIKE @pattern OR r.venue LIKE @pattern OR r.trainer_name LIKE @pattern)
    ORDER BY r.start_date DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_session_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [trn].[training_session] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Session not found', 1;
    SELECT r.* FROM [trn].[fn_session_rows](@company_id) r WHERE r.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_session_save]
    @company_id          BIGINT,
    @actor_user_id       BIGINT = NULL,
    @id                  BIGINT = NULL,
    @training_program_id BIGINT,
    @title               NVARCHAR(200) = NULL,
    @start_date          DATE,
    @end_date            DATE,
    @start_time          TIME(0) = NULL,
    @end_time            TIME(0) = NULL,
    @delivery_mode       NVARCHAR(30),
    @venue               NVARCHAR(300) = NULL,
    @online_link         NVARCHAR(500) = NULL,
    @trainer_type        NVARCHAR(30),
    @trainer_employee_id BIGINT = NULL,
    @trainer_name        NVARCHAR(200) = NULL,
    @capacity            INT = NULL,
    @nomination_deadline DATE = NULL,
    @cost                DECIMAL(18,2) = NULL,
    @row_version         BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @program_title NVARCHAR(200), @program_active BIT;
    SELECT @program_title = title, @program_active = is_active FROM [trn].[training_program] WHERE id = @training_program_id AND company_id = @company_id;
    IF @program_title IS NULL
        THROW 50400, N'trainingProgramId|Program not found.', 1;
    IF @trainer_employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @trainer_employee_id AND company_id = @company_id)
        THROW 50400, N'trainerEmployeeId|Trainer not found.', 1;
    SET @title = ISNULL(NULLIF(LTRIM(RTRIM(@title)), N''), @program_title);

    DECLARE @old_program BIGINT, @old_start DATE, @old_end DATE, @old_st TIME(0), @old_et TIME(0), @old_venue NVARCHAR(300),
            @old_link NVARCHAR(500), @status NVARCHAR(30);
    IF @id IS NULL
    BEGIN
        IF @program_active = 0
            THROW 50400, N'trainingProgramId|This program is inactive.', 1;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8);
        SELECT @rv = row_version, @status = status, @old_program = training_program_id, @old_start = start_date, @old_end = end_date,
               @old_st = start_time, @old_et = end_time, @old_venue = venue, @old_link = online_link
        FROM [trn].[training_session] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Session not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this session. Reload it and try again', 1;
        IF @status <> N'scheduled'
            THROW 50409, N'status|SESSION_CLOSED|This session is completed or cancelled.', 1;
        IF @old_program <> @training_program_id AND EXISTS (SELECT 1 FROM [trn].[training_enrolment] WHERE training_session_id = @id)
            THROW 50409, N'trainingProgramId|SESSION_HAS_ENROLMENTS|People are nominated for this session. Its program cannot change.', 1;
        IF @capacity IS NOT NULL AND @capacity < (SELECT COUNT(*) FROM [trn].[training_enrolment] WHERE training_session_id = @id
                                                  AND status IN (N'enrolled', N'completed', N'not_completed'))
            THROW 50409, N'capacity|CAPACITY_BELOW_ENROLLED|More people are enrolled than this capacity allows.', 1;
        IF EXISTS (SELECT 1 FROM [trn].[training_attendance] a JOIN [trn].[training_enrolment] e ON e.id = a.training_enrolment_id
                   WHERE e.training_session_id = @id AND (a.attendance_date < @start_date OR a.attendance_date > @end_date))
            THROW 50409, N'startDate|ATTENDANCE_OUTSIDE|Attendance is marked on days outside these dates.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @payload NVARCHAR(MAX);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [trn].[training_session] (company_id, training_program_id, title, start_date, end_date, start_time, end_time, delivery_mode,
                venue, online_link, trainer_type, trainer_employee_id, trainer_name, capacity, nomination_deadline, status, cost, created_by)
            VALUES (@company_id, @training_program_id, @title, @start_date, @end_date, @start_time, @end_time, @delivery_mode,
                @venue, @online_link, @trainer_type, @trainer_employee_id, @trainer_name, @capacity, @nomination_deadline, N'scheduled', @cost,
                @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            SET @payload = (SELECT CONVERT(NVARCHAR(20), @id) AS sessionId, CONVERT(NVARCHAR(20), @training_program_id) AS programId,
                                   @title AS title, @start_date AS startDate, @end_date AS endDate, @delivery_mode AS deliveryMode,
                                   @capacity AS capacity
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.session_scheduled',
                 @entity_type = N'trn.training_session', @entity_id = @id, @payload = @payload;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'trn.training_session', @id, N'title', @title, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [trn].[training_session]
            SET training_program_id = @training_program_id, title = @title, start_date = @start_date, end_date = @end_date,
                start_time = @start_time, end_time = @end_time, delivery_mode = @delivery_mode, venue = @venue, online_link = @online_link,
                trainer_type = @trainer_type, trainer_employee_id = @trainer_employee_id, trainer_name = @trainer_name,
                capacity = @capacity, nomination_deadline = @nomination_deadline, cost = @cost, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this session. Reload it and try again', 1;
            IF @old_start <> @start_date OR @old_end <> @end_date OR ISNULL(@old_st, '00:00') <> ISNULL(@start_time, '00:00')
               OR ISNULL(@old_et, '00:00') <> ISNULL(@end_time, '00:00') OR ISNULL(@old_venue, N'') <> ISNULL(@venue, N'')
               OR ISNULL(@old_link, N'') <> ISNULL(@online_link, N'')
            BEGIN
                DECLARE @title_n NVARCHAR(200) = LEFT(N'Training session changed: ' + @title, 200),
                        @body NVARCHAR(MAX) = @title + N' now runs ' + CONVERT(NVARCHAR(10), @start_date, 23) + N' to '
                                              + CONVERT(NVARCHAR(10), @end_date, 23) + ISNULL(N' at ' + @venue, N'') + N'.';
                EXEC [trn].[usp_notify_session] @company_id = @company_id, @session_id = @id, @statuses = N'enrolled,requested',
                     @title = @title_n, @body = @body;
                SET @payload = (SELECT CONVERT(NVARCHAR(20), @id) AS sessionId, @start_date AS startDate, @end_date AS endDate,
                                       @venue AS venue FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
                EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.session_rescheduled',
                     @entity_type = N'trn.training_session', @entity_id = @id, @payload = @payload;
            END
        END
    COMMIT;
    EXEC [trn].[usp_training_session_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_session_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @title NVARCHAR(200);
    SELECT @rv = row_version, @title = title FROM [trn].[training_session] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Session not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this session. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [trn].[training_enrolment] WHERE training_session_id = @id)
        THROW 50409, N'id|SESSION_HAS_ENROLMENTS|People are nominated for this session. Cancel it instead', 1;
    BEGIN TRAN;
        DELETE [trn].[training_session] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'trn.training_session', @id, N'title', @title, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_session_cancel]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @reason        NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @title NVARCHAR(200);
    SELECT @rv = row_version, @status = status, @title = title FROM [trn].[training_session] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Session not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this session. Reload it and try again', 1;
    IF @status <> N'scheduled'
        THROW 50409, N'status|SESSION_CLOSED|This session is completed or cancelled.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DECLARE @title_n NVARCHAR(200) = LEFT(N'Training session cancelled: ' + @title, 200);
        EXEC [trn].[usp_notify_session] @company_id = @company_id, @session_id = @id, @statuses = N'enrolled,requested',
             @title = @title_n, @body = @reason;
        UPDATE [trn].[training_enrolment] SET status = N'cancelled', decision_remarks = ISNULL(@reason, decision_remarks),
               decided_at = @now, decided_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE training_session_id = @id AND status IN (N'requested', N'enrolled');
        UPDATE [trn].[training_session] SET status = N'cancelled', cancel_reason = @reason, cancelled_at = @now,
               updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS sessionId, @title AS title, @reason AS reason
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.session_cancelled',
             @entity_type = N'trn.training_session', @entity_id = @id, @payload = @payload;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'trn.training_session', @id, N'status', @status, N'cancelled', N'cancel', @actor_user_id, @now);
    COMMIT;
    EXEC [trn].[usp_training_session_get] @company_id = @company_id, @id = @id;
END
GO

-- Closes a session: each enrolled seat becomes completed when its attendance reaches the company's minimum
-- (training settings), otherwise not_completed; nominations still waiting are cancelled.
CREATE OR ALTER PROCEDURE [trn].[usp_training_session_complete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @title NVARCHAR(200), @days INT;
    SELECT @rv = row_version, @status = status, @title = title, @days = DATEDIFF(DAY, start_date, end_date) + 1
    FROM [trn].[training_session] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Session not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this session. Reload it and try again', 1;
    IF @status <> N'scheduled'
        THROW 50409, N'status|SESSION_CLOSED|This session is completed or cancelled.', 1;

    DECLARE @min DECIMAL(5,2) = (SELECT min_attendance_percent FROM [trn].[fn_settings](@company_id));
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @done TABLE (id BIGINT, employee_id BIGINT, status NVARCHAR(30));
    BEGIN TRAN;
        UPDATE e
        SET attendance_percent = x.pct,
            status = CASE WHEN x.pct >= @min THEN N'completed' ELSE N'not_completed' END,
            completed_at = CASE WHEN x.pct >= @min THEN @now END, updated_at = @now, updated_by = @actor_user_id
        OUTPUT inserted.id, inserted.employee_id, inserted.status INTO @done
        FROM [trn].[training_enrolment] e
        CROSS APPLY (SELECT CAST(COUNT(a.id) * 100.0 / @days AS DECIMAL(5,2)) AS pct
                     FROM [trn].[training_attendance] a WHERE a.training_enrolment_id = e.id AND a.status = N'present') x
        WHERE e.training_session_id = @id AND e.status = N'enrolled';
        UPDATE [trn].[training_enrolment] SET status = N'cancelled', decision_remarks = N'The session was completed before this nomination was decided.',
               decided_at = @now, decided_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE training_session_id = @id AND status = N'requested';
        UPDATE [trn].[training_session] SET status = N'completed', completed_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;

        DECLARE @eid BIGINT = (SELECT MIN(id) FROM @done WHERE status = N'completed'), @emp BIGINT, @payload NVARCHAR(MAX),
                @title_n NVARCHAR(200) = LEFT(N'Training completed: ' + @title, 200), @link NVARCHAR(500);
        WHILE @eid IS NOT NULL
        BEGIN
            SELECT @emp = employee_id FROM @done WHERE id = @eid;
            SET @payload = (SELECT CONVERT(NVARCHAR(20), @eid) AS enrolmentId, CONVERT(NVARCHAR(20), @id) AS sessionId,
                                   CONVERT(NVARCHAR(20), @emp) AS employeeId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.completed',
                 @entity_type = N'trn.training_enrolment', @entity_id = @eid, @payload = @payload;
            SET @link = N'/training/enrolments/' + CONVERT(NVARCHAR(20), @eid);
            EXEC [trn].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title_n, @link = @link,
                 @entity_type = N'trn.training_enrolment', @entity_id = @eid;
            SET @eid = (SELECT MIN(id) FROM @done WHERE status = N'completed' AND id > @eid);
        END
        SET @payload = (SELECT CONVERT(NVARCHAR(20), @id) AS sessionId, @title AS title,
                               (SELECT COUNT(*) FROM @done WHERE status = N'completed') AS completed,
                               (SELECT COUNT(*) FROM @done WHERE status = N'not_completed') AS notCompleted
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'training.session_completed',
             @entity_type = N'trn.training_session', @entity_id = @id, @payload = @payload;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'trn.training_session', @id, N'status', @status, N'completed', N'complete', @actor_user_id, @now);
    COMMIT;
    EXEC [trn].[usp_training_session_get] @company_id = @company_id, @id = @id;
END
