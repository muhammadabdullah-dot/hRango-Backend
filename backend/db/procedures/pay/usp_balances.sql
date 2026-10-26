-- Balances: Opening Balance (amounts added to a pay item in a month's run) and Employee Accounts
-- (Provident Fund, EOBI, medical … ledgers) with the account statement.

-- Opening Balance list: one row per person with the net of their entries.
CREATE OR ALTER PROCEDURE [pay].[usp_opening_balance_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @month           DATE = NULL,
    @net_from        DECIMAL(18,2) = NULL,
    @net_to          DECIMAL(18,2) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    IF @month IS NOT NULL SET @month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1);

    SELECT o.employee_id, SUM(o.amount) AS net_amount, COUNT(*) AS entry_count, MAX(o.balance_month) AS last_month
    INTO #g
    FROM [pay].[opening_balance] o
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = o.employee_id
    JOIN [hr].[employee] e ON e.id = o.employee_id AND e.company_id = @company_id
    WHERE (@employee_id IS NULL OR o.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@month IS NULL OR o.balance_month = @month)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    GROUP BY o.employee_id
    HAVING (@net_from IS NULL OR SUM(o.amount) >= @net_from) AND (@net_to IS NULL OR SUM(o.amount) <= @net_to)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #g;

    SELECT g.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, g.net_amount, g.entry_count, g.last_month
    FROM #g g
    JOIN [hr].[employee] e ON e.id = g.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    ORDER BY e.first_name, e.last_name, e.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- One person's opening balances by month (Balances Opening Balance View). Result set 1: the person.
-- Result set 2: the entries.
CREATE OR ALTER PROCEDURE [pay].[usp_opening_balance_employee]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;
    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, jt.name AS job_title_name, l.name AS location_name, b.name AS branch_name
    FROM [hr].[employee] e
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
    LEFT JOIN [org].[location] l ON l.id = e.location_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    WHERE e.id = @employee_id;

    SELECT o.id, o.employee_id, o.balance_month, o.pay_item_id, pi.name AS pay_item_name, pi.item_type, o.amount, o.is_taxable,
           o.kind, o.description, [pay].[fn_month_locked](o.employee_id, o.balance_month) AS is_locked,
           o.created_at, o.updated_at, o.row_version
    FROM [pay].[opening_balance] o
    JOIN [pay].[pay_item] pi ON pi.id = o.pay_item_id
    WHERE o.employee_id = @employee_id
    ORDER BY o.balance_month DESC, o.id DESC;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_opening_balance_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[opening_balance] o
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = o.employee_id
                   WHERE o.id = @id)
        THROW 50404, N'Opening balance not found', 1;
    SELECT o.id, o.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           o.balance_month, o.pay_item_id, pi.name AS pay_item_name, pi.item_type, o.amount, o.is_taxable, o.kind, o.description,
           [pay].[fn_month_locked](o.employee_id, o.balance_month) AS is_locked, o.created_at, o.updated_at, o.row_version
    FROM [pay].[opening_balance] o
    JOIN [hr].[employee] e ON e.id = o.employee_id
    JOIN [pay].[pay_item] pi ON pi.id = o.pay_item_id
    WHERE o.id = @id;
END
GO

