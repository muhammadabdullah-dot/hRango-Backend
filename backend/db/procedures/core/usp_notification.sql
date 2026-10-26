-- The inbox: a signed-in user's own notifications in the active company.
-- Other modules add notifications with core.usp_notification_add (to a user) or
-- core.usp_notification_add_employee (to the sign-in accounts of an employee). From inside another
-- procedure pass @quiet = 1, so no result set comes back (INSERT ... EXEC cannot be nested).

CREATE OR ALTER PROCEDURE [core].[usp_notification_add]
    @company_id        BIGINT,
    @user_account_id   BIGINT,
    @title             NVARCHAR(200),
    @body              NVARCHAR(MAX) = NULL,
    @notification_type NVARCHAR(30) = NULL,
    @link              NVARCHAR(500) = NULL,
    @entity_type       NVARCHAR(50) = NULL,
    @entity_id         BIGINT = NULL,
    @quiet             BIT = 0          -- 1 from another procedure: no result set (no INSERT ... EXEC needed)
AS
BEGIN
    SET NOCOUNT ON;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|A notification needs a title.', 1;
    IF NOT EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @user_account_id)
        THROW 50404, N'User not found', 1;

    INSERT [core].[notification] (company_id, user_account_id, notification_type, title, body, link, entity_type, entity_id)
    VALUES (@company_id, @user_account_id, @notification_type, @title, @body, @link, @entity_type, @entity_id);
    DECLARE @id BIGINT = SCOPE_IDENTITY();

    -- Every notification is also an event, so webhooks (chat, SMS, mail gateways) can deliver it.
    DECLARE @n_payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), n.id) AS notificationId, CONVERT(NVARCHAR(30), n.user_account_id) AS userId,
               CONVERT(NVARCHAR(30), u.employee_id) AS employeeId, u.email, n.notification_type AS [type], n.title,
               n.body, n.link, n.entity_type AS entityType, CONVERT(NVARCHAR(30), n.entity_id) AS entityId,
               n.created_at AS createdAt
        FROM [core].[notification] n JOIN [auth].[user_account] u ON u.id = n.user_account_id
        WHERE n.id = @id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'notification.created',
         @entity_type = N'core.notification', @entity_id = @id, @payload = @n_payload;

    IF @quiet = 0
        SELECT @id AS id;
END
GO

-- Notifies every active sign-in account linked to an employee. Returns how many were added
-- (none when the employee has no account).
CREATE OR ALTER PROCEDURE [core].[usp_notification_add_employee]
    @company_id        BIGINT,
    @employee_id       BIGINT,
    @title             NVARCHAR(200),
    @body              NVARCHAR(MAX) = NULL,
    @notification_type NVARCHAR(30) = NULL,
    @link              NVARCHAR(500) = NULL,
    @entity_type       NVARCHAR(50) = NULL,
    @entity_id         BIGINT = NULL,
    @quiet             BIT = 0          -- 1 from another procedure: no result set (no INSERT ... EXEC needed)
AS
BEGIN
    SET NOCOUNT ON;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|A notification needs a title.', 1;

    DECLARE @added TABLE (id BIGINT PRIMARY KEY);
    INSERT [core].[notification] (company_id, user_account_id, notification_type, title, body, link, entity_type, entity_id)
    OUTPUT inserted.id INTO @added
    SELECT @company_id, u.id, @notification_type, @title, @body, @link, @entity_type, @entity_id
    FROM [auth].[user_account] u
    JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.employee_id = @employee_id AND u.is_active = 1;

    DECLARE @nid BIGINT = (SELECT MIN(id) FROM @added);
    WHILE @nid IS NOT NULL
    BEGIN
        -- Every notification is also an event, so webhooks (chat, SMS, mail gateways) can deliver it.
        DECLARE @n_payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), n.id) AS notificationId, CONVERT(NVARCHAR(30), n.user_account_id) AS userId,
                   CONVERT(NVARCHAR(30), u.employee_id) AS employeeId, u.email, n.notification_type AS [type], n.title,
                   n.body, n.link, n.entity_type AS entityType, CONVERT(NVARCHAR(30), n.entity_id) AS entityId,
                   n.created_at AS createdAt
            FROM [core].[notification] n JOIN [auth].[user_account] u ON u.id = n.user_account_id
            WHERE n.id = @nid
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'notification.created',
             @entity_type = N'core.notification', @entity_id = @nid, @payload = @n_payload;
        SET @nid = (SELECT MIN(id) FROM @added WHERE id > @nid);
    END

    IF @quiet = 0
        SELECT COUNT(*) AS added FROM @added;
END
GO

-- Result set 1: total. Result set 2: the page. Cleared notifications are gone from the inbox.
CREATE OR ALTER PROCEDURE [core].[usp_notification_list]
    @company_id  BIGINT,
    @user_id     BIGINT,
    @unread_only BIT = 0,
    @page        INT = 1,
    @page_size   INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [core].[notification]
    WHERE company_id = @company_id AND user_account_id = @user_id AND cleared_at IS NULL
      AND (@unread_only = 0 OR read_at IS NULL);

    SELECT id, notification_type, title, body, link, entity_type, entity_id, read_at, created_at
    FROM [core].[notification]
    WHERE company_id = @company_id AND user_account_id = @user_id AND cleared_at IS NULL
      AND (@unread_only = 0 OR read_at IS NULL)
    ORDER BY created_at DESC, id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- The top bar: unread count, then the latest few.
CREATE OR ALTER PROCEDURE [core].[usp_notification_summary]
    @company_id BIGINT,
    @user_id    BIGINT,
    @latest     INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS unread
    FROM [core].[notification]
    WHERE company_id = @company_id AND user_account_id = @user_id AND cleared_at IS NULL AND read_at IS NULL;

    SELECT TOP (@latest) id, notification_type, title, body, link, entity_type, entity_id, read_at, created_at
    FROM [core].[notification]
    WHERE company_id = @company_id AND user_account_id = @user_id AND cleared_at IS NULL
    ORDER BY created_at DESC, id DESC;
END
GO

-- Marks read (@action read) or clears (@action clear) one notification (@id) or all of them
-- (@id NULL). Returns how many changed. Someone else's notification is "not found".
CREATE OR ALTER PROCEDURE [core].[usp_notification_mark]
    @company_id BIGINT,
    @user_id    BIGINT,
    @id         BIGINT = NULL,
    @action     NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF @action NOT IN (N'read', N'clear')
        THROW 50400, N'action|Unknown action.', 1;
    IF @id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[notification]
                                       WHERE id = @id AND company_id = @company_id AND user_account_id = @user_id AND cleared_at IS NULL)
        THROW 50404, N'Notification not found', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    UPDATE [core].[notification]
    SET read_at = ISNULL(read_at, @now),
        cleared_at = CASE WHEN @action = N'clear' THEN @now ELSE cleared_at END,
        updated_at = @now
    WHERE company_id = @company_id AND user_account_id = @user_id AND cleared_at IS NULL
      AND (@id IS NULL OR id = @id)
      AND (@action = N'clear' OR read_at IS NULL);

    SELECT @@ROWCOUNT AS changed;
END
