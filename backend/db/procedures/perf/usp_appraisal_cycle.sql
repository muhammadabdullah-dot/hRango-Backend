-- Performance -> Appraisals: cycles (draft -> active -> closed) and their participants. Participants are
-- appraisal rows: added in draft, they wait; launching opens every one at the first review stage (self review
-- when the form has one, else manager review) with the line manager as reviewer, and tells them. People added
-- to an active cycle start at once. A cycle closes only when all its appraisals are finalised.

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_list]
    @company_id BIGINT,
    @status     NVARCHAR(30) = NULL,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [perf].[appraisal_cycle] c
    WHERE c.company_id = @company_id AND (@status IS NULL OR c.status = @status)
      AND (@pattern IS NULL OR c.name LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.* FROM [perf].[fn_appraisal_cycle_rows](@company_id) r
    WHERE (@status IS NULL OR r.status = @status) AND (@pattern IS NULL OR r.name LIKE @pattern)
    ORDER BY r.start_date DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Appraisal cycle not found', 1;
    SELECT r.* FROM [perf].[fn_appraisal_cycle_rows](@company_id) r WHERE r.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_save]
    @company_id              BIGINT,
    @actor_user_id           BIGINT = NULL,
    @id                      BIGINT = NULL,
    @name                    NVARCHAR(200),
    @appraisal_form_id       BIGINT,
    @start_date              DATE,
    @end_date                DATE,
    @self_review_due_date    DATE = NULL,
    @manager_review_due_date DATE = NULL,
    @row_version             BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|CYCLE_DUPLICATE|An appraisal cycle with this name already exists.', 1;

    DECLARE @old_status NVARCHAR(30), @old_form BIGINT, @old_start DATE, @old_end DATE;
    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8);
        SELECT @rv = row_version, @old_status = status, @old_form = appraisal_form_id, @old_start = start_date, @old_end = end_date
        FROM [perf].[appraisal_cycle] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Appraisal cycle not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this appraisal cycle. Reload it and try again', 1;
        IF @old_status = N'closed'
            THROW 50409, N'status|CYCLE_CLOSED|This appraisal cycle is closed.', 1;
        IF @old_status = N'active' AND (@old_form <> @appraisal_form_id OR @old_start <> @start_date OR @old_end <> @end_date)
            THROW 50409, N'appraisalFormId|CYCLE_LAUNCHED|The form and period of a launched cycle cannot change.', 1;
    END
    IF (@id IS NULL OR @old_form <> @appraisal_form_id)
       AND NOT EXISTS (SELECT 1 FROM [perf].[appraisal_form] WHERE id = @appraisal_form_id AND company_id = @company_id AND is_active = 1)
        THROW 50400, N'appraisalFormId|Choose an active appraisal form.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [perf].[appraisal_cycle] (company_id, name, appraisal_form_id, start_date, end_date, self_review_due_date,
                                             manager_review_due_date, status, created_by)
            VALUES (@company_id, @name, @appraisal_form_id, @start_date, @end_date, @self_review_due_date,
                    @manager_review_due_date, N'draft', @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'perf.appraisal_cycle', @id, N'name', @name, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [perf].[appraisal_cycle]
            SET name = @name, appraisal_form_id = @appraisal_form_id, start_date = @start_date, end_date = @end_date,
                self_review_due_date = @self_review_due_date, manager_review_due_date = @manager_review_due_date,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this appraisal cycle. Reload it and try again', 1;
        END
    COMMIT;

    EXEC [perf].[usp_appraisal_cycle_get] @company_id = @company_id, @id = @id;
END
GO

-- Only a draft cycle can be deleted; its waiting participants go with it and goals that named it keep
-- counting by due date.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @name NVARCHAR(200);
    SELECT @rv = row_version, @status = status, @name = name FROM [perf].[appraisal_cycle] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal cycle not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal cycle. Reload it and try again', 1;
    IF @status <> N'draft'
        THROW 50409, N'status|CYCLE_LAUNCHED|Only a draft cycle can be deleted.', 1;
    BEGIN TRAN;
        UPDATE [perf].[goal] SET appraisal_cycle_id = NULL WHERE appraisal_cycle_id = @id;
        DELETE r FROM [perf].[appraisal_rating] r JOIN [perf].[appraisal] a ON a.id = r.appraisal_id WHERE a.appraisal_cycle_id = @id;
        DELETE [perf].[appraisal] WHERE appraisal_cycle_id = @id;
        DELETE [perf].[appraisal_cycle] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.appraisal_cycle', @id, N'name', @name, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Adds people to a cycle: @employee_ids (JSON array of ids) and/or everyone working in @department_id.
-- Everyone named must be reachable through @permission_code; people already in the cycle are skipped.
-- Returns the cycle, then the number added.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_participants_add]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @employee_ids    NVARCHAR(MAX) = NULL,
    @department_id   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @self BIT, @cycle_name NVARCHAR(200);
    SELECT @status = c.status, @self = f.has_self_review, @cycle_name = c.name
    FROM [perf].[appraisal_cycle] c JOIN [perf].[appraisal_form] f ON f.id = c.appraisal_form_id
    WHERE c.id = @id AND c.company_id = @company_id;
    IF @status IS NULL
        THROW 50404, N'Appraisal cycle not found', 1;
    IF @status = N'closed'
        THROW 50409, N'status|CYCLE_CLOSED|This appraisal cycle is closed.', 1;
    IF @employee_ids IS NOT NULL AND ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Employees are not valid.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;

    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @people
    SELECT DISTINCT TRY_CONVERT(BIGINT, j.[value]) FROM OPENJSON(ISNULL(@employee_ids, N'[]')) j
    WHERE TRY_CONVERT(BIGINT, j.[value]) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @people p WHERE NOT EXISTS (
                   SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = p.employee_id))
        THROW 50400, N'employeeIds|Some of these employees were not found.', 1;
    INSERT @people
    SELECT e.id FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    WHERE @department_id IS NOT NULL AND e.department_id = @department_id AND e.status IN (N'active', N'probation', N'notice')
      AND NOT EXISTS (SELECT 1 FROM @people p WHERE p.employee_id = e.id);
    IF NOT EXISTS (SELECT 1 FROM @people)
        THROW 50400, N'employeeIds|Choose at least one employee.', 1;

    DECLARE @start NVARCHAR(30) = CASE WHEN @status = N'draft' THEN N'draft' WHEN @self = 1 THEN N'self_review' ELSE N'manager_review' END;
    DECLARE @added TABLE (id BIGINT, employee_id BIGINT);
    BEGIN TRAN;
        INSERT [perf].[appraisal] (company_id, appraisal_cycle_id, employee_id, reviewer_employee_id, status, created_by)
        OUTPUT inserted.id, inserted.employee_id INTO @added
        SELECT @company_id, @id, e.id, e.line_manager_id, @start, @actor_user_id
        FROM @people p JOIN [hr].[employee] e ON e.id = p.employee_id
        WHERE NOT EXISTS (SELECT 1 FROM [perf].[appraisal] a WHERE a.appraisal_cycle_id = @id AND a.employee_id = e.id);

        IF @status = N'active'
        BEGIN
            DECLARE @aid BIGINT = (SELECT MIN(id) FROM @added), @emp BIGINT, @link NVARCHAR(500),
                    @title NVARCHAR(200) = LEFT(N'Your appraisal is open: ' + @cycle_name, 200);
            WHILE @aid IS NOT NULL
            BEGIN
                SELECT @emp = employee_id FROM @added WHERE id = @aid;
                SET @link = N'/performance/reviews/' + CONVERT(NVARCHAR(20), @aid);
                EXEC [perf].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title,
                     @link = @link, @entity_type = N'perf.appraisal', @entity_id = @aid;
                SET @aid = (SELECT MIN(id) FROM @added WHERE id > @aid);
            END
        END
    COMMIT;

    EXEC [perf].[usp_appraisal_cycle_get] @company_id = @company_id, @id = @id;
    SELECT COUNT(*) AS added FROM @added;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_launch]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @self BIT, @form_active BIT, @name NVARCHAR(200);
    SELECT @rv = c.row_version, @status = c.status, @self = f.has_self_review, @form_active = f.is_active, @name = c.name
    FROM [perf].[appraisal_cycle] c JOIN [perf].[appraisal_form] f ON f.id = c.appraisal_form_id
    WHERE c.id = @id AND c.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal cycle not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal cycle. Reload it and try again', 1;
    IF @status <> N'draft'
        THROW 50409, N'status|CYCLE_LAUNCHED|This cycle has already been launched.', 1;
    IF @form_active = 0
        THROW 50409, N'appraisalFormId|The cycle''s appraisal form is inactive.', 1;
    IF NOT EXISTS (SELECT 1 FROM [perf].[appraisal] WHERE appraisal_cycle_id = @id)
        THROW 50409, N'participants|NO_PARTICIPANTS|Add participants before launching the cycle.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @count INT;
    BEGIN TRAN;
        UPDATE [perf].[appraisal_cycle] SET status = N'active', launched_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this appraisal cycle. Reload it and try again', 1;
        UPDATE a SET status = CASE WHEN @self = 1 THEN N'self_review' ELSE N'manager_review' END,
                     reviewer_employee_id = ISNULL(a.reviewer_employee_id, e.line_manager_id), updated_at = @now, updated_by = @actor_user_id
        FROM [perf].[appraisal] a JOIN [hr].[employee] e ON e.id = a.employee_id
        WHERE a.appraisal_cycle_id = @id;
        SET @count = @@ROWCOUNT;

        DECLARE @aid BIGINT = (SELECT MIN(id) FROM [perf].[appraisal] WHERE appraisal_cycle_id = @id), @emp BIGINT,
                @link NVARCHAR(500), @title NVARCHAR(200) = LEFT(N'Your appraisal is open: ' + @name, 200);
        WHILE @aid IS NOT NULL
        BEGIN
            SELECT @emp = employee_id FROM [perf].[appraisal] WHERE id = @aid;
            SET @link = N'/performance/reviews/' + CONVERT(NVARCHAR(20), @aid);
            EXEC [perf].[usp_notify_employee] @company_id = @company_id, @employee_id = @emp, @title = @title,
                 @link = @link, @entity_type = N'perf.appraisal', @entity_id = @aid;
            SET @aid = (SELECT MIN(id) FROM [perf].[appraisal] WHERE appraisal_cycle_id = @id AND id > @aid);
        END

        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS cycleId, @name AS name, @count AS participants
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'performance.cycle_launched',
             @entity_type = N'perf.appraisal_cycle', @entity_id = @id, @payload = @payload;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.appraisal_cycle', @id, N'status', N'draft', N'active', N'launch', @actor_user_id, @now);
    COMMIT;

    EXEC [perf].[usp_appraisal_cycle_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_cycle_close]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @name NVARCHAR(200);
    SELECT @rv = row_version, @status = status, @name = name FROM [perf].[appraisal_cycle] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal cycle not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal cycle. Reload it and try again', 1;
    IF @status <> N'active'
        THROW 50409, N'status|CYCLE_NOT_ACTIVE|Only an active cycle can be closed.', 1;
    IF EXISTS (SELECT 1 FROM [perf].[appraisal] WHERE appraisal_cycle_id = @id AND status <> N'finalised')
        THROW 50409, N'status|APPRAISALS_OPEN|Finalise or remove every appraisal before closing the cycle.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [perf].[appraisal_cycle] SET status = N'closed', closed_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS cycleId, @name AS name FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'performance.cycle_closed',
             @entity_type = N'perf.appraisal_cycle', @entity_id = @id, @payload = @payload;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.appraisal_cycle', @id, N'status', N'active', N'closed', N'close', @actor_user_id, @now);
    COMMIT;

    EXEC [perf].[usp_appraisal_cycle_get] @company_id = @company_id, @id = @id;
END
