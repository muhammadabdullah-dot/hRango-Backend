-- Engagement -> Settings -> General, kept in core.company_setting (module 'engagement'):
--   who_may_post        everyone (anyone holding engagement.feed.create) or moderators (engagement.moderation.edit)
--   allow_comments      comments and replies on posts
--   max_media_per_post  photos and videos on one post (1 to 20)
-- The row version of the form is the newest row version of the module's rows (NULL before the first save).
CREATE OR ALTER PROCEDURE [eng].[usp_engagement_settings_get]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- One subquery per key (not MAX(CASE ...)): a "null value eliminated" warning would hide the
    -- errors of the procedures that read these settings.
    SELECT ISNULL((SELECT s.setting_value FROM [core].[company_setting] s
                   WHERE s.company_id = @company_id AND s.module = N'engagement' AND s.setting_key = N'who_may_post'), N'everyone') AS who_may_post,
           CAST(ISNULL((SELECT s.setting_value FROM [core].[company_setting] s
                        WHERE s.company_id = @company_id AND s.module = N'engagement' AND s.setting_key = N'allow_comments'), N'1') AS BIT) AS allow_comments,
           CAST(ISNULL((SELECT s.setting_value FROM [core].[company_setting] s
                        WHERE s.company_id = @company_id AND s.module = N'engagement' AND s.setting_key = N'max_media_per_post'), N'10') AS INT) AS max_media_per_post,
           (SELECT MAX(s.row_version) FROM [core].[company_setting] s
            WHERE s.company_id = @company_id AND s.module = N'engagement') AS row_version;
END
GO

CREATE OR ALTER PROCEDURE [eng].[usp_engagement_settings_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT = NULL,
    @who_may_post       NVARCHAR(30),
    @allow_comments     BIT,
    @max_media_per_post INT,
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @who_may_post IS NULL OR @who_may_post NOT IN (N'everyone', N'moderators')
        THROW 50400, N'whoMayPost|Choose everyone or moderators.', 1;
    IF @allow_comments IS NULL
        THROW 50400, N'allowComments|Say whether comments are allowed.', 1;
    IF @max_media_per_post IS NULL OR @max_media_per_post NOT BETWEEN 1 AND 20
        THROW 50400, N'maxMediaPerPost|Allow between 1 and 20 photos or videos on a post.', 1;

    DECLARE @current BINARY(8) = (SELECT MAX(row_version) FROM [core].[company_setting]
                                  WHERE company_id = @company_id AND module = N'engagement');
    IF @current IS NOT NULL AND (@row_version IS NULL OR @row_version <> @current)
        THROW 50409, N'Someone else changed the engagement settings. Reload them and try again', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @new TABLE (setting_key NVARCHAR(100), setting_value NVARCHAR(MAX));
    INSERT @new VALUES (N'who_may_post', @who_may_post),
                       (N'allow_comments', CASE WHEN @allow_comments = 1 THEN N'1' ELSE N'0' END),
                       (N'max_media_per_post', CAST(@max_media_per_post AS NVARCHAR(10)));

    BEGIN TRAN;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'eng.settings', @company_id, n.setting_key, s.setting_value, n.setting_value, N'update', @actor_user_id, @now
        FROM @new n
        LEFT JOIN [core].[company_setting] s ON s.company_id = @company_id AND s.module = N'engagement' AND s.setting_key = n.setting_key
        WHERE EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);

        UPDATE s SET setting_value = n.setting_value, updated_at = @now, updated_by = @actor_user_id
        FROM [core].[company_setting] s
        JOIN @new n ON n.setting_key = s.setting_key
        WHERE s.company_id = @company_id AND s.module = N'engagement'
          AND EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);

        INSERT [core].[company_setting] (company_id, module, setting_key, setting_value, created_by)
        SELECT @company_id, N'engagement', n.setting_key, n.setting_value, @actor_user_id
        FROM @new n
        WHERE NOT EXISTS (SELECT 1 FROM [core].[company_setting] s
                          WHERE s.company_id = @company_id AND s.module = N'engagement' AND s.setting_key = n.setting_key);
    COMMIT;

    EXEC [eng].[usp_engagement_settings_get] @company_id = @company_id;
END
GO

-- Tells one employee in the inbox (all their sign-in accounts) without returning a result set, so
-- the engagement procedures can call it inside their own transactions.
CREATE OR ALTER PROCEDURE [eng].[usp_engagement_notify]
    @company_id  BIGINT,
    @employee_id BIGINT,
    @title       NVARCHAR(200),
    @body        NVARCHAR(MAX) = NULL,
    @link        NVARCHAR(500) = NULL,
    @entity_type NVARCHAR(50) = NULL,
    @entity_id   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @employee_id IS NULL
        RETURN;
    EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
         @title = @title, @body = @body, @notification_type = N'engagement', @link = @link,
         @entity_type = @entity_type, @entity_id = @entity_id;
END
