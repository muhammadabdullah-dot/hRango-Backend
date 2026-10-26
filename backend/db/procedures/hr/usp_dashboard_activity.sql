-- Dashboard figures read from other modules' tables as the ERD defines them: the time sheet
-- (att.timesheet_day) and leave requests (req.request + req.req_leave). Kept apart from the
-- workforce figures so a change there touches only this file.

-- Attendance for the employees the permission reaches.
--   1 totals for @day: present (present, half day, short day, WFH, official visit), absent, on leave
--   2 per month of @day's year: present, absent and leave days
--   3 @day's time sheet rows (latest first, up to @rows): staff, first in, last out, status
CREATE OR ALTER PROCEDURE [hr].[usp_dashboard_attendance]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @day             DATE = NULL,
    @rows            INT = 10,
    @only_employee   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @day = ISNULL(@day, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @year_start DATE = DATEFROMPARTS(YEAR(@day), 1, 1);

    DECLARE @e TABLE (id BIGINT PRIMARY KEY);
    INSERT @e
    SELECT v.employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
    WHERE @only_employee IS NULL OR v.employee_id = @only_employee;

    SELECT SUM(CASE WHEN t.day_status IN (N'present', N'half_day', N'short_day', N'wfh', N'official_visit') THEN 1 ELSE 0 END) AS present,
           SUM(CASE WHEN t.day_status = N'absent' THEN 1 ELSE 0 END) AS absent,
           SUM(CASE WHEN t.day_status = N'leave' THEN 1 ELSE 0 END) AS on_leave
    FROM [att].[timesheet_day] t JOIN @e e ON e.id = t.employee_id
    WHERE t.work_date = @day;

    SELECT MONTH(t.work_date) AS month,
           SUM(CASE WHEN t.day_status IN (N'present', N'half_day', N'short_day', N'wfh', N'official_visit') THEN 1 ELSE 0 END) AS present,
           SUM(CASE WHEN t.day_status = N'absent' THEN 1 ELSE 0 END) AS absent,
           SUM(CASE WHEN t.day_status = N'leave' THEN 1 ELSE 0 END) AS on_leave
    FROM [att].[timesheet_day] t JOIN @e e ON e.id = t.employee_id
    WHERE t.work_date BETWEEN @year_start AND @day
    GROUP BY MONTH(t.work_date)
    ORDER BY MONTH(t.work_date);

    SELECT TOP (@rows) t.employee_id, LTRIM(RTRIM(CONCAT(x.first_name, N' ', x.last_name))) AS employee_name,
           ds.name AS designation_name, t.first_in, t.last_out, t.day_status
    FROM [att].[timesheet_day] t
    JOIN @e e ON e.id = t.employee_id
    JOIN [hr].[employee] x ON x.id = t.employee_id
    LEFT JOIN [org].[designation] ds ON ds.id = x.designation_id
    WHERE t.work_date = @day
    ORDER BY t.first_in DESC, t.employee_id;
END
GO

-- Latest leave requests of the employees the permission reaches (the dashboards' Leave
-- Applications table): staff, applied on, days, reason, status.
CREATE OR ALTER PROCEDURE [hr].[usp_dashboard_leave_applications]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @rows            INT = 6,
    @only_employee   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@rows) r.id, r.employee_id, LTRIM(RTRIM(CONCAT(x.first_name, N' ', x.last_name))) AS employee_name,
           ds.name AS designation_name, r.submitted_at AS applied_at, r.from_date, r.to_date, l.days, r.reason, r.status
    FROM [req].[request] r
    JOIN [req].[request_type] rt ON rt.id = r.request_type_id AND rt.code = N'leave'
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    JOIN [hr].[employee] x ON x.id = r.employee_id
    LEFT JOIN [req].[req_leave] l ON l.request_id = r.id
    LEFT JOIN [org].[designation] ds ON ds.id = x.designation_id
    WHERE r.company_id = @company_id AND r.is_deleted = 0
      AND (@only_employee IS NULL OR r.employee_id = @only_employee)
    ORDER BY ISNULL(r.submitted_at, r.created_at) DESC, r.id DESC;
END
