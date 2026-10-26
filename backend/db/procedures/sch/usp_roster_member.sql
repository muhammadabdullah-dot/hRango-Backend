-- Roster enrolments: an employee on a roster group for a period. One roster per employee at a time.
-- Every procedure here takes the permission code the endpoint required and only reaches employees
-- auth.fn_visible_employees gives for it. "Active" = not ended before today; "discontinued" = ended.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_member_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM [sch].[roster_group_member] m
        JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = m.employee_id
        WHERE m.id = @id AND g.company_id = @company_id)
        THROW 50404, N'Enrolment not found', 1;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    SELECT m.id, m.roster_group_id, g.title AS roster_group_title, m.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, dep.name AS department_name,
           des.name AS designation_name, b.name AS branch_name, m.start_date, m.end_date,
           CASE WHEN m.end_date IS NOT NULL AND m.end_date < @today THEN N'discontinued' ELSE N'active' END AS status,
           m.created_at, m.updated_at, m.row_version
    FROM [sch].[roster_group_member] m
    JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
    JOIN [hr].[employee] e ON e.id = m.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = m.employee_id
    LEFT JOIN [org].[department] dep ON dep.id = e.department_id
    LEFT JOIN [org].[designation] des ON des.id = e.designation_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    WHERE m.id = @id AND g.company_id = @company_id;
END
GO

-- Enrolments of one roster group. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_member_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @roster_group_id BIGINT,
    @status          NVARCHAR(30) = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[roster_group] WHERE id = @roster_group_id AND company_id = @company_id)
        THROW 50404, N'Roster group not found', 1;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT m.id, m.employee_id
    INTO #m
    FROM [sch].[roster_group_member] m
    JOIN [hr].[employee] e ON e.id = m.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = m.employee_id
    WHERE m.roster_group_id = @roster_group_id
      AND (@status IS NULL
           OR (@status = N'active' AND (m.end_date IS NULL OR m.end_date >= @today))
           OR (@status = N'discontinued' AND m.end_date < @today))
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #m;

    SELECT m.id, m.roster_group_id, g.title AS roster_group_title, m.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, dep.name AS department_name,
           des.name AS designation_name, b.name AS branch_name, m.start_date, m.end_date,
           CASE WHEN m.end_date IS NOT NULL AND m.end_date < @today THEN N'discontinued' ELSE N'active' END AS status,
           m.created_at, m.updated_at, m.row_version
    FROM #m x
    JOIN [sch].[roster_group_member] m ON m.id = x.id
    JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
    JOIN [hr].[employee] e ON e.id = m.employee_id
    LEFT JOIN [org].[department] dep ON dep.id = e.department_id
    LEFT JOIN [org].[designation] des ON des.id = e.designation_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    ORDER BY e.first_name, e.last_name, m.start_date, m.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Enrols several employees in one roster group for a period. @employee_ids is a JSON array of ids.
