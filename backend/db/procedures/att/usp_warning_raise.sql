-- Raises warnings from processed time-sheet days (att.timesheet_day, written by attendance processing;
-- read only here). Re-running is safe: the calendar years that @from_date..@to_date touch are worked
-- out again for the employees in scope; warnings already paid in a payslip are kept as they are.
--
-- For each active policy and each of its rules (one per clock event), a day is measured:
--   late_arrival     late_minutes                    (clock_in)
--   early_departure  early_left_minutes              (clock_out)
--   overtime         overtime_before_minutes (clock_in) / overtime_after_minutes (clock_out)
--   half_day_leave   1 when day_status = 'half_day'  (minutes and grace do not apply)
-- Periods: day, week (from the policy's week start day, weekdays outside start..end not counted),
-- month, year; weeks are cut at the year boundary so no period crosses a calendar year.
-- A day is an occurrence when its minutes exceed the rule's minutes and the period's running total
-- has used up the policy's grace minutes. Every occurrence_count-th occurrence in a period raises a
-- warning. The n-th warning of a policy in a penalty rule's period gets that rule's penalty when n
-- equals its after_count (the highest rung matching wins); past the highest rung every warning gets
-- the highest rung. Leave and both deductions post 'penalty' to the leave ledger (percentage/100 days).
-- Warnings that did not exist before this run (same rule, same day) are "issued": each employee who got
-- any is notified once, and one warning.issued event per employee lists them.
-- @quiet = 1: no result set (when called from another procedure).
CREATE OR ALTER PROCEDURE [att].[usp_warning_raise]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @permission_code   NVARCHAR(150) = NULL,
    @from_date         DATE,
    @to_date           DATE,
    @employee_id       BIGINT = NULL,
    @warning_policy_id BIGINT = NULL,
    @quiet             BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @from_date IS NULL
        THROW 50400, N'fromDate|Start date is required.', 1;
    IF @to_date IS NULL OR @to_date < @from_date
        THROW 50400, N'toDate|The end date must be on or after the start date.', 1;
    IF YEAR(@to_date) - YEAR(@from_date) > 1
        THROW 50400, N'toDate|Process at most two calendar years at a time.', 1;
    IF @employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @warning_policy_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [att].[warning_policy] WHERE id = @warning_policy_id AND company_id = @company_id)
        THROW 50400, N'warningPolicyId|Warning policy not found.', 1;

    DECLARE @rs DATE = DATEFROMPARTS(YEAR(@from_date), 1, 1), @re DATE = DATEFROMPARTS(YEAR(@to_date), 12, 31);

    CREATE TABLE #emp (employee_id BIGINT PRIMARY KEY);
    INSERT #emp
    SELECT e.id FROM [hr].[employee] e
    WHERE e.company_id = @company_id AND (@employee_id IS NULL OR e.id = @employee_id)
      AND (@permission_code IS NULL OR e.id IN (SELECT v.employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v));

    -- Each processed day, measured under each active policy rule.
    SELECT td.id AS timesheet_day_id, td.employee_id, td.work_date, p.id AS policy_id, r.id AS rule_id,
           r.minutes AS rule_minutes, ISNULL(NULLIF(r.occurrence_count, 0), 1) AS occurrence_count,
           CASE WHEN p.applies_to = N'half_day_leave' THEN 0 ELSE ISNULL(p.grace_minutes, 0) END AS grace_minutes,
           CASE p.applies_to
                WHEN N'late_arrival' THEN CASE WHEN r.clock_event = N'clock_in' THEN ISNULL(td.late_minutes, 0) ELSE 0 END
                WHEN N'early_departure' THEN CASE WHEN r.clock_event = N'clock_out' THEN ISNULL(td.early_left_minutes, 0) ELSE 0 END
                WHEN N'overtime' THEN CASE WHEN r.clock_event = N'clock_in' THEN ISNULL(td.overtime_before_minutes, 0)
                                           ELSE ISNULL(td.overtime_after_minutes, 0) END
                WHEN N'half_day_leave' THEN CASE WHEN td.day_status = N'half_day' THEN 1 ELSE 0 END
                ELSE 0 END AS measured,
           CASE p.applies_to WHEN N'half_day_leave' THEN 0 ELSE r.minutes END AS threshold,
           CASE p.period WHEN N'day' THEN td.work_date WHEN N'week' THEN k.week_key
                         WHEN N'month' THEN k.month_key ELSE k.year_key END AS period_key,
           k.week_key, k.month_key, k.year_key, k.in_week
    INTO #m
    FROM [att].[timesheet_day] td
    JOIN #emp x ON x.employee_id = td.employee_id
    CROSS JOIN [att].[warning_policy] p
    JOIN [att].[warning_policy_rule] r ON r.warning_policy_id = p.id
    CROSS APPLY (SELECT DATEDIFF(day, '19000101', td.work_date) % 7 AS wd,                 -- 0 = Monday
                        ISNULL((CHARINDEX(LEFT(p.week_start_day, 3), N'montuewedthufrisatsun') + 2) / 3 - 1, 0) AS ws,
                        (CHARINDEX(LEFT(p.week_end_day, 3), N'montuewedthufrisatsun') + 2) / 3 - 1 AS we) w
    CROSS APPLY (SELECT CASE WHEN DATEADD(day, -((w.wd - w.ws + 7) % 7), td.work_date) < DATEFROMPARTS(YEAR(td.work_date), 1, 1)
                             THEN DATEFROMPARTS(YEAR(td.work_date), 1, 1)
                             ELSE DATEADD(day, -((w.wd - w.ws + 7) % 7), td.work_date) END AS week_key,
                        DATEFROMPARTS(YEAR(td.work_date), MONTH(td.work_date), 1) AS month_key,
                        DATEFROMPARTS(YEAR(td.work_date), 1, 1) AS year_key,
                        CASE WHEN p.period <> N'week' OR w.we IS NULL OR w.we < 0
                               OR (w.wd - w.ws + 7) % 7 <= (w.we - w.ws + 7) % 7 THEN 1 ELSE 0 END AS in_week) k
    WHERE td.work_date BETWEEN @rs AND @re
      AND td.processed_at IS NOT NULL
      AND p.company_id = @company_id AND p.is_active = 1
      AND (@warning_policy_id IS NULL OR p.id = @warning_policy_id);

    DELETE #m WHERE in_week = 0;

    -- Occurrences, numbered within the period.
    SELECT o.*, ROW_NUMBER() OVER (PARTITION BY o.employee_id, o.rule_id, o.period_key ORDER BY o.work_date) AS occurrence_no
    INTO #o
    FROM (SELECT m.*, SUM(m.measured) OVER (PARTITION BY m.employee_id, m.rule_id, m.period_key
                                            ORDER BY m.work_date ROWS UNBOUNDED PRECEDING) AS running
          FROM #m m) o
    WHERE o.measured > o.threshold AND o.running > o.grace_minutes;

    -- Warnings, numbered within each penalty period.
    SELECT o.timesheet_day_id, o.employee_id, o.work_date, o.policy_id, o.rule_id, o.measured, o.occurrence_no,
           ROW_NUMBER() OVER (PARTITION BY o.employee_id, o.policy_id, o.week_key ORDER BY o.work_date, o.rule_id) AS n_week,
           ROW_NUMBER() OVER (PARTITION BY o.employee_id, o.policy_id, o.month_key ORDER BY o.work_date, o.rule_id) AS n_month,
           ROW_NUMBER() OVER (PARTITION BY o.employee_id, o.policy_id, o.year_key ORDER BY o.work_date, o.rule_id) AS n_year
    INTO #w
    FROM #o o
    WHERE o.occurrence_no % o.occurrence_count = 0;

    DECLARE @new TABLE (id BIGINT, employee_id BIGINT, work_date DATE, penalty_rule_id BIGINT, percentage DECIMAL(5,2), deduction NVARCHAR(30),
                        rule_id BIGINT, timesheet_day_id BIGINT);
    DECLARE @old TABLE (rule_id BIGINT, timesheet_day_id BIGINT);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        DECLARE @res NVARCHAR(100) = CONCAT(N'att.warning.', @company_id);
        EXEC sp_getapplock @Resource = @res, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 60000;

        DELETE g
        FROM [lv].[leave_ledger] g
        JOIN [att].[warning] w ON w.id = g.warning_id
        JOIN #emp x ON x.employee_id = w.employee_id
        WHERE w.company_id = @company_id AND w.work_date BETWEEN @rs AND @re AND w.payslip_id IS NULL
          AND (@warning_policy_id IS NULL OR w.warning_policy_id = @warning_policy_id);

        DELETE w
        OUTPUT DELETED.warning_policy_rule_id, DELETED.timesheet_day_id INTO @old (rule_id, timesheet_day_id)
        FROM [att].[warning] w
        JOIN #emp x ON x.employee_id = w.employee_id
        WHERE w.company_id = @company_id AND w.work_date BETWEEN @rs AND @re AND w.payslip_id IS NULL
          AND (@warning_policy_id IS NULL OR w.warning_policy_id = @warning_policy_id);

        INSERT [att].[warning] (company_id, employee_id, warning_policy_id, warning_policy_rule_id, timesheet_day_id, work_date,
                                minutes, occurrence_no, penalty_rule_id, penalty_type, penalty_percentage, deduction, created_by)
        OUTPUT INSERTED.id, INSERTED.employee_id, INSERTED.work_date, INSERTED.penalty_rule_id, INSERTED.penalty_percentage,
               INSERTED.deduction, INSERTED.warning_policy_rule_id, INSERTED.timesheet_day_id
               INTO @new (id, employee_id, work_date, penalty_rule_id, percentage, deduction, rule_id, timesheet_day_id)
        SELECT @company_id, w.employee_id, w.policy_id, w.rule_id, w.timesheet_day_id, w.work_date,
               w.measured, w.occurrence_no, pr.id, pr.penalty_type, pr.percentage, pr.deduction, @actor_user_id
        FROM #w w
        OUTER APPLY (
            SELECT TOP (1) x.id, x.penalty_type, x.percentage, x.deduction
            FROM [att].[penalty_rule] x
            CROSS APPLY (SELECT CASE x.period WHEN N'week' THEN w.n_week WHEN N'month' THEN w.n_month ELSE w.n_year END AS n,
                                (SELECT MAX(y.after_count) FROM [att].[penalty_rule] y
                                 WHERE y.warning_policy_id = x.warning_policy_id AND y.period = x.period) AS top_rung) c
            WHERE x.warning_policy_id = w.policy_id
              AND (c.n = x.after_count OR (x.after_count = c.top_rung AND c.n > x.after_count))
            ORDER BY x.after_count DESC, x.percentage DESC
        ) pr
        WHERE NOT EXISTS (SELECT 1 FROM [att].[warning] k WHERE k.warning_policy_rule_id = w.rule_id
                          AND k.timesheet_day_id = w.timesheet_day_id);

        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, warning_id, remarks, created_by)
        SELECT n.employee_id, x.leave_type_id, y.fiscal_year, n.work_date, -CAST(n.percentage / 100.0 AS DECIMAL(6,2)), N'penalty',
               n.id, N'Warning penalty', @actor_user_id
        FROM @new n
        JOIN [att].[penalty_rule] x ON x.id = n.penalty_rule_id
        CROSS APPLY [lv].[fn_leave_year](@company_id, n.work_date) y
        WHERE n.deduction IN (N'leave', N'both') AND x.leave_type_id IS NOT NULL AND n.percentage > 0;

        -- Issued: new this run. A notification and an event per employee, not per warning.
        DECLARE @issued TABLE (employee_id BIGINT PRIMARY KEY, warnings INT, first_date DATE, last_date DATE);
        INSERT @issued
        SELECT n.employee_id, COUNT(*), MIN(n.work_date), MAX(n.work_date)
        FROM @new n
        WHERE NOT EXISTS (SELECT 1 FROM @old o WHERE o.rule_id = n.rule_id AND o.timesheet_day_id = n.timesheet_day_id)
        GROUP BY n.employee_id;

        DECLARE @emp BIGINT = (SELECT MIN(employee_id) FROM @issued), @count INT, @title NVARCHAR(200),
                @body NVARCHAR(MAX), @payload NVARCHAR(MAX);
        WHILE @emp IS NOT NULL
        BEGIN
            SELECT @count = warnings,
                   @body = CASE WHEN first_date = last_date THEN CONCAT(N'For ', CONVERT(NVARCHAR(10), first_date, 23), N'.')
                                ELSE CONCAT(N'Between ', CONVERT(NVARCHAR(10), first_date, 23), N' and ', CONVERT(NVARCHAR(10), last_date, 23), N'.') END
            FROM @issued WHERE employee_id = @emp;
            SET @title = CASE WHEN @count = 1 THEN N'You received an attendance warning'
                              ELSE CONCAT(N'You received ', @count, N' attendance warnings') END;
            SET @payload = (
                SELECT CONVERT(NVARCHAR(30), @emp) AS employeeId, @count AS warnings,
                       (SELECT CONVERT(NVARCHAR(30), n.id) AS id, CONVERT(NVARCHAR(10), n.work_date, 23) AS workDate,
                               CONVERT(NVARCHAR(30), n.rule_id) AS warningPolicyRuleId, n.deduction,
                               n.percentage AS penaltyPercentage
                        FROM @new n
                        WHERE n.employee_id = @emp
                          AND NOT EXISTS (SELECT 1 FROM @old o WHERE o.rule_id = n.rule_id AND o.timesheet_day_id = n.timesheet_day_id)
                        ORDER BY n.work_date, n.id
                        FOR JSON PATH) AS items
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'warning.issued',
                 @entity_type = N'hr.employee', @entity_id = @emp, @payload = @payload;
            EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
                 @title = @title, @body = @body, @notification_type = N'warning', @link = N'/attendance/time-sheet',
                 @entity_type = N'hr.employee', @entity_id = @emp;
            SET @emp = (SELECT MIN(employee_id) FROM @issued WHERE employee_id > @emp);
        END
    COMMIT;

    IF @quiet = 1
        RETURN;

    SELECT (SELECT COUNT(*) FROM @new) AS raised,
           (SELECT COUNT(*) FROM @new WHERE penalty_rule_id IS NOT NULL) AS penalised,
           @rs AS from_date, @re AS to_date;
END
