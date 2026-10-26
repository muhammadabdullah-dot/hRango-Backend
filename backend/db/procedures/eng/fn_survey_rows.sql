-- How a survey is listed. status is the effective status: a published survey past its closing date
-- reads as closed. is_open: published, started and not past its closing date (people can respond).
-- Counts: audience (asked now), responses (answered), skipped (skipped and not answered since).
CREATE OR ALTER FUNCTION [eng].[fn_survey_rows] (@company_id BIGINT, @today DATE)
RETURNS TABLE
AS RETURN
SELECT s.id, s.title, s.description, s.is_anonymous,
       CASE WHEN s.status = N'published' AND s.closes_on < @today THEN N'closed' ELSE s.status END AS status,
       s.opens_on, s.closes_on,
       CAST(CASE WHEN s.status = N'published' AND ISNULL(s.opens_on, @today) <= @today
                      AND (s.closes_on IS NULL OR s.closes_on >= @today) THEN 1 ELSE 0 END AS BIT) AS is_open,
       s.published_at, s.closed_at,
       (SELECT COUNT(*) FROM [eng].[survey_question] q WHERE q.survey_id = s.id) AS question_count,
       (SELECT COUNT(*) FROM [eng].[fn_survey_audience](s.company_id, s.id)) AS audience_count,
       (SELECT COUNT(*) FROM [eng].[survey_participant] p WHERE p.survey_id = s.id AND p.responded_at IS NOT NULL) AS response_count,
       (SELECT COUNT(*) FROM [eng].[survey_participant] p WHERE p.survey_id = s.id AND p.skipped = 1 AND p.responded_at IS NULL) AS skipped_count,
       s.created_at, s.updated_at, s.row_version
FROM [eng].[survey] s
WHERE s.company_id = @company_id;
GO

-- The questions of a survey with their options, as JSON:
-- [{id, sort_order, question_type, question_text, is_required, scale_min, scale_max, scale_min_label,
--   scale_max_label, options: [{id, sort_order, option_text}]}]
CREATE OR ALTER FUNCTION [eng].[fn_survey_questions_json] (@survey_id BIGINT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (
        SELECT CONVERT(NVARCHAR(30), q.id) AS id, q.sort_order, q.question_type, q.question_text, q.is_required,
               q.scale_min, q.scale_max, q.scale_min_label, q.scale_max_label,
               JSON_QUERY(ISNULL((SELECT CONVERT(NVARCHAR(30), o.id) AS id, o.sort_order, o.option_text
                                  FROM [eng].[survey_option] o WHERE o.survey_question_id = q.id
                                  ORDER BY o.sort_order, o.id FOR JSON PATH), N'[]')) AS options
        FROM [eng].[survey_question] q
        WHERE q.survey_id = @survey_id
        ORDER BY q.sort_order, q.id
        FOR JSON PATH, INCLUDE_NULL_VALUES);
END
