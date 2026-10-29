-- Custom Form helpers: who a form is for, how a form is listed, and its sections, fields, audience
-- and a response's answers as JSON.

-- The employees a form is for: everyone in the company (audience_kind everyone), or the employees of
-- the chosen departments (and their sub-departments), branches or people. Employees who have left or
-- were switched off are not included.
CREATE OR ALTER FUNCTION [frm].[fn_form_audience] (@company_id BIGINT, @form_id BIGINT)
RETURNS TABLE
AS RETURN
WITH f AS (
    SELECT id, audience_kind FROM [frm].[form] WHERE id = @form_id AND company_id = @company_id
),
down AS (
    SELECT d.id FROM [frm].[form_audience] a JOIN f ON f.id = a.form_id
    JOIN [org].[department] d ON d.id = a.unit_id AND d.company_id = @company_id
    WHERE a.unit_type = N'department'
    UNION ALL
    SELECT d.id FROM [org].[department] d JOIN down ON d.parent_id = down.id
)
SELECT e.id AS employee_id
FROM [hr].[employee] e
WHERE e.company_id = @company_id
  AND EXISTS (SELECT 1 FROM f)
  AND ISNULL(e.status, N'active') NOT IN (N'left', N'inactive')
  AND (   EXISTS (SELECT 1 FROM f WHERE f.audience_kind = N'everyone')
       OR e.department_id IN (SELECT id FROM down)
       OR EXISTS (SELECT 1 FROM [frm].[form_audience] a
                  WHERE a.form_id = @form_id
                    AND ((a.unit_type = N'branch' AND a.unit_id = e.branch_id)
                      OR (a.unit_type = N'employee' AND a.unit_id = e.id))));
GO

-- How a form is listed. status is the effective status: a published form past its closing date reads
-- as closed (closed_at is then the day after closes_on). is_open: published and not past closes_on.
CREATE OR ALTER FUNCTION [frm].[fn_form_rows] (@company_id BIGINT, @today DATE)
RETURNS TABLE
AS RETURN
SELECT f.id, f.title, f.description, f.category,
       CASE WHEN f.status = N'published' AND f.closes_on < @today THEN N'closed' ELSE f.status END AS status,
       f.closes_on, f.audience_kind, f.is_one_per_person, f.is_anonymous,
       CAST(CASE WHEN f.status = N'published' AND (f.closes_on IS NULL OR f.closes_on >= @today) THEN 1 ELSE 0 END AS BIT) AS is_open,
       (SELECT COUNT(*) FROM [frm].[form_field] x WHERE x.form_id = f.id) AS field_count,
       (SELECT COUNT(*) FROM [frm].[form_response] r WHERE r.form_id = f.id) AS response_count,
       f.published_at,
       ISNULL(f.closed_at, CASE WHEN f.status = N'published' AND f.closes_on < @today
                                THEN CAST(DATEADD(DAY, 1, f.closes_on) AS DATETIME2(0)) END) AS closed_at,
       f.created_at, f.created_by, ISNULL(f.updated_at, f.created_at) AS updated_at, f.row_version
FROM [frm].[form] f
WHERE f.company_id = @company_id;
GO

