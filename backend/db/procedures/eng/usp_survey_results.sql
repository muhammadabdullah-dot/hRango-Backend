-- Survey results (aggregated per question, never per person) and the individual responses of named
-- surveys. Anonymous surveys never show who answered what.

-- Result sets: 1 summary (audience, responses, skipped); 2 questions (answer count, average rating);
-- 3 option counts; 4 rating counts per value; 5 text answers (newest 100 per question, no names).
CREATE OR ALTER PROCEDURE [eng].[usp_survey_results]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [eng].[survey] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Survey not found', 1;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    SELECT r.id, r.title, r.is_anonymous, r.status, r.opens_on, r.closes_on, r.audience_count, r.response_count, r.skipped_count
    FROM [eng].[fn_survey_rows](@company_id, @today) r WHERE r.id = @id;

    SELECT q.id, q.sort_order, q.question_type, q.question_text, q.is_required, q.scale_min, q.scale_max,
           q.scale_min_label, q.scale_max_label,
           (SELECT COUNT(DISTINCT a.survey_response_id) FROM [eng].[survey_answer] a WHERE a.survey_question_id = q.id) AS answer_count,
           (SELECT CAST(AVG(CAST(a.rating_value AS DECIMAL(9,4))) AS DECIMAL(9,2)) FROM [eng].[survey_answer] a
            WHERE a.survey_question_id = q.id AND a.rating_value IS NOT NULL) AS average_rating
    FROM [eng].[survey_question] q
    WHERE q.survey_id = @id
    ORDER BY q.sort_order, q.id;

    SELECT o.survey_question_id AS question_id, o.id AS option_id, o.option_text, o.sort_order,
           (SELECT COUNT(*) FROM [eng].[survey_answer] a WHERE a.survey_option_id = o.id) AS answer_count
    FROM [eng].[survey_option] o
    JOIN [eng].[survey_question] q ON q.id = o.survey_question_id
    WHERE q.survey_id = @id
    ORDER BY q.sort_order, o.sort_order, o.id;

    SELECT a.survey_question_id AS question_id, a.rating_value, COUNT(*) AS answer_count
    FROM [eng].[survey_answer] a
    JOIN [eng].[survey_question] q ON q.id = a.survey_question_id
    WHERE q.survey_id = @id AND a.rating_value IS NOT NULL
    GROUP BY a.survey_question_id, a.rating_value
    ORDER BY a.survey_question_id, a.rating_value;

    SELECT x.question_id, x.answer_text
    FROM (SELECT a.survey_question_id AS question_id, a.answer_text,
                 ROW_NUMBER() OVER (PARTITION BY a.survey_question_id ORDER BY a.id DESC) AS n
          FROM [eng].[survey_answer] a
          JOIN [eng].[survey_question] q ON q.id = a.survey_question_id
          WHERE q.survey_id = @id AND a.answer_text IS NOT NULL) x
    WHERE x.n <= 100
    ORDER BY x.question_id, x.n;
END
GO

-- Individual responses. Result set 1: total. Result set 2: the page, newest first, with
-- answers_json [{question_id, option_id, option_text, answer_text, rating_value}].
-- Named surveys: only the respondents the caller reaches through @permission_code. Anonymous surveys:
-- refused unless @allow_anonymous (the export), and then without anyone's name.
CREATE OR ALTER PROCEDURE [eng].[usp_survey_response_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @permission_code NVARCHAR(150) = N'engagement.survey_responses.view',
    @allow_anonymous BIT = 0,
    @page            INT = 1,
    @page_size       INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @anon BIT = (SELECT is_anonymous FROM [eng].[survey] WHERE id = @id AND company_id = @company_id);
    IF @anon IS NULL
        THROW 50404, N'Survey not found', 1;
    IF @anon = 1 AND @allow_anonymous = 0
        THROW 50403, N'id|SURVEY_ANONYMOUS|This survey is anonymous: answers are shown only as totals.', 1;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT r.id FROM [eng].[survey_response] r
    WHERE r.survey_id = @id
      AND (@anon = 1 OR r.employee_id IN (SELECT v.employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v));

    SELECT COUNT(*) AS total FROM @ids;

    SELECT r.id AS response_id, r.employee_id, e.code AS employee_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, d.name AS department_name, r.submitted_at,
           (SELECT CONVERT(NVARCHAR(30), a.survey_question_id) AS question_id, CONVERT(NVARCHAR(30), a.survey_option_id) AS option_id,
                   o.option_text, a.answer_text, a.rating_value
            FROM [eng].[survey_answer] a
            JOIN [eng].[survey_question] q ON q.id = a.survey_question_id
            LEFT JOIN [eng].[survey_option] o ON o.id = a.survey_option_id
            WHERE a.survey_response_id = r.id
            ORDER BY q.sort_order, o.sort_order FOR JSON PATH) AS answers_json
    FROM @ids i
    JOIN [eng].[survey_response] r ON r.id = i.id
    LEFT JOIN [hr].[employee] e ON e.id = r.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    ORDER BY r.submitted_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
