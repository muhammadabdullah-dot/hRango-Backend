-- Perks: occasion gifts per employee (Eid ul Adha, Eid ul Fitr, Birthday, Ramadan, New Year), availed or
-- not. Employee-owned: filtered with auth.fn_visible_employees and the endpoint's code.

CREATE OR ALTER PROCEDURE [ben].[usp_perk_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[perk] p
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
                   WHERE p.id = @id AND p.company_id = @company_id)
        THROW 50404, N'Perk not found', 1;

    SELECT p.id, p.employee_id, em.code AS employee_code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
           dp.name AS department_name, p.occasion, p.perk_date, p.description, p.amount, p.status,
           p.created_at, p.updated_at, p.row_version
    FROM [ben].[perk] p
    JOIN [hr].[employee] em ON em.id = p.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = em.department_id
    WHERE p.id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, latest first.
CREATE OR ALTER PROCEDURE [ben].[usp_perk_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @occasion        NVARCHAR(30) = NULL,
    @status          NVARCHAR(30) = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @v TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @v SELECT DISTINCT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [ben].[perk] p
    JOIN @v v ON v.employee_id = p.employee_id
    JOIN [hr].[employee] em ON em.id = p.employee_id
    WHERE p.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(em.first_name, N' ', em.last_name) LIKE @pattern OR em.code LIKE @pattern)
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@occasion IS NULL OR p.occasion = @occasion)
      AND (@status IS NULL OR p.status = @status)
      AND (@from_date IS NULL OR p.perk_date >= @from_date)
      AND (@to_date IS NULL OR p.perk_date <= @to_date)
    OPTION (RECOMPILE);

    SELECT p.id, p.employee_id, em.code AS employee_code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
           dp.name AS department_name, p.occasion, p.perk_date, p.description, p.amount, p.status,
           p.created_at, p.updated_at, p.row_version
    FROM [ben].[perk] p
    JOIN @v v ON v.employee_id = p.employee_id
    JOIN [hr].[employee] em ON em.id = p.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = em.department_id
    WHERE p.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(em.first_name, N' ', em.last_name) LIKE @pattern OR em.code LIKE @pattern)
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@occasion IS NULL OR p.occasion = @occasion)
      AND (@status IS NULL OR p.status = @status)
      AND (@from_date IS NULL OR p.perk_date >= @from_date)
      AND (@to_date IS NULL OR p.perk_date <= @to_date)
    ORDER BY p.perk_date DESC, em.first_name, p.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [ben].[usp_perk_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @occasion        NVARCHAR(30),
    @perk_date       DATE,
    @description     NVARCHAR(MAX) = NULL,
    @amount          DECIMAL(18,2) = NULL,
    @status          NVARCHAR(30) = N'not_availed',
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @status = ISNULL(NULLIF(@status, N''), N'not_availed');
    IF @employee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                                           WHERE v.employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @occasion IS NULL OR @occasion NOT IN (N'eid_ul_adha', N'eid_ul_fitr', N'birthday', N'ramadan', N'new_year')
        THROW 50400, N'occasion|Occasion is eid_ul_adha, eid_ul_fitr, birthday, ramadan or new_year.', 1;
    IF @perk_date IS NULL
        THROW 50400, N'perkDate|Enter the date.', 1;
    IF @amount < 0
        THROW 50400, N'amount|The amount cannot be negative.', 1;
    IF @status NOT IN (N'availed', N'not_availed')
        THROW 50400, N'status|Status is availed or not_availed.', 1;
    IF EXISTS (SELECT 1 FROM [ben].[perk] WHERE employee_id = @employee_id AND occasion = @occasion AND perk_date = @perk_date
               AND (@id IS NULL OR id <> @id))
        THROW 50409, N'occasion|PERK_DUPLICATE|This employee already has this perk on that date.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a perk.', 1;
        DECLARE @old_rv BINARY(8);
        SELECT @old_rv = p.row_version
        FROM [ben].[perk] p
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
        WHERE p.id = @id AND p.company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Perk not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this perk. Reload it and try again', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [ben].[perk] (company_id, employee_id, occasion, perk_date, description, amount, status, created_by)
            VALUES (@company_id, @employee_id, @occasion, @perk_date, @description, @amount, @status, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.perk', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [ben].[perk]
            SET employee_id = @employee_id, occasion = @occasion, perk_date = @perk_date, description = @description,
                amount = @amount, status = @status, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this perk. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.perk', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [ben].[usp_perk_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [ben].[usp_perk_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8);
    SELECT @rv = p.row_version
    FROM [ben].[perk] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE p.id = @id AND p.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Perk not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this perk. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [ben].[perk] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.perk', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
