-- Surveys (employee side): the "Survey Available" popup and My Surveys, answering, skipping.
-- Someone may answer a survey once, while it is open, if they are in its audience. Skipping is not
-- final: a skipped survey can still be answered while it is open. Answers are final once sent.
-- Anonymous surveys keep the answers without the employee (survey_response.employee_id and
-- created_by blank, time cut to the day); survey_participant alone records that they answered.

-- Result set 1: total. Result set 2: the page. @filter: pending (open, not answered, not skipped),
-- answered, skipped, all. my_status: pending, answered, skipped, missed (closed without an answer).
CREATE OR ALTER PROCEDURE [eng].[usp_my_survey_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @filter        NVARCHAR(20) = N'pending',
    @page          INT = 1,
    @page_size     INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);

    DECLARE @rows TABLE (id BIGINT PRIMARY KEY, my_status NVARCHAR(20), responded_at DATETIME2(0), skipped_at DATETIME2(0),
                         closes_on DATE, published_at DATETIME2(0));
    INSERT @rows
    SELECT s.id,
           CASE WHEN p.responded_at IS NOT NULL THEN N'answered'
                WHEN s.status = N'closed' OR s.closes_on < @today THEN N'missed'
                WHEN p.skipped = 1 THEN N'skipped' ELSE N'pending' END,
           p.responded_at, p.skipped_at, s.closes_on, s.published_at
    FROM [eng].[survey] s
    LEFT JOIN [eng].[survey_participant] p ON p.survey_id = s.id AND p.employee_id = @me
    WHERE s.company_id = @company_id AND @me IS NOT NULL AND s.status <> N'draft'
      AND ISNULL(s.opens_on, @today) <= @today
      AND (p.employee_id IS NOT NULL OR EXISTS (SELECT 1 FROM [eng].[fn_survey_audience](@company_id, s.id) a WHERE a.employee_id = @me));

    DELETE @rows WHERE @filter <> N'all' AND my_status <> @filter;

    SELECT COUNT(*) AS total FROM @rows;

    SELECT r.id, r.title, r.description, r.is_anonymous, r.status, r.opens_on, r.closes_on, r.is_open, r.question_count,
           x.my_status, x.responded_at, x.skipped_at
    FROM @rows x
    JOIN [eng].[fn_survey_rows](@company_id, @today) r ON r.id = x.id
    ORDER BY CASE x.my_status WHEN N'pending' THEN 0 WHEN N'skipped' THEN 1 ELSE 2 END,
             ISNULL(x.closes_on, '9999-12-31'), x.published_at DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- One survey to answer, with its questions (questions_json) and the caller's status.
