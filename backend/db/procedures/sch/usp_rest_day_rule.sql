-- Rest-day rules ("Create New Rest Day"): employees, a date range, weekdays, a repeat and a step, and
-- whether the rest day is paid. Saving a rule (re)generates its rows in sch.rest_day; a date that is
-- already a rest day for an employee (another rule or an approved request) is left as it is.
-- Result set 1: the rule. Result set 2: its employees.
CREATE OR ALTER PROCEDURE [sch].[usp_rest_day_rule_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sch].[rest_day_rule] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Rest day rule not found', 1;

    SELECT r.id, r.from_date, r.to_date, r.weekdays, r.repeat_every_weeks, r.step, r.is_payable,
           (SELECT COUNT(*) FROM [sch].[rest_day_rule_employee] x WHERE x.rest_day_rule_id = r.id) AS employee_count,
           (SELECT COUNT(*) FROM [sch].[rest_day] d WHERE d.rest_day_rule_id = r.id) AS rest_day_count,
           r.created_at, r.updated_at, r.row_version
    FROM [sch].[rest_day_rule] r
    WHERE r.id = @id AND r.company_id = @company_id;

    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dep.name AS department_name, des.name AS designation_name
    FROM [sch].[rest_day_rule_employee] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    LEFT JOIN [org].[department] dep ON dep.id = e.department_id
    LEFT JOIN [org].[designation] des ON des.id = e.designation_id
    WHERE x.rest_day_rule_id = @id
    ORDER BY e.first_name, e.last_name, e.id;
END
GO

-- Rest-day rule list. @employee_id narrows to rules that include that employee; @from / @to to rules
-- that overlap the range. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [sch].[usp_rest_day_rule_list]
    @company_id  BIGINT,
    @employee_id BIGINT = NULL,
    @from_date   DATE = NULL,
    @to_date     DATE = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [sch].[rest_day_rule] r
    WHERE r.company_id = @company_id
      AND (@employee_id IS NULL OR EXISTS (SELECT 1 FROM [sch].[rest_day_rule_employee] x WHERE x.rest_day_rule_id = r.id AND x.employee_id = @employee_id))
      AND (@from_date IS NULL OR r.to_date >= @from_date)
      AND (@to_date IS NULL OR r.from_date <= @to_date)
    OPTION (RECOMPILE);

    SELECT r.id, r.from_date, r.to_date, r.weekdays, r.repeat_every_weeks, r.step, r.is_payable,
           (SELECT COUNT(*) FROM [sch].[rest_day_rule_employee] x WHERE x.rest_day_rule_id = r.id) AS employee_count,
           (SELECT COUNT(*) FROM [sch].[rest_day] d WHERE d.rest_day_rule_id = r.id) AS rest_day_count,
           r.created_at, r.updated_at, r.row_version
    FROM [sch].[rest_day_rule] r
    WHERE r.company_id = @company_id
      AND (@employee_id IS NULL OR EXISTS (SELECT 1 FROM [sch].[rest_day_rule_employee] x WHERE x.rest_day_rule_id = r.id AND x.employee_id = @employee_id))
      AND (@from_date IS NULL OR r.to_date >= @from_date)
      AND (@to_date IS NULL OR r.from_date <= @to_date)
    ORDER BY r.from_date DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds or edits a rule. @employee_ids is a JSON array of ids. Editing regenerates the rule's rest days.