-- A form as the person it is for sees it: the effective status, how often they answered, their latest
-- response, and whether they can answer now. Audience membership is checked by the caller.
CREATE OR ALTER FUNCTION [frm].[fn_form_assigned_rows] (@company_id BIGINT, @today DATE, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT r.id, r.title, r.description, r.category, r.status, r.closes_on, r.field_count, r.is_one_per_person,
       r.is_anonymous, r.is_open, r.published_at, m.my_response_count, l.last_response_id, l.last_submitted_at,
       CAST(CASE WHEN r.is_open = 1 AND (r.is_one_per_person = 0 OR m.my_response_count = 0) THEN 1 ELSE 0 END AS BIT) AS can_respond
FROM [frm].[fn_form_rows](@company_id, @today) r
CROSS APPLY (SELECT COUNT(*) AS my_response_count FROM [frm].[form_response] x
             WHERE x.form_id = r.id AND x.employee_id = @employee_id) m
OUTER APPLY (SELECT TOP 1 x.id AS last_response_id, x.submitted_at AS last_submitted_at FROM [frm].[form_response] x
             WHERE x.form_id = r.id AND x.employee_id = @employee_id ORDER BY x.submitted_at DESC, x.id DESC) l
WHERE r.status <> N'draft';
GO

-- [{id, title, description, position}], position 0-based.
CREATE OR ALTER FUNCTION [frm].[fn_form_sections_json] (@form_id BIGINT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (
        SELECT CONVERT(NVARCHAR(30), s.id) AS id, s.title, s.description,
               ROW_NUMBER() OVER (ORDER BY s.sort_order, s.id) - 1 AS position
        FROM [frm].[form_section] s
        WHERE s.form_id = @form_id
        ORDER BY s.sort_order, s.id
        FOR JSON PATH, INCLUDE_NULL_VALUES);
END
GO

-- [{id, section_id, position, type, label, help_text, required, options: [{id, label}], min, max}];
-- position is 0-based inside the field's section (or before the first section).
CREATE OR ALTER FUNCTION [frm].[fn_form_fields_json] (@form_id BIGINT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (
        SELECT CONVERT(NVARCHAR(30), f.id) AS id, CONVERT(NVARCHAR(30), f.form_section_id) AS section_id,
               ROW_NUMBER() OVER (PARTITION BY f.form_section_id ORDER BY f.sort_order, f.id) - 1 AS position,
               f.field_type AS [type], f.label, f.help_text, f.is_required AS required,
               JSON_QUERY(ISNULL((SELECT CONVERT(NVARCHAR(30), o.id) AS id, o.label
                                  FROM [frm].[form_field_option] o WHERE o.form_field_id = f.id
                                  ORDER BY o.sort_order, o.id FOR JSON PATH), N'[]')) AS options,
               f.min_value AS [min], f.max_value AS [max]
        FROM [frm].[form_field] f
        WHERE f.form_id = @form_id
        ORDER BY f.sort_order, f.id
        FOR JSON PATH, INCLUDE_NULL_VALUES);
END
GO

-- The audience targets with their names: [{id, name}] (none for everyone).
CREATE OR ALTER FUNCTION [frm].[fn_form_audience_json] (@form_id BIGINT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (
        SELECT CONVERT(NVARCHAR(30), a.unit_id) AS id,
               COALESCE(d.name, b.name, NULLIF(LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))), N''), N'(removed)') AS name
        FROM [frm].[form_audience] a
        LEFT JOIN [org].[department] d ON a.unit_type = N'department' AND d.id = a.unit_id
        LEFT JOIN [org].[branch] b ON a.unit_type = N'branch' AND b.id = a.unit_id
        LEFT JOIN [hr].[employee] e ON a.unit_type = N'employee' AND e.id = a.unit_id
        WHERE a.form_id = @form_id
        ORDER BY a.id
        FOR JSON PATH);
END
GO

-- The answers of one response: [{field_id, field_type, answer_text, answer_number, answer_date,
-- answer_bool, file_id, file_name, option_ids: [{id}]}], in the form's order.
CREATE OR ALTER FUNCTION [frm].[fn_form_answers_json] (@response_id BIGINT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (
        SELECT CONVERT(NVARCHAR(30), a.form_field_id) AS field_id, f.field_type, a.answer_text, a.answer_number,
               CONVERT(NVARCHAR(10), a.answer_date, 23) AS answer_date, a.answer_bool,
               CONVERT(NVARCHAR(30), a.file_id) AS file_id, sf.name AS file_name,
               JSON_QUERY(ISNULL((SELECT CONVERT(NVARCHAR(30), ao.form_field_option_id) AS id
                                  FROM [frm].[form_answer_option] ao
                                  JOIN [frm].[form_field_option] fo ON fo.id = ao.form_field_option_id
                                  WHERE ao.form_answer_id = a.id
                                  ORDER BY fo.sort_order, fo.id FOR JSON PATH), N'[]')) AS option_ids
        FROM [frm].[form_answer] a
        JOIN [frm].[form_field] f ON f.id = a.form_field_id
        LEFT JOIN [core].[stored_file] sf ON sf.id = a.file_id
        WHERE a.form_response_id = @response_id
        ORDER BY f.sort_order, f.id
        FOR JSON PATH, INCLUDE_NULL_VALUES);
END
