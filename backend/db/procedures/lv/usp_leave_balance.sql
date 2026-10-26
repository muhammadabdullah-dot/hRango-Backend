-- Balances and the leave ledger. Every change to a balance is a ledger row; a balance is the sum
-- (lv.fn_leave_balance). @permission_code is the code the endpoint required: rows are limited to
-- the employees it reaches (auth.fn_visible_employees).

-- One row per employee and leave type they have (by policy) or have postings of in the leave year.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_balance_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT = NULL,
    @leave_type_id   BIGINT = NULL,
    @as_of           DATE = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SET @as_of = ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @fy SMALLINT = (SELECT fiscal_year FROM [lv].[fn_leave_year](@company_id, @as_of));
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @pairs TABLE (employee_id BIGINT, leave_type_id BIGINT, PRIMARY KEY (employee_id, leave_type_id));
    INSERT @pairs
    SELECT c.employee_id, c.leave_type_id
    FROM [lv].[fn_leave_coverage](@company_id) c
    JOIN [lv].[leave_type] t ON t.id = c.leave_type_id AND t.is_active = 1
    JOIN [hr].[employee] e ON e.id = c.employee_id AND e.status <> N'left'
    UNION
    SELECT g.employee_id, g.leave_type_id
    FROM [lv].[leave_ledger] g
    JOIN [hr].[employee] e ON e.id = g.employee_id AND e.company_id = @company_id
    WHERE g.fiscal_year = @fy;

    SELECT COUNT(*) AS total
    FROM @pairs p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    WHERE (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@leave_type_id IS NULL OR p.leave_type_id = @leave_type_id)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           d.name AS department_name, t.id AS leave_type_id, t.title AS leave_type_title, t.short_code, @fy AS fiscal_year,
           b.entitled, b.used, b.pending, b.available
    FROM @pairs p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    JOIN [hr].[employee] e ON e.id = p.employee_id
    JOIN [lv].[leave_type] t ON t.id = p.leave_type_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    CROSS APPLY [lv].[fn_leave_balance](@company_id, p.employee_id, p.leave_type_id, @as_of) b
    WHERE (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@leave_type_id IS NULL OR p.leave_type_id = @leave_type_id)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    ORDER BY e.first_name, e.last_name, e.id, t.title
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_ledger_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT = NULL,
    @leave_type_id   BIGINT = NULL,
    @fiscal_year     SMALLINT = NULL,
    @reason          NVARCHAR(30) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [lv].[leave_ledger] g
    JOIN [hr].[employee] e ON e.id = g.employee_id AND e.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = g.employee_id
    WHERE (@employee_id IS NULL OR g.employee_id = @employee_id)
      AND (@leave_type_id IS NULL OR g.leave_type_id = @leave_type_id)
      AND (@fiscal_year IS NULL OR g.fiscal_year = @fiscal_year)
      AND (@reason IS NULL OR g.reason = @reason)
    OPTION (RECOMPILE);

    SELECT g.id, g.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           g.leave_type_id, t.title AS leave_type_title, t.short_code, g.fiscal_year, g.entry_date, g.days, g.reason,
           g.remarks, g.request_id, r.code AS request_code, g.leave_encashment_id, g.warning_id, g.created_at
    FROM [lv].[leave_ledger] g
    JOIN [hr].[employee] e ON e.id = g.employee_id AND e.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = g.employee_id
    JOIN [lv].[leave_type] t ON t.id = g.leave_type_id
    LEFT JOIN [req].[request] r ON r.id = g.request_id
    WHERE (@employee_id IS NULL OR g.employee_id = @employee_id)
      AND (@leave_type_id IS NULL OR g.leave_type_id = @leave_type_id)
      AND (@fiscal_year IS NULL OR g.fiscal_year = @fiscal_year)
      AND (@reason IS NULL OR g.reason = @reason)
    ORDER BY g.entry_date DESC, g.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- An opening balance or a manual adjustment (+ adds days, - takes them away). Publishes
