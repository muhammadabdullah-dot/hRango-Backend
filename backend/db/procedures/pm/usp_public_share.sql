-- The public share page (Backend Dependencies T6): GET /api/public/shares/{token}, without signing in.
-- A link answers only when "Share link with anyone" is on (is_public). Its validity period and access
-- limit are enforced here; every page and every task opened counts as one access.
-- Each procedure's first result set is the link's state: ok, not_found, expired, not_started or exhausted
-- (the service answers 404 / 410); the other sets come only when the state is ok.

-- Internal: checks a link and, when @count = 1, counts one access (only while under the limit).
CREATE OR ALTER PROCEDURE [pm].[usp_public_share_check]
    @token    NVARCHAR(100),
    @count    BIT = 1,
    @state    NVARCHAR(30) OUTPUT,
    @share_id BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @from DATETIME2(0), @to DATETIME2(0), @max INT, @used INT, @public BIT;
    SET @share_id = NULL;
    SELECT @share_id = s.id, @from = s.valid_from, @to = s.valid_to, @max = s.max_access, @public = s.is_public
    FROM [pm].[share_link] s JOIN [pm].[workspace] w ON w.id = s.workspace_id
    WHERE s.token = @token;

    IF @share_id IS NULL OR ISNULL(@public, 0) = 0
    BEGIN
        SELECT @state = N'not_found', @share_id = NULL;
        RETURN;
    END
    IF @from IS NOT NULL AND @now < @from
    BEGIN
        SET @state = N'not_started';
        RETURN;
    END
    IF @to IS NOT NULL AND @now >= @to
    BEGIN
        SET @state = N'expired';
        RETURN;
    END
    BEGIN TRAN;
        -- The link row is locked while counting, so two visitors cannot both take the last access.
        SELECT @max = max_access FROM [pm].[share_link] WITH (UPDLOCK, HOLDLOCK) WHERE id = @share_id;
        SET @used = (SELECT COUNT(*) FROM [pm].[share_access] WHERE share_link_id = @share_id);
        IF @max IS NOT NULL AND @used >= @max
            SET @state = N'exhausted';
        ELSE
        BEGIN
            SET @state = N'ok';
            IF @count = 1
                INSERT [pm].[share_access] (share_link_id, accessed_at) VALUES (@share_id, @now);
        END
    COMMIT;
END
GO

-- The shared page. Result sets: 1 state and the link (entity, title, allow_open_tasks, properties,
-- company), 2 the tasks (all properties; the service keeps the ones the link shows).
CREATE OR ALTER PROCEDURE [pm].[usp_public_share_open]
    @token NVARCHAR(100),
    @count BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @state NVARCHAR(30), @share_id BIGINT;
    EXEC [pm].[usp_public_share_check] @token = @token, @count = @count, @state = @state OUTPUT, @share_id = @share_id OUTPUT;

    SELECT @state AS state, s.id AS share_id, w.company_id, s.workspace_id, s.entity_type, s.entity_id, s.allow_open_tasks, s.properties,
           CASE s.entity_type WHEN N'task' THEN t.name WHEN N'task_list' THEN l.name ELSE w.name END AS title
    FROM (SELECT 1 AS one) x
    LEFT JOIN [pm].[share_link] s ON s.id = @share_id AND @state = N'ok'
    LEFT JOIN [pm].[workspace] w ON w.id = s.workspace_id
    LEFT JOIN [pm].[task] t ON s.entity_type = N'task' AND t.id = s.entity_id
    LEFT JOIN [pm].[task_list] l ON s.entity_type = N'task_list' AND l.id = s.entity_id;
    IF @state <> N'ok'
        RETURN;

    SELECT t.id, t.parent_task_id, t.code, t.name, st.name AS status_name, st.color AS status_color, st.status_group, t.priority,
           t.due_date, t.start_date,
           (SELECT NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name FROM [pm].[task_assignee] a
            JOIN [hr].[employee] e ON e.id = a.employee_id WHERE a.task_id = t.id ORDER BY e.first_name FOR JSON PATH) AS assignees_json,
           (SELECT g.name, g.color FROM [pm].[task_tag] x JOIN [pm].[tag] g ON g.id = x.tag_id WHERE x.task_id = t.id
            ORDER BY g.name FOR JSON PATH) AS tags_json
    FROM [pm].[fn_share_tasks](@share_id) f
    JOIN [pm].[task] t ON t.id = f.task_id
    JOIN [pm].[workspace_status] st ON st.id = t.status_id
    ORDER BY t.sort_order, t.id;
