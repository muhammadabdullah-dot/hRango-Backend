-- Payroll Settings -> Pay Components: formulas, pay items and rules. Expressions are checked by the
-- service (app/services/payroll_expression.py) before these procedures are called.

-- Adds the pay items the run works out itself (salary, overtime, absent / leave / short / penalty
-- deductions, loan installments, leave encashment, tax) and their formulas, when a company does not
-- have them yet. Never changes items that exist: the company may edit their formulas and labels.
CREATE OR ALTER PROCEDURE [pay].[usp_pay_item_system_ensure]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (SELECT COUNT(*) FROM [pay].[pay_item] WHERE company_id = @company_id AND system_code IS NOT NULL) >= 9
        RETURN;

    DECLARE @sys TABLE (system_code NVARCHAR(30), name NVARCHAR(200), label NVARCHAR(200), item_type NVARCHAR(30),
                        calculation_type NVARCHAR(30), is_taxable BIT, formula_name NVARCHAR(200), expression NVARCHAR(MAX), sort INT);
    INSERT @sys VALUES
        (N'salary', N'Salary', N'Gross Salary', N'earning', N'formula', 1, N'Salary formula',
         N'{gross_salary} * {employed_days} / {month_days}', 1),
        (N'overtime', N'Overtime', N'Overtime', N'earning', N'formula', 1, N'Overtime formula',
         N'{gross_salary} / {applicable_days} / {day_minutes} * {overtime_minutes}', 2),
        (N'absent_deduction', N'Absent Deduction', N'Absence Deductions', N'deduction', N'formula', 1, N'Absent deduction formula',
         N'{gross_salary} / {applicable_days} * ({absent_days} + {half_days} * 0.5)', 3),
        (N'leave_deduction', N'Leave Deduction', N'Leave Deductions', N'deduction', N'formula', 1, N'Leave deduction formula',
         N'{gross_salary} / {applicable_days} * {unpaid_leave_days}', 4),
        (N'short_deduction', N'Short Deduction', N'Short Deductions', N'deduction', N'formula', 1, N'Short deduction formula',
         N'{gross_salary} / {applicable_days} / {day_minutes} * {short_minutes}', 5),
        (N'penalty_deduction', N'Penalty Deduction', N'Penalty Deductions', N'deduction', N'formula', 1, N'Penalty deduction formula',
         N'{gross_salary} / {applicable_days} * {penalty_days}', 6),
        (N'loan_deduction', N'Loan Deduction', N'Loan / Advance Deduction', N'deduction', N'fixed', 0, NULL, NULL, 7),
        (N'leave_encashment', N'Leave Encashment', N'Leave Encashment', N'earning', N'fixed', 1, NULL, NULL, 8),
        (N'tax', N'Tax', N'Income Tax', N'deduction', N'fixed', 0, NULL, NULL, 9);

    BEGIN TRAN;
        INSERT [pay].[formula] (company_id, name, expression, is_custom, description)
        SELECT @company_id, s.formula_name, s.expression, 0, N'Added by the system for the ' + s.label + N' pay item.'
        FROM @sys s
        WHERE s.formula_name IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM [pay].[pay_item] p WHERE p.company_id = @company_id AND p.system_code = s.system_code)
          AND NOT EXISTS (SELECT 1 FROM [pay].[formula] f WHERE f.company_id = @company_id AND f.name = s.formula_name);

        INSERT [pay].[pay_item] (company_id, name, label, item_type, calculation_type, tax_distribution,
                                 employee_formula_id, is_taxable, system_code, description)
        SELECT @company_id,
               CASE WHEN EXISTS (SELECT 1 FROM [pay].[pay_item] x WHERE x.company_id = @company_id AND x.name = s.name)
                    THEN s.name + N' (system)' ELSE s.name END,
               s.label, s.item_type, s.calculation_type, N'current_month',
               (SELECT f.id FROM [pay].[formula] f WHERE f.company_id = @company_id AND f.name = s.formula_name),
               s.is_taxable, s.system_code,
               CASE s.system_code WHEN N'tax' THEN N'Worked out by the run from the payroll''s tax structure.'
                                  WHEN N'loan_deduction' THEN N'Loan installments due in the month.'
                                  WHEN N'leave_encashment' THEN N'Leave encashments paid through payroll.'
                                  ELSE NULL END
        FROM @sys s
        WHERE NOT EXISTS (SELECT 1 FROM [pay].[pay_item] p WHERE p.company_id = @company_id AND p.system_code = s.system_code)
        ORDER BY s.sort;
    COMMIT;
