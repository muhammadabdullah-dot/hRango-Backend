-- Payroll e-mails go out through the mail sender (core.mail_message, app/core/mail.py): each pay.mail_outbox row
-- (one person's close e-mail or salary revision letter) names the message queued for it, so the worker's result
-- (sent / failed) is copied back to the row and to the run's close e-mail state. No FK: core may clear old
-- messages on its own. Checks first, like 0002, so it also runs on a baseline rebuilt from the ERD.

IF COL_LENGTH(N'pay.mail_outbox', N'mail_message_id') IS NULL
    ALTER TABLE [pay].[mail_outbox] ADD [mail_message_id] BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'pay.mail_outbox') AND name = N'IX_mail_outbox_mail_message_id')
    CREATE NONCLUSTERED INDEX [IX_mail_outbox_mail_message_id] ON [pay].[mail_outbox] ([mail_message_id]);
GO
