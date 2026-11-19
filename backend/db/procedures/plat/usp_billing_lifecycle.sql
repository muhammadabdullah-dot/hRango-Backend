-- Billing without a payment gateway (migration 0050). The nightly run (plat.usp_billing_run, scripts/nightly.py)
-- issues each subscription's renewal invoice 7 days before it renews, ends trials and restricts access when an
-- invoice stays unpaid; paying (staff mark it paid, or accept the customer's bank transfer proof) restores it.
--
-- Access, from the oldest unpaid invoice past its due date ("days late": 1 the day after the due date):
--   a paying customer (active, past_due)   past_due at once; read_only from day 14; locked from day 30
--   a trial never paid (trial, expired)    expired and read_only from day 1 (the trial's end is the due date);
--                                          locked from day 8
--   read_only: everything can be seen and exported, nothing changed (the API refuses writes, READ_ONLY).
--   locked:    only the Account Owner gets in, to Billing (BILLING_LOCKED for everyone and everything else).
-- A subscription on a free plan (amount 0) is never billed and never restricted.

-- The day the period after the one starting on @start begins: a month (or a year) later.
CREATE OR ALTER FUNCTION [plat].[fn_period_next] (@start DATE, @cycle NVARCHAR(10))
RETURNS DATE
AS
BEGIN
    RETURN CASE WHEN @cycle = N'annual' THEN DATEADD(YEAR, 1, @start) ELSE DATEADD(MONTH, 1, @start) END;
END
GO

-- Internal, inside the caller's transaction: a new invoice with the next number (INV-2026-0042).
CREATE OR ALTER PROCEDURE [plat].[usp_invoice_issue_internal]
    @customer_id     BIGINT,
    @subscription_id BIGINT = NULL,
    @issue_date      DATE,
    @due_date        DATE,
    @amount          DECIMAL(18,2),
    @source          NVARCHAR(20) = N'manual',
    @period_start    DATE = NULL,
    @period_end      DATE = NULL,
    @actor_id        BIGINT = NULL,
    @id              BIGINT OUTPUT,
    @number          NVARCHAR(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @id = ISNULL(MAX(id), 0) + 1 FROM [plat].[invoice] WITH (UPDLOCK, HOLDLOCK);
    SET @number = CONCAT(N'INV-', YEAR(@issue_date), N'-', RIGHT(CONCAT(N'0000', @id), 4));
    INSERT [plat].[invoice] (number, customer_id, subscription_id, issue_date, due_date, amount, status, source,
                             period_start, period_end, created_by)
    VALUES (@number, @customer_id, @subscription_id, @issue_date, @due_date, @amount, N'issued', @source,
            @period_start, @period_end, @actor_id);
    SET @id = SCOPE_IDENTITY();
END
GO

-- Internal: one billing e-mail to send, once per subscription, kind and date (the e-mail goes out with the next
-- plat.usp_billing_run result).
CREATE OR ALTER PROCEDURE [plat].[usp_billing_notice_add]
    @subscription_id BIGINT,
    @kind            NVARCHAR(40),
    @ref_date        DATE,
    @invoice_id      BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT [plat].[billing_notice] (subscription_id, invoice_id, kind, ref_date)
    SELECT @subscription_id, @invoice_id, @kind, @ref_date
    WHERE NOT EXISTS (SELECT 1 FROM [plat].[billing_notice]
                      WHERE subscription_id = @subscription_id AND kind = @kind AND ref_date = @ref_date);
END
GO

-- A subscription's status and access from its unpaid invoices (see the top of this file). @notify 1 records the
-- e-mails a change calls for (trial ended, read-only, locked); a payment or a staff change passes 0.
CREATE OR ALTER PROCEDURE [plat].[usp_subscription_access_refresh]
    @subscription_id BIGINT,
    @today           DATE = NULL,
    @read_only_at    INT = 14,
    @locked_at       INT = 30,
    @trial_locked_at INT = 8,
    @notify          BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @today = ISNULL(@today, CONVERT(DATE, SYSUTCDATETIME()));
    DECLARE @status NVARCHAR(20), @access NVARCHAR(20);
    SELECT @status = status, @access = access FROM [plat].[subscription] WHERE id = @subscription_id;
    IF @status IS NULL OR @status = N'cancelled'
        RETURN;

    DECLARE @invoice_id BIGINT, @due DATE;
    SELECT TOP 1 @invoice_id = id, @due = due_date
    FROM [plat].[invoice]
    WHERE subscription_id = @subscription_id AND status = N'issued' AND due_date < @today
    ORDER BY due_date, id;

    DECLARE @new_status NVARCHAR(20) = @status, @new_access NVARCHAR(20) = N'full';
    IF @invoice_id IS NOT NULL
    BEGIN
        DECLARE @late INT = DATEDIFF(DAY, @due, @today);
        IF @status IN (N'trial', N'expired')
            SELECT @new_status = N'expired',
                   @new_access = CASE WHEN @late >= @trial_locked_at THEN N'locked' ELSE N'read_only' END;
        ELSE
            SELECT @new_status = N'past_due',
                   @new_access = CASE WHEN @late >= @locked_at THEN N'locked'
                                      WHEN @late >= @read_only_at THEN N'read_only' ELSE N'full' END;
    END
    ELSE IF @status = N'past_due'
        SET @new_status = N'active';

    IF @new_status = @status AND @new_access = @access
        RETURN;

    UPDATE [plat].[subscription]
    SET status = @new_status, access = @new_access,
        access_since = CASE WHEN @new_access = @access THEN access_since
                            WHEN @new_access = N'full' THEN NULL ELSE @today END,
        updated_at = SYSUTCDATETIME()
    WHERE id = @subscription_id;

    IF @notify = 1 AND @invoice_id IS NOT NULL
    BEGIN
        IF @new_status = N'expired' AND @status <> N'expired'
            EXEC [plat].[usp_billing_notice_add] @subscription_id = @subscription_id, @kind = N'trial_ended',
                 @ref_date = @due, @invoice_id = @invoice_id;
        ELSE IF @new_access = N'read_only' AND @access = N'full'
            EXEC [plat].[usp_billing_notice_add] @subscription_id = @subscription_id, @kind = N'read_only',
                 @ref_date = @due, @invoice_id = @invoice_id;
        IF @new_access = N'locked' AND @access <> N'locked'
            EXEC [plat].[usp_billing_notice_add] @subscription_id = @subscription_id, @kind = N'locked',
                 @ref_date = @due, @invoice_id = @invoice_id;
    END
END
GO

-- Internal, after an invoice is paid: a renewal invoice moves its subscription on to the next period (a trial
-- becomes active); then the subscription's access is worked out again.
CREATE OR ALTER PROCEDURE [plat].[usp_invoice_pay_apply]
    @invoice_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @subscription_id BIGINT, @source NVARCHAR(20), @period_start DATE, @period_end DATE;
    SELECT @subscription_id = subscription_id, @source = source, @period_start = period_start, @period_end = period_end
    FROM [plat].[invoice] WHERE id = @invoice_id;
    IF @subscription_id IS NULL
        RETURN;
    IF @source = N'renewal' AND @period_end IS NOT NULL
        UPDATE [plat].[subscription]
        SET status = N'active', renews_on = DATEADD(DAY, 1, @period_end), updated_at = SYSUTCDATETIME()
        WHERE id = @subscription_id AND status <> N'cancelled' AND (renews_on IS NULL OR renews_on <= @period_start);
    EXEC [plat].[usp_subscription_access_refresh] @subscription_id = @subscription_id, @notify = 0;
END
GO

-- The nightly billing run, for every organisation that is not suspended or cancelled:
--   1. a free plan's trial that has ended becomes active (it is never billed);
--   2. renewal invoices, @renewal_days before a subscription renews (a trial's: before it ends), once a period;
--   3. reminders: a trial ending in 7, 3 and 1 days; an invoice due today; an invoice 3 and 7 days late;
--   4. status and access of every subscription (plat.usp_subscription_access_refresh);
-- and returns every billing e-mail still to send, marking them sent (the caller queues them: app/services/billing).
CREATE OR ALTER PROCEDURE [plat].[usp_billing_run]
    @today           DATE = NULL,
    @renewal_days    INT = 7,
    @read_only_at    INT = 14,
    @locked_at       INT = 30,
    @trial_locked_at INT = 8,
    -- One organisation only (tests, or a run for one customer); NULL: every organisation.
    @customer_id     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @today = ISNULL(@today, CONVERT(DATE, SYSUTCDATETIME()));

    UPDATE s SET status = N'active', renews_on = NULL, updated_at = SYSUTCDATETIME()
    FROM [plat].[subscription] s
    WHERE s.status = N'trial' AND s.amount = 0 AND s.renews_on < @today
      AND (@customer_id IS NULL OR s.customer_id = @customer_id);

    DECLARE @sid BIGINT, @customer BIGINT, @renews DATE, @cycle NVARCHAR(10), @amount DECIMAL(18,2), @status NVARCHAR(20),
            @invoice BIGINT, @number NVARCHAR(30), @due DATE, @period_end DATE;
    DECLARE renewals CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.id, s.customer_id, s.renews_on, s.billing_cycle, s.amount, s.status
        FROM [plat].[subscription] s
        JOIN [plat].[customer] cu ON cu.id = s.customer_id AND cu.status = N'active'
        WHERE s.status IN (N'trial', N'active', N'past_due', N'expired') AND s.renews_on IS NOT NULL AND s.amount > 0
          AND s.renews_on <= DATEADD(DAY, @renewal_days, @today)
          AND (@customer_id IS NULL OR s.customer_id = @customer_id)
          AND NOT EXISTS (SELECT 1 FROM [plat].[invoice] i
                          WHERE i.subscription_id = s.id AND i.source = N'renewal' AND i.period_start = s.renews_on
                            AND i.status <> N'void');
    OPEN renewals;
    FETCH NEXT FROM renewals INTO @sid, @customer, @renews, @cycle, @amount, @status;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @due = CASE WHEN @renews < @today THEN @today ELSE @renews END;
        SET @period_end = DATEADD(DAY, -1, [plat].[fn_period_next](@renews, @cycle));
        BEGIN TRAN;
            EXEC [plat].[usp_invoice_issue_internal] @customer_id = @customer, @subscription_id = @sid,
                 @issue_date = @today, @due_date = @due, @amount = @amount, @source = N'renewal',
                 @period_start = @renews, @period_end = @period_end, @id = @invoice OUTPUT, @number = @number OUTPUT;
            DECLARE @detail NVARCHAR(1000) = (SELECT LEFT(CONCAT(@number, N' · ', name, N' · automatic renewal'), 1000)
                                              FROM [plat].[customer] WHERE id = @customer);
            DECLARE @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @invoice);
            EXEC [plat].[usp_staff_audit_add] @staff_id = NULL, @action = N'invoice_issued',
                 @entity_type = N'invoice', @entity_ref = @ref, @detail = @detail;
            -- A trial's invoice goes out with the "trial ends in 7 days" e-mail instead.
            IF @status <> N'trial'
                EXEC [plat].[usp_billing_notice_add] @subscription_id = @sid, @kind = N'invoice_issued',
                     @ref_date = @renews, @invoice_id = @invoice;
        COMMIT;
        FETCH NEXT FROM renewals INTO @sid, @customer, @renews, @cycle, @amount, @status;
    END
    CLOSE renewals;
    DEALLOCATE renewals;

    -- Trial ending in 7, 3 or 1 days, unless its invoice is already paid.
    INSERT [plat].[billing_notice] (subscription_id, invoice_id, kind, ref_date)
    SELECT s.id, i.id, CONCAT(N'trial_', DATEDIFF(DAY, @today, s.renews_on)), s.renews_on
    FROM [plat].[subscription] s
    JOIN [plat].[customer] cu ON cu.id = s.customer_id AND cu.status = N'active'
    OUTER APPLY (SELECT TOP 1 x.id, x.status FROM [plat].[invoice] x
                 WHERE x.subscription_id = s.id AND x.source = N'renewal' AND x.period_start = s.renews_on
                   AND x.status <> N'void') i
    WHERE s.status = N'trial' AND s.amount > 0 AND DATEDIFF(DAY, @today, s.renews_on) IN (7, 3, 1)
      AND (@customer_id IS NULL OR s.customer_id = @customer_id)
      AND ISNULL(i.status, N'issued') = N'issued'
      AND NOT EXISTS (SELECT 1 FROM [plat].[billing_notice] n WHERE n.subscription_id = s.id
                        AND n.kind = CONCAT(N'trial_', DATEDIFF(DAY, @today, s.renews_on)) AND n.ref_date = s.renews_on);

    -- An invoice due today, or 3 or 7 days late.
    INSERT [plat].[billing_notice] (subscription_id, invoice_id, kind, ref_date)
    SELECT i.subscription_id, i.id, k.kind, i.due_date
    FROM [plat].[invoice] i
    JOIN [plat].[subscription] s ON s.id = i.subscription_id AND s.status <> N'cancelled'
    JOIN [plat].[customer] cu ON cu.id = s.customer_id AND cu.status = N'active'
    CROSS APPLY (SELECT CASE DATEDIFF(DAY, i.due_date, @today) WHEN 0 THEN N'due_today' WHEN 3 THEN N'overdue_3'
                                                               WHEN 7 THEN N'overdue_7' END AS kind) k
    WHERE i.status = N'issued' AND k.kind IS NOT NULL
      AND (@customer_id IS NULL OR s.customer_id = @customer_id)
      AND NOT EXISTS (SELECT 1 FROM [plat].[billing_notice] n
                      WHERE n.subscription_id = i.subscription_id AND n.kind = k.kind AND n.ref_date = i.due_date);

    DECLARE refresh CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.id FROM [plat].[subscription] s
        JOIN [plat].[customer] cu ON cu.id = s.customer_id AND cu.status = N'active'
        WHERE s.status <> N'cancelled' AND (@customer_id IS NULL OR s.customer_id = @customer_id);
    OPEN refresh;
    FETCH NEXT FROM refresh INTO @sid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC [plat].[usp_subscription_access_refresh] @subscription_id = @sid, @today = @today,
             @read_only_at = @read_only_at, @locked_at = @locked_at, @trial_locked_at = @trial_locked_at;
        FETCH NEXT FROM refresh INTO @sid;
    END
    CLOSE refresh;
    DEALLOCATE refresh;

    DECLARE @sent TABLE (id BIGINT PRIMARY KEY);
    UPDATE n SET mailed_at = SYSUTCDATETIME()
    OUTPUT inserted.id INTO @sent
    FROM [plat].[billing_notice] n
    JOIN [plat].[subscription] s ON s.id = n.subscription_id
    WHERE n.mailed_at IS NULL AND (@customer_id IS NULL OR s.customer_id = @customer_id);

    SELECT n.id, n.kind, n.ref_date, s.id AS subscription_id, s.status, s.access, s.renews_on, s.billing_cycle,
           s.amount AS subscription_amount, p.name AS plan_name, cu.id AS customer_id, cu.name AS customer_name,
           COALESCE(NULLIF(LTRIM(RTRIM(cu.billing_email)), N''), cu.contact_email) AS to_address, cu.contact_name AS to_name,
           i.id AS invoice_id, i.number AS invoice_number, i.amount AS invoice_amount, i.due_date,
           i.period_start, i.period_end
    FROM @sent x
    JOIN [plat].[billing_notice] n ON n.id = x.id
    JOIN [plat].[subscription] s ON s.id = n.subscription_id
    JOIN [plat].[customer] cu ON cu.id = s.customer_id
    LEFT JOIN [plat].[plan] p ON p.id = s.plan_id
    LEFT JOIN [plat].[invoice] i ON i.id = n.invoice_id
    -- A notice whose organisation was suspended or cancelled since it was recorded is marked sent, not mailed.
    WHERE cu.status = N'active'
    ORDER BY n.id;
END
GO

-- Staff: a trial gets @days more (from its end, or from today when it has already ended). Its unpaid renewal
-- invoice is voided (a new one is issued before the new end) and access is restored.
CREATE OR ALTER PROCEDURE [plat].[usp_subscription_trial_extend]
    @actor_id    BIGINT = NULL,
    @id          BIGINT,
    @days        INT,
    @row_version BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @today DATE = CONVERT(DATE, SYSUTCDATETIME());
    DECLARE @status NVARCHAR(20), @renews DATE, @customer BIGINT;
    SELECT @status = status, @renews = renews_on, @customer = customer_id FROM [plat].[subscription] WHERE id = @id;
    IF @status IS NULL
        THROW 50404, N'Subscription not found', 1;
    IF @status NOT IN (N'trial', N'expired')
        THROW 50409, N'days|NOT_A_TRIAL|Only a trial, running or ended, can be extended.', 1;
    IF @days IS NULL OR @days < 1 OR @days > 90
        THROW 50400, N'days|Give 1 to 90 days.', 1;
    DECLARE @new_end DATE = DATEADD(DAY, @days, CASE WHEN @renews IS NULL OR @renews < @today THEN @today ELSE @renews END);

    BEGIN TRAN;
        UPDATE [plat].[subscription]
        SET status = N'trial', renews_on = @new_end, access = N'full', access_since = NULL,
            updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this subscription. Reload and try again', 1;
        UPDATE [plat].[invoice]
        SET status = N'void', updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE subscription_id = @id AND source = N'renewal' AND status = N'issued';
        DECLARE @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id);
        DECLARE @detail NVARCHAR(1000) = (SELECT LEFT(CONCAT(name, N' · ', @days, N' days · until ',
                                                             CONVERT(NVARCHAR(10), @new_end, 23)), 1000)
                                          FROM [plat].[customer] WHERE id = @customer);
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = N'trial_extended',
             @entity_type = N'subscription', @entity_ref = @ref, @detail = @detail;
    COMMIT;
    EXEC [plat].[usp_subscription_get] @id = @id;
END
GO

-- ---------------------------------------------------------------- the customer's own billing (Settings)

-- The organisation of a company: its billing details, live subscription and what it owes. No row when the
-- company belongs to no organisation.
CREATE OR ALTER PROCEDURE [plat].[usp_billing_overview]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CONVERT(DATE, SYSUTCDATETIME());
    SELECT cu.id AS customer_id, cu.name AS customer_name, cu.contact_email,
           cu.billing_name, cu.billing_email, cu.billing_address, cu.tax_number,
           s.id AS subscription_id, s.status, s.access, s.access_since, s.billing_cycle, s.amount, s.start_date,
           s.renews_on, p.name AS plan_name,
           o.open_count, o.open_amount, n.id AS next_invoice_id, n.number AS next_invoice_number,
           n.amount AS next_invoice_amount, n.due_date AS next_invoice_due,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [plat].[payment_submission] x
                                  WHERE x.invoice_id = n.id AND x.status = N'pending') THEN 1 ELSE 0 END AS BIT)
               AS next_invoice_proof_pending
    FROM [plat].[customer_company] cc
    JOIN [plat].[customer] cu ON cu.id = cc.customer_id
    OUTER APPLY (SELECT TOP 1 x.* FROM [plat].[subscription] x
                 WHERE x.customer_id = cu.id AND x.status <> N'cancelled' ORDER BY x.id DESC) s
    LEFT JOIN [plat].[plan] p ON p.id = s.plan_id
    OUTER APPLY (SELECT COUNT(*) AS open_count, ISNULL(SUM(i.amount), 0) AS open_amount FROM [plat].[invoice] i
                 WHERE i.customer_id = cu.id AND i.status = N'issued') o
    OUTER APPLY (SELECT TOP 1 i.id, i.number, i.amount, i.due_date FROM [plat].[invoice] i
                 WHERE i.customer_id = cu.id AND i.status = N'issued' ORDER BY i.due_date, i.id) n
    WHERE cc.company_id = @company_id;
