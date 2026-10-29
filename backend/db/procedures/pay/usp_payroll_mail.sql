-- Payroll e-mails: the close e-mail of a monthly run and the salary revision letter. Mail is not set up
-- yet (app.core.mail.enabled() is false): requests are recorded with status 'disabled' and nothing is
-- sent. When it is, rows are recorded 'queued' in pay.mail_outbox and the mail sender (not built) marks
-- each one 'sent' or 'failed' and the run's pay.payroll_close_email 'sent' / 'failed'.
-- The subject and body are written by the API (app/services/payroll_mail_service.py) from these rows.

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