-- Add (kind 'opening') or adjust (kind 'adjustment') an opening balance, or edit one.
CREATE OR ALTER PROCEDURE [pay].[usp_opening_balance_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @balance_month   DATE,
    @pay_item_id     BIGINT,
    @amount          DECIMAL(18,2),
    @is_taxable      BIT = 0,
    @kind            NVARCHAR(30) = N'opening',
    @description     NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @balance_month = DATEFROMPARTS(YEAR(@balance_month), MONTH(@balance_month), 1);
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @pay_item_id AND company_id = @company_id)
        THROW 50400, N'payItemId|Pay item not found.', 1;
    IF [pay].[fn_month_locked](@employee_id, @balance_month) = 1
        THROW 50409, N'balanceMonth|MONTH_LOCKED|That month''s payroll is closed for this person.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[opening_balance] (employee_id, balance_month, pay_item_id, amount, is_taxable, kind, description, created_by)
            VALUES (@employee_id, @balance_month, @pay_item_id, @amount, @is_taxable, @kind, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.opening_balance', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @old_emp BIGINT, @old_month DATE, @rv BINARY(8);
            SELECT @old_emp = o.employee_id, @old_month = o.balance_month, @rv = o.row_version FROM [pay].[opening_balance] o
            JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = o.employee_id
            WHERE o.id = @id;
            IF @rv IS NULL
                THROW 50404, N'Opening balance not found', 1;
            IF @rv <> @row_version
                THROW 50409, N'Someone else changed this opening balance. Reload it and try again', 1;
            IF [pay].[fn_month_locked](@old_emp, @old_month) = 1
                THROW 50409, N'balanceMonth|MONTH_LOCKED|That month''s payroll is closed for this person.', 1;
            UPDATE [pay].[opening_balance]
            SET employee_id = @employee_id, balance_month = @balance_month, pay_item_id = @pay_item_id, amount = @amount,
                is_taxable = @is_taxable, kind = @kind, description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.opening_balance', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_opening_balance_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_opening_balance_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @emp BIGINT, @month DATE, @rv BINARY(8);
    SELECT @emp = o.employee_id, @month = o.balance_month, @rv = o.row_version FROM [pay].[opening_balance] o
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = o.employee_id
    WHERE o.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Opening balance not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this opening balance. Reload it and try again', 1;
    IF [pay].[fn_month_locked](@emp, @month) = 1
        THROW 50409, N'balanceMonth|MONTH_LOCKED|That month''s payroll is closed for this person.', 1;
    BEGIN TRAN;
        DELETE [pay].[opening_balance] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.opening_balance', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Import (and Sample Import): @rows JSON [{"employeeCode","payItem","month","amount","taxable","description"}].
-- Rows that do not resolve are reported (row number from 1) and not added; the rest are added together.
CREATE OR ALTER PROCEDURE [pay].[usp_opening_balance_import]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @rows            NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT CONVERT(INT, j.[key]) + 1 AS row_no, x.employee_code, x.pay_item, x.month_text, x.amount, ISNULL(x.taxable, 0) AS taxable,
           x.description, e.id AS employee_id, pi.id AS pay_item_id,
           CASE WHEN TRY_CONVERT(DATE, x.month_text) IS NOT NULL THEN DATEFROMPARTS(YEAR(TRY_CONVERT(DATE, x.month_text)), MONTH(TRY_CONVERT(DATE, x.month_text)), 1)
                WHEN TRY_CONVERT(DATE, x.month_text + N'-01') IS NOT NULL THEN TRY_CONVERT(DATE, x.month_text + N'-01') END AS balance_month,
           CAST(NULL AS NVARCHAR(400)) AS error
    INTO #r
    FROM OPENJSON(@rows) j
    CROSS APPLY OPENJSON(j.[value]) WITH (employee_code NVARCHAR(30) '$.employeeCode', pay_item NVARCHAR(200) '$.payItem',
         month_text NVARCHAR(20) '$.month', amount DECIMAL(18,2) '$.amount', taxable BIT '$.taxable', description NVARCHAR(MAX) '$.description') x
    LEFT JOIN [hr].[employee] e ON e.company_id = @company_id AND e.code = x.employee_code
         AND e.id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code))
    LEFT JOIN [pay].[pay_item] pi ON pi.company_id = @company_id AND pi.name = x.pay_item;

    UPDATE #r SET error = N'Employee code not found.' WHERE employee_id IS NULL;
    UPDATE #r SET error = N'Pay item not found.' WHERE error IS NULL AND pay_item_id IS NULL;
    UPDATE #r SET error = N'Month is not a date.' WHERE error IS NULL AND balance_month IS NULL;
    UPDATE #r SET error = N'Amount is required.' WHERE error IS NULL AND (amount IS NULL OR amount = 0);
    UPDATE #r SET error = N'That month''s payroll is closed for this person.' WHERE error IS NULL AND [pay].[fn_month_locked](employee_id, balance_month) = 1;

    BEGIN TRAN;
        INSERT [pay].[opening_balance] (employee_id, balance_month, pay_item_id, amount, is_taxable, kind, description, created_by)
        SELECT employee_id, balance_month, pay_item_id, amount, taxable, N'opening', description, @actor_user_id FROM #r WHERE error IS NULL;
    COMMIT;

    SELECT COUNT(*) AS created FROM #r WHERE error IS NULL;
    SELECT row_no, error FROM #r WHERE error IS NOT NULL ORDER BY row_no;
END
GO

----------------------------------------------------------------------------------------------- employee accounts

