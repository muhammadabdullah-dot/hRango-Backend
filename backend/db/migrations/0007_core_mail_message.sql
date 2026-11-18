-- Outgoing e-mail (roadmap 1.4): one row per message, sent by the worker (app/core/mail.py) and retried
-- after failures. A message's body (which can hold a password-reset or invitation link) is cleared once it
-- is sent or given up on; the subject, address and outcome stay for the record. Checks first, like 0002,
-- so it also runs on a baseline rebuilt from the ERD.

IF OBJECT_ID(N'core.mail_message', N'U') IS NULL
    CREATE TABLE [core].[mail_message] (
        [id] BIGINT IDENTITY(1,1) NOT NULL,
        [company_id] BIGINT NULL,
        [kind] NVARCHAR(50) NOT NULL,
        [to_address] NVARCHAR(254) NOT NULL,
        [to_name] NVARCHAR(200) NULL,
        [subject] NVARCHAR(300) NOT NULL,
        [body_html] NVARCHAR(MAX) NULL,
        [body_text] NVARCHAR(MAX) NULL,
        [status] NVARCHAR(20) NOT NULL,
        [attempts] INT NOT NULL CONSTRAINT [DF_mail_message_attempts] DEFAULT 0,
        [next_attempt_at] DATETIME2(0) NULL,
        [last_attempt_at] DATETIME2(0) NULL,
        [sent_at] DATETIME2(0) NULL,
        [error] NVARCHAR(1000) NULL,
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_mail_message_created_at] DEFAULT SYSUTCDATETIME(),
        [created_by] BIGINT NULL,
        [updated_at] DATETIME2(0) NULL,
        [updated_by] BIGINT NULL,
        [row_version] ROWVERSION,
        CONSTRAINT [PK_mail_message] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [FK_mail_message_company_id] FOREIGN KEY ([company_id]) REFERENCES [org].[company] ([id])
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'core.mail_message') AND name = N'IX_mail_message_status_next_attempt_at')
    CREATE NONCLUSTERED INDEX [IX_mail_message_status_next_attempt_at] ON [core].[mail_message] ([status], [next_attempt_at]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'core.mail_message') AND name = N'IX_mail_message_company_id')
    CREATE NONCLUSTERED INDEX [IX_mail_message_company_id] ON [core].[mail_message] ([company_id]);
GO
