-- Payroll e-mails: the close e-mail of a monthly run and the salary revision letter, one pay.mail_outbox row
-- per person. With mail off (app.core.mail.enabled() false) a row is recorded 'disabled' and nothing is sent.
-- With mail on it is recorded 'queued'; the API (app/services/payroll_mail_service.py) then writes each
-- person's own message and queues it in core.mail_message (pay.usp_mail_outbox_hand_off links the two), and
-- the mail worker's result for that message is copied back (pay.usp_mail_outbox_result): the row becomes
-- 'sent' or 'failed', and the run's pay.payroll_close_email 'sent' (everyone) or 'failed' (anyone failed)
-- once none of its rows is still queued.

-- The close e-mail of a monthly run, before or after closing: what it is about and who gets it.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_close_email_preview]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = N'monthly')
        THROW 50404, N'Payroll not found', 1;

    SELECT p.id, p.code, p.name, p.payroll_month, p.currency, p.status, c.name AS company_name,
           ISNULL(ce.recipient_count,
                  (SELECT COUNT(*) FROM [pay].[payslip] ps
                   WHERE ps.payroll_id = p.id AND ps.status IN (N'ready', N'released')
                     AND [pay].[fn_employee_email](ps.employee_id) IS NOT NULL)) AS recipient_count
    FROM [pay].[payroll] p
    JOIN [org].[company] c ON c.id = p.company_id
    LEFT JOIN [pay].[payroll_close_email] ce ON ce.payroll_id = p.id
    WHERE p.id = @id;
END
GO

-- Result set 1: the close e-mail's state ('none' before the run is closed). Result set 2: who it failed for.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_close_email_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = N'monthly')
        THROW 50404, N'Payroll not found', 1;

    SELECT ISNULL(ce.status, N'none') AS status, ce.queued_at, ce.sent_at, ISNULL(ce.recipient_count, 0) AS recipient_count,
           ISNULL(o.sent_count, 0) AS sent_count, ISNULL(o.failed_count, 0) AS failed_count
    FROM (SELECT @id AS payroll_id) x
    LEFT JOIN [pay].[payroll_close_email] ce ON ce.payroll_id = x.payroll_id
    OUTER APPLY (SELECT SUM(CASE WHEN m.status = N'sent' THEN 1 ELSE 0 END) AS sent_count,
                        SUM(CASE WHEN m.status = N'failed' THEN 1 ELSE 0 END) AS failed_count
                 FROM [pay].[mail_outbox] m
                 WHERE m.company_id = @company_id AND m.entity_type = N'pay.payroll' AND m.entity_id = x.payroll_id) o;

    SELECT m.employee_id, NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N'') AS employee_name, m.error
    FROM [pay].[mail_outbox] m
    JOIN [hr].[employee] e ON e.id = m.employee_id
    WHERE m.company_id = @company_id AND m.entity_type = N'pay.payroll' AND m.entity_id = @id AND m.status = N'failed'
    ORDER BY e.first_name, e.last_name;
END
GO

-- The salary revision letter: the revision, the person's address and the last e-mail's state.
CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_email_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] s
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
                   WHERE s.id = @id)
        THROW 50404, N'Salary revision not found', 1;

    SELECT s.id, s.employee_id, e.code AS employee_code, NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N'') AS employee_name,
           s.effective_date, s.previous_amount, s.amount, s.change_type, s.change_value, s.source,
           [pay].[fn_employee_email](s.employee_id) AS to_address, c.name AS company_name, c.currency,
           ISNULL(m.status, N'none') AS email_status, m.sent_at AS emailed_at, s.row_version
    FROM [hr].[employee_salary] s
    JOIN [hr].[employee] e ON e.id = s.employee_id
    JOIN [org].[company] c ON c.id = e.company_id
    OUTER APPLY (SELECT TOP 1 o.status, o.sent_at FROM [pay].[mail_outbox] o
                 WHERE o.company_id = @company_id AND o.entity_type = N'hr.employee_salary' AND o.entity_id = s.id
                 ORDER BY o.id DESC) m
    WHERE s.id = @id;
END
GO

-- Sends (queues) the salary revision letter, or records that mail is off. @row_version is the revision's.
-- Returns the new state: status, sent_at.
CREATE OR ALTER PROCEDURE [pay].[usp_salary_revision_email_send]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8),
    @mail_enabled    BIT = 0,
    @subject         NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @emp BIGINT;
    SELECT @rv = s.row_version, @emp = s.employee_id
    FROM [hr].[employee_salary] s
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = s.employee_id
    WHERE s.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Salary revision not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this salary revision. Reload it and try again', 1;
    DECLARE @to NVARCHAR(254) = [pay].[fn_employee_email](@emp);
    IF @to IS NULL AND @mail_enabled = 1
        THROW 50400, N'to|EMAIL_MISSING|This employee has no e-mail address.', 1;
    IF @mail_enabled = 1 AND EXISTS (SELECT 1 FROM [pay].[mail_outbox] WHERE company_id = @company_id
                                     AND entity_type = N'hr.employee_salary' AND entity_id = @id AND status = N'queued')
        THROW 50409, N'status|EMAIL_QUEUED|This letter is already waiting to be sent', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @status NVARCHAR(30) = CASE WHEN @mail_enabled = 1 THEN N'queued' ELSE N'disabled' END;
    BEGIN TRAN;
        INSERT [pay].[mail_outbox] (company_id, entity_type, entity_id, employee_id, to_address, subject, status, queued_at, created_by)
        VALUES (@company_id, N'hr.employee_salary', @id, @emp, @to, @subject, @status, CASE WHEN @mail_enabled = 1 THEN @now END,
                @actor_user_id);
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'hr.employee_salary', @id, N'email', NULL, @status, N'send', @actor_user_id, @now);
    COMMIT;

    SELECT @status AS status, CAST(NULL AS DATETIME2(0)) AS sent_at;
