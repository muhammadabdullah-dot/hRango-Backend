-- Billing without a payment gateway (roadmap: billing phase 1). Subscriptions renew, trials end and late payments
-- restrict access by themselves (plat.usp_billing_run, nightly), customers see their invoices and send proof of a
-- bank transfer, and staff confirm it. Checks first, like 0002, so it also runs on a baseline rebuilt from the ERD.
--   subscription.access    full, read_only (view and export only) or locked (only the Account Owner, to pay)
--   invoice.source         manual (issued by staff) or renewal (issued for a subscription period)
--   customer.billing_*     what an invoice is made out to, and where billing e-mails go
--   payment_submission     a customer's bank transfer proof, pending until staff accept or reject it
--   billing_notice         each billing e-mail sent, so none is sent twice

IF COL_LENGTH(N'plat.subscription', N'access') IS NULL
    ALTER TABLE [plat].[subscription] ADD [access] NVARCHAR(20) NOT NULL
        CONSTRAINT [DF_subscription_access] DEFAULT N'full';
GO
IF COL_LENGTH(N'plat.subscription', N'access_since') IS NULL
    ALTER TABLE [plat].[subscription] ADD [access_since] DATE NULL;
GO

IF COL_LENGTH(N'plat.invoice', N'source') IS NULL
    ALTER TABLE [plat].[invoice] ADD [source] NVARCHAR(20) NOT NULL
        CONSTRAINT [DF_invoice_source] DEFAULT N'manual';
GO
IF COL_LENGTH(N'plat.invoice', N'period_start') IS NULL
    ALTER TABLE [plat].[invoice] ADD [period_start] DATE NULL;
GO
IF COL_LENGTH(N'plat.invoice', N'period_end') IS NULL
    ALTER TABLE [plat].[invoice] ADD [period_end] DATE NULL;
GO
-- One renewal invoice per subscription period (a voided one does not count, so a period can be billed again).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_invoice_subscription_period'
               AND object_id = OBJECT_ID(N'plat.invoice'))
    CREATE UNIQUE INDEX [UX_invoice_subscription_period] ON [plat].[invoice] ([subscription_id], [period_start])
        WHERE [source] = N'renewal' AND [status] <> N'void';
GO

IF COL_LENGTH(N'plat.customer', N'billing_name') IS NULL
    ALTER TABLE [plat].[customer] ADD [billing_name] NVARCHAR(200) NULL;
GO
IF COL_LENGTH(N'plat.customer', N'billing_email') IS NULL
    ALTER TABLE [plat].[customer] ADD [billing_email] NVARCHAR(254) NULL;
GO
IF COL_LENGTH(N'plat.customer', N'billing_address') IS NULL
    ALTER TABLE [plat].[customer] ADD [billing_address] NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'plat.customer', N'tax_number') IS NULL
    ALTER TABLE [plat].[customer] ADD [tax_number] NVARCHAR(50) NULL;
GO

IF OBJECT_ID(N'plat.payment_submission') IS NULL
    CREATE TABLE [plat].[payment_submission] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [invoice_id] BIGINT NOT NULL,
        [customer_id] BIGINT NOT NULL,
        [company_id] BIGINT NOT NULL,
        [submitted_by] BIGINT NOT NULL,
        [method] NVARCHAR(30) NOT NULL,
        [reference] NVARCHAR(100) NOT NULL,
        [paid_on] DATE NOT NULL,
        [amount] DECIMAL(18,2) NOT NULL,
        [file_id] BIGINT NULL,
        [note] NVARCHAR(500) NULL,
        [status] NVARCHAR(20) NOT NULL,
        [review_note] NVARCHAR(500) NULL,
        [reviewed_by] BIGINT NULL,
        [reviewed_at] DATETIME2(0) NULL,
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_payment_submission_created_at] DEFAULT SYSUTCDATETIME(),
        [row_version] ROWVERSION,
        CONSTRAINT [PK_payment_submission] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [FK_payment_submission_invoice] FOREIGN KEY ([invoice_id]) REFERENCES [plat].[invoice] ([id]),
        CONSTRAINT [FK_payment_submission_customer] FOREIGN KEY ([customer_id]) REFERENCES [plat].[customer] ([id]),
        CONSTRAINT [FK_payment_submission_company] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id]),
        CONSTRAINT [FK_payment_submission_user] FOREIGN KEY ([submitted_by]) REFERENCES [auth].[user_account] ([id]),
        -- The foreign key also keeps the proof out of the nightly clean-up of unused uploads (core.usp_file_purge).
        CONSTRAINT [FK_payment_submission_file] FOREIGN KEY ([file_id]) REFERENCES [core].[stored_file] ([id]),
        CONSTRAINT [FK_payment_submission_staff] FOREIGN KEY ([reviewed_by]) REFERENCES [plat].[staff_account] ([id])
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_payment_submission_status'
               AND object_id = OBJECT_ID(N'plat.payment_submission'))
    CREATE INDEX [IX_payment_submission_status] ON [plat].[payment_submission] ([status], [created_at]);
GO
-- At most one proof waiting per invoice.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_payment_submission_pending'
               AND object_id = OBJECT_ID(N'plat.payment_submission'))
    CREATE UNIQUE INDEX [UX_payment_submission_pending] ON [plat].[payment_submission] ([invoice_id])
        WHERE [status] = N'pending';
GO

IF OBJECT_ID(N'plat.billing_notice') IS NULL
    CREATE TABLE [plat].[billing_notice] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [subscription_id] BIGINT NOT NULL,
        [invoice_id] BIGINT NULL,
        [kind] NVARCHAR(40) NOT NULL,
        [ref_date] DATE NOT NULL,
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_billing_notice_created_at] DEFAULT SYSUTCDATETIME(),
        -- Set when the e-mail is handed to the mail queue (plat.usp_billing_run returns the ones still unset).
        [mailed_at] DATETIME2(0) NULL,
        CONSTRAINT [PK_billing_notice] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [FK_billing_notice_subscription] FOREIGN KEY ([subscription_id]) REFERENCES [plat].[subscription] ([id]),
        CONSTRAINT [FK_billing_notice_invoice] FOREIGN KEY ([invoice_id]) REFERENCES [plat].[invoice] ([id]),
        CONSTRAINT [UQ_billing_notice] UNIQUE ([subscription_id], [kind], [ref_date])
    );
GO
