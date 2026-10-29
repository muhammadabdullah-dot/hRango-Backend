-- Docs (Backend Dependencies T1): rich text pages in a workspace, optionally in a folder or list.
-- Who: workspace members (rank 1+) add docs; the owner and managers and above edit; the owner and HR or
-- workspace admins delete. A private doc is seen by its owner only (pm.fn_doc_access). Editors other than
-- the owner become contributors. Word and character counts are worked out by the service from the HTML.

-- Result sets: 1 total, 2 the page (docs), 3 contributors of those docs, 4 their linked tasks.
-- @id: one doc (404 when the caller cannot open it). @folder_id: docs in the folder or in its lists.
CREATE OR ALTER PROCEDURE [pm].[usp_doc_list]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @workspace_id     BIGINT = NULL,
    @folder_id        BIGINT = NULL,
    @task_list_id     BIGINT = NULL,
    @search           NVARCHAR(200) = NULL,
    @include_archived BIT = 0,
    @id               BIGINT = NULL,
    @page             INT = 1,
    @page_size        INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @id)
            THROW 50404, N'Doc not found', 1;
        SET @include_archived = 1;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    CREATE TABLE #d (id BIGINT PRIMARY KEY, sort_at DATETIME2(0));
    INSERT #d
    SELECT d.id, COALESCE(d.updated_at, d.created_at)
    FROM [pm].[doc] d
    JOIN [pm].[fn_doc_access](@company_id, @actor_user_id) a ON a.doc_id = d.id
    LEFT JOIN [pm].[task_list] l ON l.id = d.task_list_id
    WHERE (@id IS NULL OR d.id = @id)
      AND (@workspace_id IS NULL OR d.workspace_id = @workspace_id)
      AND (@folder_id IS NULL OR d.folder_id = @folder_id OR l.folder_id = @folder_id)
      AND (@task_list_id IS NULL OR d.task_list_id = @task_list_id)
      AND (@include_archived = 1 OR d.archived_at IS NULL)
      AND (@pattern IS NULL OR d.title LIKE @pattern OR d.content_html LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #d;

    CREATE TABLE #p (id BIGINT PRIMARY KEY, rn INT);
    INSERT #p
    SELECT id, rn FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY sort_at DESC, id DESC) AS rn FROM #d) x
    WHERE rn > (@page - 1) * @page_size AND rn <= @page * @page_size;

    SELECT d.id, d.workspace_id, d.folder_id, d.task_list_id AS list_id, d.title, d.content, d.content_html, d.visibility,
           d.owner_id, NULLIF(CONCAT(o.first_name, N' ', o.last_name), N' ') AS owner_name,
           d.cover_file_id, (SELECT f.name FROM [core].[stored_file] f WHERE f.id = d.cover_file_id) AS cover_file_name,
           d.settings, ISNULL(d.word_count, 0) AS word_count, ISNULL(d.character_count, 0) AS character_count,
           CAST(CASE WHEN d.archived_at IS NULL THEN 0 ELSE 1 END AS BIT) AS archived, d.archived_at,
           d.created_at, COALESCE(d.updated_at, d.created_at) AS updated_at, d.row_version
    FROM #p p
    JOIN [pm].[doc] d ON d.id = p.id
    JOIN [hr].[employee] o ON o.id = d.owner_id
    ORDER BY p.rn;

    SELECT c.doc_id, c.employee_id AS id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name
    FROM #p p JOIN [pm].[doc_contributor] c ON c.doc_id = p.id JOIN [hr].[employee] e ON e.id = c.employee_id
    ORDER BY c.doc_id, c.created_at;

    SELECT x.doc_id, x.task_id
    FROM #p p JOIN [pm].[doc_task] x ON x.doc_id = p.id
    ORDER BY x.doc_id, x.task_id;
END
GO

