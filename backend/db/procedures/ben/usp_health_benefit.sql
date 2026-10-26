-- Health Benefits: the insurance an employee holds (insurer, policy, coverage, life cover, annual payment,
-- availed / not availed) and its document (policy or insurance card, an upload). Employee-owned: filtered
-- with auth.fn_visible_employees and the endpoint's code.

CREATE OR ALTER PROCEDURE [ben].[usp_health_benefit_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[health_benefit] h
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = h.employee_id
                   WHERE h.id = @id AND h.company_id = @company_id)
        THROW 50404, N'Health benefit not found', 1;

    SELECT h.id, h.employee_id, em.code AS employee_code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
           dp.name AS department_name, h.insurer, h.policy_no, h.coverage_amount, h.life_cover_amount, h.annual_payment,
           h.start_date, h.end_date, h.status, h.remarks, h.document_file_id,
           (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = h.document_file_id) AS document_file_name,
           h.created_at, h.updated_at, h.row_version
    FROM [ben].[health_benefit] h
    JOIN [hr].[employee] em ON em.id = h.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = em.department_id
    WHERE h.id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, by employee.
CREATE OR ALTER PROCEDURE [ben].[usp_health_benefit_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @status          NVARCHAR(30) = NULL,
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
    FROM [ben].[health_benefit] h
    JOIN @v v ON v.employee_id = h.employee_id
    JOIN [hr].[employee] em ON em.id = h.employee_id
    WHERE h.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(em.first_name, N' ', em.last_name) LIKE @pattern OR em.code LIKE @pattern OR h.insurer LIKE @pattern)
      AND (@employee_id IS NULL OR h.employee_id = @employee_id)
      AND (@status IS NULL OR h.status = @status)
    OPTION (RECOMPILE);

    SELECT h.id, h.employee_id, em.code AS employee_code, NULLIF(CONCAT(em.first_name, N' ', em.last_name), N' ') AS employee_name,
           dp.name AS department_name, h.insurer, h.policy_no, h.coverage_amount, h.life_cover_amount, h.annual_payment,
           h.start_date, h.end_date, h.status, h.remarks, h.document_file_id,
           (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = h.document_file_id) AS document_file_name,
           h.created_at, h.updated_at, h.row_version
    FROM [ben].[health_benefit] h
    JOIN @v v ON v.employee_id = h.employee_id
    JOIN [hr].[employee] em ON em.id = h.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = em.department_id
    WHERE h.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(em.first_name, N' ', em.last_name) LIKE @pattern OR em.code LIKE @pattern OR h.insurer LIKE @pattern)
      AND (@employee_id IS NULL OR h.employee_id = @employee_id)
      AND (@status IS NULL OR h.status = @status)
    ORDER BY em.first_name, em.last_name, h.start_date DESC, h.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [ben].[usp_health_benefit_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT,
    @permission_code   NVARCHAR(150),
    @id                BIGINT = NULL,
    @employee_id       BIGINT,
    @insurer           NVARCHAR(200),
    @policy_no         NVARCHAR(50) = NULL,
    @coverage_amount   DECIMAL(18,2) = NULL,
    @life_cover_amount DECIMAL(18,2) = NULL,
    @annual_payment    DECIMAL(18,2) = NULL,
    @start_date        DATE = NULL,
    @end_date          DATE = NULL,
    @status            NVARCHAR(30) = N'not_availed',
    @remarks           NVARCHAR(MAX) = NULL,
    @document_file_id  BIGINT = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @insurer = LTRIM(RTRIM(@insurer));
    SET @policy_no = NULLIF(LTRIM(RTRIM(@policy_no)), N'');
    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');
    SET @status = ISNULL(NULLIF(@status, N''), N'not_availed');
    IF @employee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                                           WHERE v.employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @insurer IS NULL OR @insurer = N''
        THROW 50400, N'insurer|Enter the insurer.', 1;
    IF @coverage_amount < 0
        THROW 50400, N'coverageAmount|Coverage cannot be negative.', 1;
    IF @life_cover_amount < 0
        THROW 50400, N'lifeCoverAmount|Life cover cannot be negative.', 1;
    IF @annual_payment < 0
        THROW 50400, N'annualPayment|Annual payment cannot be negative.', 1;
    IF @end_date < @start_date
        THROW 50400, N'endDate|The end date cannot be before the start date.', 1;
    IF @status NOT IN (N'availed', N'not_availed')
        THROW 50400, N'status|Status is availed or not_availed.', 1;
    IF @document_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @document_file_id))
        THROW 50400, N'documentFileId|The file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a health benefit.', 1;
        DECLARE @old_rv BINARY(8), @old_emp BIGINT;
        SELECT @old_rv = h.row_version, @old_emp = h.employee_id
        FROM [ben].[health_benefit] h
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = h.employee_id
        WHERE h.id = @id AND h.company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Health benefit not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this health benefit. Reload it and try again', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [ben].[health_benefit] (company_id, employee_id, insurer, policy_no, coverage_amount, life_cover_amount,
                                           annual_payment, start_date, end_date, status, remarks, document_file_id, created_by)
            VALUES (@company_id, @employee_id, @insurer, @policy_no, @coverage_amount, @life_cover_amount, @annual_payment,
                    @start_date, @end_date, @status, @remarks, @document_file_id, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.health_benefit', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [ben].[health_benefit]
            SET employee_id = @employee_id, insurer = @insurer, policy_no = @policy_no, coverage_amount = @coverage_amount,
                life_cover_amount = @life_cover_amount, annual_payment = @annual_payment, start_date = @start_date,
                end_date = @end_date, status = @status, remarks = @remarks, document_file_id = @document_file_id,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this health benefit. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'ben.health_benefit', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [ben].[usp_health_benefit_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [ben].[usp_health_benefit_delete]
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
    SELECT @rv = h.row_version
    FROM [ben].[health_benefit] h
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = h.employee_id
    WHERE h.id = @id AND h.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Health benefit not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this health benefit. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [ben].[health_benefit] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.health_benefit', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
