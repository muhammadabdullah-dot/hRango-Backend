-- Payroll Settings -> Tax: tax structures with their slabs, and tax rebates per employee.

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [pay].[usp_tax_structure_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[tax_structure] t
    WHERE t.company_id = @company_id AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT t.id, t.code, t.name, t.start_date, t.end_date, t.surcharge_type, t.surcharge_value, t.description,
           (SELECT COUNT(*) FROM [pay].[tax_slab] s WHERE s.tax_structure_id = t.id) AS slab_count,
           t.created_at, t.updated_at, t.row_version
    FROM [pay].[tax_structure] t
    WHERE t.company_id = @company_id AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
    ORDER BY t.start_date DESC, t.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Result set 1: the structure. Result set 2: its slabs, lowest first.
CREATE OR ALTER PROCEDURE [pay].[usp_tax_structure_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[tax_structure] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Tax structure not found', 1;

    SELECT t.id, t.code, t.name, t.start_date, t.end_date, t.surcharge_type, t.surcharge_value, t.description,
           (SELECT COUNT(*) FROM [pay].[tax_slab] s WHERE s.tax_structure_id = t.id) AS slab_count,
           t.created_at, t.updated_at, t.row_version
    FROM [pay].[tax_structure] t WHERE t.id = @id;

    SELECT s.id, s.min_amount, s.max_amount, s.fixed_amount, s.percentage
    FROM [pay].[tax_slab] s WHERE s.tax_structure_id = @id ORDER BY s.min_amount;
END
GO

-- @slabs: JSON [{"minAmount","maxAmount","fixedAmount","percentage"}]; replaces the slabs.
CREATE OR ALTER PROCEDURE [pay].[usp_tax_structure_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @start_date      DATE,
    @end_date        DATE,
    @surcharge_type  NVARCHAR(30) = NULL,
    @surcharge_value DECIMAL(18,2) = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @slabs           NVARCHAR(MAX),
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[tax_structure] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|TAX_STRUCTURE_DUPLICATE|A tax structure with this name already exists.', 1;
    IF ISJSON(@slabs) <> 1
        THROW 50400, N'slabs|Slabs are not valid.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            EXEC [pay].[usp_sequence_next] @company_id, N'TXS-', 4, @code OUTPUT;
            INSERT [pay].[tax_structure] (company_id, code, name, start_date, end_date, surcharge_type, surcharge_value, description, created_by)
            VALUES (@company_id, @code, @name, @start_date, @end_date, @surcharge_type, @surcharge_value, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.tax_structure', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [pay].[tax_structure]
            SET name = @name, start_date = @start_date, end_date = @end_date, surcharge_type = @surcharge_type,
                surcharge_value = @surcharge_value, description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[tax_structure] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Tax structure not found', 1;
                THROW 50409, N'Someone else changed this tax structure. Reload it and try again', 1;
            END
            DELETE [pay].[tax_slab] WHERE tax_structure_id = @id;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.tax_structure', @id, N'update', @actor_user_id, @now);
        END

        INSERT [pay].[tax_slab] (tax_structure_id, min_amount, max_amount, fixed_amount, percentage, created_by)
        SELECT @id, j.min_amount, j.max_amount, ISNULL(j.fixed_amount, 0), ISNULL(j.percentage, 0), @actor_user_id
        FROM OPENJSON(@slabs) WITH (min_amount DECIMAL(18,2) '$.minAmount', max_amount DECIMAL(18,2) '$.maxAmount',
                                   fixed_amount DECIMAL(18,2) '$.fixedAmount', percentage DECIMAL(5,2) '$.percentage') j;
    COMMIT;

    EXEC [pay].[usp_tax_structure_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_tax_structure_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pay].[tax_structure] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Tax structure not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this tax structure. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [pay].[payroll] WHERE tax_structure_id = @id)
        THROW 50409, N'Payrolls use this tax structure. It cannot be deleted', 1;

    BEGIN TRAN;
        DELETE [pay].[tax_slab] WHERE tax_structure_id = @id;
        DELETE [pay].[tax_structure] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.tax_structure', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Tax rebates of the employees the caller may see through @permission_code.
CREATE OR ALTER PROCEDURE [pay].[usp_tax_rebate_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [pay].[tax_rebate] r
    JOIN [hr].[employee] e ON e.id = r.employee_id AND e.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    WHERE (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@from_date IS NULL OR r.rebate_date >= @from_date) AND (@to_date IS NULL OR r.rebate_date <= @to_date)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.id, r.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           r.rebate_date, r.amount, r.file_id, f.name AS file_name, r.description, r.created_at, r.updated_at, r.row_version
    FROM [pay].[tax_rebate] r
    JOIN [hr].[employee] e ON e.id = r.employee_id AND e.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    LEFT JOIN [core].[stored_file] f ON f.id = r.file_id
    WHERE (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@from_date IS NULL OR r.rebate_date >= @from_date) AND (@to_date IS NULL OR r.rebate_date <= @to_date)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    ORDER BY r.rebate_date DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_tax_rebate_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[tax_rebate] r
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
                   WHERE r.id = @id)
        THROW 50404, N'Tax rebate not found', 1;

    SELECT r.id, r.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           r.rebate_date, r.amount, r.file_id, f.name AS file_name, r.description, r.created_at, r.updated_at, r.row_version
    FROM [pay].[tax_rebate] r
    JOIN [hr].[employee] e ON e.id = r.employee_id
    LEFT JOIN [core].[stored_file] f ON f.id = r.file_id
    WHERE r.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_tax_rebate_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @rebate_date     DATE,
    @amount          DECIMAL(18,2),
    @file_id         BIGINT = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[tax_rebate] (employee_id, rebate_date, amount, file_id, description, created_by)
            VALUES (@employee_id, @rebate_date, @amount, @file_id, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.tax_rebate', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [pay].[tax_rebate] r
                           JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
                           WHERE r.id = @id)
                THROW 50404, N'Tax rebate not found', 1;
            UPDATE [pay].[tax_rebate]
            SET employee_id = @employee_id, rebate_date = @rebate_date, amount = @amount, file_id = @file_id,
                description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this tax rebate. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.tax_rebate', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [pay].[usp_tax_rebate_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
        @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_tax_rebate_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT r.row_version FROM [pay].[tax_rebate] r
                             JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
                             WHERE r.id = @id);
    IF @rv IS NULL
        THROW 50404, N'Tax rebate not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this tax rebate. Reload it and try again', 1;
    BEGIN TRAN;
        DELETE [pay].[tax_rebate] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.tax_rebate', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
