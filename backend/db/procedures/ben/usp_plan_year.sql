-- Benefit Plan Years: Details (name, dates), Plans (the plans offered), New Hires (when enrolment starts,
-- how long new people have to elect).

CREATE OR ALTER PROCEDURE [ben].[usp_plan_year_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[plan_year] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Plan year not found', 1;

    SELECT * FROM [ben].[fn_plan_year_rows](@company_id, @actor_user_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, latest year first. @status: upcoming, active, ended.
CREATE OR ALTER PROCEDURE [ben].[usp_plan_year_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
    @status        NVARCHAR(30) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    SELECT COUNT(*) AS total
    FROM [ben].[plan_year] y
    WHERE y.company_id = @company_id
      AND (@pattern IS NULL OR y.name LIKE @pattern)
      AND (@status IS NULL
           OR (@status = N'upcoming' AND @today < y.start_date)
           OR (@status = N'ended' AND @today > y.end_date)
           OR (@status = N'active' AND @today BETWEEN y.start_date AND y.end_date))
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [ben].[fn_plan_year_rows](@company_id, @actor_user_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern)
      AND (@status IS NULL OR r.status = @status)
    ORDER BY r.start_date DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL) or edits a plan year with the plans it offers (@plan_ids: JSON list of plan ids).
CREATE OR ALTER PROCEDURE [ben].[usp_plan_year_save]
    @company_id          BIGINT,
    @actor_user_id       BIGINT,
    @id                  BIGINT = NULL,
    @name                NVARCHAR(200),
    @start_date          DATE,
    @end_date            DATE,
    @plan_ids            NVARCHAR(MAX) = N'[]',
    @new_hire_start      NVARCHAR(30) = N'immediately',
    @waiting_period_days INT = NULL,
    @election_period     INT = 30,
    @election_unit       NVARCHAR(10) = N'day',
    @row_version         BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Enter the plan year name.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Enter the start date.', 1;
    IF @end_date IS NULL OR @end_date <= @start_date
        THROW 50400, N'endDate|The end date must be after the start date.', 1;
    IF @new_hire_start IS NULL OR @new_hire_start NOT IN (N'immediately', N'waiting_period', N'per_employee')
        THROW 50400, N'newHireStart|Choose when new hires can start their enrollment.', 1;
    IF @new_hire_start = N'waiting_period' AND (@waiting_period_days IS NULL OR @waiting_period_days < 1)
        THROW 50400, N'waitingPeriodDays|Enter the waiting period in days.', 1;
    IF @new_hire_start <> N'waiting_period'
        SET @waiting_period_days = NULL;
    IF @election_period IS NULL OR @election_period < 1 OR @election_period > 365
        THROW 50400, N'electionPeriod|Enter how long new employees have to elect (1 to 365).', 1;
    IF @election_unit IS NULL OR @election_unit NOT IN (N'day', N'week', N'month')
        THROW 50400, N'electionUnit|The unit is day, week or month.', 1;
    IF @plan_ids IS NULL OR ISJSON(@plan_ids) = 0 OR LEFT(LTRIM(@plan_ids), 1) <> N'['
        THROW 50400, N'planIds|Plans must be a JSON list.', 1;
    IF EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids) p
               WHERE p.id IS NULL OR NOT EXISTS (SELECT 1 FROM [ben].[benefit_plan] b WHERE b.id = p.id AND b.company_id = @company_id))
        THROW 50400, N'planIds|A chosen plan was not found.', 1;
    IF EXISTS (SELECT 1 FROM [ben].[plan_year] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|PLAN_YEAR_DUPLICATE|A plan year with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a plan year.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [ben].[plan_year] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Plan year not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this plan year. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [ben].[election] e JOIN [ben].[election_plan] ep ON ep.election_id = e.id
                   WHERE e.plan_year_id = @id AND ep.benefit_plan_id NOT IN (SELECT id FROM [ben].[fn_id_list](@plan_ids)))
            THROW 50409, N'planIds|PLAN_IN_USE|Employees have elected a plan you removed. Keep it in the plan year.', 1;
        IF EXISTS (SELECT 1 FROM [ben].[enrollment_window] w WHERE w.plan_year_id = @id
                   AND (w.effective_date < @start_date OR w.effective_date > @end_date))
            THROW 50409, N'startDate|WINDOW_OUTSIDE_YEAR|An enrollment window of this year becomes effective outside the new dates.', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [ben].[plan_year] (company_id, name, start_date, end_date, new_hire_start, waiting_period_days,
                                      election_period, election_unit, created_by)
            VALUES (@company_id, @name, @start_date, @end_date, @new_hire_start, @waiting_period_days,
                    @election_period, @election_unit, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.plan_year', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [ben].[plan_year]
            SET name = @name, start_date = @start_date, end_date = @end_date, new_hire_start = @new_hire_start,
                waiting_period_days = @waiting_period_days, election_period = @election_period,
                election_unit = @election_unit, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this plan year. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.plan_year', @id, N'update', @actor_user_id, @now);
        END

        DELETE [ben].[plan_year_plan]
        WHERE plan_year_id = @id AND benefit_plan_id NOT IN (SELECT id FROM [ben].[fn_id_list](@plan_ids));
        -- A plan taken out of the year is no longer offered in its windows either.
        DELETE wp FROM [ben].[enrollment_window_plan] wp
        JOIN [ben].[enrollment_window] w ON w.id = wp.enrollment_window_id
        WHERE w.plan_year_id = @id AND wp.benefit_plan_id NOT IN (SELECT id FROM [ben].[fn_id_list](@plan_ids));
        INSERT [ben].[plan_year_plan] (plan_year_id, benefit_plan_id, created_by)
        SELECT @id, p.id, @actor_user_id FROM [ben].[fn_id_list](@plan_ids) p
        WHERE NOT EXISTS (SELECT 1 FROM [ben].[plan_year_plan] x WHERE x.plan_year_id = @id AND x.benefit_plan_id = p.id);
    COMMIT;

    EXEC [ben].[usp_plan_year_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Deletes a plan year with its windows and elections. Refused while an approved election stands.
CREATE OR ALTER PROCEDURE [ben].[usp_plan_year_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [ben].[plan_year] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Plan year not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this plan year. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [ben].[election] WHERE plan_year_id = @id AND status = N'approved')
        THROW 50409, N'Employees have approved elections in this plan year; it cannot be deleted.', 1;

    BEGIN TRAN;
        DELETE ep FROM [ben].[election_plan] ep JOIN [ben].[election] e ON e.id = ep.election_id WHERE e.plan_year_id = @id;
        DELETE [ben].[election] WHERE plan_year_id = @id;
        DELETE wp FROM [ben].[enrollment_window_plan] wp JOIN [ben].[enrollment_window] w ON w.id = wp.enrollment_window_id
        WHERE w.plan_year_id = @id;
        DELETE we FROM [ben].[enrollment_window_employee] we JOIN [ben].[enrollment_window] w ON w.id = we.enrollment_window_id
        WHERE w.plan_year_id = @id;
        DELETE [ben].[enrollment_window] WHERE plan_year_id = @id;
        DELETE [ben].[plan_year_plan] WHERE plan_year_id = @id;
        DELETE [ben].[plan_year] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.plan_year', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