END
GO

-- One task of a shared page (when the link allows opening tasks). Result sets: 1 state and the link,
-- 2 the task, 3 subtasks, 4 checklist, 5 comments, 6 attachments, 7 custom field values.
-- state task_not_found: the task is not on the shared page; tasks_closed: the link does not open tasks.
CREATE OR ALTER PROCEDURE [pm].[usp_public_share_task]
    @token   NVARCHAR(100),
    @task_id BIGINT,
    @count   BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @state NVARCHAR(30), @share_id BIGINT;
    -- Checked without counting first, so a refused task does not use up an access.
    EXEC [pm].[usp_public_share_check] @token = @token, @count = 0, @state = @state OUTPUT, @share_id = @share_id OUTPUT;
    IF @state = N'ok' AND NOT EXISTS (SELECT 1 FROM [pm].[fn_share_tasks](@share_id) WHERE task_id = @task_id)
        SET @state = N'task_not_found';
    ELSE IF @state = N'ok' AND (SELECT allow_open_tasks FROM [pm].[share_link] WHERE id = @share_id) = 0
        SET @state = N'tasks_closed';
    IF @state = N'ok' AND @count = 1
        EXEC [pm].[usp_public_share_check] @token = @token, @count = 1, @state = @state OUTPUT, @share_id = @share_id OUTPUT;

    SELECT @state AS state, s.id AS share_id, w.company_id, s.workspace_id, s.entity_type, s.entity_id, s.allow_open_tasks, s.properties
    FROM (SELECT 1 AS one) x
    LEFT JOIN [pm].[share_link] s ON s.id = @share_id AND @state = N'ok'
    LEFT JOIN [pm].[workspace] w ON w.id = s.workspace_id;
    IF @state <> N'ok'
        RETURN;

    SELECT t.id, t.parent_task_id, t.code, t.name, t.description, st.name AS status_name, st.color AS status_color, st.status_group,
           t.priority, t.start_date, t.due_date, t.cover_file_id,
           (SELECT NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name FROM [pm].[task_assignee] a
            JOIN [hr].[employee] e ON e.id = a.employee_id WHERE a.task_id = t.id ORDER BY e.first_name FOR JSON PATH) AS assignees_json,
           (SELECT g.name, g.color FROM [pm].[task_tag] x JOIN [pm].[tag] g ON g.id = x.tag_id WHERE x.task_id = t.id
            ORDER BY g.name FOR JSON PATH) AS tags_json
    FROM [pm].[task] t JOIN [pm].[workspace_status] st ON st.id = t.status_id
    WHERE t.id = @task_id;

    SELECT c.id, c.code, c.name, st.name AS status_name, st.color AS status_color, st.status_group, c.due_date
    FROM [pm].[task] c JOIN [pm].[workspace_status] st ON st.id = c.status_id
    WHERE c.parent_task_id = @task_id ORDER BY c.sort_order, c.id;

    SELECT c.item_text, c.is_done FROM [pm].[checklist_item] c WHERE c.task_id = @task_id ORDER BY c.sort_order, c.id;

    SELECT c.id, c.parent_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS author_name, c.body, c.created_at
    FROM [pm].[task_comment] c JOIN [hr].[employee] e ON e.id = c.author_id
    WHERE c.task_id = @task_id ORDER BY c.created_at, c.id;

    SELECT sf.id AS file_id, sf.name, sf.mime_type, sf.size_bytes, CAST(NULL AS NVARCHAR(2000)) AS web_url
    FROM [core].[attachment] a JOIN [core].[stored_file] sf ON sf.id = a.file_id
    JOIN [pm].[share_link] s ON s.id = @share_id JOIN [pm].[workspace] w ON w.id = s.workspace_id
    WHERE a.company_id = w.company_id AND a.entity_type = N'pm.task' AND a.entity_id = @task_id
    UNION ALL
    SELECT NULL, xf.name, xf.mime_type, xf.size_bytes, xf.web_url FROM [pm].[task_external_file] xf WHERE xf.task_id = @task_id;

    SELECT f.name, f.field_type, v.field_value
    FROM [pm].[task_field_value] v JOIN [pm].[custom_field] f ON f.id = v.custom_field_id
    WHERE v.task_id = @task_id ORDER BY f.sort_order, f.id;
END
