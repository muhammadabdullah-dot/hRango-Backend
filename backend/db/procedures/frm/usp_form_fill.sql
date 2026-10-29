-- Custom Form (filling, CF2): My Forms for everyone. A person sees the published and closed forms whose
-- audience includes them (never drafts), answers the open ones, and lists their own submissions.
-- Anonymous forms keep the respondent (one response per person, My submissions) but HR never sees it.

-- Result set 1: total. Result set 2: the page, open forms first, then by closing date.
CREATE OR ALTER PROCEDURE [frm].[usp_form_assigned_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
    @page          INT = 1,
    @page_size     INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT f.id FROM [frm].[form] f
    WHERE f.company_id = @company_id AND @me IS NOT NULL AND f.status <> N'draft'
      AND (@pattern IS NULL OR f.title LIKE @pattern OR f.category LIKE @pattern OR f.description LIKE @pattern)
      AND (EXISTS (SELECT 1 FROM [frm].[fn_form_audience](@company_id, f.id) a WHERE a.employee_id = @me)
           OR EXISTS (SELECT 1 FROM [frm].[form_response] r WHERE r.form_id = f.id AND r.employee_id = @me));

    SELECT COUNT(*) AS total FROM @ids;

    SELECT r.*
    FROM @ids x
    JOIN [frm].[fn_form_assigned_rows](@company_id, @today, @me) r ON r.id = x.id
    ORDER BY r.is_open DESC, r.can_respond DESC, ISNULL(r.closes_on, '9999-12-31'), r.published_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- One form to fill, with its sections and fields. 404 when it is not meant for the caller.
CREATE OR ALTER PROCEDURE [frm].[usp_form_assigned_get]
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
        SELECT 1 FROM [frm].[form] f
        WHERE f.id = @id AND f.company_id = @company_id AND f.status <> N'draft'
          AND (EXISTS (SELECT 1 FROM [frm].[fn_form_audience](@company_id, f.id) a WHERE a.employee_id = @me)
               OR EXISTS (SELECT 1 FROM [frm].[form_response] r WHERE r.form_id = f.id AND r.employee_id = @me)))
        THROW 50404, N'Form not found', 1;

    SELECT r.*, [frm].[fn_form_sections_json](r.id) AS sections_json, [frm].[fn_form_fields_json](r.id) AS fields_json
    FROM [frm].[fn_form_assigned_rows](@company_id, @today, @me) r
    WHERE r.id = @id;
END
GO

