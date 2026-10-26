-- Employee Elections: the plans an employee elects for a plan year, in an enrollment window; HR approves
-- or rejects. Employee-owned: every procedure filters with auth.fn_visible_employees and the code the
-- endpoint required. Status: incomplete (saved, not submitted), pending, approved, rejected, waived.

CREATE OR ALTER PROCEDURE [ben].[usp_election_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[election] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
                   WHERE e.id = @id AND e.company_id = @company_id)
        THROW 50404, N'Election not found', 1;

    SELECT * FROM [ben].[fn_election_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page: pending first, then by employee.
CREATE OR ALTER PROCEDURE [ben].[usp_election_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @plan_year_id    BIGINT = NULL,
    @employee_id     BIGINT = NULL,
    @status          NVARCHAR(30) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @v TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @v SELECT DISTINCT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [ben].[fn_election_rows](@company_id) r
    JOIN @v v ON v.employee_id = r.employee_id
    WHERE (@pattern IS NULL OR r.employee_name LIKE @pattern OR r.employee_code LIKE @pattern)
      AND (@plan_year_id IS NULL OR r.plan_year_id = @plan_year_id)
      AND (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@status IS NULL OR r.status = @status)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [ben].[fn_election_rows](@company_id) r
    JOIN @v v ON v.employee_id = r.employee_id
    WHERE (@pattern IS NULL OR r.employee_name LIKE @pattern OR r.employee_code LIKE @pattern)
      AND (@plan_year_id IS NULL OR r.plan_year_id = @plan_year_id)
      AND (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@status IS NULL OR r.status = @status)
    ORDER BY CASE r.status WHEN N'pending' THEN 0 ELSE 1 END, r.employee_name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Makes (@id NULL) or changes an employee's election for a plan year.
--   @plan_ids: JSON list of plans; they must be offered in the window (or, without one, in the plan year).
--   @waive = 1 waives every plan (no plans); else @submit = 1 sends it for approval, 0 keeps it incomplete.
-- Without a window, the employee's open window of that plan year is taken; when there is none, only a
-- user holding the permission with company scope (HR recording it) may go on.
CREATE OR ALTER PROCEDURE [ben].[usp_election_save]
    @company_id           BIGINT,
    @actor_user_id        BIGINT,
    @permission_code      NVARCHAR(150),
    @id                   BIGINT = NULL,
    @employee_id          BIGINT,
    @plan_year_id         BIGINT,
    @enrollment_window_id BIGINT = NULL,
    @plan_ids             NVARCHAR(MAX) = N'[]',
    @waive                BIT = 0,
    @submit               BIT = 1,
    @remarks              NVARCHAR(MAX) = NULL,
    @row_version          BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME(), @status NVARCHAR(30);
    SET @plan_ids = ISNULL(@plan_ids, N'[]');
    SET @waive = ISNULL(@waive, 0);
    SET @submit = ISNULL(@submit, 1);
    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');

    IF @employee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                                           WHERE v.employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [ben].[plan_year] WHERE id = @plan_year_id AND company_id = @company_id)
        THROW 50400, N'planYearId|Choose the plan year.', 1;
    IF ISJSON(@plan_ids) = 0 OR LEFT(LTRIM(@plan_ids), 1) <> N'[' OR EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids) WHERE id IS NULL)
        THROW 50400, N'planIds|Plans must be a JSON list of ids.', 1;

    IF @enrollment_window_id IS NULL
        SELECT TOP (1) @enrollment_window_id = w.id
        FROM [ben].[enrollment_window] w
        WHERE w.plan_year_id = @plan_year_id AND w.company_id = @company_id AND @today <= w.closes_on
          AND (NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window_employee] x WHERE x.enrollment_window_id = w.id)
               OR EXISTS (SELECT 1 FROM [ben].[enrollment_window_employee] x WHERE x.enrollment_window_id = w.id AND x.employee_id = @employee_id))
        ORDER BY w.closes_on, w.id;
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window] w WHERE w.id = @enrollment_window_id AND w.company_id = @company_id
                       AND w.plan_year_id = @plan_year_id)
            THROW 50400, N'enrollmentWindowId|Choose a window of the plan year.', 1;
        IF EXISTS (SELECT 1 FROM [ben].[enrollment_window] w WHERE w.id = @enrollment_window_id AND @today > w.closes_on)
            THROW 50400, N'enrollmentWindowId|WINDOW_CLOSED|This enrollment window is closed.', 1;
        IF EXISTS (SELECT 1 FROM [ben].[enrollment_window_employee] x WHERE x.enrollment_window_id = @enrollment_window_id)
           AND NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window_employee] x WHERE x.enrollment_window_id = @enrollment_window_id
                           AND x.employee_id = @employee_id)
            THROW 50400, N'enrollmentWindowId|This employee is not in the enrollment window.', 1;
    END

    IF @enrollment_window_id IS NULL
       AND NOT EXISTS (SELECT 1 FROM [auth].[fn_effective_grants](@company_id, @actor_user_id) g
                       WHERE g.code = @permission_code AND g.scope = N'company')
        THROW 50400, N'enrollmentWindowId|WINDOW_CLOSED|No enrollment window is open for this employee.', 1;

    IF @waive = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids))
            THROW 50400, N'planIds|A waived election has no plans.', 1;
        SET @status = N'waived';
    END
    ELSE
    BEGIN
        IF @submit = 1 AND NOT EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids))
            THROW 50400, N'planIds|Choose at least one plan, or waive.', 1;
        IF EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids) p
                   WHERE (@enrollment_window_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window_plan] wp
                              WHERE wp.enrollment_window_id = @enrollment_window_id AND wp.benefit_plan_id = p.id))
                      OR (@enrollment_window_id IS NULL AND NOT EXISTS (SELECT 1 FROM [ben].[plan_year_plan] pp
                              WHERE pp.plan_year_id = @plan_year_id AND pp.benefit_plan_id = p.id)))
            THROW 50400, N'planIds|Choose plans offered in the enrollment window.', 1;
        SET @status = CASE WHEN @submit = 1 THEN N'pending' ELSE N'incomplete' END;
    END

    IF @id IS NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM [ben].[election] WHERE employee_id = @employee_id AND plan_year_id = @plan_year_id)
            THROW 50409, N'employeeId|ELECTION_DUPLICATE|This employee already has an election for the plan year.', 1;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an election.', 1;
        DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30), @old_emp BIGINT, @old_year BIGINT;
        SELECT @old_rv = e.row_version, @old_status = e.status, @old_emp = e.employee_id, @old_year = e.plan_year_id
        FROM [ben].[election] e
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
        WHERE e.id = @id AND e.company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Election not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this election. Reload it and try again', 1;
        IF @old_status = N'approved'
            THROW 50409, N'status|ELECTION_LOCKED|An approved election cannot be changed.', 1;
        IF @old_emp <> @employee_id OR @old_year <> @plan_year_id
            THROW 50400, N'employeeId|An election keeps its employee and plan year.', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [ben].[election] (company_id, employee_id, plan_year_id, enrollment_window_id, status, submitted_at, remarks, created_by)
            VALUES (@company_id, @employee_id, @plan_year_id, @enrollment_window_id, @status,
                    CASE WHEN @status IN (N'pending', N'waived') THEN @now END, @remarks, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
            VALUES (N'ben.election', @id, N'create', @status, @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [ben].[election]
            SET enrollment_window_id = @enrollment_window_id, status = @status,
                submitted_at = CASE WHEN @status IN (N'pending', N'waived') THEN @now END,
                decided_by_user_id = NULL, decided_at = NULL, remarks = @remarks, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this election. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.election', @id, N'status', @old_status, @status, N'update', @actor_user_id, @now);
        END

        DELETE [ben].[election_plan] WHERE election_id = @id AND benefit_plan_id NOT IN (SELECT id FROM [ben].[fn_id_list](@plan_ids));
        INSERT [ben].[election_plan] (election_id, benefit_plan_id, created_by)
        SELECT @id, p.id, @actor_user_id FROM [ben].[fn_id_list](@plan_ids) p
        WHERE NOT EXISTS (SELECT 1 FROM [ben].[election_plan] x WHERE x.election_id = @id AND x.benefit_plan_id = p.id);
    COMMIT;

    EXEC [ben].[usp_election_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Approve or reject a pending election (@decision approve / reject). Publishes benefits.election_decided and
-- tells the employee.
CREATE OR ALTER PROCEDURE [ben].[usp_election_decide]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @decision        NVARCHAR(30),
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @decision NOT IN (N'approve', N'reject')
        THROW 50400, N'decision|Decision is approve or reject.', 1;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @rv = e.row_version, @status = e.status
    FROM [ben].[election] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.employee_id
    WHERE e.id = @id AND e.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Election not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this election. Reload it and try again', 1;
    IF @status <> N'pending'
        THROW 50409, N'status|ELECTION_DECIDED|Only a pending election can be approved or rejected.', 1;

    BEGIN TRAN;
        UPDATE [ben].[election]
        SET status = CASE @decision WHEN N'approve' THEN N'approved' ELSE N'rejected' END,
            decided_by_user_id = @actor_user_id, decided_at = @now,
            remarks = COALESCE(NULLIF(LTRIM(RTRIM(@remarks)), N''), remarks), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this election. Reload it and try again', 1;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.election', @id, N'status', N'pending', CASE @decision WHEN N'approve' THEN N'approved' ELSE N'rejected' END,
                @decision, @actor_user_id, @now);

        DECLARE @employee_id BIGINT, @year NVARCHAR(200), @payload NVARCHAR(MAX);
        SELECT @employee_id = e.employee_id, @year = py.name,
               @payload = (SELECT CONVERT(NVARCHAR(30), e.id) AS electionId, CONVERT(NVARCHAR(30), e.employee_id) AS employeeId,
                                  CONVERT(NVARCHAR(30), e.plan_year_id) AS planYearId, py.name AS planYearName, e.status,
                                  e.remarks, CONVERT(NVARCHAR(30), @actor_user_id) AS decidedBy,
                                  (SELECT CONVERT(NVARCHAR(30), b.id) AS id, b.name, b.category
                                   FROM [ben].[election_plan] ep JOIN [ben].[benefit_plan] b ON b.id = ep.benefit_plan_id
                                   WHERE ep.election_id = e.id ORDER BY b.name FOR JSON PATH) AS plans
                           FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM [ben].[election] e JOIN [ben].[plan_year] py ON py.id = e.plan_year_id
        WHERE e.id = @id;
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'benefits.election_decided',
             @entity_type = N'ben.election', @entity_id = @id, @payload = @payload;

        DECLARE @title NVARCHAR(200) = LEFT(CONCAT(N'Your benefit choices for ', @year, N' were ',
                                                   CASE @decision WHEN N'approve' THEN N'approved' ELSE N'rejected' END), 200);
        DECLARE @body NVARCHAR(MAX) = NULLIF(LTRIM(RTRIM(@remarks)), N'');
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
             @title = @title, @body = @body, @notification_type = N'benefits', @link = N'/benefits/employees',
             @entity_type = N'ben.election', @entity_id = @id;
    COMMIT;

    EXEC [ben].[usp_election_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
