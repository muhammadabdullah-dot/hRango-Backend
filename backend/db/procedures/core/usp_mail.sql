-- Outgoing e-mail (core.mail_message), sent by the worker in app/core/mail.py.
-- status: queued (waiting or being retried), sent, failed (gave up), disabled (mail is switched off; kept
-- so the screens can say what would have gone out).

CREATE OR ALTER PROCEDURE [core].[usp_mail_queue]
    @company_id BIGINT = NULL,
    @kind       NVARCHAR(50),
    @to_address NVARCHAR(254),
    @to_name    NVARCHAR(200) = NULL,
    @subject    NVARCHAR(300),
    @body_html  NVARCHAR(MAX),
    @body_text  NVARCHAR(MAX) = NULL,
    @status     NVARCHAR(20) = N'queued',
    @actor_id   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @to_address = LTRIM(RTRIM(@to_address));
    IF @to_address IS NULL OR @to_address NOT LIKE N'%_@_%._%'
        THROW 50400, N'email|Enter a valid email address.', 1;
    IF @status NOT IN (N'queued', N'disabled')
        THROW 50400, N'status|A message is queued or disabled.', 1;
    INSERT [core].[mail_message] (company_id, kind, to_address, to_name, subject, body_html, body_text, status,
                                  next_attempt_at, created_by)
    VALUES (@company_id, @kind, @to_address, @to_name, LEFT(@subject, 300),
            CASE WHEN @status = N'queued' THEN @body_html END, CASE WHEN @status = N'queued' THEN @body_text END,
            @status, CASE WHEN @status = N'queued' THEN SYSUTCDATETIME() END, @actor_id);
    SELECT SCOPE_IDENTITY() AS id, @status AS status;
END
GO

-- The worker takes due messages. Each is leased for @lease_seconds (its next attempt is pushed out), so
-- several workers never send the same message twice at once.
CREATE OR ALTER PROCEDURE [core].[usp_mail_due]
    @batch         INT = 20,
    @lease_seconds INT = 300
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @taken TABLE (id BIGINT PRIMARY KEY);
    UPDATE TOP (@batch) m
    SET next_attempt_at = DATEADD(SECOND, @lease_seconds, @now), last_attempt_at = @now, attempts = m.attempts + 1
    OUTPUT inserted.id INTO @taken
    FROM [core].[mail_message] m WITH (ROWLOCK, UPDLOCK, READPAST)
    WHERE m.status = N'queued' AND m.next_attempt_at <= @now
      -- A suspended or cancelled organisation's mail waits until it is active again.
      AND NOT EXISTS (SELECT 1 FROM [plat].[customer_company] cc
                      JOIN [plat].[customer] c ON c.id = cc.customer_id AND c.status <> N'active'
                      WHERE cc.company_id = m.company_id);
    SELECT m.id, m.company_id, m.kind, m.to_address, m.to_name, m.subject, m.body_html, m.body_text, m.attempts
    FROM @taken t JOIN [core].[mail_message] m ON m.id = t.id
    ORDER BY m.id;
END
GO

-- What happened to one send. A failure is retried after 1, 5, 15 and 60 minutes, then 3 hours; after 6
-- attempts the message is marked failed. Sent or failed, the body is cleared.
CREATE OR ALTER PROCEDURE [core].[usp_mail_result]
    @id    BIGINT,
    @ok    BIT,
    @error NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @attempts INT = (SELECT attempts FROM [core].[mail_message] WHERE id = @id);
    IF @ok = 1
        UPDATE [core].[mail_message]
        SET status = N'sent', sent_at = @now, error = NULL, next_attempt_at = NULL, body_html = NULL, body_text = NULL,
            updated_at = @now
        WHERE id = @id;
    ELSE IF @attempts >= 6
        UPDATE [core].[mail_message]
        SET status = N'failed', error = LEFT(@error, 1000), next_attempt_at = NULL, body_html = NULL, body_text = NULL,
            updated_at = @now
        WHERE id = @id;
    ELSE
        UPDATE [core].[mail_message]
        SET error = LEFT(@error, 1000), updated_at = @now,
            next_attempt_at = DATEADD(MINUTE, CASE @attempts WHEN 1 THEN 1 WHEN 2 THEN 5 WHEN 3 THEN 15 WHEN 4 THEN 60 ELSE 180 END, @now)
        WHERE id = @id;
END
GO

-- One message, for the tests and support: never the body once it has gone.
CREATE OR ALTER PROCEDURE [core].[usp_mail_get]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, company_id, kind, to_address, to_name, subject, status, attempts, next_attempt_at, sent_at, error,
           body_html, body_text, created_at
    FROM [core].[mail_message] WHERE id = @id;
END
GO