-- leaves.balance_adjusted and tells the employee.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_ledger_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT,
    @leave_type_id   BIGINT,
    @entry_date      DATE,
    @days            DECIMAL(6,2),
    @reason          NVARCHAR(30),
    @remarks         NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @reason NOT IN (N'opening', N'adjustment')
        THROW 50400, N'reason|Choose opening or adjustment.', 1;
    IF @days IS NULL OR @days = 0
        THROW 50400, N'days|Days cannot be zero.', 1;
    IF @reason = N'opening' AND @days < 0
        THROW 50400, N'days|An opening balance cannot be negative.', 1;
    IF @reason = N'adjustment' AND NULLIF(LTRIM(RTRIM(@remarks)), N'') IS NULL
        THROW 50400, N'remarks|Say why the balance is adjusted.', 1;
    IF @entry_date IS NULL
        THROW 50400, N'entryDate|Date is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50403, N'You cannot change this employee''s leave balance.', 1;
    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id)
        THROW 50400, N'leaveTypeId|Leave type not found.', 1;

    DECLARE @fy SMALLINT = (SELECT fiscal_year FROM [lv].[fn_leave_year](@company_id, @entry_date));
    IF @reason = N'opening' AND EXISTS (SELECT 1 FROM [lv].[leave_ledger] WHERE employee_id = @employee_id
                                        AND leave_type_id = @leave_type_id AND fiscal_year = @fy AND reason = N'opening')
        THROW 50409, N'reason|LEAVE_OPENING_EXISTS|This employee already has an opening balance of this type for the year. Adjust it instead.', 1;

    DECLARE @id BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, remarks, created_by)
        VALUES (@employee_id, @leave_type_id, @fy, @entry_date, @days, @reason, NULLIF(LTRIM(RTRIM(@remarks)), N''), @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'lv.leave_ledger', @id, N'days', CONVERT(NVARCHAR(30), @days), N'create', @actor_user_id, @now);

        DECLARE @type_title NVARCHAR(200) = (SELECT title FROM [lv].[leave_type] WHERE id = @leave_type_id);
        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), @id) AS ledgerEntryId, CONVERT(NVARCHAR(30), @employee_id) AS employeeId,
                   CONVERT(NVARCHAR(30), @leave_type_id) AS leaveTypeId, @type_title AS leaveTypeTitle,
                   @fy AS fiscalYear, CONVERT(NVARCHAR(10), @entry_date, 23) AS entryDate, @days AS days, @reason AS reason,
                   NULLIF(LTRIM(RTRIM(@remarks)), N'') AS remarks, CONVERT(NVARCHAR(30), @actor_user_id) AS adjustedBy
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'leaves.balance_adjusted',
             @entity_type = N'lv.leave_ledger', @entity_id = @id, @payload = @payload;

        DECLARE @title NVARCHAR(200) = CONCAT(N'Your ', @type_title, N' balance was ',
                CASE WHEN @reason = N'opening' THEN N'opened with ' WHEN @days > 0 THEN N'increased by ' ELSE N'reduced by ' END,
                FORMAT(ABS(@days), N'0.##'), CASE WHEN ABS(@days) = 1 THEN N' day' ELSE N' days' END);
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
             @title = @title, @body = @remarks, @notification_type = N'leave', @link = N'/leaves/my-leaves',
             @entity_type = N'lv.leave_ledger', @entity_id = @id;
    COMMIT;

    SELECT g.id, g.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           g.leave_type_id, t.title AS leave_type_title, t.short_code, g.fiscal_year, g.entry_date, g.days, g.reason,
           g.remarks, g.request_id, CAST(NULL AS NVARCHAR(30)) AS request_code, g.leave_encashment_id, g.warning_id, g.created_at
    FROM [lv].[leave_ledger] g
    JOIN [hr].[employee] e ON e.id = g.employee_id
    JOIN [lv].[leave_type] t ON t.id = g.leave_type_id
    WHERE g.id = @id;
END
GO

