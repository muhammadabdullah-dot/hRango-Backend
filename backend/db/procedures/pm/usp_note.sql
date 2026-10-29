-- Notepad (Backend Dependencies T3): a person's own notes, per sign-in (not per workspace). Every save
-- keeps a version (note_version) for the history. Converting a note to a task or doc is done by the
-- service (it calls the task / doc procedures, then archives, deletes or keeps the note).

-- Result sets: 1 total, 2 the page. @id: one note (404 unless it is the caller's).
CREATE OR ALTER PROCEDURE [pm].[usp_note_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @archived      BIT = 0,
    @search        NVARCHAR(200) = NULL,
    @id            BIGINT = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pm].[note] WHERE id = @id AND company_id = @company_id AND user_account_id = @actor_user_id)
        THROW 50404, N'Note not found', 1;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [pm].[note] n
    WHERE n.company_id = @company_id AND n.user_account_id = @actor_user_id
      AND (@id IS NOT NULL OR (CASE WHEN n.archived_at IS NULL THEN 0 ELSE 1 END) = ISNULL(@archived, 0))
      AND (@id IS NULL OR n.id = @id)
      AND (@pattern IS NULL OR n.title LIKE @pattern OR n.content_html LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT n.id, n.title, n.content_html, CAST(CASE WHEN n.archived_at IS NULL THEN 0 ELSE 1 END AS BIT) AS archived,
           ISNULL(n.version_no, 1) AS version, n.created_at, COALESCE(n.updated_at, n.created_at) AS updated_at, n.row_version
    FROM [pm].[note] n
    WHERE n.company_id = @company_id AND n.user_account_id = @actor_user_id
      AND (@id IS NOT NULL OR (CASE WHEN n.archived_at IS NULL THEN 0 ELSE 1 END) = ISNULL(@archived, 0))
      AND (@id IS NULL OR n.id = @id)
      AND (@pattern IS NULL OR n.title LIKE @pattern OR n.content_html LIKE @pattern)
    ORDER BY COALESCE(n.updated_at, n.created_at) DESC, n.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a note (@id NULL) or saves a new version of one.
CREATE OR ALTER PROCEDURE [pm].[usp_note_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @title         NVARCHAR(400),
    @content_html  NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR LEN(@title) NOT BETWEEN 1 AND 200
        THROW 50400, N'title|Title must be 1 to 200 characters.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @version INT;
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            SET @version = 1;
            INSERT [pm].[note] (company_id, user_account_id, title, content_html, version_no, created_by)
            VALUES (@company_id, @actor_user_id, @title, @content_html, @version, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [pm].[note] WHERE id = @id AND company_id = @company_id AND user_account_id = @actor_user_id)
                THROW 50404, N'Note not found', 1;
            SET @version = ISNULL((SELECT MAX(version_no) FROM [pm].[note_version] WHERE note_id = @id), 0) + 1;
            UPDATE [pm].[note]
            SET title = @title, content_html = @content_html, version_no = @version, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'This note was changed elsewhere. Reload it and try again', 1;
        END
        INSERT [pm].[note_version] (note_id, version_no, title, content_html, edited_by_user_id, edited_at, created_by)
        VALUES (@id, @version, @title, @content_html, @actor_user_id, @now, @actor_user_id);
    COMMIT;

    EXEC [pm].[usp_note_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Archives (or, @archived = 0, restores) a note.
CREATE OR ALTER PROCEDURE [pm].[usp_note_archive]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @archived      BIT = 1,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[note] WHERE id = @id AND company_id = @company_id AND user_account_id = @actor_user_id)
        THROW 50404, N'Note not found', 1;
    UPDATE [pm].[note]
    SET archived_at = CASE WHEN @archived = 1 THEN ISNULL(archived_at, SYSUTCDATETIME()) END,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 50409, N'This note was changed elsewhere. Reload it and try again', 1;

    EXEC [pm].[usp_note_list] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pm].[usp_note_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [pm].[note] WHERE id = @id AND company_id = @company_id AND user_account_id = @actor_user_id);
    IF @rv IS NULL
        THROW 50404, N'Note not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'This note was changed elsewhere. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [pm].[note_version] WHERE note_id = @id;
        DELETE [pm].[note] WHERE id = @id;
    COMMIT;
END
GO

-- Every saved version of a note, newest first.
CREATE OR ALTER PROCEDURE [pm].[usp_note_history]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[note] WHERE id = @id AND company_id = @company_id AND user_account_id = @actor_user_id)
        THROW 50404, N'Note not found', 1;

    SELECT v.version_no AS version, v.title, v.content_html, v.edited_at,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS edited_by_name
    FROM [pm].[note_version] v
    LEFT JOIN [auth].[user_account] u ON u.id = v.edited_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE v.note_id = @id
    ORDER BY v.version_no DESC;
END
GO

-- Converting a note: the workspace a list is in (the list must be one the caller reaches).
CREATE OR ALTER PROCEDURE [pm].[usp_note_convert_place]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @task_list_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ws BIGINT;
    SELECT @ws = l.workspace_id FROM [pm].[task_list] l
    JOIN [pm].[fn_workspace_access](@company_id, @actor_user_id) a ON a.workspace_id = l.workspace_id
    WHERE l.id = @task_list_id;
    IF @ws IS NULL
        THROW 50400, N'listId|List not found.', 1;
    SELECT @ws AS workspace_id;
END