-- The period must sit inside the group's; an open end takes the group's end. An employee already on
-- a roster for any of these dates is refused. Returns the new enrolments.
CREATE OR ALTER PROCEDURE [sch].[usp_roster_member_enroll]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @roster_group_id BIGINT,
    @employee_ids    NVARCHAR(MAX),
    @start_date      DATE,
    @end_date        DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @g_from DATE, @g_to DATE;
    SELECT @g_from = from_date, @g_to = to_date FROM [sch].[roster_group] WHERE id = @roster_group_id AND company_id = @company_id;
    IF @g_from IS NULL
        THROW 50404, N'Roster group not found', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Start date is required.', 1;
    SET @end_date = ISNULL(@end_date, @g_to);
    IF @end_date IS NOT NULL AND @end_date < @start_date
        THROW 50400, N'endDate|End date cannot be before the start date.', 1;
    IF @start_date < @g_from OR (@g_to IS NOT NULL AND @end_date > @g_to)
        THROW 50400, N'startDate|The enrolment must sit inside the roster group''s dates.', 1;
    IF @employee_ids IS NULL OR ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Select at least one employee.', 1;

    DECLARE @ids TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @ids SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@employee_ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @ids)
        THROW 50400, N'employeeIds|Select at least one employee.', 1;
    IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = i.employee_id AND e.company_id = @company_id))
        THROW 50400, N'employeeIds|Employee not found.', 1;
    IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (
                   SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = i.employee_id))
        THROW 50403, N'You cannot enrol one or more of these employees.', 1;
    IF EXISTS (SELECT 1 FROM @ids i JOIN [sch].[roster_group_member] m ON m.employee_id = i.employee_id
               WHERE m.start_date <= ISNULL(@end_date, '99991231') AND @start_date <= ISNULL(m.end_date, '99991231'))
        THROW 50409, N'employeeIds|ENROLMENT_OVERLAP|One or more employees are already on a roster for these dates.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @new TABLE (id BIGINT);

    BEGIN TRAN;
        INSERT [sch].[roster_group_member] (roster_group_id, employee_id, start_date, end_date, created_by)
        OUTPUT INSERTED.id INTO @new (id)
        SELECT @roster_group_id, employee_id, @start_date, @end_date, @actor_user_id FROM @ids;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'sch.roster_group_member', id, N'create', @actor_user_id, @now FROM @new;
    COMMIT;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);
    SELECT m.id, m.roster_group_id, g.title AS roster_group_title, m.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, dep.name AS department_name,
           des.name AS designation_name, b.name AS branch_name, m.start_date, m.end_date,
           CASE WHEN m.end_date IS NOT NULL AND m.end_date < @today THEN N'discontinued' ELSE N'active' END AS status,
           m.created_at, m.updated_at, m.row_version
    FROM @new n
    JOIN [sch].[roster_group_member] m ON m.id = n.id
    JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
    JOIN [hr].[employee] e ON e.id = m.employee_id
    LEFT JOIN [org].[department] dep ON dep.id = e.department_id
    LEFT JOIN [org].[designation] des ON des.id = e.designation_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    ORDER BY e.first_name, e.last_name, m.id;
END
GO

-- Changes an enrolment's dates. Discontinuing is setting the end date (today by default, in the service).
CREATE OR ALTER PROCEDURE [sch].[usp_roster_member_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @start_date      DATE,
    @end_date        DATE = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @employee_id BIGINT, @group_id BIGINT, @old_start DATE, @old_end DATE;
    SELECT @rv = m.row_version, @employee_id = m.employee_id, @group_id = m.roster_group_id,
           @old_start = m.start_date, @old_end = m.end_date
    FROM [sch].[roster_group_member] m
    JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = m.employee_id
    WHERE m.id = @id AND g.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Enrolment not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;

    DECLARE @g_from DATE, @g_to DATE;
    SELECT @g_from = from_date, @g_to = to_date FROM [sch].[roster_group] WHERE id = @group_id;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Start date is required.', 1;
    SET @end_date = ISNULL(@end_date, @g_to);
    IF @end_date IS NOT NULL AND @end_date < @start_date
        THROW 50400, N'endDate|End date cannot be before the start date.', 1;
    IF @start_date < @g_from OR (@g_to IS NOT NULL AND @end_date > @g_to)
        THROW 50400, N'startDate|The enrolment must sit inside the roster group''s dates.', 1;
    IF EXISTS (SELECT 1 FROM [sch].[roster_group_member] m WHERE m.employee_id = @employee_id AND m.id <> @id
               AND m.start_date <= ISNULL(@end_date, '99991231') AND @start_date <= ISNULL(m.end_date, '99991231'))
        THROW 50409, N'startDate|ENROLMENT_OVERLAP|The employee is already on a roster for these dates.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [sch].[roster_group_member]
        SET start_date = @start_date, end_date = @end_date, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'sch.roster_group_member', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
        FROM (VALUES (N'start_date', CONVERT(NVARCHAR(30), @old_start, 23), CONVERT(NVARCHAR(30), @start_date, 23)),
                     (N'end_date', CONVERT(NVARCHAR(30), @old_end, 23), CONVERT(NVARCHAR(30), @end_date, 23))) f (field_name, old_value, new_value)
        WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
    COMMIT;

    EXEC [sch].[usp_roster_member_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [sch].[usp_roster_member_delete]
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
        SELECT m.row_version
        FROM [sch].[roster_group_member] m
        JOIN [sch].[roster_group] g ON g.id = m.roster_group_id
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = m.employee_id
        WHERE m.id = @id AND g.company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Enrolment not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this enrolment. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [sch].[roster_group_member] WHERE id = @id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.roster_group_member', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
