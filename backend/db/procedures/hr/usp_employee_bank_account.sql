-- Bank details per employee (employees.bank_accounts, sensitive): account holder, account number,
-- bank, branch, bank code, taxpayer id (Mini SRS EMP-2). One account is the primary one, where
-- salary goes; the first account added is primary.

CREATE OR ALTER PROCEDURE [hr].[usp_employee_bank_account_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.bank_accounts.view') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT a.id, a.employee_id, a.account_holder, a.account_number, a.bank_name, a.branch_name, a.branch_code,
           a.tax_payer_id, a.is_primary, a.created_at, a.updated_at, a.row_version
    FROM [hr].[employee_bank_account] a
    WHERE a.employee_id = @employee_id
    ORDER BY a.is_primary DESC, a.bank_name, a.id;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_bank_account_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @employee_id    BIGINT,
    @id             BIGINT = NULL,
    @account_holder NVARCHAR(200) = NULL,
    @account_number NVARCHAR(50),
    @bank_name      NVARCHAR(200),
    @branch_name    NVARCHAR(200) = NULL,
    @branch_code    NVARCHAR(30) = NULL,
    @tax_payer_id   NVARCHAR(30) = NULL,
    @is_primary     BIT = 0,
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @account_holder = NULLIF(LTRIM(RTRIM(@account_holder)), N'');
    SET @account_number = NULLIF(REPLACE(LTRIM(RTRIM(@account_number)), N' ', N''), N'');
    SET @bank_name = NULLIF(LTRIM(RTRIM(@bank_name)), N'');
    SET @branch_name = NULLIF(LTRIM(RTRIM(@branch_name)), N'');
    SET @branch_code = NULLIF(LTRIM(RTRIM(@branch_code)), N'');
    SET @tax_payer_id = NULLIF(LTRIM(RTRIM(@tax_payer_id)), N'');

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.bank_accounts.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
    IF @account_number IS NULL
        THROW 50400, N'accountNumber|Account number is required.', 1;
    IF @bank_name IS NULL
        THROW 50400, N'bankName|Bank name is required.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_bank_account] WHERE employee_id = @employee_id AND account_number = @account_number
               AND (@id IS NULL OR id <> @id))
        THROW 50409, N'accountNumber|BANK_ACCOUNT_DUPLICATE|This employee already has this account.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee_bank_account] WHERE employee_id = @employee_id AND (@id IS NULL OR id <> @id))
        SET @is_primary = 1;

    BEGIN TRAN;
    IF @is_primary = 1
        UPDATE [hr].[employee_bank_account] SET is_primary = 0, updated_at = @now, updated_by = @actor_user_id
        WHERE employee_id = @employee_id AND is_primary = 1 AND (@id IS NULL OR id <> @id);

    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_bank_account] (employee_id, account_holder, account_number, bank_name, branch_name,
                                             branch_code, tax_payer_id, is_primary, created_by)
        VALUES (@employee_id, @account_holder, @account_number, @bank_name, @branch_name, @branch_code, @tax_payer_id,
                @is_primary, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_bank_account]
        SET account_holder = @account_holder, account_number = @account_number, bank_name = @bank_name,
            branch_name = @branch_name, branch_code = @branch_code, tax_payer_id = @tax_payer_id, is_primary = @is_primary,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_bank_account] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Bank account not found', 1;
            THROW 50409, N'Someone else changed this bank account. Reload it and try again', 1;
        END
    END

    -- The account number itself is not copied into the log.
    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
    VALUES (@company_id, N'hr.employee', @employee_id, N'bank_account', @bank_name,
            CASE WHEN @row_version IS NULL THEN N'create' ELSE N'update' END, @actor_user_id, @now);
    COMMIT;

    SELECT a.id, a.employee_id, a.account_holder, a.account_number, a.bank_name, a.branch_name, a.branch_code,
           a.tax_payer_id, a.is_primary, a.created_at, a.updated_at, a.row_version
    FROM [hr].[employee_bank_account] a WHERE a.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_bank_account_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.bank_accounts.edit') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    DECLARE @rv BINARY(8), @primary BIT, @bank NVARCHAR(200);
    SELECT @rv = row_version, @primary = is_primary, @bank = bank_name
    FROM [hr].[employee_bank_account] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Bank account not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this bank account. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_bank_account] WHERE id = @id;
        IF @primary = 1
            UPDATE [hr].[employee_bank_account] SET is_primary = 1
            WHERE id = (SELECT TOP 1 id FROM [hr].[employee_bank_account] WHERE employee_id = @employee_id ORDER BY id);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee', @employee_id, N'bank_account', @bank, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
