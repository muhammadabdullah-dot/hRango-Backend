-- Announcements: the dashboards' Notice Board (kind notice) and Upcoming Events (kind event).

CREATE OR ALTER PROCEDURE [eng].[usp_announcement_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[announcement] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Announcement not found', 1;

    SELECT a.id, a.kind, a.title, a.body, a.event_date, a.publish_from, a.publish_to,
           a.author_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS author_name,
           a.created_at, a.updated_at, a.row_version
    FROM [eng].[announcement] a
    LEFT JOIN [hr].[employee] e ON e.id = a.author_id
    WHERE a.id = @id AND a.company_id = @company_id;
END
GO

-- Result set 1: total. Result set 2: the page. @current_only: only those published today.
CREATE OR ALTER PROCEDURE [eng].[usp_announcement_list]
    @company_id   BIGINT,
    @search       NVARCHAR(200) = NULL,
    @kind         NVARCHAR(30) = NULL,
    @current_only BIT = 0,
    @today        DATE = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SET @today = ISNULL(@today, CAST(SYSUTCDATETIME() AS DATE));

    SELECT COUNT(*) AS total
    FROM [eng].[announcement] a
    WHERE a.company_id = @company_id AND (@kind IS NULL OR a.kind = @kind)
      AND (@pattern IS NULL OR a.title LIKE @pattern)
      AND (@current_only = 0 OR ((a.publish_from IS NULL OR a.publish_from <= @today) AND (a.publish_to IS NULL OR a.publish_to >= @today)))
    OPTION (RECOMPILE);

    SELECT a.id, a.kind, a.title, a.body, a.event_date, a.publish_from, a.publish_to,
           a.author_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS author_name,
           a.created_at, a.updated_at, a.row_version
    FROM [eng].[announcement] a
    LEFT JOIN [hr].[employee] e ON e.id = a.author_id
    WHERE a.company_id = @company_id AND (@kind IS NULL OR a.kind = @kind)
      AND (@pattern IS NULL OR a.title LIKE @pattern)
      AND (@current_only = 0 OR ((a.publish_from IS NULL OR a.publish_from <= @today) AND (a.publish_to IS NULL OR a.publish_to >= @today)))
    ORDER BY COALESCE(a.event_date, a.publish_from, CAST(a.created_at AS DATE)) DESC, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [eng].[usp_announcement_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @kind          NVARCHAR(30),
    @title         NVARCHAR(200),
    @body          NVARCHAR(MAX) = NULL,
    @event_date    DATE = NULL,
    @publish_from  DATE = NULL,
    @publish_to    DATE = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    SET @body = NULLIF(LTRIM(RTRIM(@body)), N'');
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Title is required.', 1;
    IF @kind NOT IN (N'notice', N'event')
        THROW 50400, N'kind|Choose notice or event.', 1;
    IF @kind = N'event' AND @event_date IS NULL
        THROW 50400, N'eventDate|An event needs its date.', 1;
    IF @publish_from IS NOT NULL AND @publish_to IS NOT NULL AND @publish_to < @publish_from
        THROW 50400, N'publishTo|The end date is before the start date.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @author BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                              JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                              WHERE u.id = @actor_user_id);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [eng].[announcement] (company_id, author_id, kind, title, body, event_date, publish_from, publish_to, created_by)
            VALUES (@company_id, @author, @kind, @title, @body, @event_date, @publish_from, @publish_to, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.announcement', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an announcement.', 1;
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [eng].[announcement] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Announcement not found', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this announcement. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [eng].[announcement]
            SET kind = @kind, title = @title, body = @body, event_date = @event_date, publish_from = @publish_from,
                publish_to = @publish_to, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this announcement. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.announcement', @id, N'update', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [eng].[usp_announcement_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [eng].[usp_announcement_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [eng].[announcement] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Announcement not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this announcement. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [eng].[announcement_read] WHERE announcement_id = @id;
        DELETE [eng].[announcement] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.announcement', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
