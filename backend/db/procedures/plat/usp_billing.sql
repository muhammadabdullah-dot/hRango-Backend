-- Plans, subscriptions and invoices. Amounts are PKR. Billing is recorded here; no payment gateway takes money yet.

CREATE OR ALTER PROCEDURE [plat].[usp_plan_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.id, p.name, p.description, p.price_monthly, p.price_annual, p.employee_limit, p.is_active,
           p.created_at, p.updated_at, p.row_version,
           (SELECT COUNT(*) FROM [plat].[subscription] s WHERE s.plan_id = p.id AND s.status <> N'cancelled') AS subscription_count
    FROM [plat].[plan] p WHERE p.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Plan not found', 1;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_plan_list]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.id, p.name, p.description, p.price_monthly, p.price_annual, p.employee_limit, p.is_active,
           p.created_at, p.updated_at, p.row_version,
           (SELECT COUNT(*) FROM [plat].[subscription] s WHERE s.plan_id = p.id AND s.status <> N'cancelled') AS subscription_count
    FROM [plat].[plan] p
    ORDER BY p.price_monthly, p.name;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_plan_save]
    @actor_id       BIGINT = NULL,
    @id             BIGINT = NULL,
    @name           NVARCHAR(200),
    @description    NVARCHAR(500) = NULL,
    @price_monthly  DECIMAL(18,2),
    @price_annual   DECIMAL(18,2),
    @employee_limit INT = NULL,
    @is_active      BIT = 1,
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name = N''
        THROW 50400, N'name|Enter the plan name.', 1;
    IF EXISTS (SELECT 1 FROM [plat].[plan] WHERE name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|PLAN_DUPLICATE|A plan with this name already exists.', 1;

    DECLARE @action NVARCHAR(50) = CASE WHEN @id IS NULL THEN N'plan_added' ELSE N'plan_changed' END, @ref NVARCHAR(100);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [plat].[plan] (name, description, price_monthly, price_annual, employee_limit, is_active, created_by)
            VALUES (@name, @description, @price_monthly, @price_annual, @employee_limit, @is_active, @actor_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [plat].[plan]
            SET name = @name, description = @description, price_monthly = @price_monthly, price_annual = @price_annual,
                employee_limit = @employee_limit, is_active = @is_active,
                updated_at = SYSUTCDATETIME(), updated_by = @actor_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this plan. Reload and try again', 1;
        END
        SET @ref = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'plan', @entity_ref = @ref, @detail = @name;
    COMMIT;
    EXEC [plat].[usp_plan_get] @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_subscription_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.id, s.customer_id, c.name AS customer_name, s.plan_id, p.name AS plan_name, s.billing_cycle, s.status,
           s.amount, s.start_date, s.renews_on, s.cancelled_on, s.created_at, s.updated_at, s.row_version
    FROM [plat].[subscription] s
    JOIN [plat].[customer] c ON c.id = s.customer_id
    JOIN [plat].[plan] p ON p.id = s.plan_id
    WHERE s.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Subscription not found', 1;
END
GO

-- Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [plat].[usp_subscription_list]
    @search      NVARCHAR(200) = NULL,
    @status      NVARCHAR(20) = NULL,
    @customer_id BIGINT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [plat].[subscription] s JOIN [plat].[customer] c ON c.id = s.customer_id
    WHERE (@status IS NULL OR s.status = @status) AND (@customer_id IS NULL OR s.customer_id = @customer_id)
      AND (@pattern IS NULL OR c.name LIKE @pattern);

    SELECT s.id, s.customer_id, c.name AS customer_name, s.plan_id, p.name AS plan_name, s.billing_cycle, s.status,
           s.amount, s.start_date, s.renews_on, s.cancelled_on, s.created_at, s.updated_at, s.row_version
    FROM [plat].[subscription] s
    JOIN [plat].[customer] c ON c.id = s.customer_id
    JOIN [plat].[plan] p ON p.id = s.plan_id
    WHERE (@status IS NULL OR s.status = @status) AND (@customer_id IS NULL OR s.customer_id = @customer_id)
      AND (@pattern IS NULL OR c.name LIKE @pattern)
    ORDER BY CASE WHEN s.status = N'cancelled' THEN 1 ELSE 0 END, s.renews_on, s.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- A customer has at most one subscription that is not cancelled. @amount NULL takes the plan's price.
CREATE OR ALTER PROCEDURE [plat].[usp_subscription_save]
    @actor_id      BIGINT = NULL,
    @id            BIGINT = NULL,
    @customer_id   BIGINT,
    @plan_id       BIGINT,
    @billing_cycle NVARCHAR(10),
    @status        NVARCHAR(20),
    @amount        DECIMAL(18,2) = NULL,
    @start_date    DATE,
    @renews_on     DATE = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @billing_cycle NOT IN (N'monthly', N'annual')
        THROW 50400, N'billingCycle|Choose monthly or annual.', 1;
    IF @status NOT IN (N'trial', N'active', N'past_due', N'cancelled')
        THROW 50400, N'status|Choose trial, active, past due or cancelled.', 1;
    IF NOT EXISTS (SELECT 1 FROM [plat].[customer] WHERE id = @customer_id)
        THROW 50400, N'customerId|Choose an organisation.', 1;
    IF @renews_on IS NOT NULL AND @renews_on < @start_date
        THROW 50400, N'renewsOn|The renewal cannot be before the start date.', 1;
    IF @status <> N'cancelled' AND EXISTS (SELECT 1 FROM [plat].[subscription]
                                           WHERE customer_id = @customer_id AND status <> N'cancelled'
                                             AND (@id IS NULL OR id <> @id))
        THROW 50409, N'customerId|SUBSCRIPTION_EXISTS|This organisation already has a subscription. Change that one.', 1;

    IF @amount IS NULL
        SELECT @amount = CASE WHEN @billing_cycle = N'annual' THEN price_annual ELSE price_monthly END
        FROM [plat].[plan] WHERE id = @plan_id;
    IF @amount IS NULL
        THROW 50400, N'planId|Choose a plan.', 1;

    DECLARE @cancelled DATE = CASE WHEN @status = N'cancelled' THEN CONVERT(DATE, SYSUTCDATETIME()) END,
            @action NVARCHAR(50) = CASE WHEN @id IS NULL THEN N'subscription_added' ELSE N'subscription_changed' END,
            @ref NVARCHAR(100);
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [plat].[subscription] (customer_id, plan_id, billing_cycle, status, amount, start_date, renews_on,
                                          cancelled_on, created_by)
            VALUES (@customer_id, @plan_id, @billing_cycle, @status, @amount, @start_date, @renews_on, @cancelled, @actor_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [plat].[subscription]
            SET customer_id = @customer_id, plan_id = @plan_id, billing_cycle = @billing_cycle, status = @status,
                amount = @amount, start_date = @start_date, renews_on = @renews_on,
                cancelled_on = COALESCE(cancelled_on, @cancelled),
                updated_at = SYSUTCDATETIME(), updated_by = @actor_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this subscription. Reload and try again', 1;
        END
        SET @ref = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'subscription', @entity_ref = @ref, @detail = @status;
    COMMIT;
    EXEC [plat].[usp_subscription_get] @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [plat].[usp_invoice_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.id, i.number, i.customer_id, c.name AS customer_name, i.subscription_id, i.issue_date, i.due_date, i.amount,
           CASE WHEN i.status = N'issued' AND i.due_date < CONVERT(DATE, SYSUTCDATETIME()) THEN N'overdue' ELSE i.status END AS status,
           i.paid_on, i.payment_reference, i.created_at, i.updated_at, i.row_version
    FROM [plat].[invoice] i JOIN [plat].[customer] c ON c.id = i.customer_id
    WHERE i.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Invoice not found', 1;
END
GO

-- Result set 1: total. Result set 2: the page. @status overdue means issued and past its due date.
CREATE OR ALTER PROCEDURE [plat].[usp_invoice_list]
    @search      NVARCHAR(200) = NULL,
    @status      NVARCHAR(20) = NULL,
    @customer_id BIGINT = NULL,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CONVERT(DATE, SYSUTCDATETIME());
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    ;WITH rows AS (
        SELECT i.id, i.number, i.customer_id, c.name AS customer_name, i.subscription_id, i.issue_date, i.due_date, i.amount,
               CASE WHEN i.status = N'issued' AND i.due_date < @today THEN N'overdue' ELSE i.status END AS status,
               i.paid_on, i.payment_reference, i.created_at, i.updated_at, i.row_version
        FROM [plat].[invoice] i JOIN [plat].[customer] c ON c.id = i.customer_id
        WHERE (@customer_id IS NULL OR i.customer_id = @customer_id)
          AND (@pattern IS NULL OR c.name LIKE @pattern OR i.number LIKE @pattern)
    )
    SELECT * INTO #rows FROM rows WHERE @status IS NULL OR status = @status;

    SELECT COUNT(*) AS total FROM #rows;
    SELECT * FROM #rows
    ORDER BY issue_date DESC, id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- The number comes from the year and the next id: INV-2026-0042.
CREATE OR ALTER PROCEDURE [plat].[usp_invoice_add]
    @actor_id        BIGINT = NULL,
    @customer_id     BIGINT,
    @subscription_id BIGINT = NULL,
    @issue_date      DATE,
    @due_date        DATE,
    @amount          DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [plat].[customer] WHERE id = @customer_id)
        THROW 50400, N'customerId|Choose an organisation.', 1;
    IF @amount <= 0
        THROW 50400, N'amount|Enter an amount above zero.', 1;
    IF @due_date < @issue_date
        THROW 50400, N'dueDate|The due date cannot be before the issue date.', 1;
    IF @subscription_id IS NULL
        SELECT TOP 1 @subscription_id = id FROM [plat].[subscription]
        WHERE customer_id = @customer_id AND status <> N'cancelled' ORDER BY id DESC;

    DECLARE @id BIGINT, @number NVARCHAR(30), @ref NVARCHAR(100);
    BEGIN TRAN;
        SELECT @id = ISNULL(MAX(id), 0) + 1 FROM [plat].[invoice] WITH (UPDLOCK, HOLDLOCK);
        SET @number = CONCAT(N'INV-', YEAR(@issue_date), N'-', RIGHT(CONCAT(N'0000', @id), 4));
        INSERT [plat].[invoice] (number, customer_id, subscription_id, issue_date, due_date, amount, status, created_by)
        VALUES (@number, @customer_id, @subscription_id, @issue_date, @due_date, @amount, N'issued', @actor_id);
        SET @id = SCOPE_IDENTITY();
        SET @ref = CONVERT(NVARCHAR(30), @id);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = N'invoice_issued',
             @entity_type = N'invoice', @entity_ref = @ref, @detail = @number;
    COMMIT;
    EXEC [plat].[usp_invoice_get] @id = @id;
END
GO

-- Paid or void. A paid or voided invoice stays as it is.
CREATE OR ALTER PROCEDURE [plat].[usp_invoice_status_set]
    @actor_id          BIGINT = NULL,
    @id                BIGINT,
    @status            NVARCHAR(20),
    @paid_on           DATE = NULL,
    @payment_reference NVARCHAR(100) = NULL,
    @row_version       BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @status NOT IN (N'paid', N'void')
        THROW 50400, N'status|Choose paid or void.', 1;
    DECLARE @old NVARCHAR(20) = (SELECT status FROM [plat].[invoice] WHERE id = @id), @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id);
    IF @old IS NULL
        THROW 50404, N'Invoice not found', 1;
    IF @old <> N'issued'
        THROW 50409, N'status|INVOICE_CLOSED|This invoice is already paid or void.', 1;
    IF @status = N'paid' AND @paid_on IS NULL
        SET @paid_on = CONVERT(DATE, SYSUTCDATETIME());

    DECLARE @action NVARCHAR(50) = N'invoice_' + @status;
    BEGIN TRAN;
        UPDATE [plat].[invoice]
        SET status = @status, paid_on = CASE WHEN @status = N'paid' THEN @paid_on END,
            payment_reference = @payment_reference, updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this invoice. Reload and try again', 1;
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'invoice', @entity_ref = @ref;
    COMMIT;
    EXEC [plat].[usp_invoice_get] @id = @id;
END
GO