END
GO

-- Result set 1: total. Result set 2: the organisation's invoices, newest first, each with its latest payment proof.
CREATE OR ALTER PROCEDURE [plat].[usp_billing_invoice_list]
    @company_id BIGINT,
    @page       INT = 1,
    @page_size  INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CONVERT(DATE, SYSUTCDATETIME());
    DECLARE @customer BIGINT = (SELECT customer_id FROM [plat].[customer_company] WHERE company_id = @company_id);
    SELECT COUNT(*) AS total FROM [plat].[invoice] WHERE customer_id = @customer;
    SELECT i.id, i.number, i.issue_date, i.due_date, i.amount,
           CASE WHEN i.status = N'issued' AND i.due_date < @today THEN N'overdue' ELSE i.status END AS status,
           i.paid_on, i.payment_reference, i.source, i.period_start, i.period_end,
           ps.status AS proof_status, ps.reference AS proof_reference, ps.paid_on AS proof_paid_on,
           ps.review_note AS proof_review_note, ps.created_at AS proof_sent_at
    FROM [plat].[invoice] i
    OUTER APPLY (SELECT TOP 1 x.status, x.reference, x.paid_on, x.review_note, x.created_at
                 FROM [plat].[payment_submission] x WHERE x.invoice_id = i.id ORDER BY x.id DESC) ps
    WHERE i.customer_id = @customer
    ORDER BY i.issue_date DESC, i.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- One invoice of the organisation, with what it is made out to (for the printed invoice). 404 for another