CREATE OR ALTER PROCEDURE [pay].[usp_employee_account_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @scope           NVARCHAR(10) = N'all',
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @account_type_id BIGINT = NULL,
    @month           DATE = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @month IS NOT NULL SET @month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1);

    SELECT a.id INTO #ids
    FROM [pay].[employee_account_entry] a
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    JOIN [hr].[employee] e ON e.id = a.employee_id AND e.company_id = @company_id
    WHERE (@scope <> N'my' OR a.employee_id = @me)
      AND (@employee_id IS NULL OR a.employee_id = @employee_id)
      AND (@account_type_id IS NULL OR a.account_type_id = @account_type_id)
      AND (@month IS NULL OR a.entry_month = @month)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT a.id, a.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           a.account_type_id, t.name AS account_name, t.category AS account_category, a.entry_month, a.credit, a.debit,
           a.is_processed, a.payslip_id, a.pay_rule_id, r.name AS pay_rule_name, a.description, a.created_at, a.updated_at, a.row_version
    FROM #ids i
    JOIN [pay].[employee_account_entry] a ON a.id = i.id
    JOIN [hr].[employee] e ON e.id = a.employee_id
    JOIN [pay].[account_type] t ON t.id = a.account_type_id
    LEFT JOIN [pay].[pay_rule] r ON r.id = a.pay_rule_id
    ORDER BY a.entry_month DESC, e.first_name, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_employee_account_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[employee_account_entry] a
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
                   WHERE a.id = @id)
        THROW 50404, N'Account entry not found', 1;
    SELECT a.id, a.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           a.account_type_id, t.name AS account_name, t.category AS account_category, a.entry_month, a.credit, a.debit,
           a.is_processed, a.payslip_id, a.pay_rule_id, r.name AS pay_rule_name, a.description, a.created_at, a.updated_at, a.row_version
    FROM [pay].[employee_account_entry] a
    JOIN [hr].[employee] e ON e.id = a.employee_id
    JOIN [pay].[account_type] t ON t.id = a.account_type_id
    LEFT JOIN [pay].[pay_rule] r ON r.id = a.pay_rule_id
    WHERE a.id = @id;
END
GO