END
GO

-- Everything the expression checker and the run need: result set 1 pay items, 2 formulas, 3 rules.
CREATE OR ALTER PROCEDURE [pay].[usp_pay_component_all]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.id, p.name, p.item_type, p.calculation_type, p.system_code, p.eligibility_expression,
           p.employee_formula_id, p.employer_formula_id
    FROM [pay].[pay_item] p WHERE p.company_id = @company_id;
    SELECT f.id, f.name, f.expression FROM [pay].[formula] f WHERE f.company_id = @company_id;
    SELECT r.id, r.name, r.expression, r.account_type_id FROM [pay].[pay_rule] r WHERE r.company_id = @company_id;
END
GO

----------------------------------------------------------------------------------------------- formulas

CREATE OR ALTER PROCEDURE [pay].[usp_formula_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[formula] f
    WHERE f.company_id = @company_id AND (@pattern IS NULL OR f.name LIKE @pattern OR f.expression LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT f.id, f.name, f.expression, f.is_salary_division, f.for_integration, f.is_custom, f.description,
           f.created_at, f.updated_at, f.row_version
    FROM [pay].[formula] f
    WHERE f.company_id = @company_id AND (@pattern IS NULL OR f.name LIKE @pattern OR f.expression LIKE @pattern)
    ORDER BY f.name, f.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_formula_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[formula] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Formula not found', 1;
    SELECT f.id, f.name, f.expression, f.is_salary_division, f.for_integration, f.is_custom, f.description,
           f.created_at, f.updated_at, f.row_version
    FROM [pay].[formula] f WHERE f.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_formula_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT = NULL,
    @id                 BIGINT = NULL,
    @name               NVARCHAR(200),
    @expression         NVARCHAR(MAX),
    @is_salary_division BIT = 0,
    @for_integration    BIT = 0,
    @description        NVARCHAR(MAX) = NULL,
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[formula] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|FORMULA_DUPLICATE|A formula with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[formula] (company_id, name, expression, is_salary_division, for_integration, is_custom, description, created_by)
            VALUES (@company_id, @name, @expression, @is_salary_division, @for_integration, 1, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.formula', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @old NVARCHAR(MAX) = (SELECT expression FROM [pay].[formula] WHERE id = @id AND company_id = @company_id);
            UPDATE [pay].[formula]
            SET name = @name, expression = @expression, is_salary_division = @is_salary_division,
                for_integration = @for_integration, description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[formula] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Formula not found', 1;
                THROW 50409, N'Someone else changed this formula. Reload it and try again', 1;
            END
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.formula', @id, N'expression', @old, @expression, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_formula_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_formula_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @custom BIT;
    SELECT @rv = row_version, @custom = is_custom FROM [pay].[formula] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Formula not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this formula. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE employee_formula_id = @id OR employer_formula_id = @id)
       OR EXISTS (SELECT 1 FROM [pay].[reward_benefit] WHERE formula_id = @id)
        THROW 50409, N'Pay items or benefits use this formula. It cannot be deleted', 1;
    BEGIN TRAN;
        -- Anything else still pointing here (loan types) stops the delete with error 547.
        DELETE [pay].[formula] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.formula', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

----------------------------------------------------------------------------------------------- pay items

CREATE OR ALTER PROCEDURE [pay].[usp_pay_item_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @item_type  NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[pay_item] p
    WHERE p.company_id = @company_id AND (@item_type IS NULL OR p.item_type = @item_type)
      AND (@pattern IS NULL OR p.name LIKE @pattern OR p.label LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT p.id, p.name, p.label, p.item_type, p.calculation_type, p.tax_distribution,
           p.employee_formula_id, ef.name AS employee_formula_name, ef.expression,
           p.employer_formula_id, rf.name AS employer_formula_name, rf.expression AS employer_expression,
           p.is_taxable, p.is_display_only, p.is_benefit, p.is_advance_payment, p.eligibility_expression,
           p.system_code, p.description, p.created_at, p.updated_at, p.row_version
    FROM [pay].[pay_item] p
    LEFT JOIN [pay].[formula] ef ON ef.id = p.employee_formula_id
    LEFT JOIN [pay].[formula] rf ON rf.id = p.employer_formula_id
    WHERE p.company_id = @company_id AND (@item_type IS NULL OR p.item_type = @item_type)
      AND (@pattern IS NULL OR p.name LIKE @pattern OR p.label LIKE @pattern)
    ORDER BY CASE WHEN p.system_code IS NULL THEN 1 ELSE 0 END, p.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_pay_item_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Pay item not found', 1;
    SELECT p.id, p.name, p.label, p.item_type, p.calculation_type, p.tax_distribution,
           p.employee_formula_id, ef.name AS employee_formula_name, ef.expression,
           p.employer_formula_id, rf.name AS employer_formula_name, rf.expression AS employer_expression,
           p.is_taxable, p.is_display_only, p.is_benefit, p.is_advance_payment, p.eligibility_expression,
           p.system_code, p.description, p.created_at, p.updated_at, p.row_version
    FROM [pay].[pay_item] p
    LEFT JOIN [pay].[formula] ef ON ef.id = p.employee_formula_id
    LEFT JOIN [pay].[formula] rf ON rf.id = p.employer_formula_id
    WHERE p.id = @id;
END
GO

-- A system pay item keeps its type and calculation type; its name, label, formulas and flags may change.
CREATE OR ALTER PROCEDURE [pay].[usp_pay_item_save]
    @company_id             BIGINT,
    @actor_user_id          BIGINT = NULL,
    @id                     BIGINT = NULL,
    @name                   NVARCHAR(200),
    @label                  NVARCHAR(200) = NULL,
    @item_type              NVARCHAR(30),
    @calculation_type       NVARCHAR(30),
    @tax_distribution       NVARCHAR(30),
    @employee_formula_id    BIGINT = NULL,
    @employer_formula_id    BIGINT = NULL,
    @is_taxable             BIT = 0,
    @is_display_only        BIT = 0,
    @is_benefit             BIT = 0,
    @is_advance_payment     BIT = 0,
    @eligibility_expression NVARCHAR(MAX) = NULL,
    @description            NVARCHAR(MAX) = NULL,
    @row_version            BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|PAY_ITEM_DUPLICATE|A pay item with this name already exists.', 1;
    IF @employee_formula_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[formula] WHERE id = @employee_formula_id AND company_id = @company_id)
        THROW 50400, N'employeeFormulaId|Formula not found.', 1;
    IF @employer_formula_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[formula] WHERE id = @employer_formula_id AND company_id = @company_id)
        THROW 50400, N'employerFormulaId|Formula not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[pay_item] (company_id, name, label, item_type, calculation_type, tax_distribution, employee_formula_id,
                                     employer_formula_id, is_taxable, is_display_only, is_benefit, is_advance_payment,
                                     eligibility_expression, description, created_by)
            VALUES (@company_id, @name, @label, @item_type, @calculation_type, @tax_distribution, @employee_formula_id,
                    @employer_formula_id, @is_taxable, @is_display_only, @is_benefit, @is_advance_payment,
                    NULLIF(LTRIM(RTRIM(@eligibility_expression)), N''), @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.pay_item', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @sys NVARCHAR(30), @old_type NVARCHAR(30), @old_calc NVARCHAR(30), @rv BINARY(8);
            SELECT @sys = system_code, @old_type = item_type, @old_calc = calculation_type, @rv = row_version
            FROM [pay].[pay_item] WHERE id = @id AND company_id = @company_id;
            IF @rv IS NULL
                THROW 50404, N'Pay item not found', 1;
            IF @rv <> @row_version
                THROW 50409, N'Someone else changed this pay item. Reload it and try again', 1;
            IF @sys IS NOT NULL AND (@item_type <> @old_type OR @calculation_type <> @old_calc)
                THROW 50400, N'itemType|The system works this pay item out; its type and calculation cannot change.', 1;
            UPDATE [pay].[pay_item]
            SET name = @name, label = @label, item_type = @item_type, calculation_type = @calculation_type,
                tax_distribution = @tax_distribution, employee_formula_id = @employee_formula_id,
                employer_formula_id = @employer_formula_id, is_taxable = @is_taxable, is_display_only = @is_display_only,
                is_benefit = @is_benefit, is_advance_payment = @is_advance_payment,
                eligibility_expression = NULLIF(LTRIM(RTRIM(@eligibility_expression)), N''), description = @description,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this pay item. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.pay_item', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_pay_item_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_pay_item_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @sys NVARCHAR(30);
    SELECT @rv = row_version, @sys = system_code FROM [pay].[pay_item] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Pay item not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this pay item. Reload it and try again', 1;
    IF @sys IS NOT NULL
        THROW 50409, N'The system works this pay item out. It cannot be deleted', 1;
    IF EXISTS (SELECT 1 FROM [pay].[payslip_line] WHERE pay_item_id = @id)
       OR EXISTS (SELECT 1 FROM [pay].[payroll_pay_item] WHERE pay_item_id = @id)
       OR EXISTS (SELECT 1 FROM [pay].[opening_balance] WHERE pay_item_id = @id)
       OR EXISTS (SELECT 1 FROM [pay].[reward_benefit] WHERE pay_item_id = @id)
        THROW 50409, N'Payrolls, payslips, balances or benefits use this pay item. It cannot be deleted', 1;
    BEGIN TRAN;
        -- Employee pay items, loan types and promotion requests still pointing here stop the delete (547).
        DELETE [pay].[pay_item] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.pay_item', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

----------------------------------------------------------------------------------------------- rules

CREATE OR ALTER PROCEDURE [pay].[usp_pay_rule_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [pay].[pay_rule] r
    WHERE r.company_id = @company_id AND (@pattern IS NULL OR r.name LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.id, r.name, r.expression, r.account_type_id, a.name AS account_type_name, a.category AS account_category,
           r.description, r.created_at, r.updated_at, r.row_version
    FROM [pay].[pay_rule] r
    JOIN [pay].[account_type] a ON a.id = r.account_type_id
    WHERE r.company_id = @company_id AND (@pattern IS NULL OR r.name LIKE @pattern)
    ORDER BY r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_pay_rule_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[pay_rule] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Rule not found', 1;
    SELECT r.id, r.name, r.expression, r.account_type_id, a.name AS account_type_name, a.category AS account_category,
           r.description, r.created_at, r.updated_at, r.row_version
    FROM [pay].[pay_rule] r
    JOIN [pay].[account_type] a ON a.id = r.account_type_id
    WHERE r.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_pay_rule_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @expression      NVARCHAR(MAX),
    @account_type_id BIGINT,
    @description     NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[account_type] WHERE id = @account_type_id AND company_id = @company_id)
        THROW 50400, N'accountTypeId|Account type not found.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[pay_rule] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|PAY_RULE_DUPLICATE|A rule with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[pay_rule] (company_id, name, expression, account_type_id, description, created_by)
            VALUES (@company_id, @name, @expression, @account_type_id, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.pay_rule', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [pay].[pay_rule]
            SET name = @name, expression = @expression, account_type_id = @account_type_id, description = @description,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [pay].[pay_rule] WHERE id = @id AND company_id = @company_id)
                    THROW 50404, N'Rule not found', 1;
                THROW 50409, N'Someone else changed this rule. Reload it and try again', 1;
            END
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.pay_rule', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_pay_rule_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_pay_rule_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pay].[pay_rule] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Rule not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this rule. Reload it and try again', 1;
    BEGIN TRAN;
        -- Postings the rule made stay in the employee accounts; they lose the link to the rule.
        UPDATE [pay].[employee_account_entry] SET pay_rule_id = NULL WHERE pay_rule_id = @id;
        DELETE [pay].[pay_rule] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.pay_rule', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
