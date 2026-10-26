-- Job openings ("New Job Position"): list, add / edit, delete, and publish / hold / close / reopen.
-- Scope: rec.fn_visible_openings with the permission the endpoint required.

CREATE OR ALTER PROCEDURE [rec].[usp_job_opening_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v
                   WHERE v.job_opening_id = @id)
        THROW 50404, N'Job opening not found', 1;
    SELECT * FROM [rec].[fn_opening_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page: open first, then the latest.
CREATE OR ALTER PROCEDURE [rec].[usp_job_opening_list]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @search           NVARCHAR(200) = NULL,
    @status           NVARCHAR(30) = NULL,
    @department_id    BIGINT = NULL,
    @branch_id        BIGINT = NULL,
    @job_title_id     BIGINT = NULL,
    @open_position_id BIGINT = NULL,
    @page             INT = 1,
    @page_size        INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @v TABLE (id BIGINT PRIMARY KEY);
    INSERT @v SELECT job_opening_id FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [rec].[job_opening] o
    JOIN @v v ON v.id = o.id
    WHERE o.company_id = @company_id
      AND (@pattern IS NULL OR o.title LIKE @pattern OR o.code LIKE @pattern)
      AND (@status IS NULL OR o.status = @status)
      AND (@department_id IS NULL OR o.department_id = @department_id)
      AND (@branch_id IS NULL OR o.branch_id = @branch_id)
      AND (@job_title_id IS NULL OR o.job_title_id = @job_title_id)
      AND (@open_position_id IS NULL OR o.open_position_id = @open_position_id)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [rec].[fn_opening_rows](@company_id) x
    JOIN @v v ON v.id = x.id
    WHERE (@pattern IS NULL OR x.title LIKE @pattern OR x.code LIKE @pattern)
      AND (@status IS NULL OR x.status = @status)
      AND (@department_id IS NULL OR x.department_id = @department_id)
      AND (@branch_id IS NULL OR x.branch_id = @branch_id)
      AND (@job_title_id IS NULL OR x.job_title_id = @job_title_id)
      AND (@open_position_id IS NULL OR x.open_position_id = @open_position_id)
    ORDER BY CASE x.status WHEN N'open' THEN 0 WHEN N'on_hold' THEN 1 WHEN N'draft' THEN 2 ELSE 3 END, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL, as a draft) or edits an opening. From a Manpower open position the blanks take the
