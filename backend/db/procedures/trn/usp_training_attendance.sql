-- Training -> Attendance: present / absent / excused per participant per session day. Calendar days from the
-- session's start to its end count as session days. Marks are only taken for enrolled seats on a scheduled
-- session, for days that have come.

-- Result sets: 1 the session; 2 its participants (seats), with days present; 3 the marks.
CREATE OR ALTER PROCEDURE [trn].[usp_training_attendance_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @session_id      BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [trn].[training_session] WHERE id = @session_id AND company_id = @company_id)
        THROW 50404, N'Session not found', 1;
    SELECT s.id, s.title, s.start_date, s.end_date, s.session_days, s.status FROM [trn].[fn_session_rows](@company_id) s WHERE s.id = @session_id;

    SELECT r.id AS enrolment_id, r.employee_id, r.employee_code, r.employee_name, r.status, r.present_days, r.session_days,
           r.attendance_to_date, r.row_version
    INTO #seats
    FROM [trn].[fn_enrolment_rows](@company_id) r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    WHERE r.training_session_id = @session_id AND r.status IN (N'enrolled', N'completed', N'not_completed');

    SELECT * FROM #seats ORDER BY employee_name, enrolment_id;
    SELECT a.training_enrolment_id AS enrolment_id, a.attendance_date, a.status, a.remarks
    FROM [trn].[training_attendance] a JOIN #seats s ON s.enrolment_id = a.training_enrolment_id
    ORDER BY a.attendance_date, a.training_enrolment_id;
END
GO

-- @marks: [{"enrolmentId", "status", "remarks"}] for one @attendance_date.
CREATE OR ALTER PROCEDURE [trn].[usp_training_attendance_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @session_id      BIGINT,
    @attendance_date DATE,
    @marks           NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @start DATE, @end DATE;
    SELECT @status = status, @start = start_date, @end = end_date FROM [trn].[training_session] WHERE id = @session_id AND company_id = @company_id;
    IF @status IS NULL
        THROW 50404, N'Session not found', 1;
    IF @status <> N'scheduled'
        THROW 50409, N'status|SESSION_CLOSED|This session is completed or cancelled.', 1;
    IF @attendance_date < @start OR @attendance_date > @end
        THROW 50400, N'attendanceDate|The date is outside the session.', 1;
    IF @attendance_date > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'attendanceDate|Attendance cannot be marked for a day that has not come.', 1;
    IF ISJSON(@marks) = 0
        THROW 50400, N'marks|Marks are not valid.', 1;

    DECLARE @in TABLE (enrolment_id BIGINT PRIMARY KEY, status NVARCHAR(30), remarks NVARCHAR(MAX));
    INSERT @in SELECT x.enrolment_id, x.status, x.remarks
    FROM OPENJSON(@marks) WITH (enrolment_id BIGINT '$.enrolmentId', status NVARCHAR(30) '$.status', remarks NVARCHAR(MAX) '$.remarks') x;
    IF EXISTS (SELECT 1 FROM @in i WHERE NOT EXISTS (
                   SELECT 1 FROM [trn].[training_enrolment] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
                   WHERE e.id = i.enrolment_id AND e.training_session_id = @session_id AND e.status = N'enrolled'))
        THROW 50400, N'marks|Attendance can only be marked for people enrolled on this session.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE a SET status = i.status, remarks = i.remarks, updated_at = @now, updated_by = @actor_user_id
        FROM [trn].[training_attendance] a JOIN @in i ON i.enrolment_id = a.training_enrolment_id
        WHERE a.attendance_date = @attendance_date;
        INSERT [trn].[training_attendance] (training_enrolment_id, attendance_date, status, remarks, created_by)
        SELECT i.enrolment_id, @attendance_date, i.status, i.remarks, @actor_user_id FROM @in i
        WHERE NOT EXISTS (SELECT 1 FROM [trn].[training_attendance] a WHERE a.training_enrolment_id = i.enrolment_id
                          AND a.attendance_date = @attendance_date);
    COMMIT;
    EXEC [trn].[usp_training_attendance_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @session_id = @session_id;
END