-- organisation's.
CREATE OR ALTER PROCEDURE [plat].[usp_billing_invoice_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [plat].[invoice] i
                   JOIN [plat].[customer_company] cc ON cc.customer_id = i.customer_id AND cc.company_id = @company_id
                   WHERE i.id = @id)
        THROW 50404, N'Invoice not found', 1;
    DECLARE @today DATE = CONVERT(DATE, SYSUTCDATETIME());
    SELECT i.id, i.number, i.issue_date, i.due_date, i.amount,
           CASE WHEN i.status = N'issued' AND i.due_date < @today THEN N'overdue' ELSE i.status END AS status,
           i.paid_on, i.payment_reference, i.source, i.period_start, i.period_end,
           ps.status AS proof_status, ps.reference AS proof_reference, ps.paid_on AS proof_paid_on,
           ps.review_note AS proof_review_note, ps.created_at AS proof_sent_at,
           COALESCE(NULLIF(LTRIM(RTRIM(cu.billing_name)), N''), cu.name) AS bill_to_name,
           COALESCE(NULLIF(LTRIM(RTRIM(cu.billing_email)), N''), cu.contact_email) AS bill_to_email,
           cu.billing_address AS bill_to_address, cu.tax_number AS bill_to_tax_number,
           p.name AS plan_name, s.billing_cycle
    FROM [plat].[invoice] i
    JOIN [plat].[customer] cu ON cu.id = i.customer_id
    LEFT JOIN [plat].[subscription] s ON s.id = i.subscription_id
    LEFT JOIN [plat].[plan] p ON p.id = s.plan_id
    OUTER APPLY (SELECT TOP 1 x.status, x.reference, x.paid_on, x.review_note, x.created_at
                 FROM [plat].[payment_submission] x WHERE x.invoice_id = i.id ORDER BY x.id DESC) ps
    WHERE i.id = @id;