END
GO

-- Rows of one close e-mail or letter still to hand to the mail sender: queued, no message queued for them yet.
CREATE OR ALTER PROCEDURE [pay].[usp_mail_outbox_pending]
    @company_id  BIGINT,
    @entity_type NVARCHAR(50),
    @entity_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.id, o.entity_type, o.entity_id, o.employee_id, o.to_address, o.subject,
           NULLIF(CONCAT_WS(N' ', e.first_name, e.last_name), N'') AS employee_name
    FROM [pay].[mail_outbox] o
    JOIN [hr].[employee] e ON e.id = o.employee_id
    WHERE o.company_id = @company_id AND o.entity_type = @entity_type AND o.entity_id = @entity_id
      AND o.status = N'queued' AND o.mail_message_id IS NULL
    ORDER BY o.id;
END
GO

-- A closed run's close e-mail state from its rows: 'queued' while any row waits, then 'failed' when anyone's
-- failed, else 'sent' (sent_at: the last one sent). A run recorded 'disabled' (mail off) stays so.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_close_email_refresh]
    @payroll_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @queued INT, @sent INT, @failed INT, @last DATETIME2(0);
    SELECT @queued = ISNULL(SUM(CASE WHEN status = N'queued' THEN 1 ELSE 0 END), 0),
           @sent = ISNULL(SUM(CASE WHEN status = N'sent' THEN 1 ELSE 0 END), 0),
           @failed = ISNULL(SUM(CASE WHEN status = N'failed' THEN 1 ELSE 0 END), 0), @last = MAX(sent_at)
    FROM [pay].[mail_outbox] WHERE entity_type = N'pay.payroll' AND entity_id = @payroll_id;
    UPDATE [pay].[payroll_close_email]
    SET status = CASE WHEN @queued > 0 THEN N'queued' WHEN @failed > 0 THEN N'failed' ELSE N'sent' END,
        sent_at = CASE WHEN @queued = 0 AND @sent > 0 THEN @last END, updated_at = SYSUTCDATETIME()
    WHERE payroll_id = @payroll_id AND status IN (N'queued', N'sent', N'failed');
END
GO

-- What handing one row to the mail sender gave: the message queued for it (@status 'queued'), mail switched off
-- meanwhile ('disabled'), or refused before it could be queued ('failed' with @error, e.g. a bad address).
CREATE OR ALTER PROCEDURE [pay].[usp_mail_outbox_hand_off]
    @id              BIGINT,
    @mail_message_id BIGINT = NULL,
    @status          NVARCHAR(30),
    @error           NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @type NVARCHAR(50), @entity BIGINT;
    SELECT @type = entity_type, @entity = entity_id FROM [pay].[mail_outbox] WHERE id = @id;
    IF @type IS NULL
        THROW 50404, N'E-mail not found', 1;
    BEGIN TRAN;
        UPDATE [pay].[mail_outbox]
        SET mail_message_id = @mail_message_id,
            status = CASE WHEN @status IN (N'queued', N'disabled') THEN @status ELSE N'failed' END,
            error = CASE WHEN @status IN (N'queued', N'disabled') THEN NULL ELSE LEFT(@error, 1000) END,
            updated_at = SYSUTCDATETIME()
        WHERE id = @id;
        IF @type = N'pay.payroll'
            EXEC [pay].[usp_payroll_close_email_refresh] @payroll_id = @entity;
    COMMIT;
END
GO

-- The mail worker's result for one message (app/core/mail.py calls it after core.usp_mail_result): copied to the
-- row that names it, and to its run's close e-mail. A failure the worker will retry leaves the row 'queued' with
-- the error; after the last attempt it is 'failed'.
CREATE OR ALTER PROCEDURE [pay].[usp_mail_outbox_result]
    @mail_message_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(20), @sent_at DATETIME2(0), @error NVARCHAR(1000);
    SELECT @status = status, @sent_at = sent_at, @error = error FROM [core].[mail_message] WHERE id = @mail_message_id;
    IF @status IS NULL
        RETURN;
    DECLARE @payroll_id BIGINT = (SELECT TOP 1 entity_id FROM [pay].[mail_outbox]
                                  WHERE mail_message_id = @mail_message_id AND entity_type = N'pay.payroll');
    BEGIN TRAN;
        UPDATE [pay].[mail_outbox]
        SET status = CASE @status WHEN N'sent' THEN N'sent' WHEN N'failed' THEN N'failed' ELSE status END,
            sent_at = CASE WHEN @status = N'sent' THEN @sent_at ELSE sent_at END,
            error = CASE WHEN @status = N'sent' THEN NULL ELSE @error END,
            updated_at = SYSUTCDATETIME()
        WHERE mail_message_id = @mail_message_id AND status = N'queued';
        IF @payroll_id IS NOT NULL
            EXEC [pay].[usp_payroll_close_email_refresh] @payroll_id = @payroll_id;
    COMMIT;
END
