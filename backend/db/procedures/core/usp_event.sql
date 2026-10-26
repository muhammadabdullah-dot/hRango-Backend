-- Events and webhooks. A module publishes an event in the same transaction as its change
-- (core.usp_event_publish); every active webhook of the company that subscribes to the event type
-- gets a delivery row; the worker (app/services/webhook_dispatcher.py) sends them and retries with
-- back-off. Subscriptions: an exact type, "module.*", or "*".

CREATE OR ALTER PROCEDURE [core].[usp_event_publish]
    @company_id  BIGINT,
    @event_type  NVARCHAR(100),
    @entity_type NVARCHAR(50) = NULL,
    @entity_id   BIGINT = NULL,
    @payload     NVARCHAR(MAX) = N'{}'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISJSON(@payload) = 0
        THROW 50400, N'An event payload must be JSON.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @id BIGINT;
    INSERT [core].[outbox_event] (company_id, event_type, entity_type, entity_id, payload, occurred_at)
    VALUES (@company_id, @event_type, @entity_type, @entity_id, @payload, @now);
    SET @id = SCOPE_IDENTITY();

    INSERT [core].[webhook_delivery] (webhook_id, outbox_event_id, status, attempts, next_attempt_at)
    SELECT w.id, @id, N'pending', 0, @now
    FROM [core].[webhook] w
    WHERE w.company_id = @company_id AND w.is_active = 1
      AND EXISTS (SELECT 1 FROM OPENJSON(w.events) j
                  WHERE j.[value] = N'*' OR j.[value] = @event_type
                     OR (RIGHT(j.[value], 2) = N'.*' AND LEFT(@event_type, LEN(j.[value]) - 1) = LEFT(j.[value], LEN(j.[value]) - 1)));
END
GO

-- The worker takes due deliveries. Each is leased for @lease_seconds (its next attempt is pushed
-- out), so several workers never send the same delivery twice at once.
CREATE OR ALTER PROCEDURE [core].[usp_webhook_due]
    @batch         INT = 20,
    @lease_seconds INT = 120
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @taken TABLE (id BIGINT PRIMARY KEY);

    UPDATE TOP (@batch) d
    SET next_attempt_at = DATEADD(SECOND, @lease_seconds, @now), last_attempt_at = @now, attempts = d.attempts + 1
    OUTPUT inserted.id INTO @taken
    FROM [core].[webhook_delivery] d WITH (ROWLOCK, UPDLOCK, READPAST)
    JOIN [core].[webhook] w ON w.id = d.webhook_id AND w.is_active = 1
    WHERE d.status = N'pending' AND d.next_attempt_at <= @now;

    SELECT d.id, d.attempts, w.id AS webhook_id, w.url, w.secret, e.id AS event_id, e.company_id, e.event_type,
           e.entity_type, e.entity_id, e.payload, e.occurred_at
    FROM @taken t
    JOIN [core].[webhook_delivery] d ON d.id = t.id
    JOIN [core].[webhook] w ON w.id = d.webhook_id
    JOIN [core].[outbox_event] e ON e.id = d.outbox_event_id
    ORDER BY e.id;
END
GO

-- What happened to one send. A failure is retried after 1, 5 and 15 minutes, then 1, 3, 6 and 12
-- hours; after 8 attempts the delivery is marked failed (it can be redelivered by hand).
CREATE OR ALTER PROCEDURE [core].[usp_webhook_delivery_result]
    @id            BIGINT,
    @ok            BIT,
    @response_code INT = NULL,
    @response_body NVARCHAR(2000) = NULL,
    @error         NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @attempts INT, @webhook_id BIGINT;
    SELECT @attempts = attempts, @webhook_id = webhook_id FROM [core].[webhook_delivery] WHERE id = @id;
    IF @webhook_id IS NULL
        RETURN;

    BEGIN TRAN;
        UPDATE [core].[webhook_delivery]
        SET status = CASE WHEN @ok = 1 THEN N'delivered' WHEN @attempts >= 8 THEN N'failed' ELSE N'pending' END,
            next_attempt_at = CASE WHEN @ok = 1 OR @attempts >= 8 THEN NULL
                                   ELSE DATEADD(MINUTE, CHOOSE(@attempts, 1, 5, 15, 60, 180, 360, 720, 720), @now) END,
            response_code = @response_code, response_body = LEFT(@response_body, 2000), error = LEFT(@error, 1000),
            updated_at = @now
        WHERE id = @id;

        UPDATE [core].[webhook]
        SET last_delivery_at = @now, last_status_code = @response_code,
            failure_count = CASE WHEN @ok = 1 THEN 0 ELSE failure_count + 1 END
        WHERE id = @webhook_id;
    COMMIT;
END
GO

-- Settings → Integrations → Webhooks.