-- Posts the year's allotment ('allotment', once per leave year; once per employment for tenure
-- 'employment') and tops up earned balances ('earned': a twelfth a month up to @as_of).
-- Who: active employees the actor reaches, by the leave types their policy gives (lv.fn_leave_coverage),
-- of active types with Auto Allotment (or the one @leave_type_id named), matching the type's gender,
-- marital status and probation pre-conditions.
-- How much: the allowance (x12 for tenure 'monthly'), or the experience slab for the months served at
-- the start of the year; Pro Rated joiners get the months left in the year (the joining month counts
-- when Auto Balance on Joining Month is set), rounded to half days.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_allotment_process]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @fiscal_year     SMALLINT,
    @as_of           DATE = NULL,
    @leave_type_id   BIGINT = NULL,
    @employee_id     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @fiscal_year IS NULL OR @fiscal_year NOT BETWEEN 2000 AND 2100
        THROW 50400, N'fiscalYear|Choose a year.', 1;
    IF @leave_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id)
        THROW 50400, N'leaveTypeId|Leave type not found.', 1;
    IF @employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
        THROW 50400, N'employeeId|Employee not found.', 1;

    DECLARE @start_month INT = (SELECT MONTH(year_start) FROM [lv].[fn_leave_year](@company_id, DATEFROMPARTS(@fiscal_year, 12, 31)));
    DECLARE @ys DATE = DATEFROMPARTS(@fiscal_year, @start_month, 1);
    DECLARE @ye DATE = DATEADD(day, -1, DATEADD(year, 1, @ys));
    SET @as_of = ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE));
    IF @as_of > @ye SET @as_of = @ye;

    DECLARE @w TABLE (employee_id BIGINT, leave_type_id BIGINT, is_earned BIT, tenure NVARCHAR(30),
                      first_month DATE, entitlement DECIMAL(9,2), earned_target DECIMAL(9,2));

    INSERT @w
    SELECT c.employee_id, t.id, t.is_earned, t.tenure, f.first_month,
           CASE WHEN t.pro_rated = 1
                THEN ROUND(b.base_days * DATEDIFF(month, f.first_month, DATEADD(day, 1, @ye)) / 12.0 * 2, 0) / 2
                ELSE b.base_days END,
           CASE WHEN @as_of < f.first_month THEN 0
                ELSE ROUND(b.base_days / 12.0 * CASE WHEN DATEDIFF(month, f.first_month, DATEADD(day, 1, @as_of)) > 12 THEN 12
                                                     ELSE DATEDIFF(month, f.first_month, DATEADD(day, 1, @as_of)) END, 2) END
    FROM [lv].[fn_leave_coverage](@company_id) c
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = c.employee_id
    JOIN [hr].[employee] e ON e.id = c.employee_id
    JOIN [lv].[leave_type] t ON t.id = c.leave_type_id
    OUTER APPLY (SELECT MAX(p.joining_date) AS joining_date FROM [hr].[employment_period] p WHERE p.employee_id = e.id) j
    CROSS APPLY (SELECT CASE WHEN j.joining_date IS NULL OR j.joining_date <= @ys THEN @ys
                             WHEN t.auto_balance_on_joining = 1 THEN DATEFROMPARTS(YEAR(j.joining_date), MONTH(j.joining_date), 1)
                             ELSE DATEADD(month, 1, DATEFROMPARTS(YEAR(j.joining_date), MONTH(j.joining_date), 1)) END AS first_month,
                        CASE WHEN j.joining_date IS NULL OR j.joining_date > @ys THEN 0
                             ELSE DATEDIFF(month, j.joining_date, @ys) END AS service_months) f
    CROSS APPLY (SELECT CAST(CASE WHEN t.balance_basis = N'experience'
                                  THEN (SELECT TOP (1) s.balance FROM [lv].[leave_type_experience_slab] s
                                        WHERE s.leave_type_id = t.id AND f.service_months >= s.min_months
                                          AND f.service_months <= ISNULL(s.max_months, 2147483647)
                                        ORDER BY s.min_months DESC)
                                  ELSE c.allowance END
                             * CASE WHEN t.tenure = N'monthly' THEN 12 ELSE 1 END AS DECIMAL(9,2)) AS base_days) b
    WHERE t.is_active = 1
      AND e.status <> N'left'
      AND (t.id = @leave_type_id OR (@leave_type_id IS NULL AND t.auto_allotment = 1))
      AND (@employee_id IS NULL OR e.id = @employee_id)
      AND (t.gender = N'any' OR e.gender = t.gender)
      AND (t.marital_status = N'any' OR e.marital_status = t.marital_status)
      AND NOT (e.status = N'probation' AND t.allowed_in_probation = 0 AND t.is_probation_type = 0)
      AND f.first_month <= @ye
      AND ISNULL(b.base_days, 0) > 0;

    DECLARE @posted TABLE (reason NVARCHAR(30), days DECIMAL(6,2));
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        DECLARE @res NVARCHAR(100) = CONCAT(N'lv.allotment.', @company_id);
        EXEC sp_getapplock @Resource = @res, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;

        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, remarks, created_by)
        OUTPUT INSERTED.reason, INSERTED.days INTO @posted (reason, days)
        SELECT w.employee_id, w.leave_type_id, @fiscal_year, w.first_month, w.entitlement, N'allotment',
               CONCAT(N'Allotment ', @fiscal_year), @actor_user_id
        FROM @w w
        WHERE w.is_earned = 0 AND w.entitlement > 0
          AND NOT EXISTS (SELECT 1 FROM [lv].[leave_ledger] g
                          WHERE g.employee_id = w.employee_id AND g.leave_type_id = w.leave_type_id AND g.reason = N'allotment'
                            AND (w.tenure = N'employment' OR g.fiscal_year = @fiscal_year));

        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, remarks, created_by)
        OUTPUT INSERTED.reason, INSERTED.days INTO @posted (reason, days)
        SELECT w.employee_id, w.leave_type_id, @fiscal_year, @as_of, w.earned_target - x.earned, N'earned',
               CONCAT(N'Earned to ', CONVERT(NVARCHAR(10), @as_of, 23)), @actor_user_id
        FROM @w w
        CROSS APPLY (SELECT ISNULL(SUM(g.days), 0) AS earned FROM [lv].[leave_ledger] g
                     WHERE g.employee_id = w.employee_id AND g.leave_type_id = w.leave_type_id
                       AND g.fiscal_year = @fiscal_year AND g.reason = N'earned') x
        WHERE w.is_earned = 1 AND w.earned_target - x.earned > 0;

        IF EXISTS (SELECT 1 FROM @posted)
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'lv.allotment', @company_id, N'fiscal_year', CONVERT(NVARCHAR(10), @fiscal_year), N'process', @actor_user_id, @now);
    COMMIT;

    SELECT @fiscal_year AS fiscal_year,
           (SELECT COUNT(*) FROM @posted WHERE reason = N'allotment') AS allotted,
           (SELECT COUNT(*) FROM @posted WHERE reason = N'earned') AS earned,
           CAST(ISNULL((SELECT SUM(days) FROM @posted), 0) AS DECIMAL(12,2)) AS days;
