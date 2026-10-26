-- Loan & Advance Settings -> Types (Functional Requirements p. 46).
CREATE OR ALTER PROCEDURE [loan].[usp_loan_type_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [loan].[loan_type] t
    WHERE t.company_id = @company_id AND (@pattern IS NULL OR t.name LIKE @pattern) AND (@is_active IS NULL OR t.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT t.id, t.name, t.is_active, t.guarantor_required, t.non_payable, t.min_experience_months,
           t.gap_between_requests_months, t.installments, t.gap_between_installments_months, t.formula_id,
           f.name AS formula_name, t.deduction_pay_item_id, p.name AS deduction_pay_item_name, t.description,
           (SELECT et.id, et.name FROM [loan].[loan_type_employment_type] x
            JOIN [org].[employment_type] et ON et.id = x.employment_type_id
            WHERE x.loan_type_id = t.id ORDER BY et.name FOR JSON PATH) AS employment_types_json,
           t.created_at, t.updated_at, t.row_version
    FROM [loan].[loan_type] t
    LEFT JOIN [pay].[formula] f ON f.id = t.formula_id
    LEFT JOIN [pay].[pay_item] p ON p.id = t.deduction_pay_item_id
    WHERE t.company_id = @company_id AND (@pattern IS NULL OR t.name LIKE @pattern) AND (@is_active IS NULL OR t.is_active = @is_active)
    ORDER BY t.name, t.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [loan].[usp_loan_type_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [loan].[loan_type] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Loan & advance type not found', 1;

    SELECT t.id, t.name, t.is_active, t.guarantor_required, t.non_payable, t.min_experience_months,
           t.gap_between_requests_months, t.installments, t.gap_between_installments_months, t.formula_id,
           f.name AS formula_name, t.deduction_pay_item_id, p.name AS deduction_pay_item_name, t.description,
           (SELECT et.id, et.name FROM [loan].[loan_type_employment_type] x
            JOIN [org].[employment_type] et ON et.id = x.employment_type_id
            WHERE x.loan_type_id = t.id ORDER BY et.name FOR JSON PATH) AS employment_types_json,
           t.created_at, t.updated_at, t.row_version
    FROM [loan].[loan_type] t
    LEFT JOIN [pay].[formula] f ON f.id = t.formula_id
    LEFT JOIN [pay].[pay_item] p ON p.id = t.deduction_pay_item_id
    WHERE t.id = @id;
END
GO

-- Adds (@id NULL) or edits a type. @employment_type_ids: JSON array of the contract types that may
-- apply (at least one). A payable type names the pay item its installments are deducted through.
CREATE OR ALTER PROCEDURE [loan].[usp_loan_type_save]
    @company_id                      BIGINT,
    @actor_user_id                   BIGINT = NULL,
    @id                              BIGINT = NULL,
    @name                            NVARCHAR(200),
    @is_active                       BIT = 1,
    @guarantor_required              BIT = 0,
    @non_payable                     BIT = 0,
    @min_experience_months           INT,
    @gap_between_requests_months     INT = NULL,
    @installments                    INT,
    @gap_between_installments_months INT = NULL,
    @formula_id                      BIGINT = NULL,
    @deduction_pay_item_id           BIGINT = NULL,
    @description                     NVARCHAR(MAX) = NULL,
    @employment_type_ids             NVARCHAR(MAX) = NULL,
    @row_version                     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    IF @name IS NULL
        THROW 50400, N'name|Name is required.', 1;
    IF @min_experience_months IS NULL OR @min_experience_months < 0
        THROW 50400, N'minExperienceMonths|Employee experience in months is required.', 1;
    IF @installments IS NULL OR @installments < 1
        THROW 50400, N'installments|Number of installments must be at least 1.', 1;
    IF @gap_between_requests_months < 0
        THROW 50400, N'gapBetweenRequestsMonths|Gap cannot be negative.', 1;
    IF @gap_between_installments_months < 0
        THROW 50400, N'gapBetweenInstallmentsMonths|Gap cannot be negative.', 1;
    IF @formula_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[formula] WHERE id = @formula_id AND company_id = @company_id)
        THROW 50400, N'formulaId|Formula not found.', 1;
    IF ISNULL(@non_payable, 0) = 0 AND @deduction_pay_item_id IS NULL
        THROW 50400, N'deductionPayItemId|Choose the deduction pay item, or tick Non-Payable.', 1;
    IF @deduction_pay_item_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @deduction_pay_item_id AND company_id = @company_id)
        THROW 50400, N'deductionPayItemId|Pay item not found.', 1;
    IF ISJSON(ISNULL(@employment_type_ids, N'[]')) = 0 OR NOT EXISTS (SELECT 1 FROM OPENJSON(ISNULL(@employment_type_ids, N'[]')))
        THROW 50400, N'employmentTypeIds|Choose at least one employment contract type.', 1;
    IF EXISTS (SELECT 1 FROM OPENJSON(@employment_type_ids) j
               WHERE NOT EXISTS (SELECT 1 FROM [org].[employment_type] et WHERE et.id = TRY_CAST(j.value AS BIGINT) AND et.company_id = @company_id))
        THROW 50400, N'employmentTypeIds|An employment contract type was not found.', 1;
    IF EXISTS (SELECT 1 FROM [loan].[loan_type] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|LOAN_TYPE_DUPLICATE|A loan & advance type with this name already exists.', 1;
    IF ISNULL(@non_payable, 0) = 1
        SET @deduction_pay_item_id = NULL;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [loan].[loan_type] (company_id, name, is_active, guarantor_required, non_payable, min_experience_months,
                                       gap_between_requests_months, installments, gap_between_installments_months, formula_id,
                                       deduction_pay_item_id, description, created_by)
            VALUES (@company_id, @name, ISNULL(@is_active, 1), ISNULL(@guarantor_required, 0), ISNULL(@non_payable, 0),
                    @min_experience_months, @gap_between_requests_months, @installments, @gap_between_installments_months,
                    @formula_id, @deduction_pay_item_id, NULLIF(LTRIM(RTRIM(@description)), N''), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'loan.loan_type', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            IF @row_version IS NULL
                THROW 50400, N'rowVersion is required to edit a loan & advance type', 1;
            DECLARE @rv BINARY(8) = (SELECT row_version FROM [loan].[loan_type] WHERE id = @id AND company_id = @company_id);
            IF @rv IS NULL
                THROW 50404, N'Loan & advance type not found', 1;
            UPDATE [loan].[loan_type]
            SET name = @name, is_active = ISNULL(@is_active, 1), guarantor_required = ISNULL(@guarantor_required, 0),
                non_payable = ISNULL(@non_payable, 0), min_experience_months = @min_experience_months,
                gap_between_requests_months = @gap_between_requests_months, installments = @installments,
                gap_between_installments_months = @gap_between_installments_months, formula_id = @formula_id,
                deduction_pay_item_id = @deduction_pay_item_id, description = NULLIF(LTRIM(RTRIM(@description)), N''),
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this loan & advance type. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'loan.loan_type', @id, N'update', @actor_user_id, @now);
        END

        DELETE [loan].[loan_type_employment_type] WHERE loan_type_id = @id;
        INSERT [loan].[loan_type_employment_type] (loan_type_id, employment_type_id, created_by)
        SELECT DISTINCT @id, TRY_CAST(j.value AS BIGINT), @actor_user_id FROM OPENJSON(@employment_type_ids) j;
    COMMIT;

    EXEC [loan].[usp_loan_type_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [loan].[usp_loan_type_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [loan].[loan_type] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Loan & advance type not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this loan & advance type. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [req].[req_loan] WHERE loan_type_id = @id) OR EXISTS (SELECT 1 FROM [loan].[loan] WHERE loan_type_id = @id)
        THROW 50409, N'This type is used by loan requests. Make it inactive instead.', 1;

    BEGIN TRAN;
        DELETE [loan].[loan_type_employment_type] WHERE loan_type_id = @id;
        DELETE [loan].[loan_type] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'loan.loan_type', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Loan & Advance Settings -> Categories (Functional Requirements p. 47).
CREATE OR ALTER PROCEDURE [loan].[usp_loan_category_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [loan].[loan_category]
    WHERE company_id = @company_id AND (@pattern IS NULL OR name LIKE @pattern) AND (@is_active IS NULL OR is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT id, name, is_active, description, created_at, updated_at, row_version
    FROM [loan].[loan_category]
    WHERE company_id = @company_id AND (@pattern IS NULL OR name LIKE @pattern) AND (@is_active IS NULL OR is_active = @is_active)
    ORDER BY name, id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [loan].[usp_loan_category_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [loan].[loan_category] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Loan & advance category not found', 1;
    SELECT id, name, is_active, description, created_at, updated_at, row_version
    FROM [loan].[loan_category] WHERE id = @id;
END
GO

CREATE OR ALTER PROCEDURE [loan].[usp_loan_category_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @is_active     BIT = 1,
    @description   NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    IF @name IS NULL
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [loan].[loan_category] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|LOAN_CATEGORY_DUPLICATE|A category with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [loan].[loan_category] (company_id, name, is_active, description, created_by)
            VALUES (@company_id, @name, ISNULL(@is_active, 1), NULLIF(LTRIM(RTRIM(@description)), N''), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'loan.loan_category', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            IF @row_version IS NULL
                THROW 50400, N'rowVersion is required to edit a category', 1;
            IF NOT EXISTS (SELECT 1 FROM [loan].[loan_category] WHERE id = @id AND company_id = @company_id)
                THROW 50404, N'Loan & advance category not found', 1;
            UPDATE [loan].[loan_category]
            SET name = @name, is_active = ISNULL(@is_active, 1), description = NULLIF(LTRIM(RTRIM(@description)), N''),
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this category. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'loan.loan_category', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [loan].[usp_loan_category_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [loan].[usp_loan_category_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [loan].[loan_category] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Loan & advance category not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this category. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [req].[req_loan] WHERE loan_category_id = @id) OR EXISTS (SELECT 1 FROM [loan].[loan] WHERE loan_category_id = @id)
        THROW 50409, N'This category is used by loan requests. Make it inactive instead.', 1;

    BEGIN TRAN;
        DELETE [loan].[loan_category] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'loan.loan_category', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
