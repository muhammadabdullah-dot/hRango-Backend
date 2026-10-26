-- Planning: "Add Planning" with Plan for New Positions and Plan for Existing Positions. Saving a plan
-- submits it: its lines are priced here, and one pending e-budget is made per position title and
-- department. The plan's status then follows its budgets (mp.usp_manpower_plan_status_sync).
-- Scope: a plan is reached through its department or station (mp.fn_unit_reach); @permission_code is the
-- code the endpoint required.

-- Result set 1: the plan. Result set 2: its lines. Result set 3: its budgets. Result set 4: its files
-- (core.attachment, entity_type mp.manpower_plan).
CREATE OR ALTER PROCEDURE [mp].[usp_manpower_plan_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [mp].[manpower_plan] x WHERE x.id = @id AND x.company_id = @company_id
                   AND EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                               WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                  OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
        THROW 50404, N'Plan not found', 1;

    SELECT * FROM [mp].[fn_plan_rows](@company_id) WHERE id = @id;

    SELECT l.id, l.kind, l.sort_order, l.position_id, ps.code AS position_code,
           COALESCE(pjt.name, ejt.name) AS job_title_name,
           l.employee_id, em.code AS employee_code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
           COALESCE(pdp.name, edp.name) AS department_name, COALESCE(pbr.name, ebr.name) AS branch_name,
           l.headcount, l.start_date, l.end_date, l.months, l.min_salary, l.max_salary, l.monthly_salary,
           l.total_allowance, l.total_salary, l.annual_gross, l.e_budget_id
    FROM [mp].[manpower_plan_line] l
    LEFT JOIN [mp].[position] ps ON ps.id = l.position_id
    LEFT JOIN [org].[job_title] pjt ON pjt.id = ps.job_title_id
    LEFT JOIN [org].[department] pdp ON pdp.id = ps.department_id
    LEFT JOIN [org].[branch] pbr ON pbr.id = ps.branch_id
    LEFT JOIN [hr].[employee] em ON em.id = l.employee_id
    LEFT JOIN [org].[job_title] ejt ON ejt.id = em.job_title_id
    LEFT JOIN [org].[department] edp ON edp.id = em.department_id
    LEFT JOIN [org].[branch] ebr ON ebr.id = em.branch_id
    WHERE l.manpower_plan_id = @id
    ORDER BY CASE l.kind WHEN N'new_position' THEN 0 ELSE 1 END, l.sort_order, l.id;

    SELECT * FROM [mp].[fn_budget_rows](@company_id) WHERE manpower_plan_id = @id ORDER BY title, id;

    SELECT a.id AS attachment_id, f.id, f.name, f.mime_type, f.size_bytes, a.created_at
    FROM [core].[attachment] a
    JOIN [core].[stored_file] f ON f.id = a.file_id
    WHERE a.company_id = @company_id AND a.entity_type = N'mp.manpower_plan' AND a.entity_id = @id
    ORDER BY a.id;
END
GO

-- Result set 1: total. Result set 2: the page, newest first.
-- @mode: new (has new positions) or existing (has existing positions).
CREATE OR ALTER PROCEDURE [mp].[usp_manpower_plan_list]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @search             NVARCHAR(200) = NULL,
    @budget_duration_id BIGINT = NULL,
    @mode               NVARCHAR(30) = NULL,
    @status             NVARCHAR(30) = NULL,
    @is_current         BIT = NULL,
    @page               INT = 1,
    @page_size          INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @reach TABLE (unit_type NVARCHAR(30), unit_id BIGINT);
    INSERT @reach SELECT unit_type, unit_id FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code);
    DECLARE @all BIT = CASE WHEN EXISTS (SELECT 1 FROM @reach WHERE unit_type = N'company') THEN 1 ELSE 0 END;

    SELECT COUNT(*) AS total
    FROM [mp].[fn_plan_rows](@company_id) x
    WHERE (@all = 1 OR EXISTS (SELECT 1 FROM @reach r WHERE (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                                        OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
      AND (@pattern IS NULL OR x.title LIKE @pattern)
      AND (@budget_duration_id IS NULL OR x.budget_duration_id = @budget_duration_id)
      AND (@mode IS NULL OR (@mode = N'new' AND x.has_new_positions = 1) OR (@mode = N'existing' AND x.has_existing_positions = 1))
      AND (@status IS NULL OR x.status = @status)
      AND (@is_current IS NULL OR x.is_current = @is_current)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [mp].[fn_plan_rows](@company_id) x
    WHERE (@all = 1 OR EXISTS (SELECT 1 FROM @reach r WHERE (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                                        OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
      AND (@pattern IS NULL OR x.title LIKE @pattern)
      AND (@budget_duration_id IS NULL OR x.budget_duration_id = @budget_duration_id)
      AND (@mode IS NULL OR (@mode = N'new' AND x.has_new_positions = 1) OR (@mode = N'existing' AND x.has_existing_positions = 1))
      AND (@status IS NULL OR x.status = @status)
      AND (@is_current IS NULL OR x.is_current = @is_current)
    ORDER BY x.created_at DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- A plan's status from its budgets: all approved -> approved, any rejected -> rejected, else pending.
-- Called inside the budget procedures' transactions.
CREATE OR ALTER PROCEDURE [mp].[usp_manpower_plan_status_sync]
    @plan_id       BIGINT,
    @actor_user_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @plan_id IS NULL RETURN;

    DECLARE @status NVARCHAR(30) =
        CASE WHEN EXISTS (SELECT 1 FROM [mp].[e_budget] WHERE manpower_plan_id = @plan_id AND status = N'rejected') THEN N'rejected'
             WHEN EXISTS (SELECT 1 FROM [mp].[e_budget] WHERE manpower_plan_id = @plan_id)
                  AND NOT EXISTS (SELECT 1 FROM [mp].[e_budget] WHERE manpower_plan_id = @plan_id AND status <> N'approved') THEN N'approved'
             ELSE N'pending' END;

    UPDATE [mp].[manpower_plan]
    SET status = @status, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @plan_id AND status <> @status;
END
GO

-- Adds (@id NULL) or edits and resubmits a plan, with all its lines in one call:
--   @lines = [{"kind": "new_position", "positionId", "headcount", "startDate", "endDate",
--              "minSalary", "maxSalary", "totalAllowance"},
--             {"kind": "existing_employee", "employeeId", "startDate", "endDate", "monthlySalary", "totalAllowance"}]
-- Blank min / max salary takes the position's band; blank monthly salary takes the employee's current
-- salary (hr.employee_salary). A month of a line: (max salary + allowance) x headcount for a new position,
-- monthly salary + allowance for an existing one; its annual gross is that times its months (calendar
-- months from start to end, both counted). Monthly / annual amount of the plan are the sums.
CREATE OR ALTER PROCEDURE [mp].[usp_manpower_plan_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @id                 BIGINT = NULL,
    @title              NVARCHAR(200),
    @budget_duration_id BIGINT,
    @division_id        BIGINT = NULL,
    @branch_id          BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @sub_department_id  BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @description        NVARCHAR(MAX) = NULL,
    @lines              NVARCHAR(MAX),
    @file_ids           NVARCHAR(MAX) = NULL,    -- JSON array of uploaded file ids; NULL keeps the plan's files
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(2048), @today DATE = CAST(SYSUTCDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @d_start DATE, @d_end DATE;

    SET @title = LTRIM(RTRIM(@title));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Enter the title.', 1;
    IF @file_ids IS NOT NULL AND ISJSON(@file_ids) = 0
        THROW 50400, N'fileIds|File ids are not valid.', 1;
    DECLARE @files TABLE (file_id BIGINT PRIMARY KEY);
    INSERT @files SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) FROM OPENJSON(ISNULL(@file_ids, N'[]'))
    WHERE TRY_CONVERT(BIGINT, [value]) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @files x WHERE NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, x.file_id)))
        THROW 50400, N'fileIds|A file was not found. Upload it again.', 1;
    SELECT @d_start = start_date, @d_end = end_date FROM [mp].[budget_duration]
    WHERE id = @budget_duration_id AND company_id = @company_id;
    IF @d_start IS NULL
        THROW 50400, N'budgetDurationId|Choose the plan year.', 1;
    IF @division_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[division] WHERE id = @division_id AND company_id = @company_id)
        THROW 50400, N'divisionId|Division not found.', 1;
    IF @branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Station not found.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @sub_department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @sub_department_id AND company_id = @company_id
                                                      AND (@department_id IS NULL OR parent_id = @department_id))
        THROW 50400, N'subDepartmentId|Choose a sub-department of the department.', 1;
    IF @employee_group_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[employee_group] WHERE id = @employee_group_id AND company_id = @company_id)
        THROW 50400, N'employeeGroupId|Employee group not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                   WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @department_id)
                      OR (r.unit_type = N'branch' AND r.unit_id = @branch_id))
        THROW 50403, N'You cannot plan for this department or station.', 1;
    IF @lines IS NULL OR ISJSON(@lines) = 0 OR LEFT(LTRIM(@lines), 1) <> N'['
        THROW 50400, N'lines|Lines must be a JSON list.', 1;

    CREATE TABLE #l (
        line_no INT PRIMARY KEY, kind NVARCHAR(30), position_id BIGINT, employee_id BIGINT, headcount INT,
        start_date DATE, end_date DATE, min_salary DECIMAL(18,2), max_salary DECIMAL(18,2), monthly_salary DECIMAL(18,2),
        total_allowance DECIMAL(18,2), months INT, total_salary DECIMAL(18,2), annual_gross DECIMAL(18,2),
        job_title_id BIGINT, department_id BIGINT, raw NVARCHAR(MAX));

    INSERT #l (line_no, kind, position_id, employee_id, headcount, start_date, end_date, min_salary, max_salary,
               monthly_salary, total_allowance, raw)
    SELECT CAST(j.[key] AS INT),
           JSON_VALUE(j.value, '$.kind'),
           TRY_CAST(JSON_VALUE(j.value, '$.positionId') AS BIGINT),
           TRY_CAST(JSON_VALUE(j.value, '$.employeeId') AS BIGINT),
           TRY_CAST(JSON_VALUE(j.value, '$.headcount') AS INT),
           TRY_CAST(JSON_VALUE(j.value, '$.startDate') AS DATE),
           TRY_CAST(JSON_VALUE(j.value, '$.endDate') AS DATE),
           TRY_CAST(JSON_VALUE(j.value, '$.minSalary') AS DECIMAL(18,2)),
           TRY_CAST(JSON_VALUE(j.value, '$.maxSalary') AS DECIMAL(18,2)),
           TRY_CAST(JSON_VALUE(j.value, '$.monthlySalary') AS DECIMAL(18,2)),
           ISNULL(TRY_CAST(JSON_VALUE(j.value, '$.totalAllowance') AS DECIMAL(18,2)), 0),
           j.value
    FROM OPENJSON(@lines) j;

    IF NOT EXISTS (SELECT 1 FROM #l)
        THROW 50400, N'lines|Add at least one new or existing position.', 1;
    IF (SELECT COUNT(*) FROM #l) > 500
        THROW 50400, N'lines|A plan has at most 500 lines.', 1;

    -- Defaults from the position's band and the employee's salary; the grouping keys for the budgets.
    UPDATE l SET
        headcount = ISNULL(l.headcount, 1),
        min_salary = ISNULL(l.min_salary, band.min_salary),
        max_salary = ISNULL(l.max_salary, band.max_salary),
        monthly_salary = NULL, job_title_id = p.job_title_id, department_id = p.department_id
    FROM #l l
    JOIN [mp].[position] p ON p.id = l.position_id AND p.company_id = @company_id
    OUTER APPLY [mp].[fn_position_band](p.id, @today) band
    WHERE l.kind = N'new_position';

    UPDATE l SET
        headcount = 1, min_salary = NULL, max_salary = NULL,
        monthly_salary = ISNULL(l.monthly_salary, (SELECT TOP (1) s.amount FROM [hr].[employee_salary] s
                                                   WHERE s.employee_id = e.id AND s.effective_date <= @today
                                                   ORDER BY s.effective_date DESC)),
        job_title_id = e.job_title_id, department_id = e.department_id
    FROM #l l
    JOIN [hr].[employee] e ON e.id = l.employee_id AND e.company_id = @company_id
    WHERE l.kind = N'existing_employee';

    -- The first problem, by line, names its field: lines[2].startDate.
    SELECT TOP (1) @msg = CONCAT(N'lines[', l.line_no, N'].', x.field, N'|', x.message)
    FROM #l l
    CROSS APPLY (
        SELECT TOP (1) v.field, v.message
        FROM (VALUES
            (1, N'kind', CASE WHEN l.kind IS NULL OR l.kind NOT IN (N'new_position', N'existing_employee')
                               THEN N'Kind is new_position or existing_employee.' END),
            (2, N'positionId', CASE WHEN l.kind = N'new_position' AND (l.position_id IS NULL OR NOT EXISTS (
                                        SELECT 1 FROM [mp].[position] p WHERE p.id = l.position_id AND p.company_id = @company_id))
                                     THEN N'Choose the position.'
                                     WHEN l.kind = N'new_position' AND EXISTS (SELECT 1 FROM [mp].[position] p WHERE p.id = l.position_id AND p.status <> N'active')
                                     THEN N'This position is inactive.' END),
            (3, N'employeeId', CASE WHEN l.kind = N'existing_employee' AND (l.employee_id IS NULL OR NOT EXISTS (
                                        SELECT 1 FROM [hr].[employee] e WHERE e.id = l.employee_id AND e.company_id = @company_id))
                                     THEN N'Choose the employee.'
                                     WHEN l.kind = N'existing_employee' AND EXISTS (SELECT 1 FROM #l o WHERE o.kind = l.kind
                                          AND o.employee_id = l.employee_id AND o.line_no < l.line_no)
                                     THEN N'This employee is already in the plan.' END),
            (4, N'headcount', CASE WHEN l.headcount IS NULL OR l.headcount < 1 OR l.headcount > 10000
                                   THEN N'Headcount is a whole number from 1.' END),
            (5, N'startDate', CASE WHEN l.start_date IS NULL THEN N'Enter the start date.'
                                   WHEN l.start_date < @d_start OR l.start_date > @d_end THEN N'The start must fall in the plan year.' END),
            (6, N'endDate', CASE WHEN l.end_date IS NULL THEN N'Enter the end date.'
                                 WHEN l.end_date < l.start_date THEN N'The end cannot be before the start.'
                                 WHEN l.end_date > @d_end THEN N'The end must fall in the plan year.' END),
            (7, N'minSalary', CASE WHEN l.kind = N'new_position' AND (l.min_salary IS NULL OR l.min_salary < 0)
                                   THEN N'Enter the min salary.' END),
            (8, N'maxSalary', CASE WHEN l.kind = N'new_position' AND (l.max_salary IS NULL OR l.max_salary <= 0)
                                   THEN N'Enter the max salary.'
                                   WHEN l.kind = N'new_position' AND l.max_salary < l.min_salary
                                   THEN N'Max salary cannot be below the min salary.' END),
            (9, N'monthlySalary', CASE WHEN l.kind = N'existing_employee' AND (l.monthly_salary IS NULL OR l.monthly_salary <= 0)
                                       THEN N'Enter the monthly salary.' END),
            (10, N'totalAllowance', CASE WHEN l.total_allowance < 0 THEN N'The allowance cannot be negative.' END)
        ) v (n, field, message)
        WHERE v.message IS NOT NULL
        ORDER BY v.n
    ) x
    ORDER BY l.line_no;
    IF @msg IS NOT NULL
        THROW 50400, @msg, 1;

    UPDATE #l SET
        months = DATEDIFF(MONTH, start_date, end_date) + 1,
        total_salary = CASE kind WHEN N'new_position' THEN (max_salary + total_allowance) * headcount
                                 ELSE monthly_salary + total_allowance END;
    UPDATE #l SET annual_gross = total_salary * months;

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a plan.', 1;
        DECLARE @old_rv BINARY(8), @old_dept BIGINT, @old_branch BIGINT;
        SELECT @old_rv = row_version, @old_dept = department_id, @old_branch = branch_id
        FROM [mp].[manpower_plan] WHERE id = @id AND company_id = @company_id;
        IF @old_rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                          WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @old_dept)
                                             OR (r.unit_type = N'branch' AND r.unit_id = @old_branch))
            THROW 50404, N'Plan not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this plan. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [mp].[e_budget] WHERE manpower_plan_id = @id AND status = N'approved')
            THROW 50409, N'status|PLAN_LOCKED|This plan has approved budgets, so it can no longer be changed.', 1;
    END

    DECLARE @budgets TABLE (id BIGINT, job_title_id BIGINT, department_id BIGINT);

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [mp].[manpower_plan] (company_id, title, budget_duration_id, division_id, branch_id, department_id,
                                         sub_department_id, employee_group_id, description, monthly_amount, annual_amount,
                                         status, submitted_at, created_by)
            VALUES (@company_id, @title, @budget_duration_id, @division_id, @branch_id, @department_id, @sub_department_id,
                    @employee_group_id, @description, 0, 0, N'pending', @now, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.manpower_plan', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [mp].[manpower_plan]
            SET title = @title, budget_duration_id = @budget_duration_id, division_id = @division_id, branch_id = @branch_id,
                department_id = @department_id, sub_department_id = @sub_department_id, employee_group_id = @employee_group_id,
                description = @description, status = N'pending', submitted_at = @now, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this plan. Reload it and try again', 1;
            -- Edited plans go back for approval with fresh budgets.
            DELETE [mp].[manpower_plan_line] WHERE manpower_plan_id = @id;
            DELETE [mp].[e_budget] WHERE manpower_plan_id = @id;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.manpower_plan', @id, N'update', @actor_user_id, @now);
        END

        MERGE [mp].[e_budget] AS t
        USING (
            SELECT g.job_title_id, g.department_id, g.amount, g.positions, g.start_date, g.end_date,
                   ISNULL(jt.name, N'Existing positions') AS title
            FROM (SELECT job_title_id, department_id, SUM(annual_gross) AS amount,
                         SUM(CASE WHEN kind = N'new_position' THEN headcount ELSE 0 END) AS positions,
                         MIN(start_date) AS start_date, MAX(end_date) AS end_date
                  FROM #l GROUP BY job_title_id, department_id) g
            LEFT JOIN [org].[job_title] jt ON jt.id = g.job_title_id
        ) AS s ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (company_id, budget_duration_id, manpower_plan_id, job_title_id, department_id, title, amount,
                    total_positions, start_date, end_date, status, created_by)
            VALUES (@company_id, @budget_duration_id, @id, s.job_title_id, s.department_id, s.title, s.amount,
                    s.positions, s.start_date, s.end_date, N'pending', @actor_user_id)
        OUTPUT INSERTED.id, s.job_title_id, s.department_id INTO @budgets (id, job_title_id, department_id);

        INSERT [mp].[manpower_plan_line] (manpower_plan_id, kind, sort_order, position_id, employee_id, e_budget_id, headcount,
                                          start_date, end_date, months, min_salary, max_salary, monthly_salary,
                                          total_allowance, total_salary, annual_gross, created_by)
        SELECT @id, l.kind, l.line_no, CASE WHEN l.kind = N'new_position' THEN l.position_id END,
               CASE WHEN l.kind = N'existing_employee' THEN l.employee_id END, b.id, l.headcount,
               l.start_date, l.end_date, l.months, l.min_salary, l.max_salary, l.monthly_salary,
               l.total_allowance, l.total_salary, l.annual_gross, @actor_user_id
        FROM #l l
        JOIN @budgets b ON ISNULL(b.job_title_id, -1) = ISNULL(l.job_title_id, -1)
                       AND ISNULL(b.department_id, -1) = ISNULL(l.department_id, -1);

        UPDATE [mp].[manpower_plan]
        SET monthly_amount = (SELECT SUM(total_salary) FROM #l), annual_amount = (SELECT SUM(annual_gross) FROM #l)
        WHERE id = @id;

        -- Plan files: the list given replaces the plan's attachments.
        IF @file_ids IS NOT NULL
        BEGIN
            DELETE a FROM [core].[attachment] a
            WHERE a.company_id = @company_id AND a.entity_type = N'mp.manpower_plan' AND a.entity_id = @id
              AND NOT EXISTS (SELECT 1 FROM @files x WHERE x.file_id = a.file_id);
            INSERT [core].[attachment] (company_id, entity_type, entity_id, file_id, created_by)
            SELECT @company_id, N'mp.manpower_plan', @id, x.file_id, @actor_user_id
            FROM @files x
            WHERE NOT EXISTS (SELECT 1 FROM [core].[attachment] a
                              WHERE a.entity_type = N'mp.manpower_plan' AND a.entity_id = @id AND a.file_id = x.file_id);
        END
    COMMIT;

    EXEC [mp].[usp_manpower_plan_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Deletes a plan with its lines and budgets. Refused once a budget is approved (its open positions stand).
CREATE OR ALTER PROCEDURE [mp].[usp_manpower_plan_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @dept BIGINT, @branch BIGINT;
    SELECT @rv = row_version, @dept = department_id, @branch = branch_id
    FROM [mp].[manpower_plan] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @dept)
                                     OR (r.unit_type = N'branch' AND r.unit_id = @branch))
        THROW 50404, N'Plan not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this plan. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [mp].[e_budget] WHERE manpower_plan_id = @id AND status = N'approved')
        THROW 50409, N'status|PLAN_LOCKED|This plan has approved budgets, so it cannot be deleted.', 1;

    BEGIN TRAN;
        DELETE [core].[attachment] WHERE company_id = @company_id AND entity_type = N'mp.manpower_plan' AND entity_id = @id;
        DELETE [mp].[manpower_plan_line] WHERE manpower_plan_id = @id;
        DELETE [mp].[e_budget] WHERE manpower_plan_id = @id;
        DELETE [mp].[manpower_plan] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.manpower_plan', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
