-- Clock In / Clock Out from the web dashboard and the mobile app, for the signed-in user's own employee record.
-- The location and IP checks are done in app/services/attendance_service.py with what usp_clock_context returns.

-- Result set 1: the employee, the switches, now, the current shift and the last punch.
-- Result set 2: geo fences the punch must fall in (is_shift_fence = the current shift's fence, when
--               "Geo Fences Required On Shift" is on). Result set 3: IP restrictions that apply.
CREATE OR ALTER PROCEDURE [att].[usp_clock_context]
    @company_id    BIGINT,
    @actor_user_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @employee_id BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                                   JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                                   WHERE u.id = @actor_user_id);
    DECLARE @now DATETIME2(0) = [att].[fn_company_now](@company_id);
    DECLARE @geo_on_shift BIT = CASE WHEN [att].[fn_setting](@company_id, N'scheduling', N'geo_fence_required_on_shift') IN (N'true', N'1') THEN 1 ELSE 0 END;

    DECLARE @schedule_id BIGINT, @start_at DATETIME2(0), @end_at DATETIME2(0), @shift_fence BIGINT;
    SELECT TOP 1 @schedule_id = s.id, @start_at = s.start_at, @end_at = s.end_at, @shift_fence = s.geo_fence_id
    FROM [sch].[schedule] s
    WHERE s.employee_id = @employee_id AND s.company_id = @company_id
      AND s.start_at <= DATEADD(HOUR, 4, @now) AND s.end_at >= DATEADD(HOUR, -4, @now)
    ORDER BY ABS(DATEDIFF(MINUTE, s.start_at, @now));

    DECLARE @last_type NVARCHAR(30), @last_at DATETIME2(0), @last_id BIGINT;
    SELECT TOP 1 @last_id = p.id, @last_type = p.punch_type, @last_at = p.punched_at
    FROM [att].[punch] p
    WHERE p.employee_id = @employee_id AND p.is_ignored = 0
      AND p.punched_at > DATEADD(HOUR, -20, @now) AND p.punched_at <= DATEADD(MINUTE, 5, @now)
    ORDER BY p.punched_at DESC, p.id DESC;

    SELECT @employee_id AS employee_id,
           (SELECT CONCAT(first_name, N' ', last_name) FROM [hr].[employee] WHERE id = @employee_id) AS employee_name,
           @now AS now_local,
           CAST(CASE WHEN [att].[fn_setting](@company_id, N'attendance', N'dashboard_punch') IN (N'true', N'1') THEN 1 ELSE 0 END AS BIT) AS dashboard_punch,
           CAST(CASE WHEN [att].[fn_setting](@company_id, N'attendance', N'picture_on_dashboard_punch') IN (N'true', N'1') THEN 1 ELSE 0 END AS BIT) AS picture_required,
           @geo_on_shift AS geo_fence_required_on_shift,
           @schedule_id AS schedule_id, @start_at AS expected_in, @end_at AS expected_out,
           @last_id AS last_punch_id, @last_type AS last_punch_type, @last_at AS last_punched_at,
           CASE WHEN @last_type IN (N'check_in', N'break_in') THEN N'check_out' ELSE N'check_in' END AS next_punch_type;

    SELECT f.id, f.code, f.name, f.shape, f.center_lat, f.center_lng, f.radius_m, f.polygon_points,
           CAST(CASE WHEN @geo_on_shift = 1 AND f.id = @shift_fence THEN 1 ELSE 0 END AS BIT) AS is_shift_fence
    FROM [att].[geo_fence] f
    WHERE f.company_id = @company_id AND f.is_active = 1
      AND (f.id IN (SELECT geo_fence_id FROM [att].[fn_employee_geo_fences](@company_id, @employee_id))
           OR (@geo_on_shift = 1 AND f.id = @shift_fence));

    SELECT r.id, r.code, r.ipv4, r.ipv6, r.netmask, r.range_start, r.range_end
    FROM [att].[ip_restriction] r
    WHERE r.id IN (SELECT ip_restriction_id FROM [att].[fn_employee_ip_restrictions](@company_id, @employee_id));
END
GO

-- Records the punch at the company's current time and re-processes the day. Returns the punch.
CREATE OR ALTER PROCEDURE [att].[usp_clock_punch]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @punch_type    NVARCHAR(30),
    @source        NVARCHAR(30),
    @latitude      DECIMAL(9,6) = NULL,
    @longitude     DECIMAL(9,6) = NULL,
    @ip_address    NVARCHAR(45) = NULL,
    @photo_file_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                                   JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                                   WHERE u.id = @actor_user_id);
    IF @employee_id IS NULL
        THROW 50403, N'Your user is not linked to an employee in this company', 1;
    IF @punch_type NOT IN (N'check_in', N'check_out')
        THROW 50400, N'punchType|Punch type must be check in or check out.', 1;
    IF @source NOT IN (N'web', N'mobile')
        THROW 50400, N'source|Source must be web or mobile.', 1;
    IF @photo_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @photo_file_id))
        THROW 50400, N'photoFileId|The photo was not found. Take it again.', 1;

    DECLARE @now DATETIME2(0) = [att].[fn_company_now](@company_id), @id BIGINT;
    IF EXISTS (SELECT 1 FROM [att].[punch] WHERE employee_id = @employee_id AND punch_type = @punch_type
               AND punched_at > DATEADD(MINUTE, -1, @now))
        THROW 50409, N'punchType|PUNCH_REPEATED|You punched a moment ago.', 1;

    BEGIN TRAN;
        INSERT [att].[punch] (company_id, employee_id, punched_at, punch_type, source, latitude, longitude, ip_address,
                              photo_file_id, created_by)
        VALUES (@company_id, @employee_id, @now, @punch_type, @source, @latitude, @longitude, @ip_address,
                @photo_file_id, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    COMMIT;

    EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @now;
    EXEC [att].[usp_punch_get] @company_id = @company_id, @id = @id;
END