CREATE OR ALTER PROCEDURE [sch].[usp_rest_day_rule_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT = NULL,
    @id                 BIGINT = NULL,
    @from_date          DATE,
    @to_date            DATE,
    @weekdays           NVARCHAR(30),
    @repeat_every_weeks INT = 0,
    @step               INT = 1,
    @is_payable         BIT = 0,
    @employee_ids       NVARCHAR(MAX),
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @repeat_every_weeks = ISNULL(@repeat_every_weeks, 0);
    SET @step = CASE WHEN @repeat_every_weeks = 0 THEN 1 ELSE ISNULL(@step, 1) END;
    SET @weekdays = NULLIF(REPLACE(LTRIM(RTRIM(@weekdays)), N' ', N''), N'');

    IF @from_date IS NULL
        THROW 50400, N'fromDate|From date is required.', 1;
    IF @to_date IS NULL
        THROW 50400, N'toDate|To date is required.', 1;
    IF @to_date < @from_date
        THROW 50400, N'toDate|To date cannot be before the from date.', 1;
    IF DATEDIFF(DAY, @from_date, @to_date) > 366
        THROW 50400, N'toDate|A rule covers at most a year.', 1;
    IF @weekdays IS NULL
        THROW 50400, N'weekdays|Pick at least one day.', 1;
    IF EXISTS (SELECT 1 FROM STRING_SPLIT(@weekdays, N',') WHERE ISNULL(TRY_CAST(value AS INT), 0) NOT BETWEEN 1 AND 7)
        THROW 50400, N'weekdays|Weekdays are 1 (Monday) to 7 (Sunday).', 1;
    IF @repeat_every_weeks NOT BETWEEN 0 AND 8
        THROW 50400, N'repeatEveryWeeks|Repeat is 0 (every week) or every 1 to 8 weeks.', 1;
    IF @step < 1 OR (@repeat_every_weeks > 0 AND @step > @repeat_every_weeks)
        THROW 50400, N'step|Step is between 1 and the number of weeks in the repeat.', 1;
    IF @employee_ids IS NULL OR ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Select at least one employee.', 1;

    DECLARE @ids TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @ids SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(@employee_ids) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @ids)
        THROW 50400, N'employeeIds|Select at least one employee.', 1;
    IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = i.employee_id AND e.company_id = @company_id))
        THROW 50400, N'employeeIds|Employee not found.', 1;

    -- Normalise the weekdays to "1,3,7".
    SELECT @weekdays = STRING_AGG(CAST(w AS NVARCHAR(1)), N',') WITHIN GROUP (ORDER BY w)
    FROM (SELECT DISTINCT TRY_CAST(value AS INT) AS w FROM STRING_SPLIT(@weekdays, N',')) x;

    IF NOT EXISTS (SELECT 1 FROM [sch].[fn_pattern_dates](@from_date, @to_date, @weekdays, @repeat_every_weeks, @step))
        THROW 50400, N'weekdays|These dates and days give no rest day.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a rest day rule.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sch].[rest_day_rule] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Rest day rule not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this rest day rule. Reload it and try again', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [sch].[rest_day_rule] (company_id, from_date, to_date, weekdays, repeat_every_weeks, step, is_payable, created_by)
            VALUES (@company_id, @from_date, @to_date, @weekdays, @repeat_every_weeks, @step, ISNULL(@is_payable, 0), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.rest_day_rule', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [sch].[rest_day_rule]
            SET from_date = @from_date, to_date = @to_date, weekdays = @weekdays, repeat_every_weeks = @repeat_every_weeks,
                step = @step, is_payable = ISNULL(@is_payable, 0), updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this rest day rule. Reload it and try again', 1;
            DELETE [sch].[rest_day] WHERE rest_day_rule_id = @id;
            DELETE [sch].[rest_day_rule_employee] WHERE rest_day_rule_id = @id;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'sch.rest_day_rule', @id, N'update', @actor_user_id, @now);
        END

        INSERT [sch].[rest_day_rule_employee] (rest_day_rule_id, employee_id, created_by)
        SELECT @id, employee_id, @actor_user_id FROM @ids;

        INSERT [sch].[rest_day] (company_id, employee_id, rest_date, is_payable, rest_day_rule_id, created_by)
        SELECT @company_id, i.employee_id, d.d, ISNULL(@is_payable, 0), @id, @actor_user_id
        FROM @ids i
        CROSS JOIN [sch].[fn_pattern_dates](@from_date, @to_date, @weekdays, @repeat_every_weeks, @step) d
        WHERE NOT EXISTS (SELECT 1 FROM [sch].[rest_day] r WHERE r.employee_id = i.employee_id AND r.rest_date = d.d);
    COMMIT;

    EXEC [sch].[usp_rest_day_rule_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a rule and the rest days it made. Shifts are not touched.
CREATE OR ALTER PROCEDURE [sch].[usp_rest_day_rule_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sch].[rest_day_rule] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Rest day rule not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this rest day rule. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [sch].[rest_day] WHERE rest_day_rule_id = @id;
        DELETE [sch].[rest_day_rule_employee] WHERE rest_day_rule_id = @id;
        DELETE [sch].[rest_day_rule] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'sch.rest_day_rule', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