END
GO

-- Year end: for carry-forward types, moves what is left of @from_fiscal_year into the next year
-- (a debit in the old year, a credit in the new one, both reason 'carry_forward'). With an
-- Accumulative Count, the days carried are capped at (count - 1) x the yearly allowance, so a
-- balance never holds more than that many years' worth. Runs once per employee, type and year.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_carry_forward_process]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @from_fiscal_year SMALLINT,
    @leave_type_id    BIGINT = NULL,
    @employee_id      BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @from_fiscal_year IS NULL OR @from_fiscal_year NOT BETWEEN 2000 AND 2100
        THROW 50400, N'fromFiscalYear|Choose a year.', 1;
    IF @leave_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id AND carry_forward = 1)
        THROW 50400, N'leaveTypeId|Choose a leave type that carries forward.', 1;

    DECLARE @start_month INT = (SELECT MONTH(year_start) FROM [lv].[fn_leave_year](@company_id, DATEFROMPARTS(@from_fiscal_year, 12, 31)));
    DECLARE @ys DATE = DATEFROMPARTS(@from_fiscal_year, @start_month, 1);
    DECLARE @next_start DATE = DATEADD(year, 1, @ys), @now DATETIME2(0) = SYSUTCDATETIME();

    DECLARE @c TABLE (employee_id BIGINT, leave_type_id BIGINT, days DECIMAL(6,2));
    INSERT @c
    SELECT x.employee_id, x.leave_type_id,
           CASE WHEN t.accumulative_count IS NOT NULL
                     AND b.available > t.allowance * CASE WHEN t.tenure = N'monthly' THEN 12 ELSE 1 END * (t.accumulative_count - 1)
                THEN t.allowance * CASE WHEN t.tenure = N'monthly' THEN 12 ELSE 1 END * (t.accumulative_count - 1)
                ELSE b.available END
    FROM (SELECT DISTINCT g.employee_id, g.leave_type_id FROM [lv].[leave_ledger] g WHERE g.fiscal_year = @from_fiscal_year) x
    JOIN [hr].[employee] e ON e.id = x.employee_id AND e.company_id = @company_id AND e.status <> N'left'
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
    JOIN [lv].[leave_type] t ON t.id = x.leave_type_id AND t.carry_forward = 1 AND t.tenure <> N'employment'
    CROSS APPLY [lv].[fn_leave_balance](@company_id, x.employee_id, x.leave_type_id, @ys) b
    WHERE b.available > 0
      AND (@leave_type_id IS NULL OR x.leave_type_id = @leave_type_id)
      AND (@employee_id IS NULL OR x.employee_id = @employee_id)
      AND NOT EXISTS (SELECT 1 FROM [lv].[leave_ledger] g WHERE g.employee_id = x.employee_id AND g.leave_type_id = x.leave_type_id
                      AND g.fiscal_year = @from_fiscal_year + 1 AND g.reason = N'carry_forward');
    DELETE @c WHERE days <= 0;

    BEGIN TRAN;
        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, remarks, created_by)
        SELECT employee_id, leave_type_id, @from_fiscal_year, DATEADD(day, -1, @next_start), -days, N'carry_forward',
               CONCAT(N'Carried to ', @from_fiscal_year + 1), @actor_user_id
        FROM @c
        UNION ALL
        SELECT employee_id, leave_type_id, @from_fiscal_year + 1, @next_start, days, N'carry_forward',
               CONCAT(N'Carried from ', @from_fiscal_year), @actor_user_id
        FROM @c;

        IF EXISTS (SELECT 1 FROM @c)
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'lv.carry_forward', @company_id, N'fiscal_year', CONVERT(NVARCHAR(10), @from_fiscal_year), N'process', @actor_user_id, @now);
    COMMIT;

    SELECT @from_fiscal_year AS from_fiscal_year, COUNT(*) AS carried, ISNULL(SUM(days), 0) AS days FROM @c;
END
