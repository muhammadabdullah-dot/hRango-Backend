-- Comments on posts ("Comment written"): replies one level deep (a reply to a reply joins the same
-- thread), @mentions, Like on a comment, edit and delete. Whoever may read a post may comment on it,
-- unless the post is hidden or the company switched comments off (setting allow_comments).
-- The post's author is told of a new comment, the comment's author of a reply or a like, and
-- mentioned people of the mention; nobody is told of their own action.

-- Result set 1: number of threads. Result set 2: the page of top-level comments, oldest first.
-- Result set 3: the replies of those comments, oldest first.
CREATE OR ALTER PROCEDURE [eng].[usp_post_comment_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @post_id       BIGINT,
    @page          INT = 1,
    @page_size     INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @post_id)
        THROW 50404, N'Post not found', 1;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);

    DECLARE @top TABLE (id BIGINT PRIMARY KEY, commented_at DATETIME2(0));
    INSERT @top
    SELECT id, commented_at FROM [eng].[post_comment] WHERE post_id = @post_id AND parent_id IS NULL
    ORDER BY commented_at, id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;

    SELECT COUNT(*) AS total FROM [eng].[post_comment] WHERE post_id = @post_id AND parent_id IS NULL;

    SELECT r.* FROM @top t JOIN [eng].[fn_post_comment_rows](@me) r ON r.id = t.id
    ORDER BY r.commented_at, r.id;

    SELECT r.* FROM [eng].[fn_post_comment_rows](@me) r
    WHERE r.parent_id IN (SELECT id FROM @top)
    ORDER BY r.commented_at, r.id;
END
GO

CREATE OR ALTER PROCEDURE [eng].[usp_post_comment_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @post_id BIGINT = (SELECT post_id FROM [eng].[post_comment] WHERE id = @id);
    IF @post_id IS NULL OR NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @post_id)
        THROW 50404, N'Comment not found', 1;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);

    SELECT r.* FROM [eng].[fn_post_comment_rows](@me) r WHERE r.id = @id;
END
GO