CREATE OR ALTER PROCEDURE [core].[usp_webhook_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [core].[webhook] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Webhook not found', 1;
    SELECT w.id, w.name, w.url, w.secret, w.events, w.is_active, w.failure_count, w.last_delivery_at,
           w.last_status_code, w.created_at, w.updated_at, w.row_version,
           (SELECT COUNT(*) FROM [core].[webhook_delivery] d WHERE d.webhook_id = w.id AND d.status = N'pending') AS pending_count,
           (SELECT COUNT(*) FROM [core].[webhook_delivery] d WHERE d.webhook_id = w.id AND d.status = N'failed') AS failed_count
    FROM [core].[webhook] w
    WHERE w.id = @id AND w.company_id = @company_id;
END
GO

CREATE OR ALTER PROCEDURE [core].[usp_webhook_list]
    @company_id BIGINT,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS total FROM [core].[webhook] WHERE company_id = @company_id;
    SELECT w.id, w.name, w.url, w.secret, w.events, w.is_active, w.failure_count, w.last_delivery_at,
           w.last_status_code, w.created_at, w.updated_at, w.row_version,
           (SELECT COUNT(*) FROM [core].[webhook_delivery] d WHERE d.webhook_id = w.id AND d.status = N'pending') AS pending_count,
           (SELECT COUNT(*) FROM [core].[webhook_delivery] d WHERE d.webhook_id = w.id AND d.status = N'failed') AS failed_count
    FROM [core].[webhook] w
    WHERE w.company_id = @company_id
    ORDER BY w.name, w.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Adds (@id NULL, @secret required) or edits a webhook. @secret on an edit replaces it (rotation).
CREATE OR ALTER PROCEDURE [core].[usp_webhook_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @url           NVARCHAR(1000),
    @events        NVARCHAR(MAX),
    @is_active     BIT = 1,
    @secret        NVARCHAR(100) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Give the webhook a name.', 1;
    IF @url IS NULL OR (@url NOT LIKE N'https://%' AND @url NOT LIKE N'http://%')
        THROW 50400, N'url|The address must start with http:// or https://.', 1;
    IF ISJSON(@events) = 0 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@events))
        THROW 50400, N'events|Choose at least one event.', 1;
    IF EXISTS (SELECT 1 FROM [core].[webhook] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|WEBHOOK_DUPLICATE|A webhook with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        IF @secret IS NULL
            THROW 50400, N'A new webhook needs a secret.', 1;
        BEGIN TRAN;
            INSERT [core].[webhook] (company_id, name, url, secret, events, is_active, failure_count, created_by)
            VALUES (@company_id, @name, @url, @secret, @events, @is_active, 0, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
            VALUES (@company_id, N'core.webhook', @id, N'create', @url, @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8), @old_url NVARCHAR(1000);
        SELECT @rv = row_version, @old_url = url FROM [core].[webhook] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Webhook not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this webhook. Reload it and try again.', 1;
        BEGIN TRAN;
            UPDATE [core].[webhook]
            SET name = @name, url = @url, events = @events, is_active = @is_active, secret = ISNULL(@secret, secret),
                failure_count = CASE WHEN @is_active = 1 AND is_active = 0 THEN 0 ELSE failure_count END,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'core.webhook', @id, CASE WHEN @secret IS NULL THEN N'url' ELSE N'secret' END,
                    @old_url, CASE WHEN @secret IS NULL THEN @url ELSE N'rotated' END, N'update', @actor_user_id, @now);
        COMMIT;
    END
    EXEC [core].[usp_webhook_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [core].[usp_webhook_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [core].[webhook] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Webhook not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this webhook. Reload it and try again.', 1;
    BEGIN TRAN;
        DELETE [core].[webhook_delivery] WHERE webhook_id = @id;
        DELETE [core].[webhook] WHERE id = @id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'core.webhook', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- A test event for one webhook only.
CREATE OR ALTER PROCEDURE [core].[usp_webhook_ping]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [core].[webhook] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Webhook not found', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @event BIGINT;
    BEGIN TRAN;
        INSERT [core].[outbox_event] (company_id, event_type, entity_type, entity_id, payload, occurred_at)
        VALUES (@company_id, N'webhook.ping', N'core.webhook', @id,
                (SELECT CONVERT(NVARCHAR(30), @id) AS webhookId, CONVERT(NVARCHAR(30), @actor_user_id) AS sentBy
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @now);
        SET @event = SCOPE_IDENTITY();
        INSERT [core].[webhook_delivery] (webhook_id, outbox_event_id, status, attempts, next_attempt_at)
        VALUES (@id, @event, N'pending', 0, @now);
    COMMIT;
    SELECT SCOPE_IDENTITY() AS delivery_id, @event AS event_id;
END
GO

CREATE OR ALTER PROCEDURE [core].[usp_webhook_delivery_list]
    @company_id BIGINT,
    @webhook_id BIGINT,
    @status     NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [core].[webhook] WHERE id = @webhook_id AND company_id = @company_id)
        THROW 50404, N'Webhook not found', 1;
    SELECT COUNT(*) AS total FROM [core].[webhook_delivery]
    WHERE webhook_id = @webhook_id AND (@status IS NULL OR status = @status);
    SELECT d.id, d.status, d.attempts, d.next_attempt_at, d.last_attempt_at, d.response_code, d.response_body, d.error,
           e.id AS event_id, e.event_type, e.entity_type, e.entity_id, e.occurred_at, d.created_at
    FROM [core].[webhook_delivery] d
    JOIN [core].[outbox_event] e ON e.id = d.outbox_event_id
    WHERE d.webhook_id = @webhook_id AND (@status IS NULL OR d.status = @status)
    ORDER BY d.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Sends a delivery again (a failed one, or a delivered one on purpose).
CREATE OR ALTER PROCEDURE [core].[usp_webhook_redeliver]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d SET status = N'pending', attempts = 0, next_attempt_at = SYSUTCDATETIME(), error = NULL,
                 updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    FROM [core].[webhook_delivery] d
    JOIN [core].[webhook] w ON w.id = d.webhook_id AND w.company_id = @company_id
    WHERE d.id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Delivery not found', 1;
END
