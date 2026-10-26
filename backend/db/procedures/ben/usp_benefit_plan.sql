-- Benefit Plans: "Add {Category} Plan" (Plan Details), copy and delete. Enrolled counts come from
-- approved elections.

CREATE OR ALTER PROCEDURE [ben].[usp_benefit_plan_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[benefit_plan] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Plan not found', 1;

    SELECT * FROM [ben].[fn_benefit_plan_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, by category then name.
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_plan_list]
    @company_id   BIGINT,
    @search       NVARCHAR(200) = NULL,
    @category     NVARCHAR(30) = NULL,
    @plan_year_id BIGINT = NULL,
    @status       NVARCHAR(30) = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [ben].[benefit_plan] b
    WHERE b.company_id = @company_id
      AND (@pattern IS NULL OR b.name LIKE @pattern OR b.carrier LIKE @pattern)
      AND (@category IS NULL OR b.category = @category)
      AND (@status IS NULL OR b.status = @status)
      AND (@plan_year_id IS NULL OR EXISTS (SELECT 1 FROM [ben].[plan_year_plan] pp WHERE pp.plan_year_id = @plan_year_id AND pp.benefit_plan_id = b.id))
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [ben].[fn_benefit_plan_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern OR r.carrier LIKE @pattern)
      AND (@category IS NULL OR r.category = @category)
      AND (@status IS NULL OR r.status = @status)
      AND (@plan_year_id IS NULL OR EXISTS (SELECT 1 FROM [ben].[plan_year_plan] pp WHERE pp.plan_year_id = @plan_year_id AND pp.benefit_plan_id = r.id))
    ORDER BY CASE r.category WHEN N'medical' THEN 1 WHEN N'dental' THEN 2 WHEN N'vision' THEN 3 WHEN N'retirement' THEN 4
                             WHEN N'hsa' THEN 5 WHEN N'life' THEN 6 ELSE 7 END, r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [ben].[usp_benefit_plan_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @category      NVARCHAR(30),
    @name          NVARCHAR(200),
    @plan_type     NVARCHAR(100) = NULL,
    @plan_type_ref NVARCHAR(50) = NULL,
    @carrier       NVARCHAR(200) = NULL,
    @start_date    DATE,
    @end_date      DATE,
    @description   NVARCHAR(MAX) = NULL,
    @status        NVARCHAR(30) = N'active',
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @plan_type = NULLIF(LTRIM(RTRIM(@plan_type)), N'');
    SET @plan_type_ref = NULLIF(LTRIM(RTRIM(@plan_type_ref)), N'');
    SET @carrier = NULLIF(LTRIM(RTRIM(@carrier)), N'');
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @status = ISNULL(NULLIF(@status, N''), N'active');
    IF @category IS NULL OR @category NOT IN (N'medical', N'dental', N'vision', N'retirement', N'hsa', N'life', N'others')
        THROW 50400, N'category|Choose the plan category.', 1;
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Enter the plan name.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Enter the start date.', 1;
    IF @end_date IS NULL OR @end_date < @start_date
        THROW 50400, N'endDate|The end date cannot be before the start date.', 1;
    IF @status NOT IN (N'active', N'inactive')
        THROW 50400, N'status|Status is active or inactive.', 1;
    IF EXISTS (SELECT 1 FROM [ben].[benefit_plan] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|BENEFIT_PLAN_DUPLICATE|A plan with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a plan.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [ben].[benefit_plan] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Plan not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this plan. Reload it and try again', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [ben].[benefit_plan] (company_id, category, name, plan_type, plan_type_ref, carrier, start_date, end_date,
                                         description, status, created_by)
            VALUES (@company_id, @category, @name, @plan_type, @plan_type_ref, @carrier, @start_date, @end_date,
                    @description, @status, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.benefit_plan', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [ben].[benefit_plan]
            SET category = @category, name = @name, plan_type = @plan_type, plan_type_ref = @plan_type_ref, carrier = @carrier,
                start_date = @start_date, end_date = @end_date, description = @description, status = @status,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this plan. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.benefit_plan', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [ben].[usp_benefit_plan_get] @company_id = @company_id, @id = @id;
END
GO

-- Copies a plan's details as "<name> (copy)" (then "(copy 2)" ...). Its files and years are not copied.
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_plan_duplicate]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @name NVARCHAR(200) = (SELECT name FROM [ben].[benefit_plan] WHERE id = @id AND company_id = @company_id);
    IF @name IS NULL
        THROW 50404, N'Plan not found', 1;

    DECLARE @new_name NVARCHAR(200) = LEFT(@name, 190) + N' (copy)', @n INT = 1, @new_id BIGINT;
    WHILE EXISTS (SELECT 1 FROM [ben].[benefit_plan] WHERE company_id = @company_id AND name = @new_name)
    BEGIN
        SET @n += 1;
        SET @new_name = LEFT(@name, 186) + N' (copy ' + CAST(@n AS NVARCHAR(10)) + N')';
    END

    BEGIN TRAN;
        INSERT [ben].[benefit_plan] (company_id, category, name, plan_type, plan_type_ref, carrier, start_date, end_date,
                                     description, status, created_by)
        SELECT company_id, category, @new_name, plan_type, plan_type_ref, carrier, start_date, end_date, description,
               status, @actor_user_id
        FROM [ben].[benefit_plan] WHERE id = @id;
        SET @new_id = SCOPE_IDENTITY();
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (N'ben.benefit_plan', @new_id, N'create', CONCAT(N'copy of ', @id), @actor_user_id, SYSUTCDATETIME());
    COMMIT;

    EXEC [ben].[usp_benefit_plan_get] @company_id = @company_id, @id = @new_id;
END
GO

-- Deletes a plan nobody has elected, with its links to years and windows and its file links.
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_plan_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [ben].[benefit_plan] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Plan not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this plan. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [ben].[election_plan] WHERE benefit_plan_id = @id)
        THROW 50409, N'Employees have elected this plan; it cannot be deleted.', 1;

    BEGIN TRAN;
        DELETE [ben].[plan_year_plan] WHERE benefit_plan_id = @id;
        DELETE [ben].[enrollment_window_plan] WHERE benefit_plan_id = @id;
        DELETE [core].[attachment] WHERE entity_type = N'ben.benefit_plan' AND entity_id = @id;
        DELETE [ben].[benefit_plan] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.benefit_plan', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