CREATE OR ALTER PROCEDURE [eng].[usp_my_survey_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    IF @me IS NULL OR NOT EXISTS (
        SELECT 1 FROM [eng].[survey] s
        WHERE s.id = @id AND s.company_id = @company_id AND s.status <> N'draft' AND ISNULL(s.opens_on, @today) <= @today
          AND (EXISTS (SELECT 1 FROM [eng].[survey_participant] p WHERE p.survey_id = s.id AND p.employee_id = @me)
               OR EXISTS (SELECT 1 FROM [eng].[fn_survey_audience](@company_id, s.id) a WHERE a.employee_id = @me)))
        THROW 50404, N'Survey not found', 1;

    SELECT r.id, r.title, r.description, r.is_anonymous, r.status, r.opens_on, r.closes_on, r.is_open, r.question_count,
           CASE WHEN p.responded_at IS NOT NULL THEN N'answered'
                WHEN r.is_open = 0 THEN N'missed'
                WHEN p.skipped = 1 THEN N'skipped' ELSE N'pending' END AS my_status,
           p.responded_at, p.skipped_at, [eng].[fn_survey_questions_json](r.id) AS questions_json
    FROM [eng].[fn_survey_rows](@company_id, @today) r
    LEFT JOIN [eng].[survey_participant] p ON p.survey_id = r.id AND p.employee_id = @me
    WHERE r.id = @id;
END
GO

-- Sends the caller's answers. @answers: [{question_id, option_ids: [..], text, rating}].
CREATE OR ALTER PROCEDURE [eng].[usp_survey_respond]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @answers       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    IF @me IS NULL
        THROW 50403, N'Only employees can answer surveys.', 1;
    DECLARE @status NVARCHAR(30), @opens DATE, @closes DATE, @anon BIT;
    SELECT @status = status, @opens = opens_on, @closes = closes_on, @anon = is_anonymous
    FROM [eng].[survey] WHERE id = @id AND company_id = @company_id;
    IF @status IS NULL OR @status = N'draft'
        THROW 50404, N'Survey not found', 1;
    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_survey_audience](@company_id, @id) WHERE employee_id = @me)
       AND NOT EXISTS (SELECT 1 FROM [eng].[survey_participant] WHERE survey_id = @id AND employee_id = @me)
        THROW 50403, N'This survey is not addressed to you.', 1;
    IF @status <> N'published' OR ISNULL(@opens, @today) > @today OR @closes < @today
        THROW 50409, N'id|SURVEY_CLOSED|This survey is not open for answers.', 1;
    IF ISJSON(ISNULL(@answers, N'[]')) = 0
        THROW 50400, N'answers|The answers are not valid.', 1;

    DECLARE @a TABLE (question_id BIGINT, option_ids NVARCHAR(MAX), answer_text NVARCHAR(MAX), rating INT);
    INSERT @a
    SELECT j.question_id, j.option_ids, NULLIF(LTRIM(RTRIM(j.answer_text)), N''), j.rating
    FROM OPENJSON(ISNULL(@answers, N'[]')) WITH (question_id BIGINT '$.question_id', option_ids NVARCHAR(MAX) '$.option_ids' AS JSON,
                                                 answer_text NVARCHAR(MAX) '$.text', rating INT '$.rating') j;
    IF EXISTS (SELECT 1 FROM @a a WHERE a.question_id IS NULL
                  OR NOT EXISTS (SELECT 1 FROM [eng].[survey_question] q WHERE q.id = a.question_id AND q.survey_id = @id))
        THROW 50400, N'answers|An answer is for a question that is not in this survey.', 1;
    IF EXISTS (SELECT question_id FROM @a GROUP BY question_id HAVING COUNT(*) > 1)
        THROW 50400, N'answers|A question is answered twice.', 1;

    DECLARE @opt TABLE (question_id BIGINT, option_id BIGINT);
    INSERT @opt SELECT DISTINCT a.question_id, TRY_CAST(o.[value] AS BIGINT)
    FROM @a a CROSS APPLY OPENJSON(ISNULL(a.option_ids, N'[]')) o;

    DECLARE @chk TABLE (question_id BIGINT PRIMARY KEY, sort_order INT, question_type NVARCHAR(30), is_required BIT,
                        scale_min INT, scale_max INT, n_opts INT, answer_text NVARCHAR(MAX), rating INT);
    INSERT @chk
    SELECT q.id, q.sort_order, q.question_type, q.is_required, q.scale_min, q.scale_max,
           CASE WHEN q.question_type IN (N'single', N'dropdown', N'multiple') THEN (SELECT COUNT(*) FROM @opt x WHERE x.question_id = q.id) ELSE 0 END,
           CASE WHEN q.question_type IN (N'text', N'paragraph') THEN a.answer_text END,
           CASE WHEN q.question_type = N'rating' THEN a.rating END
    FROM [eng].[survey_question] q
    LEFT JOIN @a a ON a.question_id = q.id
    WHERE q.survey_id = @id;

    DECLARE @bad BIGINT, @msg NVARCHAR(400);
    SELECT TOP 1 @bad = x.question_id FROM @opt o JOIN @chk x ON x.question_id = o.question_id
    WHERE x.question_type IN (N'single', N'dropdown', N'multiple')
      AND (o.option_id IS NULL OR NOT EXISTS (SELECT 1 FROM [eng].[survey_option] so WHERE so.id = o.option_id AND so.survey_question_id = o.question_id))
    ORDER BY x.sort_order;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers[', @bad, N']|Choose one of the question''s options.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = question_id FROM @chk WHERE question_type IN (N'single', N'dropdown') AND n_opts > 1 ORDER BY sort_order;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers[', @bad, N']|Choose only one option.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = question_id FROM @chk
    WHERE (question_type = N'text' AND LEN(answer_text) > 500) OR (question_type = N'paragraph' AND LEN(answer_text) > 5000)
    ORDER BY sort_order;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers[', @bad, N']|The answer is too long (short answers 500, paragraphs 5000 characters).');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = question_id FROM @chk WHERE question_type = N'rating' AND rating NOT BETWEEN scale_min AND scale_max ORDER BY sort_order;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers[', @bad, N']|Choose a value on the scale.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = question_id FROM @chk
    WHERE is_required = 1 AND n_opts = 0 AND answer_text IS NULL AND rating IS NULL ORDER BY sort_order;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers[', @bad, N']|This question needs an answer.');
        THROW 50400, @msg, 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @stamp DATETIME2(0) = CASE WHEN @anon = 1 THEN CAST(@today AS DATETIME2(0)) ELSE @now END;
    DECLARE @by BIGINT = CASE WHEN @anon = 1 THEN NULL ELSE @actor_user_id END;
    DECLARE @response_id BIGINT;

    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM [eng].[survey_participant] WITH (UPDLOCK, HOLDLOCK)
                   WHERE survey_id = @id AND employee_id = @me AND responded_at IS NOT NULL)
            THROW 50409, N'id|SURVEY_ALREADY_ANSWERED|You have already answered this survey.', 1;

        UPDATE [eng].[survey_participant] SET responded_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE survey_id = @id AND employee_id = @me;
        IF @@ROWCOUNT = 0
            INSERT [eng].[survey_participant] (survey_id, employee_id, responded_at, skipped, created_by)
            VALUES (@id, @me, @now, 0, @actor_user_id);

        INSERT [eng].[survey_response] (survey_id, employee_id, submitted_at, created_at, created_by)
        VALUES (@id, CASE WHEN @anon = 1 THEN NULL ELSE @me END, @stamp, @stamp, @by);
        SET @response_id = SCOPE_IDENTITY();

        INSERT [eng].[survey_answer] (survey_response_id, survey_question_id, survey_option_id, answer_text, rating_value, created_at, created_by)
        SELECT @response_id, o.question_id, o.option_id, NULL, NULL, @stamp, @by
        FROM @opt o JOIN @chk x ON x.question_id = o.question_id
        WHERE x.question_type IN (N'single', N'dropdown', N'multiple')
        UNION ALL
        SELECT @response_id, x.question_id, NULL, x.answer_text, x.rating, @stamp, @by
        FROM @chk x WHERE x.answer_text IS NOT NULL OR x.rating IS NOT NULL;

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), s.id) AS surveyId, s.title, s.is_anonymous AS isAnonymous,
                   CASE WHEN s.is_anonymous = 0 THEN CONVERT(NVARCHAR(30), @me) END AS employeeId,
                   (SELECT COUNT(*) FROM [eng].[survey_participant] p WHERE p.survey_id = s.id AND p.responded_at IS NOT NULL) AS responseCount
            FROM [eng].[survey] s WHERE s.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'engagement.survey_response_submitted',
             @entity_type = N'eng.survey', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [eng].[usp_my_survey_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- "Skip" on the popup: the survey stops showing as pending for the caller.
CREATE OR ALTER PROCEDURE [eng].[usp_survey_skip]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    IF @me IS NULL
        THROW 50403, N'Only employees can answer surveys.', 1;
    DECLARE @status NVARCHAR(30), @opens DATE, @closes DATE;
    SELECT @status = status, @opens = opens_on, @closes = closes_on FROM [eng].[survey] WHERE id = @id AND company_id = @company_id;
    IF @status IS NULL OR @status = N'draft'
        THROW 50404, N'Survey not found', 1;
    IF NOT EXISTS (SELECT 1 FROM [eng].[fn_survey_audience](@company_id, @id) WHERE employee_id = @me)
       AND NOT EXISTS (SELECT 1 FROM [eng].[survey_participant] WHERE survey_id = @id AND employee_id = @me)
        THROW 50403, N'This survey is not addressed to you.', 1;
    IF @status <> N'published' OR ISNULL(@opens, @today) > @today OR @closes < @today
        THROW 50409, N'id|SURVEY_CLOSED|This survey is not open.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM [eng].[survey_participant] WITH (UPDLOCK, HOLDLOCK)
                   WHERE survey_id = @id AND employee_id = @me AND responded_at IS NOT NULL)
            THROW 50409, N'id|SURVEY_ALREADY_ANSWERED|You have already answered this survey.', 1;
        UPDATE [eng].[survey_participant] SET skipped = 1, skipped_at = ISNULL(skipped_at, @now), updated_at = @now, updated_by = @actor_user_id
        WHERE survey_id = @id AND employee_id = @me;
        IF @@ROWCOUNT = 0
            INSERT [eng].[survey_participant] (survey_id, employee_id, skipped, skipped_at, created_by)
            VALUES (@id, @me, 1, @now, @actor_user_id);
    COMMIT;

    EXEC [eng].[usp_my_survey_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
