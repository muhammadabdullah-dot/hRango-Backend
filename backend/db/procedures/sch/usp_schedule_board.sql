-- Internal: the employees a Scheduling board shows, into the caller's #emp (employee_id BIGINT).
-- Always only those auth.fn_visible_employees gives for @permission_code; @tab narrows further:
-- my = the caller's own employee record, subordinates = direct and indirect reports, all = everyone
-- reachable. @time_slot_id: with a shift of that slot in the range; @roster_group_id: enrolled in
-- that group for some of the range.
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_board_employees]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @tab                NVARCHAR(30) = N'all',
    @from_date          DATE,
    @to_date            DATE,
    @search             NVARCHAR(200) = NULL,
    @employee_id        BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @branch_id          BIGINT = NULL,
    @location_id        BIGINT = NULL,
    @designation_id     BIGINT = NULL,
    @employment_type_id BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @grade_id           BIGINT = NULL,
    @status             NVARCHAR(30) = NULL,
    @time_slot_id       BIGINT = NULL,
    @roster_group_id    BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    CREATE TABLE #team (id BIGINT PRIMARY KEY);
    IF @tab = N'subordinates' AND @me IS NOT NULL
    BEGIN
        ;WITH team AS (
            SELECT e.id FROM [hr].[employee] e WHERE e.line_manager_id = @me AND e.company_id = @company_id
            UNION ALL
            SELECT e.id FROM [hr].[employee] e JOIN team t ON e.line_manager_id = t.id
        )
        INSERT #team (id) SELECT DISTINCT id FROM team OPTION (MAXRECURSION 100);
    END

    INSERT #emp (employee_id)
    SELECT e.id
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    WHERE e.company_id = @company_id
      AND (@tab = N'all' OR (@tab = N'my' AND e.id = @me) OR (@tab = N'subordinates' AND e.id IN (SELECT id FROM #team)))
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
      AND (@employee_id IS NULL OR e.id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@location_id IS NULL OR e.location_id = @location_id)
      AND (@designation_id IS NULL OR e.designation_id = @designation_id)
      AND (@employment_type_id IS NULL OR e.employment_type_id = @employment_type_id)
      AND (@employee_group_id IS NULL OR e.employee_group_id = @employee_group_id)
      AND (@grade_id IS NULL OR e.grade_id = @grade_id)
      AND (@status IS NULL OR e.status = @status)
      AND (@time_slot_id IS NULL OR EXISTS (SELECT 1 FROM [sch].[schedule] s WHERE s.employee_id = e.id
                                             AND s.time_slot_id = @time_slot_id AND s.work_date BETWEEN @from_date AND @to_date))
      AND (@roster_group_id IS NULL OR EXISTS (SELECT 1 FROM [sch].[roster_group_member] m WHERE m.employee_id = e.id
                                                AND m.roster_group_id = @roster_group_id AND m.start_date <= @to_date
                                                AND (m.end_date IS NULL OR m.end_date >= @from_date)))
    OPTION (RECOMPILE);
END
GO

-- The Scheduling board (week or month): a page of employees and what is planned for them from
-- @from_date to @to_date. Result sets:
--   1 total employees   2 the page of employees, with planned minutes and shifts in the range
--   3 their shifts      4 their rest days   5 their holidays
--   6 planned minutes and shifts per date over every matching employee (the "Planned Hours" footer)
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_board]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @tab                NVARCHAR(30) = N'all',
    @from_date          DATE,
    @to_date            DATE,
    @search             NVARCHAR(200) = NULL,
    @employee_id        BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @branch_id          BIGINT = NULL,
    @location_id        BIGINT = NULL,
    @designation_id     BIGINT = NULL,
    @employment_type_id BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @grade_id           BIGINT = NULL,
    @status             NVARCHAR(30) = NULL,
    @time_slot_id       BIGINT = NULL,
    @roster_group_id    BIGINT = NULL,
    @page               INT = 1,
    @page_size          INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #emp (employee_id BIGINT PRIMARY KEY);
    EXEC [sch].[usp_schedule_board_employees] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @tab = @tab, @from_date = @from_date, @to_date = @to_date, @search = @search,
         @employee_id = @employee_id, @department_id = @department_id, @branch_id = @branch_id, @location_id = @location_id,
         @designation_id = @designation_id, @employment_type_id = @employment_type_id, @employee_group_id = @employee_group_id,
         @grade_id = @grade_id, @status = @status, @time_slot_id = @time_slot_id, @roster_group_id = @roster_group_id;

    SELECT COUNT(*) AS total FROM #emp;

    CREATE TABLE #page (employee_id BIGINT PRIMARY KEY, sort_no INT);
    INSERT #page (employee_id, sort_no)
    SELECT x.employee_id, x.rn
    FROM (SELECT e.id AS employee_id, ROW_NUMBER() OVER (ORDER BY e.first_name, e.last_name, e.id) AS rn
          FROM #emp p JOIN [hr].[employee] e ON e.id = p.employee_id) x
    WHERE x.rn > (@page - 1) * @page_size AND x.rn <= @page * @page_size;

    SELECT e.id, e.code, CONCAT(e.first_name, N' ', e.last_name) AS name, des.name AS designation_name,
           dep.name AS department_name, e.status, e.default_time_slot_id, ts.name AS default_time_slot_name,
           ISNULL(t.planned_minutes, 0) AS planned_minutes, ISNULL(t.shift_count, 0) AS shift_count
    FROM #page p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [org].[designation] des ON des.id = e.designation_id
    LEFT JOIN [org].[department] dep ON dep.id = e.department_id
    LEFT JOIN [sch].[time_slot] ts ON ts.id = e.default_time_slot_id
    OUTER APPLY (SELECT SUM(s.planned_minutes) AS planned_minutes, COUNT(*) AS shift_count
                 FROM [sch].[schedule] s WHERE s.employee_id = e.id AND s.work_date BETWEEN @from_date AND @to_date) t
    ORDER BY p.sort_no;

    SELECT s.id, s.employee_id, s.work_date, s.start_at, s.end_at, s.time_slot_id, ts.code AS time_slot_code,
           ts.name AS time_slot_name, ts.color AS time_slot_color, ts.is_flexible,
           CAST(CASE WHEN CAST(s.end_at AS DATE) > s.work_date THEN 1 ELSE 0 END AS BIT) AS is_overnight,
           s.geo_fence_id, gf.name AS geo_fence_name, s.is_wfh, s.planned_minutes, s.schedule_batch_id, s.row_version
    FROM #page p
    JOIN [sch].[schedule] s ON s.employee_id = p.employee_id AND s.work_date BETWEEN @from_date AND @to_date
    JOIN [sch].[time_slot] ts ON ts.id = s.time_slot_id
    LEFT JOIN [att].[geo_fence] gf ON gf.id = s.geo_fence_id
    ORDER BY p.sort_no, s.start_at;

    SELECT r.id, r.employee_id, r.rest_date, r.is_payable, r.rest_day_rule_id, r.request_id
    FROM #page p
    JOIN [sch].[rest_day] r ON r.employee_id = p.employee_id AND r.rest_date BETWEEN @from_date AND @to_date
    ORDER BY p.sort_no, r.rest_date;

    SELECT h.employee_id, h.holiday_date, h.holiday_id, h.holiday_name, h.holiday_type, h.attendance_exempt
    FROM [sch].[fn_employee_holidays](@company_id, @from_date, @to_date) h
    JOIN #page p ON p.employee_id = h.employee_id
    ORDER BY p.sort_no, h.holiday_date, h.holiday_id;

    SELECT s.work_date, SUM(s.planned_minutes) AS planned_minutes, COUNT(*) AS shift_count
    FROM #emp p
    JOIN [sch].[schedule] s ON s.employee_id = p.employee_id AND s.work_date BETWEEN @from_date AND @to_date
    GROUP BY s.work_date
    ORDER BY s.work_date;
END
GO

-- The year view: per employee and month, planned minutes, shifts and rest days.
-- Result sets: 1 total employees, 2 the page of employees, 3 their months (only months with something).
CREATE OR ALTER PROCEDURE [sch].[usp_schedule_year]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @tab                NVARCHAR(30) = N'all',
    @year               INT,
    @search             NVARCHAR(200) = NULL,
    @employee_id        BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @branch_id          BIGINT = NULL,
    @location_id        BIGINT = NULL,
    @designation_id     BIGINT = NULL,
    @employment_type_id BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @grade_id           BIGINT = NULL,
    @status             NVARCHAR(30) = NULL,
    @time_slot_id       BIGINT = NULL,
    @roster_group_id    BIGINT = NULL,
    @page               INT = 1,
    @page_size          INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @from_date DATE = DATEFROMPARTS(@year, 1, 1), @to_date DATE = DATEFROMPARTS(@year, 12, 31);

    CREATE TABLE #emp (employee_id BIGINT PRIMARY KEY);
    EXEC [sch].[usp_schedule_board_employees] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @tab = @tab, @from_date = @from_date, @to_date = @to_date, @search = @search,
         @employee_id = @employee_id, @department_id = @department_id, @branch_id = @branch_id, @location_id = @location_id,
         @designation_id = @designation_id, @employment_type_id = @employment_type_id, @employee_group_id = @employee_group_id,
         @grade_id = @grade_id, @status = @status, @time_slot_id = @time_slot_id, @roster_group_id = @roster_group_id;

    SELECT COUNT(*) AS total FROM #emp;

    CREATE TABLE #page (employee_id BIGINT PRIMARY KEY, sort_no INT);
    INSERT #page (employee_id, sort_no)
    SELECT x.employee_id, x.rn
    FROM (SELECT e.id AS employee_id, ROW_NUMBER() OVER (ORDER BY e.first_name, e.last_name, e.id) AS rn
          FROM #emp p JOIN [hr].[employee] e ON e.id = p.employee_id) x
    WHERE x.rn > (@page - 1) * @page_size AND x.rn <= @page * @page_size;

    SELECT e.id, e.code, CONCAT(e.first_name, N' ', e.last_name) AS name, des.name AS designation_name,
           dep.name AS department_name, e.status, e.default_time_slot_id, ts.name AS default_time_slot_name,
           ISNULL(t.planned_minutes, 0) AS planned_minutes, ISNULL(t.shift_count, 0) AS shift_count
    FROM #page p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [org].[designation] des ON des.id = e.designation_id
    LEFT JOIN [org].[department] dep ON dep.id = e.department_id
    LEFT JOIN [sch].[time_slot] ts ON ts.id = e.default_time_slot_id
    OUTER APPLY (SELECT SUM(s.planned_minutes) AS planned_minutes, COUNT(*) AS shift_count
                 FROM [sch].[schedule] s WHERE s.employee_id = e.id AND s.work_date BETWEEN @from_date AND @to_date) t
    ORDER BY p.sort_no;

    SELECT m.employee_id, m.month_no, SUM(m.planned_minutes) AS planned_minutes, SUM(m.shift_count) AS shift_count,
           SUM(m.rest_days) AS rest_days
    FROM (
        SELECT s.employee_id, MONTH(s.work_date) AS month_no, s.planned_minutes, 1 AS shift_count, 0 AS rest_days
        FROM #page p JOIN [sch].[schedule] s ON s.employee_id = p.employee_id AND s.work_date BETWEEN @from_date AND @to_date
        UNION ALL
        SELECT r.employee_id, MONTH(r.rest_date), 0, 0, 1
        FROM #page p JOIN [sch].[rest_day] r ON r.employee_id = p.employee_id AND r.rest_date BETWEEN @from_date AND @to_date
    ) m
    GROUP BY m.employee_id, m.month_no
    ORDER BY m.employee_id, m.month_no;
END
