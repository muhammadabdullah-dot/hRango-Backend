-- Newsfeed posts: the feed (pinned first, then newest), My Posts (edit, delete, copy link), the
-- moderation list, one post, views, pin and hide. Who reads a post: eng.fn_visible_posts.
-- Staff post to everyone, their own department (or one above it) or their own branch; moderators
-- (engagement.moderation.edit) to any department or branch. A company may let only moderators post
-- (setting who_may_post).

-- Result set 1: total. Result set 2: the page.
-- @mode feed: what the caller may read, pinned first; mine: the caller's own posts (My Posts);
-- moderation: every post of the authors the caller moderates, hidden ones included.
CREATE OR ALTER PROCEDURE [eng].[usp_post_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @mode          NVARCHAR(20) = N'feed',
    @author_id     BIGINT = NULL,
    @search        NVARCHAR(200) = NULL,
    @hidden_only   BIT = 0,
    @page          INT = 1,
    @page_size     INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY, is_pinned BIT, posted_at DATETIME2(0));
    INSERT @ids (id, is_pinned, posted_at)
    SELECT p.id, p.is_pinned, p.posted_at
    FROM [eng].[post] p
    WHERE p.company_id = @company_id AND p.is_deleted = 0
      AND (   (@mode = N'feed' AND p.id IN (SELECT v.post_id FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) v))
           OR (@mode = N'mine' AND p.author_id = @me)
           OR (@mode = N'moderation' AND p.author_id IN (
                  SELECT m.employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.view') m)))
      AND (@author_id IS NULL OR p.author_id = @author_id)
      AND (@pattern IS NULL OR p.body LIKE @pattern)
      AND (@hidden_only = 0 OR p.is_hidden = 1)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM @ids;

    SELECT r.*, CAST(CASE WHEN m.employee_id IS NULL THEN 0 ELSE 1 END AS BIT) AS can_moderate
    FROM @ids i
    JOIN [eng].[fn_post_rows](@company_id, @me) r ON r.id = i.id
    LEFT JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.edit') m ON m.employee_id = r.author_id
    ORDER BY CASE WHEN @mode = N'feed' THEN i.is_pinned ELSE 0 END DESC, i.posted_at DESC, i.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One post the caller may read (the "Copy link" target).
CREATE OR ALTER PROCEDURE [eng].[usp_post_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);

    SELECT r.*, CAST(CASE WHEN EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.edit') m
                                       WHERE m.employee_id = r.author_id) THEN 1 ELSE 0 END AS BIT) AS can_moderate
    FROM [eng].[fn_post_rows](@company_id, @me) r
    WHERE r.id = @id;
END
GO

-- Creates (@id NULL) or edits the caller's own post. @media: JSON array of uploaded file ids (photos
-- and videos, in order); @mentions: JSON array of employee ids. Mentioned people must be in the post's
-- audience; each newly mentioned person is told in the inbox.
CREATE OR ALTER PROCEDURE [eng].[usp_post_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @body          NVARCHAR(MAX) = NULL,
    @visibility    NVARCHAR(30) = N'public',
    @department_id BIGINT = NULL,
    @branch_id     BIGINT = NULL,
    @media         NVARCHAR(MAX) = NULL,
    @mentions      NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @me BIGINT, @my_dept BIGINT, @my_branch BIGINT, @my_name NVARCHAR(200);
    SELECT @me = e.id, @my_dept = e.department_id, @my_branch = e.branch_id,
           @my_name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')
    FROM [auth].[user_account] u
    JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.id = @actor_user_id;
    IF @me IS NULL
        THROW 50403, N'Only employees can post on the newsfeed.', 1;

    DECLARE @can_moderate BIT = CASE WHEN EXISTS (
        SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.edit') WHERE employee_id = @me)
        THEN 1 ELSE 0 END;
    DECLARE @who_may_post NVARCHAR(30), @max_media INT;
    DECLARE @settings TABLE (who_may_post NVARCHAR(30), allow_comments BIT, max_media_per_post INT, row_version BINARY(8));
    INSERT @settings EXEC [eng].[usp_engagement_settings_get] @company_id = @company_id;
    SELECT @who_may_post = who_may_post, @max_media = max_media_per_post FROM @settings;

    DECLARE @author BIGINT, @rv BINARY(8), @deleted BIT;
    IF @id IS NULL
    BEGIN
        IF @who_may_post = N'moderators' AND @can_moderate = 0
            THROW 50403, N'body|POSTING_RESTRICTED|In this company only moderators can post.', 1;
    END
    ELSE
    BEGIN
        SELECT @author = author_id, @rv = row_version, @deleted = is_deleted
        FROM [eng].[post] WHERE id = @id AND company_id = @company_id;
        IF @author IS NULL OR @deleted = 1
            THROW 50404, N'Post not found', 1;
        IF @author <> @me
            THROW 50403, N'You can edit only your own posts.', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a post.', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this post. Reload it and try again', 1;
    END

    SET @body = NULLIF(LTRIM(RTRIM(@body)), N'');
    IF LEN(@body) > 5000
        THROW 50400, N'body|A post must be within 5000 characters.', 1;
    SET @visibility = ISNULL(@visibility, N'public');
    IF @visibility NOT IN (N'public', N'department', N'branch')
        THROW 50400, N'visibility|Choose public, department or branch.', 1;

    IF @visibility = N'department'
    BEGIN
        SET @branch_id = NULL;
        SET @department_id = ISNULL(@department_id, @my_dept);
        IF @department_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
            THROW 50400, N'departmentId|Choose the department that sees this post.', 1;
        IF @can_moderate = 0
        BEGIN
            DECLARE @mine_dept INT;
            WITH up AS (
                SELECT id, parent_id FROM [org].[department] WHERE id = @my_dept
                UNION ALL
                SELECT d.id, d.parent_id FROM [org].[department] d JOIN up ON d.id = up.parent_id
            )
            SELECT @mine_dept = COUNT(*) FROM up WHERE id = @department_id;
            IF @mine_dept = 0
                THROW 50403, N'departmentId|You can post only to your own department.', 1;
        END
    END
    ELSE IF @visibility = N'branch'
    BEGIN
        SET @department_id = NULL;
        SET @branch_id = ISNULL(@branch_id, @my_branch);
        IF @branch_id IS NULL OR NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
            THROW 50400, N'branchId|Choose the branch that sees this post.', 1;
        IF @can_moderate = 0 AND @branch_id <> ISNULL(@my_branch, 0)
            THROW 50403, N'branchId|You can post only to your own branch.', 1;
    END
    ELSE
        SELECT @department_id = NULL, @branch_id = NULL;

    -- Photos and videos, in the order given.
    IF @media IS NOT NULL AND ISJSON(@media) = 0
        THROW 50400, N'mediaFileIds|The photos and videos are not valid.', 1;
    DECLARE @md TABLE (file_id BIGINT PRIMARY KEY, sort_order INT, media_type NVARCHAR(30), mime_type NVARCHAR(100));
    INSERT @md (file_id, sort_order)
    SELECT x.file_id, MIN(x.pos)
    FROM (SELECT TRY_CAST(j.[value] AS BIGINT) AS file_id, CAST(j.[key] AS INT) AS pos FROM OPENJSON(ISNULL(@media, N'[]')) j) x
    WHERE x.file_id IS NOT NULL
    GROUP BY x.file_id;
    IF EXISTS (SELECT 1 FROM @md m WHERE NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, m.file_id)))
        THROW 50400, N'mediaFileIds|A photo or video was not found. Upload it again.', 1;
    UPDATE m SET mime_type = f.mime_type,
                 media_type = CASE WHEN f.mime_type LIKE N'video/%' THEN N'video' WHEN f.mime_type LIKE N'image/%' THEN N'photo' END
    FROM @md m JOIN [core].[stored_file] f ON f.id = m.file_id;
    IF EXISTS (SELECT 1 FROM @md WHERE media_type IS NULL)
        THROW 50400, N'mediaFileIds|Only photos and videos can be added to a post.', 1;
    IF (SELECT COUNT(*) FROM @md) > @max_media
    BEGIN
        DECLARE @too_many NVARCHAR(200) = CONCAT(N'mediaFileIds|A post can have at most ', @max_media, N' photos and videos.');
        THROW 50400, @too_many, 1;
    END
    IF @body IS NULL AND NOT EXISTS (SELECT 1 FROM @md)
        THROW 50400, N'body|Write something or add a photo or video.', 1;

    IF @mentions IS NOT NULL AND ISJSON(@mentions) = 0
        THROW 50400, N'mentionIds|The mentioned people are not valid.', 1;
    DECLARE @mn TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @mn SELECT DISTINCT TRY_CAST(j.[value] AS BIGINT) FROM OPENJSON(ISNULL(@mentions, N'[]')) j
    WHERE TRY_CAST(j.[value] AS BIGINT) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM @mn m WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = m.employee_id AND e.company_id = @company_id))
        THROW 50400, N'mentionIds|A mentioned person was not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @old_mentions TABLE (employee_id BIGINT PRIMARY KEY);
    DECLARE @is_new BIT = CASE WHEN @id IS NULL THEN 1 ELSE 0 END;

    BEGIN TRAN;
        IF @is_new = 1
        BEGIN
            INSERT [eng].[post] (company_id, author_id, body, visibility, department_id, branch_id, posted_at, created_by)
            VALUES (@company_id, @me, @body, @visibility, @department_id, @branch_id, @now, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.post', @id, N'create', @visibility, @actor_user_id, @now);
        END
        ELSE
        BEGIN
            INSERT @old_mentions SELECT DISTINCT employee_id FROM [eng].[post_mention] WHERE post_id = @id AND post_comment_id IS NULL;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'eng.post', @id, x.field_name, x.old_value, x.new_value, N'update', @actor_user_id, @now
            FROM [eng].[post] p
            CROSS APPLY (VALUES (N'body', LEFT(p.body, 4000), LEFT(@body, 4000)),
                                (N'visibility', p.visibility, @visibility)) x (field_name, old_value, new_value)
            WHERE p.id = @id AND EXISTS (SELECT x.old_value EXCEPT SELECT x.new_value);

            UPDATE [eng].[post]
            SET body = @body, visibility = @visibility, department_id = @department_id, branch_id = @branch_id,
                edited_at = @now, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this post. Reload it and try again', 1;
            DELETE [eng].[post_media] WHERE post_id = @id;
            DELETE [eng].[post_mention] WHERE post_id = @id AND post_comment_id IS NULL;
        END

        INSERT [eng].[post_media] (post_id, file_id, media_type, sort_order, created_by)
        SELECT @id, file_id, media_type, ROW_NUMBER() OVER (ORDER BY sort_order), @actor_user_id FROM @md;
        INSERT [eng].[post_mention] (post_id, employee_id, created_by)
        SELECT @id, employee_id, @actor_user_id FROM @mn;

        IF EXISTS (SELECT 1 FROM @mn m WHERE NOT EXISTS (SELECT 1 FROM [eng].[fn_post_audience](@company_id, m.employee_id) a WHERE a.post_id = @id))
            THROW 50400, N'mentionIds|You mentioned someone who will not see this post.', 1;

        DECLARE @who BIGINT = (SELECT MIN(employee_id) FROM @mn WHERE employee_id <> @me
                               AND employee_id NOT IN (SELECT employee_id FROM @old_mentions));
        DECLARE @title NVARCHAR(200) = LEFT(CONCAT(@my_name, N' mentioned you in a post'), 200);
        DECLARE @snippet NVARCHAR(300) = LEFT(@body, 300);
        DECLARE @link NVARCHAR(500) = CONCAT(N'/engagement/posts/', @id);
        WHILE @who IS NOT NULL
        BEGIN
            EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @who, @title = @title,
                 @body = @snippet, @link = @link, @entity_type = N'eng.post', @entity_id = @id;
            SET @who = (SELECT MIN(employee_id) FROM @mn WHERE employee_id > @who AND employee_id <> @me
                        AND employee_id NOT IN (SELECT employee_id FROM @old_mentions));
        END

        IF @is_new = 1
        BEGIN
            DECLARE @payload NVARCHAR(MAX) = (
                SELECT CONVERT(NVARCHAR(30), p.id) AS postId, CONVERT(NVARCHAR(30), p.author_id) AS authorId,
                       @my_name AS authorName, p.visibility, CONVERT(NVARCHAR(30), p.department_id) AS departmentId,
                       CONVERT(NVARCHAR(30), p.branch_id) AS branchId, LEFT(p.body, 500) AS body,
                       (SELECT COUNT(*) FROM @md) AS mediaCount, p.posted_at AS postedAt, @link AS link
                FROM [eng].[post] p WHERE p.id = @id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.post_published',
                 @entity_type = N'eng.post', @entity_id = @id, @payload = @payload;
        END
    COMMIT;

    EXEC [eng].[usp_post_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Deletes a post: its author (engagement.feed.delete) or a moderator of its author
-- (engagement.moderation.delete). The row stays, marked deleted, for the audit trail.
CREATE OR ALTER PROCEDURE [eng].[usp_post_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    DECLARE @author BIGINT, @rv BINARY(8);
    SELECT @author = author_id, @rv = row_version FROM [eng].[post] WHERE id = @id AND company_id = @company_id;

    IF NOT ((@author = @me AND EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.feed.delete') WHERE employee_id = @me))
            OR EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.delete') WHERE employee_id = @author))
        THROW 50403, N'You can delete only your own posts.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this post. Reload it and try again', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [eng].[post]
        SET is_deleted = 1, deleted_at = @now, deleted_by_user_id = @actor_user_id, is_pinned = 0,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this post. Reload it and try again', 1;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.post', @id, N'delete', @actor_user_id, @now);

        IF @author <> ISNULL(@me, 0)
            EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @author,
                 @title = N'Your post was removed by a moderator', @entity_type = N'eng.post', @entity_id = @id;

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), @id) AS postId, CONVERT(NVARCHAR(30), @author) AS authorId,
                   CAST(CASE WHEN @author = ISNULL(@me, 0) THEN 1 ELSE 0 END AS BIT) AS byAuthor, @now AS deletedAt
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.post_deleted',
             @entity_type = N'eng.post', @entity_id = @id, @payload = @payload;
    COMMIT;
END
GO

-- Counts the caller's view of a post, once per person; the author's own views do not count.
CREATE OR ALTER PROCEDURE [eng].[usp_post_view]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    DECLARE @counted BIT = 0;

    IF @me IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [eng].[post] WHERE id = @id AND author_id = @me)
    BEGIN
        BEGIN TRAN;
            INSERT [eng].[post_view] (post_id, employee_id, viewed_at, created_by)
            SELECT @id, @me, SYSUTCDATETIME(), @actor_user_id
            WHERE NOT EXISTS (SELECT 1 FROM [eng].[post_view] WITH (UPDLOCK, HOLDLOCK) WHERE post_id = @id AND employee_id = @me);
            SET @counted = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
        COMMIT;
    END

    SELECT @id AS id, (SELECT COUNT(*) FROM [eng].[post_view] WHERE post_id = @id) AS view_count, @counted AS counted;
END
GO

-- Pins a post to the top of the feed, or unpins it: moderators of its author.
CREATE OR ALTER PROCEDURE [eng].[usp_post_pin]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @is_pinned     BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;
    DECLARE @author BIGINT, @hidden BIT;
    SELECT @author = author_id, @hidden = is_hidden FROM [eng].[post] WHERE id = @id;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.edit') WHERE employee_id = @author)
        THROW 50403, N'You do not moderate this post.', 1;
    IF @is_pinned = 1 AND @hidden = 1
        THROW 50409, N'isPinned|POST_HIDDEN|A hidden post cannot be pinned. Show it first.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [eng].[post]
        SET is_pinned = @is_pinned, pinned_at = CASE WHEN @is_pinned = 1 THEN @now END,
            pinned_by_user_id = CASE WHEN @is_pinned = 1 THEN @actor_user_id END, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND is_pinned <> @is_pinned;
        IF @@ROWCOUNT > 0
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.post', @id, CASE WHEN @is_pinned = 1 THEN N'pin' ELSE N'unpin' END, @actor_user_id, @now);
    COMMIT;

    EXEC [eng].[usp_post_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- Hides a post from the feed (only its author and moderators still see it), or shows it again.
-- Hiding unpins the post and tells the author.
CREATE OR ALTER PROCEDURE [eng].[usp_post_hide]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @is_hidden     BIT,
    @reason        NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;
    DECLARE @author BIGINT, @was BIT;
    SELECT @author = author_id, @was = is_hidden FROM [eng].[post] WHERE id = @id;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'engagement.moderation.edit') WHERE employee_id = @author)
        THROW 50403, N'You do not moderate this post.', 1;
    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF LEN(@reason) > 500
        THROW 50400, N'reason|The reason must be within 500 characters.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    BEGIN TRAN;
        UPDATE [eng].[post]
        SET is_hidden = @is_hidden, hidden_at = CASE WHEN @is_hidden = 1 THEN @now END,
            hidden_by_user_id = CASE WHEN @is_hidden = 1 THEN @actor_user_id END,
            hidden_reason = CASE WHEN @is_hidden = 1 THEN @reason END,
            is_pinned = CASE WHEN @is_hidden = 1 THEN 0 ELSE is_pinned END,
            pinned_at = CASE WHEN @is_hidden = 1 THEN NULL ELSE pinned_at END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;

        IF @was <> @is_hidden
        BEGIN
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.post', @id, N'hidden_reason', @reason,
                    CASE WHEN @is_hidden = 1 THEN N'hide' ELSE N'unhide' END, @actor_user_id, @now);
            IF @is_hidden = 1
            BEGIN
                IF @author <> ISNULL(@me, 0)
                    EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @author,
                         @title = N'Your post was hidden by a moderator', @body = @reason,
                         @link = N'/engagement/my-posts', @entity_type = N'eng.post', @entity_id = @id;
                DECLARE @payload NVARCHAR(MAX) = (
                    SELECT CONVERT(NVARCHAR(30), @id) AS postId, CONVERT(NVARCHAR(30), @author) AS authorId,
                           @reason AS reason, @now AS hiddenAt
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
                EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.post_hidden',
                     @entity_type = N'eng.post', @entity_id = @id, @payload = @payload;
            END
        END
    COMMIT;

    EXEC [eng].[usp_post_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
