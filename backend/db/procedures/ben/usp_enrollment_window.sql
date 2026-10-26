-- Enrollment Windows: "New Open Enrollment Window" step 1 (name, plan year, effective date, plans, last day
-- to enrol) and step 2 (who can enrol). kind: open_enrollment, life_event (Qualifying Life Event), new_hire.

CREATE OR ALTER PROCEDURE [ben].[usp_enrollment_window_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Enrollment window not found', 1;

    SELECT * FROM [ben].[fn_window_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page: open first, then by last day.
CREATE OR ALTER PROCEDURE [ben].[usp_enrollment_window_list]
    @company_id   BIGINT,
    @search       NVARCHAR(200) = NULL,
    @plan_year_id BIGINT = NULL,
    @kind         NVARCHAR(30) = NULL,
    @status       NVARCHAR(30) = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [ben].[fn_window_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern)
      AND (@plan_year_id IS NULL OR r.plan_year_id = @plan_year_id)
      AND (@kind IS NULL OR r.kind = @kind)
      AND (@status IS NULL OR r.status = @status)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [ben].[fn_window_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern)
      AND (@plan_year_id IS NULL OR r.plan_year_id = @plan_year_id)
      AND (@kind IS NULL OR r.kind = @kind)
      AND (@status IS NULL OR r.status = @status)
    ORDER BY CASE r.status WHEN N'open' THEN 0 ELSE 1 END, r.closes_on, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL) or edits a window. @plan_ids: JSON list, plans of the plan year (at least one).
-- @employee_ids: JSON list of who may enrol; empty means everyone.
CREATE OR ALTER PROCEDURE [ben].[usp_enrollment_window_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @id             BIGINT = NULL,
    @plan_year_id   BIGINT,
    @kind           NVARCHAR(30) = N'open_enrollment',
    @name           NVARCHAR(200),
    @effective_date DATE,
    @closes_on      DATE,
    @description    NVARCHAR(MAX) = NULL,
    @plan_ids       NVARCHAR(MAX),
    @employee_ids   NVARCHAR(MAX) = N'[]',
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @y_start DATE, @y_end DATE, @now DATETIME2(0) = SYSUTCDATETIME();
    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @employee_ids = ISNULL(@employee_ids, N'[]');

    SELECT @y_start = start_date, @y_end = end_date FROM [ben].[plan_year] WHERE id = @plan_year_id AND company_id = @company_id;
    IF @y_start IS NULL
        THROW 50400, N'planYearId|Choose the plan year.', 1;
    IF @kind IS NULL OR @kind NOT IN (N'open_enrollment', N'life_event', N'new_hire')
        THROW 50400, N'kind|Kind is open_enrollment, life_event or new_hire.', 1;
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Enter the enrollment name.', 1;
    IF @effective_date IS NULL OR @effective_date < @y_start OR @effective_date > @y_end
        THROW 50400, N'effectiveDate|The effective date must fall in the plan year.', 1;
    IF @closes_on IS NULL
        THROW 50400, N'closesOn|Enter the last day to enrol.', 1;
    IF @plan_ids IS NULL OR ISJSON(@plan_ids) = 0 OR LEFT(LTRIM(@plan_ids), 1) <> N'['
       OR NOT EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids))
        THROW 50400, N'planIds|Choose at least one plan.', 1;
    IF EXISTS (SELECT 1 FROM [ben].[fn_id_list](@plan_ids) p
               WHERE p.id IS NULL OR NOT EXISTS (SELECT 1 FROM [ben].[plan_year_plan] pp WHERE pp.plan_year_id = @plan_year_id AND pp.benefit_plan_id = p.id))
        THROW 50400, N'planIds|Choose plans offered in the plan year.', 1;
    IF ISJSON(@employee_ids) = 0 OR LEFT(LTRIM(@employee_ids), 1) <> N'['
       OR EXISTS (SELECT 1 FROM [ben].[fn_id_list](@employee_ids) e
                  WHERE e.id IS NULL OR NOT EXISTS (SELECT 1 FROM [hr].[employee] x WHERE x.id = e.id AND x.company_id = @company_id))
        THROW 50400, N'employeeIds|A chosen employee was not found.', 1;

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an enrollment window.', 1;
        DECLARE @old_rv BINARY(8), @old_year BIGINT;
        SELECT @old_rv = row_version, @old_year = plan_year_id FROM [ben].[enrollment_window] WHERE id = @id AND company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Enrollment window not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this enrollment window. Reload it and try again', 1;
        IF @old_year <> @plan_year_id AND EXISTS (SELECT 1 FROM [ben].[election] WHERE enrollment_window_id = @id)
            THROW 50409, N'planYearId|Employees have elected in this window; its plan year cannot change.', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [ben].[enrollment_window] (company_id, plan_year_id, kind, name, effective_date, closes_on, description, created_by)
            VALUES (@company_id, @plan_year_id, @kind, @name, @effective_date, @closes_on, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.enrollment_window', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [ben].[enrollment_window]
            SET plan_year_id = @plan_year_id, kind = @kind, name = @name, effective_date = @effective_date,
                closes_on = @closes_on, description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this enrollment window. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.enrollment_window', @id, N'update', @actor_user_id, @now);
        END

        DELETE [ben].[enrollment_window_plan]
        WHERE enrollment_window_id = @id AND benefit_plan_id NOT IN (SELECT id FROM [ben].[fn_id_list](@plan_ids));
        INSERT [ben].[enrollment_window_plan] (enrollment_window_id, benefit_plan_id, created_by)
        SELECT @id, p.id, @actor_user_id FROM [ben].[fn_id_list](@plan_ids) p
        WHERE NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window_plan] x WHERE x.enrollment_window_id = @id AND x.benefit_plan_id = p.id);

        DELETE [ben].[enrollment_window_employee]
        WHERE enrollment_window_id = @id AND employee_id NOT IN (SELECT id FROM [ben].[fn_id_list](@employee_ids));
        INSERT [ben].[enrollment_window_employee] (enrollment_window_id, employee_id, created_by)
        SELECT @id, e.id, @actor_user_id FROM [ben].[fn_id_list](@employee_ids) e
        WHERE NOT EXISTS (SELECT 1 FROM [ben].[enrollment_window_employee] x WHERE x.enrollment_window_id = @id AND x.employee_id = e.id);
    COMMIT;

    EXEC [ben].[usp_enrollment_window_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a window. Elections made in it stay, no longer tied to a window.
CREATE OR ALTER PROCEDURE [ben].[usp_enrollment_window_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [ben].[enrollment_window] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Enrollment window not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this enrollment window. Reload it and try again', 1;

    BEGIN TRAN;
        UPDATE [ben].[election] SET enrollment_window_id = NULL WHERE enrollment_window_id = @id;
        DELETE [ben].[enrollment_window_plan] WHERE enrollment_window_id = @id;
        DELETE [ben].[enrollment_window_employee] WHERE enrollment_window_id = @id;
        DELETE [ben].[enrollment_window] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.enrollment_window', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
