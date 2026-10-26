-- Surveys (HR side): the builder (title, closing date, questions, options, audience), publishing,
-- closing, extending, deleting. A survey is edited only while it is a draft; once published, only its
-- closing date moves. Publishing tells everyone in the audience ("Survey Available").

-- Result set 1: total. Result set 2: the page, newest first. @status filters the effective status.
CREATE OR ALTER PROCEDURE [eng].[usp_survey_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @status     NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [eng].[fn_survey_rows](@company_id, @today) r
    WHERE (@status IS NULL OR r.status = @status) AND (@pattern IS NULL OR r.title LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [eng].[fn_survey_rows](@company_id, @today) r
    WHERE (@status IS NULL OR r.status = @status) AND (@pattern IS NULL OR r.title LIKE @pattern)
    ORDER BY r.created_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One survey with its questions (questions_json) and audience (audience_json: [{unit_type, unit_id, name}]).
CREATE OR ALTER PROCEDURE [eng].[usp_survey_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[survey] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Survey not found', 1;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    SELECT r.*, [eng].[fn_survey_questions_json](r.id) AS questions_json,
           (SELECT a.unit_type, CONVERT(NVARCHAR(30), a.unit_id) AS unit_id,
                   COALESCE(d.name, b.name, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')) AS name
            FROM [eng].[survey_audience] a
            LEFT JOIN [org].[department] d ON a.unit_type = N'department' AND d.id = a.unit_id
            LEFT JOIN [org].[branch] b ON a.unit_type = N'branch' AND b.id = a.unit_id
            LEFT JOIN [hr].[employee] e ON a.unit_type = N'employee' AND e.id = a.unit_id
            WHERE a.survey_id = r.id ORDER BY a.unit_type, a.id FOR JSON PATH) AS audience_json
    FROM [eng].[fn_survey_rows](@company_id, @today) r
    WHERE r.id = @id;
END
GO

-- Creates (@id NULL) or edits a draft survey, replacing its questions and audience.
-- @questions: [{question_type, question_text, is_required, scale_min, scale_max, scale_min_label,
--               scale_max_label, options: ["text", ...]}]; @audience: [{unit_type, unit_id}] (none = everyone).
CREATE OR ALTER PROCEDURE [eng].[usp_survey_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @title         NVARCHAR(200),
    @description   NVARCHAR(MAX) = NULL,
    @is_anonymous  BIT = 0,
    @opens_on      DATE = NULL,
    @closes_on     DATE = NULL,
    @questions     NVARCHAR(MAX) = NULL,
    @audience      NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Give the survey a title.', 1;
    IF @opens_on IS NOT NULL AND @closes_on IS NOT NULL AND @closes_on < @opens_on
        THROW 50400, N'closesOn|The closing date is before the opening date.', 1;
    IF ISJSON(ISNULL(@questions, N'[]')) = 0
        THROW 50400, N'questions|The questions are not valid.', 1;
    IF ISJSON(ISNULL(@audience, N'[]')) = 0
        THROW 50400, N'audience|The audience is not valid.', 1;

    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    IF @id IS NOT NULL
    BEGIN
        SELECT @rv = row_version, @status = status FROM [eng].[survey] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Survey not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a survey.', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
        IF @status <> N'draft'
            THROW 50409, N'status|SURVEY_NOT_DRAFT|A published survey cannot be changed; only its closing date can move.', 1;
    END

    -- Audience
    DECLARE @aud TABLE (unit_type NVARCHAR(30), unit_id BIGINT, PRIMARY KEY (unit_type, unit_id));
    INSERT @aud
    SELECT DISTINCT j.unit_type, j.unit_id
    FROM OPENJSON(ISNULL(@audience, N'[]')) WITH (unit_type NVARCHAR(30) '$.unit_type', unit_id BIGINT '$.unit_id') j;
    IF EXISTS (SELECT 1 FROM @aud WHERE unit_type IS NULL OR unit_id IS NULL OR unit_type NOT IN (N'department', N'branch', N'employee'))
        THROW 50400, N'audience|Choose departments, branches or people.', 1;
    IF EXISTS (SELECT 1 FROM @aud a WHERE
                  (a.unit_type = N'department' AND NOT EXISTS (SELECT 1 FROM [org].[department] d WHERE d.id = a.unit_id AND d.company_id = @company_id))
               OR (a.unit_type = N'branch' AND NOT EXISTS (SELECT 1 FROM [org].[branch] b WHERE b.id = a.unit_id AND b.company_id = @company_id))
               OR (a.unit_type = N'employee' AND NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = a.unit_id AND e.company_id = @company_id)))
        THROW 50400, N'audience|A department, branch or person in the audience was not found.', 1;

    -- Questions
    DECLARE @q TABLE (pos INT PRIMARY KEY, question_type NVARCHAR(30), question_text NVARCHAR(MAX), is_required BIT,
                      scale_min INT, scale_max INT, scale_min_label NVARCHAR(200), scale_max_label NVARCHAR(200),
                      options NVARCHAR(MAX));
    INSERT @q
    SELECT CAST(j.[key] AS INT), x.question_type, LTRIM(RTRIM(x.question_text)), ISNULL(x.is_required, 0),
           x.scale_min, x.scale_max, NULLIF(LTRIM(RTRIM(x.scale_min_label)), N''), NULLIF(LTRIM(RTRIM(x.scale_max_label)), N''),
           x.options
    FROM OPENJSON(ISNULL(@questions, N'[]')) j
    CROSS APPLY OPENJSON(j.[value]) WITH (question_type NVARCHAR(30) '$.question_type', question_text NVARCHAR(MAX) '$.question_text',
        is_required BIT '$.is_required', scale_min INT '$.scale_min', scale_max INT '$.scale_max',
        scale_min_label NVARCHAR(200) '$.scale_min_label', scale_max_label NVARCHAR(200) '$.scale_max_label',
        options NVARCHAR(MAX) '$.options' AS JSON) x;

    IF (SELECT COUNT(*) FROM @q) > 100
        THROW 50400, N'questions|A survey can have at most 100 questions.', 1;
    UPDATE @q SET scale_min = ISNULL(scale_min, 1), scale_max = ISNULL(scale_max, 5) WHERE question_type = N'rating';

    DECLARE @pos INT = (SELECT MIN(pos) FROM @q), @msg NVARCHAR(400), @n INT;
    DECLARE @qt NVARCHAR(30), @qx NVARCHAR(MAX), @smin INT, @smax INT, @smin_l NVARCHAR(200), @smax_l NVARCHAR(200), @opts NVARCHAR(MAX);
    WHILE @pos IS NOT NULL
    BEGIN
        SELECT @qt = question_type, @qx = question_text, @smin = scale_min, @smax = scale_max, @smin_l = scale_min_label,
               @smax_l = scale_max_label, @opts = options
        FROM @q WHERE pos = @pos;
        IF @qt IS NULL OR @qt NOT IN (N'single', N'dropdown', N'multiple', N'text', N'paragraph', N'rating')
        BEGIN
            SET @msg = CONCAT(N'questions[', @pos, N'].questionType|Choose the question type.');
            THROW 50400, @msg, 1;
        END
        IF @qx IS NULL OR @qx = N'' OR LEN(@qx) > 1000
        BEGIN
            SET @msg = CONCAT(N'questions[', @pos, N'].questionText|Write the question (up to 1000 characters).');
            THROW 50400, @msg, 1;
        END
        IF @qt IN (N'single', N'dropdown', N'multiple')
        BEGIN
            SELECT @n = COUNT(*) FROM OPENJSON(ISNULL(@opts, N'[]')) o WHERE NULLIF(LTRIM(RTRIM(o.[value])), N'') IS NOT NULL;
            IF @n < 2
            BEGIN
                SET @msg = CONCAT(N'questions[', @pos, N'].options|Give at least two options.');
                THROW 50400, @msg, 1;
            END
            IF EXISTS (SELECT 1 FROM OPENJSON(ISNULL(@opts, N'[]')) o WHERE LEN(LTRIM(RTRIM(o.[value]))) > 500)
               OR EXISTS (SELECT LTRIM(RTRIM(o.[value])) FROM OPENJSON(ISNULL(@opts, N'[]')) o
                          WHERE NULLIF(LTRIM(RTRIM(o.[value])), N'') IS NOT NULL
                          GROUP BY LTRIM(RTRIM(o.[value])) HAVING COUNT(*) > 1)
            BEGIN
                SET @msg = CONCAT(N'questions[', @pos, N'].options|Options must be different and up to 500 characters.');
                THROW 50400, @msg, 1;
            END
        END
        IF @qt = N'rating' AND (@smin NOT IN (0, 1) OR @smax NOT BETWEEN 2 AND 10)
        BEGIN
            SET @msg = CONCAT(N'questions[', @pos, N'].scaleMax|A scale runs from 0 or 1 up to 2 to 10.');
            THROW 50400, @msg, 1;
        END
        IF LEN(@smin_l) > 100 OR LEN(@smax_l) > 100
        BEGIN
            SET @msg = CONCAT(N'questions[', @pos, N'].scaleMinLabel|Scale labels are up to 100 characters.');
            THROW 50400, @msg, 1;
        END
        SET @pos = (SELECT MIN(pos) FROM @q WHERE pos > @pos);
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [eng].[survey] (company_id, title, description, is_anonymous, status, opens_on, closes_on, created_by)
            VALUES (@company_id, @title, @description, ISNULL(@is_anonymous, 0), N'draft', @opens_on, @closes_on, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.survey', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [eng].[survey]
            SET title = @title, description = @description, is_anonymous = ISNULL(@is_anonymous, 0), opens_on = @opens_on,
                closes_on = @closes_on, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
            DELETE o FROM [eng].[survey_option] o JOIN [eng].[survey_question] q ON q.id = o.survey_question_id WHERE q.survey_id = @id;
            DELETE [eng].[survey_question] WHERE survey_id = @id;
            DELETE [eng].[survey_audience] WHERE survey_id = @id;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'eng.survey', @id, N'update', @actor_user_id, @now);
        END

        INSERT [eng].[survey_audience] (survey_id, unit_type, unit_id, created_by)
        SELECT @id, unit_type, unit_id, @actor_user_id FROM @aud;

        DECLARE @qid BIGINT, @order INT = 0;
        SET @pos = (SELECT MIN(pos) FROM @q);
        WHILE @pos IS NOT NULL
        BEGIN
            SET @order += 1;
            INSERT [eng].[survey_question] (survey_id, sort_order, question_type, question_text, is_required, scale_min, scale_max,
                                            scale_min_label, scale_max_label, created_by)
            SELECT @id, @order, question_type, question_text, is_required,
                   CASE WHEN question_type = N'rating' THEN scale_min END, CASE WHEN question_type = N'rating' THEN scale_max END,
                   CASE WHEN question_type = N'rating' THEN scale_min_label END, CASE WHEN question_type = N'rating' THEN scale_max_label END,
                   @actor_user_id
            FROM @q WHERE pos = @pos;
            SET @qid = SCOPE_IDENTITY();

            INSERT [eng].[survey_option] (survey_question_id, sort_order, option_text, created_by)
            SELECT @qid, ROW_NUMBER() OVER (ORDER BY CAST(o.[key] AS INT)), LTRIM(RTRIM(o.[value])), @actor_user_id
            FROM @q x CROSS APPLY OPENJSON(ISNULL(x.options, N'[]')) o
            WHERE x.pos = @pos AND x.question_type IN (N'single', N'dropdown', N'multiple')
              AND NULLIF(LTRIM(RTRIM(o.[value])), N'') IS NOT NULL;

            SET @pos = (SELECT MIN(pos) FROM @q WHERE pos > @pos);
        END
    COMMIT;

    EXEC [eng].[usp_survey_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a survey that nobody has answered yet (drafts, or published ones without answers).
-- Answered surveys are closed instead, so their results stay.
CREATE OR ALTER PROCEDURE [eng].[usp_survey_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [eng].[survey] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Survey not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [eng].[survey_response] WHERE survey_id = @id)
        THROW 50409, N'id|SURVEY_HAS_RESPONSES|People have answered this survey. Close it instead of deleting it.', 1;

    BEGIN TRAN;
        DELETE [eng].[survey_participant] WHERE survey_id = @id;
        DELETE o FROM [eng].[survey_option] o JOIN [eng].[survey_question] q ON q.id = o.survey_question_id WHERE q.survey_id = @id;
        DELETE [eng].[survey_question] WHERE survey_id = @id;
        DELETE [eng].[survey_audience] WHERE survey_id = @id;
        DELETE [eng].[survey] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.survey', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Publishes a draft: it needs at least one question and a closing date not in the past. Everyone in
-- the audience is told in the inbox ("Survey Available").
CREATE OR ALTER PROCEDURE [eng].[usp_survey_publish]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @title NVARCHAR(200), @opens DATE, @closes DATE, @anon BIT;
    SELECT @rv = row_version, @status = status, @title = title, @opens = opens_on, @closes = closes_on, @anon = is_anonymous
    FROM [eng].[survey] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Survey not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
    IF @status <> N'draft'
        THROW 50409, N'status|SURVEY_NOT_DRAFT|This survey is already published.', 1;
    IF NOT EXISTS (SELECT 1 FROM [eng].[survey_question] WHERE survey_id = @id)
        THROW 50400, N'questions|Add at least one question before publishing.', 1;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    IF @closes IS NOT NULL AND @closes < @today
        THROW 50400, N'closesOn|The closing date has passed. Move it before publishing.', 1;
    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_survey_audience](@company_id, @id))
        THROW 50400, N'audience|Nobody is in this survey''s audience.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @people TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @people SELECT employee_id FROM [eng].[fn_survey_audience](@company_id, @id);

    BEGIN TRAN;
        UPDATE [eng].[survey]
        SET status = N'published', opens_on = ISNULL(opens_on, @today), published_at = @now,
            published_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.survey', @id, N'publish', @actor_user_id, @now);

        DECLARE @n_title NVARCHAR(200) = LEFT(CONCAT(N'Survey available: ', @title), 200);
        DECLARE @n_body NVARCHAR(400) = CASE WHEN @closes IS NULL THEN N'Your feedback is valuable. Please take a few minutes to complete this survey.'
            ELSE CONCAT(N'Your feedback is valuable. Please respond by ', CONVERT(NVARCHAR(10), @closes, 23), N'.') END;
        DECLARE @link NVARCHAR(500) = CONCAT(N'/engagement/my-surveys/', @id);
        DECLARE @who BIGINT = (SELECT MIN(employee_id) FROM @people);
        WHILE @who IS NOT NULL
        BEGIN
            EXEC [eng].[usp_engagement_notify] @company_id = @company_id, @employee_id = @who, @title = @n_title,
                 @body = @n_body, @link = @link, @entity_type = N'eng.survey', @entity_id = @id;
            SET @who = (SELECT MIN(employee_id) FROM @people WHERE employee_id > @who);
        END

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), s.id) AS surveyId, s.title, s.is_anonymous AS isAnonymous, s.opens_on AS opensOn,
                   s.closes_on AS closesOn, (SELECT COUNT(*) FROM @people) AS audienceCount,
                   (SELECT COUNT(*) FROM [eng].[survey_question] q WHERE q.survey_id = s.id) AS questionCount,
                   s.published_at AS publishedAt, @link AS link
            FROM [eng].[survey] s WHERE s.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.survey_published',
             @entity_type = N'eng.survey', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [eng].[usp_survey_get] @company_id = @company_id, @id = @id;
END
GO

-- Closes a published survey now: nobody can respond any more; the results stay.
CREATE OR ALTER PROCEDURE [eng].[usp_survey_close]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = row_version, @status = status FROM [eng].[survey] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Survey not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
    IF @status <> N'published'
        THROW 50409, N'status|SURVEY_NOT_PUBLISHED|Only a published survey can be closed.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [eng].[survey]
        SET status = N'closed', closed_at = @now, closed_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.survey', @id, N'close', @actor_user_id, @now);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), r.id) AS surveyId, r.title, r.audience_count AS audienceCount,
                   r.response_count AS responseCount, r.skipped_count AS skippedCount, r.closed_at AS closedAt
            FROM [eng].[fn_survey_rows](@company_id, CAST(@now AS DATE)) r WHERE r.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.survey_closed',
             @entity_type = N'eng.survey', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [eng].[usp_survey_get] @company_id = @company_id, @id = @id;
END
GO

-- Moves the closing date of a published survey (extend, or close earlier). A survey that already
-- passed its closing date opens again when the new date is later.
CREATE OR ALTER PROCEDURE [eng].[usp_survey_closing_date]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @closes_on     DATE = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @opens DATE, @old DATE;
    SELECT @rv = row_version, @status = status, @opens = opens_on, @old = closes_on
    FROM [eng].[survey] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Survey not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
    IF @status <> N'published'
        THROW 50409, N'status|SURVEY_NOT_PUBLISHED|Only a published survey''s closing date can move; edit a draft instead.', 1;
    IF @closes_on IS NOT NULL AND (@closes_on < CAST(SYSUTCDATETIME() AS DATE) OR @closes_on < @opens)
        THROW 50400, N'closesOn|The closing date cannot be in the past or before the opening date.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [eng].[survey] SET closes_on = @closes_on, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this survey. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'eng.survey', @id, N'closes_on', CONVERT(NVARCHAR(10), @old, 23), CONVERT(NVARCHAR(10), @closes_on, 23),
                N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [eng].[usp_survey_get] @company_id = @company_id, @id = @id;
END