-- Sends the caller's answers. @answers: [{field_id, value}] where value is, by the field's type:
-- short_text / long_text a string; number / rating a number; date a "yyyy-MM-dd" string; single_choice /
-- dropdown an option id; multiple_choice an array of option ids; checkbox true / false; file an upload id.
-- null, "" and [] mean no answer. Errors name the field: answers.<fieldId>.
CREATE OR ALTER PROCEDURE [frm].[usp_form_response_submit]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @answers       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE), @msg NVARCHAR(400), @bad BIGINT;
    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    DECLARE @status NVARCHAR(30), @closes DATE, @anon BIT, @one BIT, @title NVARCHAR(200);
    SELECT @status = status, @closes = closes_on, @anon = is_anonymous, @one = is_one_per_person, @title = title
    FROM [frm].[form] WHERE id = @id AND company_id = @company_id;
    IF @status IS NULL OR @me IS NULL
       OR NOT EXISTS (SELECT 1 FROM [frm].[fn_form_audience](@company_id, @id) WHERE employee_id = @me)
        THROW 50404, N'Form not found', 1;
    IF @status = N'draft'
        THROW 50409, N'id|FORM_NOT_PUBLISHED|This form is not published.', 1;
    IF @status = N'closed' OR @closes < @today
        THROW 50409, N'id|FORM_CLOSED|This form is closed.', 1;
    IF @one = 1 AND EXISTS (SELECT 1 FROM [frm].[form_response] WHERE form_id = @id AND employee_id = @me)
        THROW 50409, N'id|ALREADY_RESPONDED|You have already answered this form.', 1;
    IF ISJSON(ISNULL(@answers, N'[]')) = 0
        THROW 50400, N'answers|The answers are not valid.', 1;

    -- The answers as sent: the JSON type of value is 0 null, 1 string, 2 number, 3 true / false, 4 array, 5 object.
    DECLARE @a TABLE (pos INT PRIMARY KEY, field_id BIGINT, val NVARCHAR(MAX), vtype INT);
    INSERT @a
    SELECT CAST(j.[key] AS INT), x.field_id, v.[value], ISNULL(v.[type], 0)
    FROM OPENJSON(ISNULL(@answers, N'[]')) j
    CROSS APPLY OPENJSON(CASE WHEN j.[type] = 5 THEN j.[value] ELSE N'{}' END) WITH (field_id BIGINT '$.field_id') x
    OUTER APPLY (SELECT TOP 1 k.[value], k.[type] FROM OPENJSON(CASE WHEN j.[type] = 5 THEN j.[value] ELSE N'{}' END) k
                 WHERE k.[key] = N'value') v;

    IF EXISTS (SELECT 1 FROM @a WHERE field_id IS NULL)
        THROW 50400, N'answers|Every answer needs its question.', 1;
    SET @bad = (SELECT TOP 1 a.field_id FROM @a a
                WHERE NOT EXISTS (SELECT 1 FROM [frm].[form_field] f WHERE f.id = a.field_id AND f.form_id = @id)
                   OR EXISTS (SELECT 1 FROM @a o WHERE o.field_id = a.field_id AND o.pos < a.pos)
                ORDER BY a.pos);
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers.', @bad, N'|This answer is not for a question on this form, or answers it twice.');
        THROW 50400, @msg, 1;
    END

    -- One row per question, with the answer read by the question's type.
    DECLARE @c TABLE (field_id BIGINT PRIMARY KEY, sort_order INT, field_type NVARCHAR(30), is_required BIT,
                      min_value DECIMAL(18,4), max_value DECIMAL(18,4), val NVARCHAR(MAX), vtype INT,
                      txt NVARCHAR(MAX), num DECIMAL(18,4), dt DATE, bool BIT, file_id BIGINT, problem NVARCHAR(300));
    INSERT @c (field_id, sort_order, field_type, is_required, min_value, max_value, val, vtype)
    SELECT f.id, f.sort_order, f.field_type, f.is_required, f.min_value, f.max_value, a.val, ISNULL(a.vtype, 0)
    FROM [frm].[form_field] f LEFT JOIN @a a ON a.field_id = f.id
    WHERE f.form_id = @id;

    UPDATE @c SET vtype = 0, val = NULL
    WHERE (vtype = 1 AND LTRIM(RTRIM(val)) = N'')
       OR (vtype = 4 AND NOT EXISTS (SELECT 1 FROM OPENJSON(CASE WHEN vtype = 4 THEN val ELSE N'[]' END)));

    UPDATE @c SET txt = LTRIM(RTRIM(val)) WHERE vtype = 1 AND field_type IN (N'short_text', N'long_text');
    UPDATE @c SET num = TRY_CAST(val AS DECIMAL(18,4)) WHERE vtype = 2 AND field_type IN (N'number', N'rating');
    UPDATE @c SET dt = TRY_CONVERT(DATE, val, 23) WHERE vtype = 1 AND field_type = N'date' AND val LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]';
    UPDATE @c SET bool = CASE WHEN val = N'true' THEN 1 ELSE 0 END WHERE vtype = 3 AND field_type = N'checkbox';
    UPDATE @c SET file_id = TRY_CAST(val AS BIGINT) WHERE vtype IN (1, 2) AND field_type = N'file';

    DECLARE @o TABLE (field_id BIGINT, option_id BIGINT);
    INSERT @o SELECT c.field_id, TRY_CAST(c.val AS BIGINT)
    FROM @c c WHERE c.vtype IN (1, 2) AND c.field_type IN (N'single_choice', N'dropdown');
    INSERT @o SELECT DISTINCT c.field_id, TRY_CAST(k.[value] AS BIGINT)
    FROM @c c CROSS APPLY OPENJSON(CASE WHEN c.vtype = 4 THEN c.val ELSE N'[]' END) k
    WHERE c.vtype = 4 AND c.field_type = N'multiple_choice';

    UPDATE @c SET problem = N'This answer is not valid for the question.'
    WHERE vtype <> 0 AND (
           (field_type IN (N'short_text', N'long_text') AND txt IS NULL)
        OR (field_type IN (N'number', N'rating') AND num IS NULL)
        OR (field_type = N'date' AND dt IS NULL)
        OR (field_type = N'checkbox' AND bool IS NULL)
        OR (field_type = N'file' AND file_id IS NULL)
        OR (field_type IN (N'single_choice', N'dropdown') AND vtype NOT IN (1, 2))
        OR (field_type = N'multiple_choice' AND vtype <> 4));
    UPDATE c SET problem = N'Choose one of the question''s options.'
    FROM @c c
    WHERE c.problem IS NULL
      AND EXISTS (SELECT 1 FROM @o o WHERE o.field_id = c.field_id
                    AND (o.option_id IS NULL OR NOT EXISTS (SELECT 1 FROM [frm].[form_field_option] fo
                                                            WHERE fo.id = o.option_id AND fo.form_field_id = c.field_id)));
    UPDATE @c SET problem = N'The file was not found. Upload it again.'
    WHERE problem IS NULL AND file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, file_id));
    UPDATE @c SET problem = CONCAT(N'The answer must be ', CASE WHEN min_value IS NOT NULL THEN CONCAT(N'at least ', CAST(min_value AS INT), N' and ') END,
                                   N'at most ', CAST(ISNULL(max_value, CASE field_type WHEN N'short_text' THEN 500 ELSE 5000 END) AS INT), N' characters.')
    WHERE problem IS NULL AND txt IS NOT NULL
      AND (LEN(txt) < ISNULL(min_value, 0) OR LEN(txt) > ISNULL(max_value, CASE field_type WHEN N'short_text' THEN 500 ELSE 5000 END));
    UPDATE @c SET problem = N'The number is outside the allowed range.'
    WHERE problem IS NULL AND field_type = N'number' AND num IS NOT NULL AND (num < min_value OR num > max_value);
    UPDATE @c SET problem = N'Choose a value on the scale.'
    WHERE problem IS NULL AND field_type = N'rating' AND num IS NOT NULL AND (num <> FLOOR(num) OR num < 1 OR num > ISNULL(max_value, 5));
    UPDATE c SET problem = N'Choose an allowed number of options.'
    FROM @c c CROSS APPLY (SELECT COUNT(*) AS n FROM @o o WHERE o.field_id = c.field_id) k
    WHERE c.problem IS NULL AND c.field_type = N'multiple_choice' AND c.vtype = 4 AND (k.n < c.min_value OR k.n > c.max_value);
    -- A required checkbox must be ticked (a consent box).
    UPDATE @c SET problem = N'This question needs an answer.'
    WHERE problem IS NULL AND is_required = 1 AND (vtype = 0 OR (field_type = N'checkbox' AND bool = 0));
    -- TODO(business): date min / max, file type limits per question.

    SELECT TOP 1 @bad = field_id, @msg = problem FROM @c WHERE problem IS NOT NULL ORDER BY sort_order, field_id;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers.', @bad, N'|', @msg);
        THROW 50400, @msg, 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @rid BIGINT;
    DECLARE @amap TABLE (field_id BIGINT PRIMARY KEY, answer_id BIGINT);
    BEGIN TRAN;
        IF @one = 1 AND EXISTS (SELECT 1 FROM [frm].[form_response] WITH (UPDLOCK, HOLDLOCK) WHERE form_id = @id AND employee_id = @me)
            THROW 50409, N'id|ALREADY_RESPONDED|You have already answered this form.', 1;

        INSERT [frm].[form_response] (company_id, form_id, employee_id, submitted_at, created_by)
        VALUES (@company_id, @id, @me, @now, @actor_user_id);
        SET @rid = SCOPE_IDENTITY();

        MERGE [frm].[form_answer] AS t
        USING (SELECT field_id, txt, num, dt, bool, file_id FROM @c WHERE vtype <> 0) AS src ON 1 = 0
        WHEN NOT MATCHED THEN INSERT (form_response_id, form_field_id, answer_text, answer_number, answer_date, answer_bool, file_id, created_by)
             VALUES (@rid, src.field_id, src.txt, src.num, src.dt, src.bool, src.file_id, @actor_user_id)
        OUTPUT src.field_id, inserted.id INTO @amap (field_id, answer_id);

        INSERT [frm].[form_answer_option] (form_answer_id, form_field_option_id, created_by)
        SELECT m.answer_id, o.option_id, @actor_user_id FROM @o o JOIN @amap m ON m.field_id = o.field_id;

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), @id) AS formId, @title AS title, CONVERT(NVARCHAR(30), @rid) AS responseId,
                   CAST(@anon AS BIT) AS anonymous, CASE WHEN @anon = 0 THEN CONVERT(NVARCHAR(30), @me) END AS employeeId,
                   @now AS submittedAt
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'forms.response_submitted',
             @entity_type = N'frm.form', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [frm].[usp_form_response_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @rid, @as_hr = 0;
END
GO

-- My submissions: the caller's own responses, anonymous forms included. Result set 1: total. 2: the page.
CREATE OR ALTER PROCEDURE [frm].[usp_form_my_response_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
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

    SELECT COUNT(*) AS total
    FROM [frm].[form_response] r JOIN [frm].[form] f ON f.id = r.form_id
    WHERE r.company_id = @company_id AND r.employee_id = @me
      AND (@pattern IS NULL OR f.title LIKE @pattern OR f.category LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT r.id, r.form_id, f.title AS form_title, f.category, f.is_anonymous, r.submitted_at
    FROM [frm].[form_response] r JOIN [frm].[form] f ON f.id = r.form_id
    WHERE r.company_id = @company_id AND r.employee_id = @me
      AND (@pattern IS NULL OR f.title LIKE @pattern OR f.category LIKE @pattern)
    ORDER BY r.submitted_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