-- Adds a doc to @workspace_id (@id NULL) or edits one. A list's folder is taken when only the list is
-- given. Only the owner (or HR and workspace admins) changes who can see the doc.
CREATE OR ALTER PROCEDURE [pm].[usp_doc_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT = NULL,
    @workspace_id    BIGINT = NULL,
    @title           NVARCHAR(200),
    @content         NVARCHAR(MAX) = NULL,
    @content_html    NVARCHAR(MAX) = NULL,
    @visibility      NVARCHAR(30) = N'workspace',
    @folder_id       BIGINT = NULL,
    @task_list_id    BIGINT = NULL,
    @cover_file_id   BIGINT = NULL,
    @settings        NVARCHAR(MAX) = NULL,
    @word_count      INT = NULL,
    @character_count INT = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT, @me BIGINT, @owner BIGINT, @old_visibility NVARCHAR(30);
    IF @id IS NULL
        SELECT @rank = role_rank, @me = employee_id FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    ELSE
    BEGIN
        SELECT @rank = a.role_rank, @me = a.employee_id, @workspace_id = d.workspace_id, @owner = d.owner_id, @old_visibility = d.visibility
        FROM [pm].[fn_doc_access](@company_id, @actor_user_id) a JOIN [pm].[doc] d ON d.id = a.doc_id WHERE a.doc_id = @id;
        IF @workspace_id IS NULL
            THROW 50404, N'Doc not found', 1;
    END
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @me IS NULL OR @rank < 1
        THROW 50403, N'Only workspace members can write docs.', 1;
    IF @id IS NOT NULL AND @owner <> @me AND @rank < 3
        THROW 50403, N'Only the doc''s owner, or managers and above, can edit it.', 1;
    IF @id IS NOT NULL AND @visibility <> @old_visibility AND @owner <> @me AND @rank < 4
        THROW 50403, N'Only the doc''s owner changes who can see it.', 1;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR LEN(@title) NOT BETWEEN 1 AND 50
        THROW 50400, N'title|Title must be 1 to 50 characters.', 1;
    IF ISNULL(@visibility, N'') NOT IN (N'private', N'workspace', N'public')
        THROW 50400, N'visibility|Choose private, workspace or public.', 1;
    IF @content IS NOT NULL AND ISJSON(@content) = 0
        THROW 50400, N'content|The document content is not valid.', 1;
    IF @settings IS NOT NULL AND ISJSON(@settings) = 0
        THROW 50400, N'settings|Doc settings are not valid.', 1;
    IF @task_list_id IS NOT NULL
    BEGIN
        DECLARE @list_folder BIGINT, @list_ws BIGINT;
        SELECT @list_ws = workspace_id, @list_folder = folder_id FROM [pm].[task_list] WHERE id = @task_list_id;
        IF @list_ws IS NULL OR @list_ws <> @workspace_id
            THROW 50400, N'listId|The list is not in this workspace.', 1;
        IF @folder_id IS NOT NULL AND ISNULL(@list_folder, 0) <> @folder_id
            THROW 50400, N'folderId|The list is not in this folder.', 1;
        SET @folder_id = @list_folder;
    END
    IF @folder_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[folder] WHERE id = @folder_id AND workspace_id = @workspace_id)
        THROW 50400, N'folderId|The folder is not in this workspace.', 1;
    IF @cover_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @cover_file_id))
        THROW 50400, N'coverFileId|The cover image was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        INSERT [pm].[doc] (company_id, workspace_id, folder_id, task_list_id, title, content, content_html, visibility, owner_id,
                           cover_file_id, settings, word_count, character_count, created_by)
        VALUES (@company_id, @workspace_id, @folder_id, @task_list_id, @title, @content, @content_html, @visibility, @me,
                @cover_file_id, @settings, @word_count, @character_count, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        BEGIN TRAN;
            UPDATE [pm].[doc]
            SET title = @title, content = @content, content_html = @content_html, visibility = @visibility, folder_id = @folder_id,
                task_list_id = @task_list_id, cover_file_id = @cover_file_id, settings = @settings, word_count = @word_count,
                character_count = @character_count, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this doc. Reload it and try again', 1;
            IF @me <> @owner AND NOT EXISTS (SELECT 1 FROM [pm].[doc_contributor] WHERE doc_id = @id AND employee_id = @me)
                INSERT [pm].[doc_contributor] (doc_id, employee_id, created_by) VALUES (@id, @me, @actor_user_id);
        COMMIT;
    END

    EXEC [pm].[usp_doc_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_doc_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT, @owner BIT, @rv BINARY(8);
    SELECT @rank = a.role_rank, @owner = a.is_owner, @rv = d.row_version
    FROM [pm].[fn_doc_access](@company_id, @actor_user_id) a JOIN [pm].[doc] d ON d.id = a.doc_id WHERE a.doc_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Doc not found', 1;
    IF @owner = 0 AND @rank < 4
        THROW 50403, N'Only the doc''s owner, HR or a workspace admin can delete it.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this doc. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [pm].[doc_comment] WHERE doc_id = @id;
        DELETE [pm].[doc_contributor] WHERE doc_id = @id;
        DELETE [pm].[doc_task] WHERE doc_id = @id;
        DELETE [pm].[recent_item] WHERE entity_type = N'doc' AND entity_id = @id;
        DELETE [pm].[doc] WHERE id = @id;
    COMMIT;
END
GO

-- Archives (or, @archived = 0, restores) a doc. Same people as editing.
CREATE OR ALTER PROCEDURE [pm].[usp_doc_archive]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @archived      BIT = 1,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT, @owner BIT;
    SELECT @rank = role_rank, @owner = is_owner FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Doc not found', 1;
    IF @owner = 0 AND @rank < 3
        THROW 50403, N'Only the doc''s owner, or managers and above, can archive it.', 1;

    UPDATE [pm].[doc]
    SET archived_at = CASE WHEN @archived = 1 THEN ISNULL(archived_at, SYSUTCDATETIME()) END,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 50409, N'Someone else changed this doc. Reload it and try again', 1;

    EXEC [pm].[usp_doc_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- A copy of a doc the caller can open, owned by the caller (content, place and settings; not the
-- comments, contributors or linked tasks).
CREATE OR ALTER PROCEDURE [pm].[usp_doc_duplicate]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @title         NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT, @me BIGINT;
    SELECT @rank = role_rank, @me = employee_id FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Doc not found', 1;
    IF @me IS NULL OR @rank < 1
        THROW 50403, N'Only workspace members can write docs.', 1;

    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    IF @title IS NULL
        SET @title = LEFT(CONCAT(N'Copy of ', (SELECT title FROM [pm].[doc] WHERE id = @id)), 50);
    IF LEN(@title) > 50
        THROW 50400, N'title|Title must be 1 to 50 characters.', 1;

    DECLARE @new BIGINT;
    INSERT [pm].[doc] (company_id, workspace_id, folder_id, task_list_id, title, content, content_html, visibility, owner_id,
                       cover_file_id, settings, word_count, character_count, created_by)
    SELECT company_id, workspace_id, folder_id, task_list_id, @title, content, content_html, visibility, @me,
           cover_file_id, settings, word_count, character_count, @actor_user_id
    FROM [pm].[doc] WHERE id = @id;
    SET @new = SCOPE_IDENTITY();

    EXEC [pm].[usp_doc_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @new;
END
GO

-- Links a doc to tasks (replaces the set). @task_ids: JSON array of task ids in the doc's workspace that
-- the caller can see.
CREATE OR ALTER PROCEDURE [pm].[usp_doc_tasks_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @task_ids      NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT, @owner BIT, @ws BIGINT;
    SELECT @rank = role_rank, @owner = is_owner, @ws = workspace_id FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Doc not found', 1;
    IF @owner = 0 AND @rank < 3
        THROW 50403, N'Only the doc''s owner, or managers and above, can link it to tasks.', 1;
    IF ISJSON(ISNULL(@task_ids, N'[]')) = 0
        THROW 50400, N'taskIds|Tasks are not valid.', 1;

    DECLARE @t TABLE (task_id BIGINT PRIMARY KEY);
    INSERT @t SELECT DISTINCT TRY_CONVERT(BIGINT, value) FROM OPENJSON(ISNULL(@task_ids, N'[]')) WHERE TRY_CONVERT(BIGINT, value) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @t x WHERE NOT EXISTS (SELECT 1 FROM [pm].[fn_task_access](@company_id, @actor_user_id) a
                                                   WHERE a.task_id = x.task_id AND a.workspace_id = @ws))
        THROW 50400, N'taskIds|A task was not found in this workspace.', 1;

    BEGIN TRAN;
        DELETE [pm].[doc_task] WHERE doc_id = @id AND task_id NOT IN (SELECT task_id FROM @t);
        INSERT [pm].[doc_task] (doc_id, task_id, created_by)
        SELECT @id, task_id, @actor_user_id FROM @t x WHERE NOT EXISTS (SELECT 1 FROM [pm].[doc_task] d WHERE d.doc_id = @id AND d.task_id = x.task_id);
        UPDATE [pm].[doc] SET updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    EXEC [pm].[usp_doc_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Comments on a doc, oldest first (replies carry parent_id). @id: one comment.
CREATE OR ALTER PROCEDURE [pm].[usp_doc_comment_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @doc_id        BIGINT = NULL,
    @id            BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL
        SET @doc_id = (SELECT doc_id FROM [pm].[doc_comment] WHERE id = @id);
    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @doc_id)
        THROW 50404, N'Doc not found', 1;

    SELECT c.id, c.doc_id, c.parent_id, c.author_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS author_name, c.body,
           c.edited_at, c.created_at, (SELECT COUNT(*) FROM [pm].[doc_comment] x WHERE x.parent_id = c.id) AS reply_count,
           c.row_version
    FROM [pm].[doc_comment] c
    JOIN [hr].[employee] a ON a.id = c.author_id
    WHERE c.doc_id = @doc_id AND (@id IS NULL OR c.id = @id)
    ORDER BY c.created_at, c.id;
END
GO

-- Workspace members comment on docs they can open.
-- TODO(pm): edit / delete / resolve / mentions as on task comments.
CREATE OR ALTER PROCEDURE [pm].[usp_doc_comment_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @doc_id        BIGINT,
    @body          NVARCHAR(MAX),
    @parent_id     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT, @me BIGINT;
    SELECT @rank = role_rank, @me = employee_id FROM [pm].[fn_doc_access](@company_id, @actor_user_id) WHERE doc_id = @doc_id;
    IF @rank IS NULL
        THROW 50404, N'Doc not found', 1;
    IF @me IS NULL OR @rank < 1
        THROW 50403, N'Only workspace members can comment.', 1;
    SET @body = NULLIF(LTRIM(RTRIM(@body)), N'');
    IF @body IS NULL OR LEN(@body) > 2000
        THROW 50400, N'body|A comment is 1 to 2000 characters.', 1;
    IF @parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[doc_comment] WHERE id = @parent_id AND doc_id = @doc_id)
        THROW 50400, N'parentId|The comment you reply to was not found.', 1;

    DECLARE @id BIGINT;
    INSERT [pm].[doc_comment] (doc_id, author_id, body, parent_id, created_by) VALUES (@doc_id, @me, @body, @parent_id, @actor_user_id);
    SET @id = SCOPE_IDENTITY();

    EXEC [pm].[usp_doc_comment_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