-- position's title, job title, department, station and open seats; the openings of one open position
-- may not ask for more unfilled vacancies than it has seats open. A blank code takes the next JOB-0001.
CREATE OR ALTER PROCEDURE [rec].[usp_job_opening_save]
    @company_id            BIGINT,
    @actor_user_id         BIGINT,
    @permission_code       NVARCHAR(150),
    @id                    BIGINT = NULL,
    @code                  NVARCHAR(30) = NULL,
    @title                 NVARCHAR(200) = NULL,
    @open_position_id      BIGINT = NULL,
    @job_title_id          BIGINT = NULL,
    @designation_id        BIGINT = NULL,
    @department_id         BIGINT = NULL,
    @branch_id             BIGINT = NULL,
    @employment_type_id    BIGINT = NULL,
    @hiring_manager_id     BIGINT = NULL,
    @city_id               BIGINT = NULL,
    @work_mode             NVARCHAR(30) = NULL,
    @experience_from_years INT = NULL,
    @experience_to_years   INT = NULL,
    @vacancies             INT = NULL,
    @posted_on             DATE = NULL,
    @apply_by              DATE = NULL,
    @close_on              DATE = NULL,
    @salary_from           DECIMAL(18,2) = NULL,
    @salary_to             DECIMAL(18,2) = NULL,
    @is_salary_visible     BIT = 0,
    @description           NVARCHAR(MAX) = NULL,
    @requirements          NVARCHAR(MAX) = NULL,
    @row_version           BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @code = NULLIF(LTRIM(RTRIM(@code)), N'');
    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @requirements = NULLIF(LTRIM(RTRIM(@requirements)), N'');

    DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30), @old_code NVARCHAR(30), @hired INT = 0;
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_rv = o.row_version, @old_status = o.status, @old_code = o.code
        FROM [rec].[job_opening] o
        JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = o.id
        WHERE o.id = @id;
        IF @old_rv IS NULL
            THROW 50404, N'Job opening not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a job opening.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this job opening. Reload it and try again', 1;
        IF @old_status = N'closed'
            THROW 50409, N'status|OPENING_CLOSED|A closed opening cannot be edited. Reopen it first.', 1;
        SET @hired = (SELECT COUNT(*) FROM [rec].[application] WHERE job_opening_id = @id AND stage = N'hired');
        SET @code = ISNULL(@code, @old_code);
    END

    -- From a Manpower open position: fill the blanks from it.
    DECLARE @op_seats INT, @op_status NVARCHAR(30);
    IF @open_position_id IS NOT NULL
    BEGIN
        SELECT @op_seats = total_positions, @op_status = status,
               @title = ISNULL(@title, title), @job_title_id = ISNULL(@job_title_id, job_title_id),
               @department_id = ISNULL(@department_id, department_id), @branch_id = ISNULL(@branch_id, branch_id)
        FROM [mp].[open_position] WHERE id = @open_position_id AND company_id = @company_id;
        IF @op_seats IS NULL
            THROW 50400, N'openPositionId|Open position not found.', 1;
        IF @op_status <> N'active' AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM [rec].[job_opening]
                                                                   WHERE id = @id AND open_position_id = @open_position_id))
            THROW 50409, N'openPositionId|OPEN_POSITION_CLOSED|This open position is closed.', 1;
        IF @vacancies IS NULL
            SET @vacancies = @op_seats - ISNULL((SELECT SUM(o.vacancies - h.n)
                                                 FROM [rec].[job_opening] o
                                                 OUTER APPLY (SELECT COUNT(*) AS n FROM [rec].[application] a
                                                              WHERE a.job_opening_id = o.id AND a.stage = N'hired') h
                                                 WHERE o.open_position_id = @open_position_id AND o.status <> N'closed'
                                                   AND (@id IS NULL OR o.id <> @id)), 0) + @hired;
    END
    IF @title IS NULL AND @job_title_id IS NOT NULL
        SET @title = (SELECT name FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id);

    -- Field checks.
    IF @title IS NULL
        THROW 50400, N'title|Job title is required.', 1;
    IF @vacancies IS NULL OR @vacancies < 1
        THROW 50400, N'vacancies|Enter the number of vacancies (1 or more).', 1;
    IF @vacancies < @hired
        THROW 50400, N'vacancies|Vacancies cannot be fewer than the candidates already hired.', 1;
    IF @work_mode IS NOT NULL AND @work_mode NOT IN (N'on_site', N'remote', N'hybrid')
        THROW 50400, N'workMode|Choose on site, remote or hybrid.', 1;
    IF @experience_from_years < 0 OR @experience_to_years < 0
        THROW 50400, N'experienceFromYears|Experience cannot be negative.', 1;
    IF @experience_to_years < @experience_from_years
        THROW 50400, N'experienceToYears|Experience To cannot be less than Experience From.', 1;
    IF @salary_from < 0 OR @salary_to < 0
        THROW 50400, N'salaryFrom|Salary cannot be negative.', 1;
    IF @salary_to < @salary_from
        THROW 50400, N'salaryTo|Salary To cannot be less than Salary From.', 1;
    IF @apply_by < @posted_on
        THROW 50400, N'applyBy|The last date to apply cannot be before the posted date.', 1;
    IF @close_on < @posted_on
        THROW 50400, N'closeOn|The close date cannot be before the posted date.', 1;
    IF @job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50400, N'jobTitleId|Job title not found.', 1;
    IF @designation_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[designation] WHERE id = @designation_id AND company_id = @company_id)
        THROW 50400, N'designationId|Designation not found.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Station not found.', 1;
    IF @employment_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[employment_type] WHERE id = @employment_type_id AND company_id = @company_id)
        THROW 50400, N'employmentTypeId|Employment type not found.', 1;
    IF @hiring_manager_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @hiring_manager_id AND company_id = @company_id
                                                      AND status NOT IN (N'left', N'inactive'))
        THROW 50400, N'hiringManagerId|Hiring manager not found.', 1;
    IF @city_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[city] WHERE id = @city_id)
        THROW 50400, N'cityId|City not found.', 1;
    IF @code IS NOT NULL AND EXISTS (SELECT 1 FROM [rec].[job_opening] WHERE company_id = @company_id AND code = @code
                                     AND (@id IS NULL OR id <> @id))
        THROW 50409, N'code|OPENING_CODE_DUPLICATE|Another job opening has this code.', 1;
    IF @open_position_id IS NOT NULL
       AND @vacancies - @hired + ISNULL((SELECT SUM(o.vacancies - h.n)
                                         FROM [rec].[job_opening] o
                                         OUTER APPLY (SELECT COUNT(*) AS n FROM [rec].[application] a
                                                      WHERE a.job_opening_id = o.id AND a.stage = N'hired') h
                                         WHERE o.open_position_id = @open_position_id AND o.status <> N'closed'
                                           AND (@id IS NULL OR o.id <> @id)), 0) > @op_seats
        THROW 50409, N'vacancies|OPEN_POSITION_SEATS|The open position does not have that many seats left to recruit for.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        IF @code IS NULL
        BEGIN
            DECLARE @next INT = 1 + ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(code, 5, 20) AS INT))
                                            FROM [rec].[job_opening] WITH (UPDLOCK, HOLDLOCK)
                                            WHERE company_id = @company_id AND code LIKE N'JOB-%'), 0);
            SET @code = N'JOB-' + RIGHT(N'0000' + CAST(@next AS NVARCHAR(10)), CASE WHEN @next > 9999 THEN 10 ELSE 4 END);
        END
        INSERT [rec].[job_opening] (company_id, code, title, open_position_id, job_title_id, designation_id, department_id,
                                    branch_id, employment_type_id, hiring_manager_id, city_id, work_mode,
                                    experience_from_years, experience_to_years, vacancies, posted_on, apply_by, close_on,
                                    salary_from, salary_to, is_salary_visible, description, requirements, status, created_by)
        VALUES (@company_id, @code, @title, @open_position_id, @job_title_id, @designation_id, @department_id,
                @branch_id, @employment_type_id, @hiring_manager_id, @city_id, @work_mode,
                @experience_from_years, @experience_to_years, @vacancies, @posted_on, @apply_by, @close_on,
                @salary_from, @salary_to, ISNULL(@is_salary_visible, 0), @description, @requirements, N'draft', @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.job_opening', @id, N'create', @code, @actor_user_id, @now);
    END
    ELSE
    BEGIN
        DECLARE @before NVARCHAR(MAX) = (
            SELECT code, title, open_position_id, job_title_id, designation_id, department_id, branch_id, employment_type_id,
                   hiring_manager_id, city_id, work_mode, experience_from_years, experience_to_years, vacancies, posted_on,
                   apply_by, close_on, salary_from, salary_to, is_salary_visible
            FROM [rec].[job_opening] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        UPDATE [rec].[job_opening]
        SET code = @code, title = @title, open_position_id = @open_position_id, job_title_id = @job_title_id,
            designation_id = @designation_id, department_id = @department_id, branch_id = @branch_id,
            employment_type_id = @employment_type_id, hiring_manager_id = @hiring_manager_id, city_id = @city_id,
            work_mode = @work_mode, experience_from_years = @experience_from_years,
            experience_to_years = @experience_to_years, vacancies = @vacancies, posted_on = @posted_on,
            apply_by = @apply_by, close_on = @close_on, salary_from = @salary_from, salary_to = @salary_to,
            is_salary_visible = ISNULL(@is_salary_visible, 0), description = @description, requirements = @requirements,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this job opening. Reload it and try again', 1;
        DECLARE @after NVARCHAR(MAX) = (
            SELECT code, title, open_position_id, job_title_id, designation_id, department_id, branch_id, employment_type_id,
                   hiring_manager_id, city_id, work_mode, experience_from_years, experience_to_years, vacancies, posted_on,
                   apply_by, close_on, salary_from, salary_to, is_salary_visible
            FROM [rec].[job_opening] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'rec.job_opening', @id, b.[key], b.value, a.value, N'update', @actor_user_id, @now
        FROM OPENJSON(@before) b JOIN OPENJSON(@after) a ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);
    END

    -- The saved opening must still be one the caller reaches (a department recruiter cannot place it elsewhere).
    IF NOT EXISTS (SELECT 1 FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v WHERE v.job_opening_id = @id)
        THROW 50403, N'You can only place openings within the departments and stations your permission covers.', 1;
    COMMIT;

    EXEC [rec].[usp_job_opening_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Deletes an opening nobody has applied to.
CREATE OR ALTER PROCEDURE [rec].[usp_job_opening_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @code NVARCHAR(30);
    SELECT @rv = o.row_version, @code = o.code
    FROM [rec].[job_opening] o
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = o.id
    WHERE o.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Job opening not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required to delete a job opening.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this job opening. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [rec].[application] WHERE job_opening_id = @id)
        THROW 50409, N'id|OPENING_IN_USE|This opening has applications. Close it instead.', 1;

    BEGIN TRAN;
        DELETE FROM [rec].[job_opening] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this job opening. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, old_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.job_opening', @id, N'delete', @code, @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Publish (draft -> open), hold (open -> on_hold), close (any -> closed) or reopen (on_hold / closed -> open).
CREATE OR ALTER PROCEDURE [rec].[usp_job_opening_status]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @action          NVARCHAR(30),
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @old NVARCHAR(30), @vacancies INT, @op BIGINT, @new NVARCHAR(30),
            @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SELECT @rv = o.row_version, @old = o.status, @vacancies = o.vacancies, @op = o.open_position_id
    FROM [rec].[job_opening] o
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = o.id
    WHERE o.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Job opening not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this job opening. Reload it and try again', 1;

    SET @new = CASE @action WHEN N'publish' THEN N'open' WHEN N'hold' THEN N'on_hold' WHEN N'close' THEN N'closed'
                            WHEN N'reopen' THEN N'open' END;
    IF @new IS NULL
        THROW 50400, N'action|Choose publish, hold, close or reopen.', 1;
    IF NOT (   (@action = N'publish' AND @old = N'draft')
            OR (@action = N'hold' AND @old = N'open')
            OR (@action = N'close' AND @old <> N'closed')
            OR (@action = N'reopen' AND @old IN (N'on_hold', N'closed')))
        THROW 50409, N'status|OPENING_STATUS|The opening cannot do that in its current state.', 1;
    IF @new = N'open' AND @vacancies <= (SELECT COUNT(*) FROM [rec].[application] WHERE job_opening_id = @id AND stage = N'hired')
        THROW 50409, N'vacancies|OPENING_FILLED|Every vacancy of this opening is filled. Add vacancies first.', 1;
    IF @new = N'open' AND @op IS NOT NULL AND EXISTS (SELECT 1 FROM [mp].[open_position] WHERE id = @op AND status <> N'active')
        THROW 50409, N'openPositionId|OPEN_POSITION_CLOSED|The open position behind this opening is closed.', 1;

    BEGIN TRAN;
        UPDATE [rec].[job_opening]
        SET status = @new,
            posted_on = CASE WHEN @action = N'publish' THEN ISNULL(posted_on, @today) ELSE posted_on END,
            published_at = CASE WHEN @action = N'publish' THEN @now ELSE published_at END,
            closed_at = CASE WHEN @new = N'closed' THEN @now WHEN @new = N'open' THEN NULL ELSE closed_at END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this job opening. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.job_opening', @id, N'status', @old, @new, @action, @actor_user_id, @now);

        IF @action IN (N'publish', N'close')
        BEGIN
            DECLARE @payload NVARCHAR(MAX) = (
                SELECT CONVERT(NVARCHAR(30), o.id) AS jobOpeningId, o.code, o.title, o.status, o.vacancies,
                       CONVERT(NVARCHAR(30), o.department_id) AS departmentId, CONVERT(NVARCHAR(30), o.branch_id) AS branchId,
                       o.posted_on AS postedOn, o.apply_by AS applyBy, N'manual' AS reason
                FROM [rec].[job_opening] o WHERE o.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            DECLARE @event NVARCHAR(100) = CASE @action WHEN N'publish' THEN N'recruitment.opening_published'
                                                        ELSE N'recruitment.opening_closed' END;
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event,
                 @entity_type = N'rec.job_opening', @entity_id = @id, @payload = @payload;
        END
    COMMIT;

    EXEC [rec].[usp_job_opening_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO
