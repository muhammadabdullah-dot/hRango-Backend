-- Request Settings -> Expense Categories (Travel Fee, Tech & Soft, Venue Rental ...) and
-- Request Settings -> Reimbursement (the pay items approved expense and air ticket claims are paid
-- under through payroll). A category's own pay item wins over the default expense pay item.

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [req].[usp_expense_category_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(210) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [req].[expense_category] c
    WHERE c.company_id = @company_id AND (@is_active IS NULL OR c.is_active = @is_active)
      AND (@pattern IS NULL OR c.name LIKE @pattern);

    SELECT c.id, c.name, c.pay_item_id, p.name AS pay_item_name, c.max_amount, c.receipt_required, c.is_active,
           c.description, c.created_at, c.updated_at, c.row_version
    FROM [req].[expense_category] c
    LEFT JOIN [pay].[pay_item] p ON p.id = c.pay_item_id
    WHERE c.company_id = @company_id AND (@is_active IS NULL OR c.is_active = @is_active)
      AND (@pattern IS NULL OR c.name LIKE @pattern)
    ORDER BY c.name, c.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_expense_category_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [req].[expense_category] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Expense category not found', 1;
    SELECT c.id, c.name, c.pay_item_id, p.name AS pay_item_name, c.max_amount, c.receipt_required, c.is_active,
           c.description, c.created_at, c.updated_at, c.row_version
    FROM [req].[expense_category] c
    LEFT JOIN [pay].[pay_item] p ON p.id = c.pay_item_id
    WHERE c.id = @id;
END
GO

-- Add (@id NULL) or edit. The pay item, when given, must be one of the company's reimbursement items.
CREATE OR ALTER PROCEDURE [req].[usp_expense_category_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @id               BIGINT = NULL,
    @name             NVARCHAR(200),
    @pay_item_id      BIGINT = NULL,
    @max_amount       DECIMAL(18,2) = NULL,
    @receipt_required BIT = 0,
    @is_active        BIT = 1,
    @description      NVARCHAR(MAX) = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    IF @name IS NULL
        THROW 50400, N'name|Name is required.', 1;
    IF @max_amount IS NOT NULL AND @max_amount <= 0
        THROW 50400, N'maxAmount|The limit must be more than zero, or empty for no limit.', 1;
    IF @pay_item_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @pay_item_id
                                                AND company_id = @company_id AND item_type = N'reimbursement')
        THROW 50400, N'payItemId|Choose one of the company''s reimbursement pay items.', 1;
    IF EXISTS (SELECT 1 FROM [req].[expense_category] WHERE company_id = @company_id AND name = @name
               AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|EXPENSE_CATEGORY_DUPLICATE|An expense category with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [req].[expense_category] (company_id, name, pay_item_id, max_amount, receipt_required, is_active,
                                             description, created_by)
            VALUES (@company_id, @name, @pay_item_id, @max_amount, ISNULL(@receipt_required, 0), ISNULL(@is_active, 1),
                    NULLIF(LTRIM(RTRIM(@description)), N''), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'req.expense_category', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [req].[expense_category] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Expense category not found', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this expense category. Reload it and try again', 1;
        BEGIN TRAN;
            UPDATE [req].[expense_category]
            SET name = @name, pay_item_id = @pay_item_id, max_amount = @max_amount,
                receipt_required = ISNULL(@receipt_required, 0), is_active = ISNULL(@is_active, 1),
                description = NULLIF(LTRIM(RTRIM(@description)), N''), updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this expense category. Reload it and try again', 1;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'req.expense_category', @id, N'update', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [req].[usp_expense_category_get] @company_id = @company_id, @id = @id;
END
GO

-- A category claims were made under cannot be deleted; switch it off instead.
CREATE OR ALTER PROCEDURE [req].[usp_expense_category_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [req].[expense_category] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Expense category not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this expense category. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [req].[expense_line] WHERE expense_category_id = @id)
        THROW 50409, N'id|EXPENSE_CATEGORY_IN_USE|Claims were made under this category. Switch it off instead.', 1;
    BEGIN TRAN;
        DELETE [req].[expense_category] WHERE id = @id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'req.expense_category', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Request Settings -> Reimbursement. Always one row (empty values until saved).
CREATE OR ALTER PROCEDURE [req].[usp_reimbursement_setting_get]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.expense_pay_item_id, ep.name AS expense_pay_item_name,
           s.air_ticket_pay_item_id, ap.name AS air_ticket_pay_item_name, s.updated_at, s.row_version
    FROM (SELECT @company_id AS company_id) c
    LEFT JOIN [req].[reimbursement_setting] s ON s.company_id = c.company_id
    LEFT JOIN [pay].[pay_item] ep ON ep.id = s.expense_pay_item_id
    LEFT JOIN [pay].[pay_item] ap ON ap.id = s.air_ticket_pay_item_id;
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_reimbursement_setting_save]
    @company_id             BIGINT,
    @actor_user_id          BIGINT,
    @expense_pay_item_id    BIGINT = NULL,
    @air_ticket_pay_item_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @expense_pay_item_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @expense_pay_item_id
                                                        AND company_id = @company_id AND item_type = N'reimbursement')
        THROW 50400, N'expensePayItemId|Choose one of the company''s reimbursement pay items.', 1;
    IF @air_ticket_pay_item_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[pay_item] WHERE id = @air_ticket_pay_item_id
                                                           AND company_id = @company_id AND item_type = N'reimbursement')
        THROW 50400, N'airTicketPayItemId|Choose one of the company''s reimbursement pay items.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [req].[reimbursement_setting]
        SET expense_pay_item_id = @expense_pay_item_id, air_ticket_pay_item_id = @air_ticket_pay_item_id,
            updated_at = @now, updated_by = @actor_user_id
        WHERE company_id = @company_id;
        IF @@ROWCOUNT = 0
            INSERT [req].[reimbursement_setting] (company_id, expense_pay_item_id, air_ticket_pay_item_id, created_by)
            VALUES (@company_id, @expense_pay_item_id, @air_ticket_pay_item_id, @actor_user_id);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'req.reimbursement_setting', @company_id, N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [req].[usp_reimbursement_setting_get] @company_id = @company_id;
END