-- Adds a comment or a reply (@id NULL) or edits the caller's own comment. @mentions: JSON array of
-- employee ids; they must be able to read the post.
CREATE OR ALTER PROCEDURE [eng].[usp_post_comment_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @post_id       BIGINT = NULL,
    @parent_id     BIGINT = NULL,
    @body          NVARCHAR(MAX),
    @mentions      NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @author BIGINT, @rv BINARY(8);
    IF @id IS NOT NULL
    BEGIN
        SELECT @post_id = post_id, @author = employee_id, @rv = row_version FROM [eng].[post_comment] WHERE id = @id;
        IF @post_id IS NULL
            THROW 50404, N'Comment not found', 1;
    END
    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @post_id)
        THROW 50404, N'Post not found', 1;

    DECLARE @me BIGINT, @my_name NVARCHAR(200);
    SELECT @me = e.id, @my_name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')
    FROM [auth].[user_account] u JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.id = @actor_user_id;
    IF @me IS NULL
        THROW 50403, N'Only employees can comment on posts.', 1;

    DECLARE @post_author BIGINT, @hidden BIT;
    SELECT @post_author = author_id, @hidden = is_hidden FROM [eng].[post] WHERE id = @post_id;

    SET @body = LTRIM(RTRIM(@body));
    IF @body IS NULL OR @body = N''
        THROW 50400, N'body|Write a comment first.', 1;
    IF LEN(@body) > 2000
        THROW 50400, N'body|A comment must be within 2000 characters.', 1;

    IF @mentions IS NOT NULL AND ISJSON(@mentions) = 0
        THROW 50400, N'mentionIds|The mentioned people are not valid.', 1;
    DECLARE @mn TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @mn SELECT DISTINCT TRY_CAST(j.[value] AS BIGINT) FROM OPENJSON(ISNULL(@mentions, N'[]')) j
    WHERE TRY_CAST(j.[value] AS BIGINT) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @mn m WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = m.employee_id AND e.company_id = @company_id))
        THROW 50400, N'mentionIds|A mentioned person was not found.', 1;
    IF EXISTS (SELECT 1 FROM @mn m WHERE NOT EXISTS (SELECT 1 FROM [eng].[fn_post_audience](@company_id, m.employee_id) a WHERE a.post_id = @post_id))
        THROW 50400, N'mentionIds|You mentioned someone who cannot see this post.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @told TABLE (employee_id BIGINT PRIMARY KEY);   -- people already told about this comment
    INSERT @told VALUES (@me);
    DECLARE @link NVARCHAR(500) = CONCAT(N'/engagement/posts/', @post_id);
    DECLARE @snippet NVARCHAR(300) = LEFT(@body, 300);
    DECLARE @title NVARCHAR(200);

    IF @id IS NULL
    BEGIN
        IF @hidden = 1
            THROW 50409, N'body|POST_HIDDEN|This post is hidden; it cannot take new comments.', 1;
        DECLARE @settings TABLE (who_may_post NVARCHAR(30), allow_comments BIT, max_media_per_post INT, row_version BINARY(8));
        INSERT @settings EXEC [eng].[usp_engagement_settings_get] @company_id = @company_id;
        IF EXISTS (SELECT 1 FROM @settings WHERE allow_comments = 0)
            THROW 50403, N'body|COMMENTS_OFF|Comments are switched off in this company.', 1;

        DECLARE @parent_author BIGINT;
        IF @parent_id IS NOT NULL
        BEGIN
            DECLARE @grand BIGINT;
            SELECT @parent_author = employee_id, @grand = parent_id FROM [eng].[post_comment] WHERE id = @parent_id AND post_id = @post_id;
            IF @parent_author IS NULL
                THROW 50400, N'parentId|The comment you reply to was not found.', 1;
            SET @parent_id = ISNULL(@grand, @parent_id);   -- one level: a reply to a reply joins the thread
        END

        BEGIN TRAN;
            INSERT [eng].[post_comment] (post_id, employee_id, parent_id, body, commented_at, created_by)
            VALUES (@post_id, @me, @parent_id, @body, @now, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [eng].[post_mention] (post_id, post_comment_id, employee_id, created_by)
            SELECT @post_id, @id, employee_id, @actor_user_id FROM @mn;

            IF NOT EXISTS (SELECT 1 FROM @told WHERE employee_id = @post_author)
            BEGIN
                SET @title = LEFT(CONCAT(@my_name, N' commented on your post'), 200);
                EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @post_author, @title = @title,
                     @body = @snippet, @link = @link, @entity_type = N'eng.post', @entity_id = @post_id;
                INSERT @told VALUES (@post_author);
            END
            IF @parent_author IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @told WHERE employee_id = @parent_author)
            BEGIN
                SET @title = LEFT(CONCAT(@my_name, N' replied to your comment'), 200);
                EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @parent_author, @title = @title,
                     @body = @snippet, @link = @link, @entity_type = N'eng.post', @entity_id = @post_id;
                INSERT @told VALUES (@parent_author);
            END

            DECLARE @payload NVARCHAR(MAX) = (
                SELECT CONVERT(NVARCHAR(30), @id) AS commentId, CONVERT(NVARCHAR(30), @post_id) AS postId,
                       CONVERT(NVARCHAR(30), @parent_id) AS parentId, CONVERT(NVARCHAR(30), @me) AS authorId,
                       @my_name AS authorName, CONVERT(NVARCHAR(30), @post_author) AS postAuthorId, LEFT(@body, 500) AS body,
                       @now AS commentedAt, @link AS link
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.comment_added',
                 @entity_type = N'eng.post_comment', @entity_id = @id, @payload = @payload;
    END
    ELSE
    BEGIN
        IF @author <> @me
            THROW 50403, N'You can edit only your own comments.', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a comment.', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;

        BEGIN TRAN;
            INSERT @told SELECT DISTINCT employee_id FROM [eng].[post_mention]
            WHERE post_comment_id = @id AND employee_id NOT IN (SELECT employee_id FROM @told);
            UPDATE [eng].[post_comment] SET body = @body, edited_at = @now, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;
            DELETE [eng].[post_mention] WHERE post_comment_id = @id;
            INSERT [eng].[post_mention] (post_id, post_comment_id, employee_id, created_by)
            SELECT @post_id, @id, employee_id, @actor_user_id FROM @mn;
    END

        -- Newly mentioned people (still inside the transaction).
        SET @title = LEFT(CONCAT(@my_name, N' mentioned you in a comment'), 200);
        DECLARE @who BIGINT = (SELECT MIN(employee_id) FROM @mn WHERE employee_id NOT IN (SELECT employee_id FROM @told));
        WHILE @who IS NOT NULL
        BEGIN
            EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @who, @title = @title,
                 @body = @snippet, @link = @link, @entity_type = N'eng.post', @entity_id = @post_id;
            SET @who = (SELECT MIN(employee_id) FROM @mn WHERE employee_id > @who AND employee_id NOT IN (SELECT employee_id FROM @told));
        END
    COMMIT;

    EXEC [eng].[usp_post_comment_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Deletes a comment with its replies: its author (engagement.feed.delete) or a moderator of its
-- author (engagement.moderation.delete).
CREATE OR ALTER PROCEDURE [eng].[usp_post_comment_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @post_id BIGINT, @author BIGINT, @rv BINARY(8);
    SELECT @post_id = post_id, @author = employee_id, @rv = row_version FROM [eng].[post_comment] WHERE id = @id;
    IF @post_id IS NULL OR NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @post_id)
        THROW 50404, N'Comment not found', 1;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    IF NOT ((@author = @me AND EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.feed.delete') WHERE employee_id = @me))
            OR EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.delete') WHERE employee_id = @author))
        THROW 50403, N'You can delete only your own comments.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;

    DECLARE @gone TABLE (id BIGINT PRIMARY KEY);
    INSERT @gone SELECT id FROM [eng].[post_comment] WHERE id = @id OR parent_id = @id;
    BEGIN TRAN;
        DELETE [eng].[post_comment_like] WHERE post_comment_id IN (SELECT id FROM @gone);
        DELETE [eng].[post_mention] WHERE post_comment_id IN (SELECT id FROM @gone);
        DELETE [eng].[post_comment] WHERE parent_id = @id;
        DELETE [eng].[post_comment] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this comment. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.post', @post_id, N'comment', CONVERT(NVARCHAR(30), @id), N'delete_comment', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Likes (@liked 1) or unlikes a comment. A new like tells the comment's author. Returns the comment.
CREATE OR ALTER PROCEDURE [eng].[usp_post_comment_like]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @liked         BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @post_id BIGINT, @author BIGINT;
    SELECT @post_id = post_id, @author = employee_id FROM [eng].[post_comment] WHERE id = @id;
    IF @post_id IS NULL OR NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @post_id)
        THROW 50404, N'Comment not found', 1;
    DECLARE @me BIGINT, @my_name NVARCHAR(200);
    SELECT @me = e.id, @my_name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')
    FROM [auth].[user_account] u JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.id = @actor_user_id;
    IF @me IS NULL
        THROW 50403, N'Only employees can like comments.', 1;

    BEGIN TRAN;
        IF @liked = 1
        BEGIN
            INSERT [eng].[post_comment_like] (post_comment_id, employee_id, liked_at, created_by)
            SELECT @id, @me, SYSUTCDATETIME(), @actor_user_id
            WHERE NOT EXISTS (SELECT 1 FROM [eng].[post_comment_like] WITH (UPDLOCK, HOLDLOCK) WHERE post_comment_id = @id AND employee_id = @me);
            IF @@ROWCOUNT > 0 AND @author <> @me
            BEGIN
                DECLARE @title NVARCHAR(200) = LEFT(CONCAT(@my_name, N' liked your comment'), 200);
                DECLARE @link NVARCHAR(500) = CONCAT(N'/engagement/posts/', @post_id);
                EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @author, @title = @title,
                     @link = @link, @entity_type = N'eng.post', @entity_id = @post_id;
            END
        END
        ELSE
            DELETE [eng].[post_comment_like] WHERE post_comment_id = @id AND employee_id = @me;
    COMMIT;

    EXEC [eng].[usp_post_comment_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
