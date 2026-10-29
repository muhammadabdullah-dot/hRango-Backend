-- Custom Form (responses, CF3): HR reads the answers of a form, the counts per answer of its choice-like
-- questions, and one response. Anonymous forms never show the respondent (and cannot be searched by
-- respondent). Named forms show only the respondents the caller reaches through forms.responses.view.

-- Result set 1: total. Result set 2: the page, newest first, with answers_json (frm.fn_form_answers_json).
-- @search matches the respondent's name or code (named forms only).
CREATE OR ALTER PROCEDURE [frm].[usp_form_response_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @search        NVARCHAR(200) = NULL,
    @page          INT = 1,
    @page_size     INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @anon BIT = (SELECT is_anonymous FROM [frm].[form] WHERE id = @id AND company_id = @company_id);
    IF @anon IS NULL
        THROW 50404, N'Form not found', 1;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN @anon = 1 OR NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT r.id
    FROM [frm].[form_response] r
    JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.form_id = @id AND r.company_id = @company_id
      AND (@anon = 1 OR r.employee_id IN (SELECT v.employee_id
                                          FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'forms.responses.view') v))
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern);

    SELECT COUNT(*) AS total FROM @ids;

    SELECT r.id, r.form_id, r.submitted_at, f.is_anonymous,
           CASE WHEN f.is_anonymous = 0 THEN r.employee_id END AS employee_id,
           CASE WHEN f.is_anonymous = 0 THEN NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N'') END AS employee_name,
           CASE WHEN f.is_anonymous = 0 THEN e.code END AS employee_code,
           CASE WHEN f.is_anonymous = 0 THEN d.name END AS department_name,
           [frm].[fn_form_answers_json](r.id) AS answers_json
    FROM @ids x
    JOIN [frm].[form_response] r ON r.id = x.id
    JOIN [frm].[form] f ON f.id = r.form_id
    LEFT JOIN [hr].[employee] e ON e.id = r.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    ORDER BY r.submitted_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Counts per answer. Result sets: 1 total responses; 2 fields (answered count, scale); 3 option counts
-- (every option, zeros included); 4 checkbox counts (true / false); 5 rating counts per value.
CREATE OR ALTER PROCEDURE [frm].[usp_form_response_summary]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [frm].[form] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Form not found', 1;

    SELECT COUNT(*) AS total FROM [frm].[form_response] WHERE form_id = @id;

    SELECT f.id AS field_id, f.field_type, f.max_value,
           (SELECT COUNT(*) FROM [frm].[form_answer] a WHERE a.form_field_id = f.id) AS answered
    FROM [frm].[form_field] f
    WHERE f.form_id = @id
    ORDER BY f.sort_order, f.id;

    SELECT o.form_field_id AS field_id, o.id AS option_id,
           (SELECT COUNT(*) FROM [frm].[form_answer_option] ao WHERE ao.form_field_option_id = o.id) AS answer_count
    FROM [frm].[form_field_option] o
    JOIN [frm].[form_field] f ON f.id = o.form_field_id
    WHERE f.form_id = @id
    ORDER BY f.sort_order, o.sort_order, o.id;

    SELECT a.form_field_id AS field_id, a.answer_bool AS value, COUNT(*) AS answer_count
    FROM [frm].[form_answer] a
    JOIN [frm].[form_field] f ON f.id = a.form_field_id
    WHERE f.form_id = @id AND f.field_type = N'checkbox' AND a.answer_bool IS NOT NULL
    GROUP BY a.form_field_id, a.answer_bool;

    SELECT a.form_field_id AS field_id, CAST(a.answer_number AS INT) AS value, COUNT(*) AS answer_count
    FROM [frm].[form_answer] a
    JOIN [frm].[form_field] f ON f.id = a.form_field_id
    WHERE f.form_id = @id AND f.field_type = N'rating' AND a.answer_number IS NOT NULL
    GROUP BY a.form_field_id, CAST(a.answer_number AS INT)
    ORDER BY a.form_field_id, CAST(a.answer_number AS INT);
END
GO

-- One response with its form's questions. @as_hr = 1: the caller holds forms.responses.view and may read
-- any response of an anonymous form and the named ones of the respondents they reach; anyone may read
-- their own responses. Otherwise 404. The respondent is blank on anonymous forms.
CREATE OR ALTER PROCEDURE [frm].[usp_form_response_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @as_hr         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT u.employee_id FROM [auth].[user_account] u
                          JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
                          WHERE u.id = @actor_user_id);
    DECLARE @emp BIGINT, @anon BIT;
    SELECT @emp = r.employee_id, @anon = f.is_anonymous
    FROM [frm].[form_response] r JOIN [frm].[form] f ON f.id = r.form_id
    WHERE r.id = @id AND r.company_id = @company_id;
    IF @emp IS NULL
       OR NOT (   @emp = @me
               OR (@as_hr = 1 AND (@anon = 1 OR EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id,
                                                                                                      N'forms.responses.view') v
                                                          WHERE v.employee_id = @emp))))
        THROW 50404, N'Response not found', 1;

    SELECT r.id, r.form_id, r.submitted_at, f.is_anonymous,
           CASE WHEN f.is_anonymous = 0 THEN r.employee_id END AS employee_id,
           CASE WHEN f.is_anonymous = 0 THEN NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N'') END AS employee_name,
           CASE WHEN f.is_anonymous = 0 THEN e.code END AS employee_code,
           CASE WHEN f.is_anonymous = 0 THEN d.name END AS department_name,
           [frm].[fn_form_answers_json](r.id) AS answers_json,
           f.title AS form_title, f.description AS form_description,
           [frm].[fn_form_sections_json](f.id) AS sections_json, [frm].[fn_form_fields_json](f.id) AS fields_json
    FROM [frm].[form_response] r
    JOIN [frm].[form] f ON f.id = r.form_id
    LEFT JOIN [hr].[employee] e ON e.id = r.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE r.id = @id;
END