END
GO

-- What the organisation's invoices are made out to, and where billing e-mails go.
CREATE OR ALTER PROCEDURE [plat].[usp_billing_details_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @billing_name    NVARCHAR(200) = NULL,
    @billing_email   NVARCHAR(254) = NULL,
    @billing_address NVARCHAR(500) = NULL,
    @tax_number      NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @customer BIGINT = (SELECT customer_id FROM [plat].[customer_company] WHERE company_id = @company_id);
    IF @customer IS NULL
        THROW 50404, N'This organisation has no hRango account to bill', 1;
    SELECT @billing_name = NULLIF(LTRIM(RTRIM(@billing_name)), N''), @billing_email = NULLIF(LTRIM(RTRIM(@billing_email)), N''),
           @billing_address = NULLIF(LTRIM(RTRIM(@billing_address)), N''), @tax_number = NULLIF(LTRIM(RTRIM(@tax_number)), N'');
    IF @billing_email IS NOT NULL AND @billing_email NOT LIKE N'%_@_%._%'
        THROW 50400, N'billingEmail|Enter an e-mail address such as accounts@company.com.', 1;
    UPDATE [plat].[customer]
    SET billing_name = @billing_name, billing_email = @billing_email, billing_address = @billing_address,
        tax_number = @tax_number, updated_at = SYSUTCDATETIME()
    WHERE id = @customer;
    EXEC [plat].[usp_billing_overview] @company_id = @company_id;
END
GO

-- A payment proof with its invoice, organisation and who sent it (staff list rows, and after a change).
CREATE OR ALTER PROCEDURE [plat].[usp_payment_submission_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ps.id, ps.invoice_id, i.number AS invoice_number, i.amount AS invoice_amount, i.due_date AS invoice_due,
           ps.customer_id, cu.name AS customer_name, ps.company_id, ps.method, ps.reference, ps.paid_on, ps.amount,
           ps.file_id, sf.name AS file_name, ps.note, ps.status, ps.review_note, ps.reviewed_at,
           st.display_name AS reviewed_by_name,
           ps.created_at, COALESCE(u.display_name, u.email) AS submitted_by_name, u.email AS submitted_by_email,
           COALESCE(NULLIF(LTRIM(RTRIM(cu.billing_email)), N''), cu.contact_email) AS to_address, cu.contact_name AS to_name,
           ps.row_version
    FROM [plat].[payment_submission] ps
    JOIN [plat].[invoice] i ON i.id = ps.invoice_id
    JOIN [plat].[customer] cu ON cu.id = ps.customer_id
    JOIN [auth].[user_account] u ON u.id = ps.submitted_by
    LEFT JOIN [plat].[staff_account] st ON st.id = ps.reviewed_by
    LEFT JOIN [core].[stored_file] sf ON sf.id = ps.file_id
    WHERE ps.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Payment not found', 1;
END
GO

-- The customer: "we paid this invoice by bank transfer", with the reference and a proof file (an upload of this
-- company). It waits for staff (plat.usp_payment_submission_review); one at a time per invoice.
CREATE OR ALTER PROCEDURE [plat].[usp_payment_submit]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @invoice_id    BIGINT,
    @reference     NVARCHAR(100),
    @paid_on       DATE,
    @amount        DECIMAL(18,2),
    @file_id       BIGINT = NULL,
    @note          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @customer BIGINT, @status NVARCHAR(20);
    SELECT @customer = i.customer_id, @status = i.status
    FROM [plat].[invoice] i
    JOIN [plat].[customer_company] cc ON cc.customer_id = i.customer_id AND cc.company_id = @company_id
    WHERE i.id = @invoice_id;
    IF @customer IS NULL
        THROW 50404, N'Invoice not found', 1;
    IF @status <> N'issued'
        THROW 50409, N'invoiceId|INVOICE_CLOSED|This invoice is already paid or void.', 1;
    IF EXISTS (SELECT 1 FROM [plat].[payment_submission] WHERE invoice_id = @invoice_id AND status = N'pending')
        THROW 50409, N'invoiceId|PAYMENT_PENDING|A payment for this invoice is already waiting to be confirmed.', 1;
    SET @reference = NULLIF(LTRIM(RTRIM(@reference)), N'');
    IF @reference IS NULL
        THROW 50400, N'reference|Enter the transfer''s reference (the bank''s transaction or slip number).', 1;
    IF @paid_on IS NULL OR @paid_on > DATEADD(DAY, 1, CONVERT(DATE, SYSUTCDATETIME()))
        THROW 50400, N'paidOn|Enter the day you paid; it cannot be in the future.', 1;
    IF @amount IS NULL OR @amount <= 0
        THROW 50400, N'amount|Enter the amount you paid.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    INSERT [plat].[payment_submission] (invoice_id, customer_id, company_id, submitted_by, method, reference, paid_on,
                                        amount, file_id, note, status)
    VALUES (@invoice_id, @customer, @company_id, @actor_user_id, N'bank_transfer', @reference, @paid_on, @amount,
            @file_id, NULLIF(LTRIM(RTRIM(@note)), N''), N'pending');
    DECLARE @id BIGINT = SCOPE_IDENTITY();
    EXEC [plat].[usp_payment_submission_get] @id = @id;
END
GO

-- Staff: result set 1 total, 2 the page (pending first by default: @status pending).
CREATE OR ALTER PROCEDURE [plat].[usp_payment_submission_list]
    @status    NVARCHAR(20) = NULL,
    @page      INT = 1,
    @page_size INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS total FROM [plat].[payment_submission] WHERE @status IS NULL OR status = @status;
    SELECT ps.id, ps.invoice_id, i.number AS invoice_number, i.amount AS invoice_amount, i.due_date AS invoice_due,
           ps.customer_id, cu.name AS customer_name, ps.company_id, ps.method, ps.reference, ps.paid_on, ps.amount,
           ps.file_id, sf.name AS file_name, ps.note, ps.status, ps.review_note, ps.reviewed_at,
           st.display_name AS reviewed_by_name,
           ps.created_at, COALESCE(u.display_name, u.email) AS submitted_by_name, u.email AS submitted_by_email,
           COALESCE(NULLIF(LTRIM(RTRIM(cu.billing_email)), N''), cu.contact_email) AS to_address, cu.contact_name AS to_name,
           ps.row_version
    FROM [plat].[payment_submission] ps
    JOIN [plat].[invoice] i ON i.id = ps.invoice_id
    JOIN [plat].[customer] cu ON cu.id = ps.customer_id
    JOIN [auth].[user_account] u ON u.id = ps.submitted_by
    LEFT JOIN [plat].[staff_account] st ON st.id = ps.reviewed_by
    LEFT JOIN [core].[stored_file] sf ON sf.id = ps.file_id
    WHERE @status IS NULL OR ps.status = @status
    ORDER BY CASE WHEN ps.status = N'pending' THEN 0 ELSE 1 END, ps.created_at DESC, ps.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Staff: accept a payment proof (its invoice becomes paid, with the proof's date and reference, and the
-- subscription moves on) or reject it with a reason the customer is told.
CREATE OR ALTER PROCEDURE [plat].[usp_payment_submission_review]
    @actor_id    BIGINT = NULL,
    @id          BIGINT,
    @decision    NVARCHAR(20),
    @note        NVARCHAR(500) = NULL,
    @row_version BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @decision NOT IN (N'accept', N'reject')
        THROW 50400, N'decision|Choose accept or reject.', 1;
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');
    IF @decision = N'reject' AND @note IS NULL
        THROW 50400, N'note|Say why, so the organisation knows what to fix.', 1;
    DECLARE @status NVARCHAR(20), @invoice BIGINT, @paid_on DATE, @reference NVARCHAR(100), @customer BIGINT;
    SELECT @status = status, @invoice = invoice_id, @paid_on = paid_on, @reference = reference, @customer = customer_id
    FROM [plat].[payment_submission] WHERE id = @id;
    IF @status IS NULL
        THROW 50404, N'Payment not found', 1;
    IF @status <> N'pending'
        THROW 50409, N'decision|PAYMENT_DECIDED|This payment has already been accepted or rejected.', 1;
    IF @decision = N'accept' AND (SELECT status FROM [plat].[invoice] WHERE id = @invoice) <> N'issued'
        THROW 50409, N'decision|INVOICE_CLOSED|Its invoice is already paid or void. Reject this payment instead.', 1;

    DECLARE @ref NVARCHAR(100) = CONVERT(NVARCHAR(30), @id);
    DECLARE @detail NVARCHAR(1000) = (SELECT LEFT(CONCAT(i.number, N' · ', cu.name, N' · ', @reference), 1000)
                                      FROM [plat].[invoice] i JOIN [plat].[customer] cu ON cu.id = i.customer_id
                                      WHERE i.id = @invoice);
    BEGIN TRAN;
        UPDATE [plat].[payment_submission]
        SET status = CASE WHEN @decision = N'accept' THEN N'accepted' ELSE N'rejected' END, review_note = @note,
            reviewed_by = @actor_id, reviewed_at = SYSUTCDATETIME()
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this payment. Reload and try again', 1;
        IF @decision = N'accept'
        BEGIN
            UPDATE [plat].[invoice]
            SET status = N'paid', paid_on = @paid_on, payment_reference = @reference,
                updated_at = SYSUTCDATETIME(), updated_by = @actor_id
            WHERE id = @invoice;
            EXEC [plat].[usp_invoice_pay_apply] @invoice_id = @invoice;
        END
        DECLARE @action NVARCHAR(50) = CASE WHEN @decision = N'accept' THEN N'payment_accepted' ELSE N'payment_rejected' END;
        EXEC [plat].[usp_staff_audit_add] @staff_id = @actor_id, @action = @action,
             @entity_type = N'invoice', @entity_ref = @ref, @detail = @detail;
    COMMIT;
    EXEC [plat].[usp_payment_submission_get] @id = @id;
END
GO

-- Who an invoice's e-mails go to and what they say (a payment receipt).
CREATE OR ALTER PROCEDURE [plat].[usp_invoice_mail_target]
    @invoice_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.id AS invoice_id, i.number AS invoice_number, i.amount AS invoice_amount, i.due_date, i.paid_on,
           i.period_start, i.period_end, cu.id AS customer_id, cu.name AS customer_name,
           COALESCE(NULLIF(LTRIM(RTRIM(cu.billing_email)), N''), cu.contact_email) AS to_address, cu.contact_name AS to_name,
           s.status, s.renews_on, p.name AS plan_name
    FROM [plat].[invoice] i
    JOIN [plat].[customer] cu ON cu.id = i.customer_id
    LEFT JOIN [plat].[subscription] s ON s.id = i.subscription_id
    LEFT JOIN [plat].[plan] p ON p.id = s.plan_id
    WHERE i.id = @invoice_id;
END
GO
