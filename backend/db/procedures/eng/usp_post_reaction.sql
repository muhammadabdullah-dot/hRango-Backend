-- Reactions on a post ("Liked", "Reactions on Post"): one per person per post; a new reaction tells
-- the post's author (never for their own reaction). Kinds: like, love, celebrate, support, insightful, funny.

-- Sets, changes (@kind) or takes off (@kind NULL) the caller's reaction. Returns the post.
CREATE OR ALTER PROCEDURE [eng].[usp_post_react]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @kind          NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;
    DECLARE @me BIGINT, @my_name NVARCHAR(200);
    SELECT @me = e.id, @my_name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')
    FROM [auth].[user_account] u JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.id = @actor_user_id;
    IF @me IS NULL
        THROW 50403, N'Only employees can react to posts.', 1;
    IF @kind IS NOT NULL AND @kind NOT IN (N'like', N'love', N'celebrate', N'support', N'insightful', N'funny')
        THROW 50400, N'kind|Choose like, love, celebrate, support, insightful or funny.', 1;
    DECLARE @author BIGINT, @hidden BIT;
    SELECT @author = author_id, @hidden = is_hidden FROM [eng].[post] WHERE id = @id;
    IF @hidden = 1 AND @kind IS NOT NULL
        THROW 50409, N'kind|POST_HIDDEN|This post is hidden.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @kind IS NULL
            DELETE [eng].[post_reaction] WHERE post_id = @id AND employee_id = @me;
        ELSE
        BEGIN
            UPDATE [eng].[post_reaction] WITH (UPDLOCK, HOLDLOCK)
            SET kind = @kind, reacted_at = @now, updated_at = @now, updated_by = @actor_user_id
            WHERE post_id = @id AND employee_id = @me;
            IF @@ROWCOUNT = 0
            BEGIN
                INSERT [eng].[post_reaction] (post_id, employee_id, kind, reacted_at, created_by)
                VALUES (@id, @me, @kind, @now, @actor_user_id);
                IF @author <> @me
                BEGIN
                    DECLARE @title NVARCHAR(200) = LEFT(CONCAT(@my_name, N' reacted to your post'), 200);
                    DECLARE @link NVARCHAR(500) = CONCAT(N'/engagement/posts/', @id);
                    EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @author, @title = @title,
                         @link = @link, @entity_type = N'eng.post', @entity_id = @id;
                END
            END
        END
    COMMIT;

    EXEC [eng].[usp_post_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- "Reactions on Post": who reacted and how. Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [eng].[usp_post_reaction_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @kind          NVARCHAR(30) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_visible_posts](@company_id, @actor_user_id) WHERE post_id = @id)
        THROW 50404, N'Post not found', 1;

    SELECT COUNT(*) AS total FROM [eng].[post_reaction] WHERE post_id = @id AND (@kind IS NULL OR kind = @kind);

    SELECT r.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.photo_file_id, d.name AS department_name, r.kind, r.reacted_at
    FROM [eng].[post_reaction] r
    JOIN [hr].[employee] e ON e.id = r.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE r.post_id = @id AND (@kind IS NULL OR r.kind = @kind)
    ORDER BY r.reacted_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