-- Entries a payroll rule posted belong to that payroll and cannot be edited here.
CREATE OR ALTER PROCEDURE [pay].[usp_employee_account_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @account_type_id BIGINT,
    @entry_month     DATE,
    @credit          DECIMAL(18,2) = 0,
    @debit           DECIMAL(18,2) = 0,
    @is_processed    BIT = 0,
    @description     NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @entry_month = DATEFROMPARTS(YEAR(@entry_month), MONTH(@entry_month), 1);
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [pay].[account_type] WHERE id = @account_type_id AND company_id = @company_id)
        THROW 50400, N'accountTypeId|Account type not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [pay].[employee_account_entry] (employee_id, account_type_id, entry_month, credit, debit, is_processed, description, created_by)
            VALUES (@employee_id, @account_type_id, @entry_month, ISNULL(@credit, 0), ISNULL(@debit, 0), @is_processed, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.employee_account_entry', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @rv BINARY(8), @rule BIGINT, @slip BIGINT;
            SELECT @rv = a.row_version, @rule = a.pay_rule_id, @slip = a.payslip_id FROM [pay].[employee_account_entry] a
            JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
            WHERE a.id = @id;
            IF @rv IS NULL
                THROW 50404, N'Account entry not found', 1;
            IF @rv <> @row_version
                THROW 50409, N'Someone else changed this account entry. Reload it and try again', 1;
            IF @rule IS NOT NULL OR @slip IS NOT NULL
                THROW 50409, N'status|ENTRY_FROM_PAYROLL|A payroll posted this entry. It cannot be changed here', 1;
            UPDATE [pay].[employee_account_entry]
            SET employee_id = @employee_id, account_type_id = @account_type_id, entry_month = @entry_month, credit = ISNULL(@credit, 0),
                debit = ISNULL(@debit, 0), is_processed = @is_processed, description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.employee_account_entry', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_employee_account_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_employee_account_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @rule BIGINT, @slip BIGINT;
    SELECT @rv = a.row_version, @rule = a.pay_rule_id, @slip = a.payslip_id FROM [pay].[employee_account_entry] a
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = a.employee_id
    WHERE a.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Account entry not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this account entry. Reload it and try again', 1;
    IF @rule IS NOT NULL OR @slip IS NOT NULL
        THROW 50409, N'status|ENTRY_FROM_PAYROLL|A payroll posted this entry. It cannot be deleted here', 1;
    BEGIN TRAN;
        DELETE [pay].[employee_account_entry] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.employee_account_entry', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Import File (Opening Balance, Provident Fund): @rows JSON [{"employeeCode","account","month","credit","debit","description"}].
CREATE OR ALTER PROCEDURE [pay].[usp_employee_account_import]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @rows            NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT CONVERT(INT, j.[key]) + 1 AS row_no, x.credit, x.debit, x.description, e.id AS employee_id, t.id AS account_type_id,
           CASE WHEN TRY_CONVERT(DATE, x.month_text) IS NOT NULL THEN DATEFROMPARTS(YEAR(TRY_CONVERT(DATE, x.month_text)), MONTH(TRY_CONVERT(DATE, x.month_text)), 1)
                WHEN TRY_CONVERT(DATE, x.month_text + N'-01') IS NOT NULL THEN TRY_CONVERT(DATE, x.month_text + N'-01') END AS entry_month,
           CAST(NULL AS NVARCHAR(400)) AS error
    INTO #r
    FROM OPENJSON(@rows) j
    CROSS APPLY OPENJSON(j.[value]) WITH (employee_code NVARCHAR(30) '$.employeeCode', account NVARCHAR(200) '$.account',
         month_text NVARCHAR(20) '$.month', credit DECIMAL(18,2) '$.credit', debit DECIMAL(18,2) '$.debit', description NVARCHAR(MAX) '$.description') x
    LEFT JOIN [hr].[employee] e ON e.company_id = @company_id AND e.code = x.employee_code
         AND e.id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code))
    LEFT JOIN [pay].[account_type] t ON t.company_id = @company_id AND (t.name = x.account OR t.code = x.account);

    UPDATE #r SET error = N'Employee code not found.' WHERE employee_id IS NULL;
    UPDATE #r SET error = N'Account not found.' WHERE error IS NULL AND account_type_id IS NULL;
    UPDATE #r SET error = N'Month is not a date.' WHERE error IS NULL AND entry_month IS NULL;
    UPDATE #r SET error = N'Give a credit or a debit.' WHERE error IS NULL AND ISNULL(credit, 0) = 0 AND ISNULL(debit, 0) = 0;

    BEGIN TRAN;
        INSERT [pay].[employee_account_entry] (employee_id, account_type_id, entry_month, credit, debit, is_processed, description, created_by)
        SELECT employee_id, account_type_id, entry_month, ISNULL(credit, 0), ISNULL(debit, 0), 1, description, @actor_user_id
        FROM #r WHERE error IS NULL;
    COMMIT;

    SELECT COUNT(*) AS created FROM #r WHERE error IS NULL;
    SELECT row_no, error FROM #r WHERE error IS NOT NULL ORDER BY row_no;
END
GO

-- Employee Account Statement: one person's entries in month order with a running balance per account.
CREATE OR ALTER PROCEDURE [pay].[usp_account_statement]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT = NULL,
    @account_type_id BIGINT = NULL,
    @from_month      DATE = NULL,
    @to_month        DATE = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF @employee_id IS NULL
        SET @employee_id = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @employee_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;

    SELECT a.id, a.employee_id, CONCAT(e.first_name, N' ', e.last_name) AS employee_name, a.account_type_id, t.name AS account_name,
           a.entry_month, a.credit, a.debit, a.is_processed, a.description,
           SUM(a.credit - a.debit) OVER (PARTITION BY a.account_type_id ORDER BY a.entry_month, a.id ROWS UNBOUNDED PRECEDING) AS balance
    INTO #s
    FROM [pay].[employee_account_entry] a
    JOIN [hr].[employee] e ON e.id = a.employee_id
    JOIN [pay].[account_type] t ON t.id = a.account_type_id
    WHERE a.employee_id = @employee_id AND (@account_type_id IS NULL OR a.account_type_id = @account_type_id)
      AND (@to_month IS NULL OR a.entry_month <= @to_month);

    DELETE #s WHERE @from_month IS NOT NULL AND entry_month < DATEFROMPARTS(YEAR(@from_month), MONTH(@from_month), 1);

    SELECT COUNT(*) AS total FROM #s;
    SELECT * FROM #s ORDER BY entry_month, account_name, id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
