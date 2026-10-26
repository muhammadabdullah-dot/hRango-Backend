-- Payroll Settings lists: account types, rewards (benefits, incentives) and disbursement banks.

----------------------------------------------------------------------------------------------- account types

CREATE OR ALTER PROCEDURE [pay].[usp_account_type_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @category   NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[account_type] a
    WHERE a.company_id = @company_id AND (@category IS NULL OR a.category = @category)
      AND (@pattern IS NULL OR a.name LIKE @pattern OR a.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT a.id, a.code, a.name, a.category, a.ref_id,
           CASE a.category WHEN N'benefit' THEN b.name WHEN N'leave_quota' THEN lt.title WHEN N'custom_pay_item' THEN pi.name END AS ref_name,
           a.created_at, a.updated_at, a.row_version
    FROM [pay].[account_type] a
    LEFT JOIN [pay].[reward_benefit] b ON a.category = N'benefit' AND b.id = a.ref_id
    LEFT JOIN [lv].[leave_type] lt ON a.category = N'leave_quota' AND lt.id = a.ref_id
    LEFT JOIN [pay].[pay_item] pi ON a.category = N'custom_pay_item' AND pi.id = a.ref_id
    WHERE a.company_id = @company_id AND (@category IS NULL OR a.category = @category)
      AND (@pattern IS NULL OR a.name LIKE @pattern OR a.code LIKE @pattern)
    ORDER BY a.name, a.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_account_type_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[account_type] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Account type not found', 1;
    SELECT a.id, a.code, a.name, a.category, a.ref_id,
           CASE a.category WHEN N'benefit' THEN b.name WHEN N'leave_quota' THEN lt.title WHEN N'custom_pay_item' THEN pi.name END AS ref_name,
           a.created_at, a.updated_at, a.row_version
    FROM [pay].[account_type] a
    LEFT JOIN [pay].[reward_benefit] b ON a.category = N'benefit' AND b.id = a.ref_id
    LEFT JOIN [lv].[leave_type] lt ON a.category = N'leave_quota' AND lt.id = a.ref_id
    LEFT JOIN [pay].[pay_item] pi ON a.category = N'custom_pay_item' AND pi.id = a.ref_id
    WHERE a.id = @id;
END
GO

-- @ref_id is the benefit, leave type or pay item the category asks for.
CREATE OR ALTER PROCEDURE [pay].[usp_account_type_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @category      NVARCHAR(30),
    @ref_id        BIGINT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF @ref_id IS NOT NULL AND NOT (
           (@category = N'benefit' AND EXISTS (SELECT 1 FROM [pay].[reward_benefit] WHERE id = @ref_id AND company_id = @company_id))
        OR (@category = N'leave_quota' AND EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE id = @ref_id AND company_id = @company_id))
        OR (@category = N'custom_pay_item' AND EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @ref_id AND company_id = @company_id)))
        THROW 50400, N'refId|Not found for this account category.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[account_type] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|ACCOUNT_TYPE_DUPLICATE|An account type with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            EXEC [pay].[usp_sequence_next] @company_id, N'ACT-', 4, @code OUTPUT;
            INSERT [pay].[account_type] (company_id, code, category, ref_id, name, created_by)
            VALUES (@company_id, @code, @category, @ref_id, @name, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.account_type', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [pay].[account_type]
            SET name = @name, category = @category, ref_id = @ref_id, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[account_type] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Account type not found', 1;
                THROW 50409, N'Someone else changed this account type. Reload it and try again', 1;
            END
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.account_type', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_account_type_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_account_type_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pay].[account_type] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Account type not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this account type. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [pay].[pay_rule] WHERE account_type_id = @id)
       OR EXISTS (SELECT 1 FROM [pay].[employee_account_entry] WHERE account_type_id = @id)
        THROW 50409, N'Rules or employee accounts use this account type. It cannot be deleted', 1;
    BEGIN TRAN;
        DELETE [pay].[account_type] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.account_type', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

----------------------------------------------------------------------------------------------- benefits

CREATE OR ALTER PROCEDURE [pay].[usp_reward_benefit_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[reward_benefit] b
    WHERE b.company_id = @company_id AND (@pattern IS NULL OR b.name LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT b.id, b.name, b.benefit_type, b.pay_item_id, pi.name AS pay_item_name, b.formula_id, f.name AS formula_name,
           b.is_group, b.is_accumulative, b.description,
           (SELECT COUNT(*) FROM [pay].[reward_benefit_member] m WHERE m.reward_benefit_id = b.id) AS member_count,
           b.created_at, b.updated_at, b.row_version
    FROM [pay].[reward_benefit] b
    JOIN [pay].[pay_item] pi ON pi.id = b.pay_item_id
    LEFT JOIN [pay].[formula] f ON f.id = b.formula_id
    WHERE b.company_id = @company_id AND (@pattern IS NULL OR b.name LIKE @pattern)
    ORDER BY b.name, b.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Result set 1: the benefit. 2: members. 3: additional information fields.
CREATE OR ALTER PROCEDURE [pay].[usp_reward_benefit_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[reward_benefit] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Benefit not found', 1;
    SELECT b.id, b.name, b.benefit_type, b.pay_item_id, pi.name AS pay_item_name, b.formula_id, f.name AS formula_name,
           b.is_group, b.is_accumulative, b.description,
           (SELECT COUNT(*) FROM [pay].[reward_benefit_member] m WHERE m.reward_benefit_id = b.id) AS member_count,
           b.created_at, b.updated_at, b.row_version
    FROM [pay].[reward_benefit] b
    JOIN [pay].[pay_item] pi ON pi.id = b.pay_item_id
    LEFT JOIN [pay].[formula] f ON f.id = b.formula_id
    WHERE b.id = @id;

    SELECT m.id, m.employee_id, NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N'') AS employee_name, m.employee_group_id, g.name AS employee_group_name
    FROM [pay].[reward_benefit_member] m
    LEFT JOIN [hr].[employee] e ON e.id = m.employee_id
    LEFT JOIN [org].[employee_group] g ON g.id = m.employee_group_id
    WHERE m.reward_benefit_id = @id ORDER BY m.id;

    SELECT id, name, field_type, is_required, min_value, max_value, min_length, max_length, field_value
    FROM [pay].[reward_benefit_field] WHERE reward_benefit_id = @id ORDER BY id;
END
GO

-- @members: JSON [{"employeeId"} | {"employeeGroupId"}]. @fields: JSON [{"name","fieldType","isRequired",
-- "minValue","maxValue","minLength","maxLength","fieldValue"}]. Both replace what is there.
CREATE OR ALTER PROCEDURE [pay].[usp_reward_benefit_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @benefit_type    NVARCHAR(30),
    @pay_item_id     BIGINT,
    @formula_id      BIGINT = NULL,
    @is_group        BIT = 0,
    @is_accumulative BIT = 0,
    @description     NVARCHAR(MAX) = NULL,
    @members         NVARCHAR(MAX) = N'[]',
    @fields          NVARCHAR(MAX) = N'[]',
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @pay_item_id AND company_id = @company_id)
        THROW 50400, N'payItemId|Pay item not found.', 1;
    IF @formula_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[formula] WHERE id = @formula_id AND company_id = @company_id)
        THROW 50400, N'formulaId|Formula not found.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[reward_benefit] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|BENEFIT_DUPLICATE|A benefit with this name already exists.', 1;

    DECLARE @m TABLE (employee_id BIGINT, employee_group_id BIGINT);
    INSERT @m SELECT employee_id, employee_group_id
    FROM OPENJSON(ISNULL(@members, N'[]')) WITH (employee_id BIGINT '$.employeeId', employee_group_id BIGINT '$.employeeGroupId');
    IF EXISTS (SELECT 1 FROM @m x WHERE x.employee_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = x.employee_id AND e.company_id = @company_id))
        THROW 50400, N'members|An employee in the members was not found.', 1;
    IF EXISTS (SELECT 1 FROM @m x WHERE x.employee_group_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [org].[employee_group] g WHERE g.id = x.employee_group_id AND g.company_id = @company_id))
        THROW 50400, N'members|An employee group in the members was not found.', 1;
    IF @is_group = 1 AND NOT EXISTS (SELECT 1 FROM @m)
        THROW 50400, N'members|Pick the members of the group.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[reward_benefit] (company_id, name, benefit_type, pay_item_id, formula_id, is_group, is_accumulative, description, created_by)
            VALUES (@company_id, @name, @benefit_type, @pay_item_id, @formula_id, @is_group, @is_accumulative, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.reward_benefit', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [pay].[reward_benefit]
            SET name = @name, benefit_type = @benefit_type, pay_item_id = @pay_item_id, formula_id = @formula_id,
                is_group = @is_group, is_accumulative = @is_accumulative, description = @description,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[reward_benefit] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Benefit not found', 1;
                THROW 50409, N'Someone else changed this benefit. Reload it and try again', 1;
            END
            DELETE [pay].[reward_benefit_member] WHERE reward_benefit_id = @id;
            DELETE [pay].[reward_benefit_field] WHERE reward_benefit_id = @id;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.reward_benefit', @id, N'update', @actor_user_id, @now);
        END

        INSERT [pay].[reward_benefit_member] (reward_benefit_id, employee_id, employee_group_id, created_by)
        SELECT DISTINCT @id, employee_id, employee_group_id, @actor_user_id FROM @m
        WHERE employee_id IS NOT NULL OR employee_group_id IS NOT NULL;

        INSERT [pay].[reward_benefit_field] (reward_benefit_id, name, field_type, is_required, min_value, max_value,
                                             min_length, max_length, field_value, created_by)
        SELECT @id, j.name, j.field_type, ISNULL(j.is_required, 0), j.min_value, j.max_value, j.min_length, j.max_length,
               j.field_value, @actor_user_id
        FROM OPENJSON(ISNULL(@fields, N'[]')) WITH (name NVARCHAR(200) '$.name', field_type NVARCHAR(30) '$.fieldType',
             is_required BIT '$.isRequired', min_value DECIMAL(18,4) '$.minValue', max_value DECIMAL(18,4) '$.maxValue',
             min_length INT '$.minLength', max_length INT '$.maxLength', field_value NVARCHAR(MAX) '$.fieldValue') j;
    COMMIT;
    EXEC [pay].[usp_reward_benefit_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_reward_benefit_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pay].[reward_benefit] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Benefit not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this benefit. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [pay].[account_type] WHERE category = N'benefit' AND ref_id = @id)
        THROW 50409, N'An account type uses this benefit. It cannot be deleted', 1;
    BEGIN TRAN;
        DELETE [pay].[reward_benefit_member] WHERE reward_benefit_id = @id;
        DELETE [pay].[reward_benefit_field] WHERE reward_benefit_id = @id;
        DELETE [pay].[reward_benefit] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.reward_benefit', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

----------------------------------------------------------------------------------------------- incentives

CREATE OR ALTER PROCEDURE [pay].[usp_sales_incentive_list]
    @company_id BIGINT,
    @branch_id  BIGINT = NULL,
    @month      DATE = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS total FROM [pay].[sales_incentive] s
    WHERE s.company_id = @company_id AND (@branch_id IS NULL OR s.branch_id = @branch_id)
      AND (@month IS NULL OR s.applicable_month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1))
    OPTION (RECOMPILE);

    SELECT s.id, s.branch_id, b.name AS branch_name, s.applicable_month, s.incentive_type, s.target_amount,
           s.value_type, s.reward_value, s.description, s.created_at, s.updated_at, s.row_version
    FROM [pay].[sales_incentive] s
    JOIN [org].[branch] b ON b.id = s.branch_id
    WHERE s.company_id = @company_id AND (@branch_id IS NULL OR s.branch_id = @branch_id)
      AND (@month IS NULL OR s.applicable_month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1))
    ORDER BY s.applicable_month DESC, s.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_sales_incentive_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[sales_incentive] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Incentive not found', 1;
    SELECT s.id, s.branch_id, b.name AS branch_name, s.applicable_month, s.incentive_type, s.target_amount,
           s.value_type, s.reward_value, s.description, s.created_at, s.updated_at, s.row_version
    FROM [pay].[sales_incentive] s
    JOIN [org].[branch] b ON b.id = s.branch_id
    WHERE s.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_sales_incentive_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT = NULL,
    @id               BIGINT = NULL,
    @branch_id        BIGINT,
    @applicable_month DATE,
    @incentive_type   NVARCHAR(30),
    @target_amount    DECIMAL(18,2),
    @value_type       NVARCHAR(30),
    @reward_value     DECIMAL(18,2),
    @description      NVARCHAR(MAX) = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Branch not found.', 1;
    SET @applicable_month = DATEFROMPARTS(YEAR(@applicable_month), MONTH(@applicable_month), 1);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[sales_incentive] (company_id, branch_id, applicable_month, incentive_type, target_amount, value_type, reward_value, description, created_by)
            VALUES (@company_id, @branch_id, @applicable_month, @incentive_type, @target_amount, @value_type, @reward_value, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [pay].[sales_incentive]
            SET branch_id = @branch_id, applicable_month = @applicable_month, incentive_type = @incentive_type,
                target_amount = @target_amount, value_type = @value_type, reward_value = @reward_value,
                description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[sales_incentive] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Incentive not found', 1;
                THROW 50409, N'Someone else changed this incentive. Reload it and try again', 1;
            END
        END
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.sales_incentive', @id, CASE WHEN @row_version IS NULL THEN N'create' ELSE N'update' END, @actor_user_id, @now);
    COMMIT;
    EXEC [pay].[usp_sales_incentive_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_sales_incentive_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pay].[sales_incentive] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Incentive not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this incentive. Reload it and try again', 1;
    BEGIN TRAN;
        DELETE [pay].[sales_incentive] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.sales_incentive', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

----------------------------------------------------------------------------------------------- disbursement banks

CREATE OR ALTER PROCEDURE [pay].[usp_disbursement_bank_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[disbursement_bank] d
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.bank_name LIKE @pattern OR d.branch_name LIKE @pattern OR d.branch_code LIKE @pattern OR d.account_holder LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT d.id, d.account_holder, d.account_number, d.bank_name, d.branch_name, d.branch_code, d.branch_location,
           d.tax_payer_id, d.effective_date, d.description, d.created_at, d.updated_at, d.row_version
    FROM [pay].[disbursement_bank] d
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.bank_name LIKE @pattern OR d.branch_name LIKE @pattern OR d.branch_code LIKE @pattern OR d.account_holder LIKE @pattern)
    ORDER BY d.bank_name, d.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_disbursement_bank_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[disbursement_bank] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Disbursement bank not found', 1;
    SELECT d.id, d.account_holder, d.account_number, d.bank_name, d.branch_name, d.branch_code, d.branch_location,
           d.tax_payer_id, d.effective_date, d.description, d.created_at, d.updated_at, d.row_version
    FROM [pay].[disbursement_bank] d WHERE d.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_disbursement_bank_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @account_holder  NVARCHAR(200),
    @account_number  NVARCHAR(50),
    @bank_name       NVARCHAR(200),
    @branch_name     NVARCHAR(200) = NULL,
    @branch_code     NVARCHAR(30),
    @branch_location NVARCHAR(200),
    @tax_payer_id    NVARCHAR(30),
    @effective_date  DATE = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM [pay].[disbursement_bank] WHERE company_id = @company_id AND account_number = @account_number AND (@id IS NULL OR id <> @id))
        THROW 50409, N'accountNumber|BANK_DUPLICATE|A disbursement bank with this account number already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[disbursement_bank] (company_id, account_holder, account_number, bank_name, branch_name, branch_code,
                                              branch_location, tax_payer_id, effective_date, description, created_by)
            VALUES (@company_id, @account_holder, @account_number, @bank_name, @branch_name, @branch_code,
                    @branch_location, @tax_payer_id, @effective_date, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [pay].[disbursement_bank]
            SET account_holder = @account_holder, account_number = @account_number, bank_name = @bank_name,
                branch_name = @branch_name, branch_code = @branch_code, branch_location = @branch_location,
                tax_payer_id = @tax_payer_id, effective_date = @effective_date, description = @description,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[disbursement_bank] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Disbursement bank not found', 1;
                THROW 50409, N'Someone else changed this disbursement bank. Reload it and try again', 1;
            END
        END
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.disbursement_bank', @id, CASE WHEN @row_version IS NULL THEN N'create' ELSE N'update' END, @actor_user_id, @now);
    COMMIT;
    EXEC [pay].[usp_disbursement_bank_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_disbursement_bank_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pay].[disbursement_bank] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Disbursement bank not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this disbursement bank. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [pay].[payroll] WHERE disbursement_bank_id = @id)
        THROW 50409, N'Payrolls pay through this bank. It cannot be deleted', 1;
    BEGIN TRAN;
        DELETE [pay].[disbursement_bank] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.disbursement_bank', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
