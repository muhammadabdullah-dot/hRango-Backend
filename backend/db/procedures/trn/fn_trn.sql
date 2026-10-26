-- Training: shared functions. One file so they are created in dependency order.

-- The "My" and "Team" tabs: the actor's own employee or their direct and indirect reports.
CREATE OR ALTER FUNCTION [trn].[fn_tab_employees] (@actor_user_id BIGINT, @tab NVARCHAR(20))
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT u.employee_id AS id FROM [auth].[user_account] u WHERE u.id = @actor_user_id AND u.employee_id IS NOT NULL
),
team AS (
    SELECT e.id FROM [hr].[employee] e JOIN me ON e.line_manager_id = me.id
    UNION ALL
    SELECT e.id FROM [hr].[employee] e JOIN team t ON e.line_manager_id = t.id
)
SELECT id AS employee_id FROM me WHERE @tab = N'my'
UNION ALL
SELECT id FROM team WHERE @tab = N'team';
GO

-- Training settings with their defaults (core.company_setting, module 'training').
CREATE OR ALTER FUNCTION [trn].[fn_settings] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
-- Subqueries, not MAX(CASE ...): an aggregate that drops NULLs raises warning 8153 ahead of a later THROW.
SELECT CAST(ISNULL((SELECT TOP 1 s.setting_value FROM [core].[company_setting] s WHERE s.company_id = @company_id
                    AND s.module = N'training' AND s.setting_key = N'min_attendance_percent'), N'80') AS DECIMAL(5,2)) AS min_attendance_percent,
       CAST(ISNULL((SELECT TOP 1 s.setting_value FROM [core].[company_setting] s WHERE s.company_id = @company_id
                    AND s.module = N'training' AND s.setting_key = N'allow_self_nomination'), N'1') AS BIT) AS allow_self_nomination,
       (SELECT MAX(s.row_version) FROM [core].[company_setting] s WHERE s.company_id = @company_id AND s.module = N'training') AS row_version;
GO

CREATE OR ALTER FUNCTION [trn].[fn_program_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.title, p.training_category_id, c.name AS training_category_name, p.description, p.delivery_mode,
       p.provider_type, p.provider_name, p.duration_hours, p.cost_per_head, p.issues_certificate,
       p.certificate_validity_months, p.is_mandatory, p.is_active,
       (SELECT a.id, CONVERT(NVARCHAR(20), a.file_id) AS fileId, f.name, a.label, f.mime_type AS mimeType, f.size_bytes AS sizeBytes
        FROM [core].[attachment] a JOIN [core].[stored_file] f ON f.id = a.file_id
        WHERE a.company_id = p.company_id AND a.entity_type = N'trn.training_program' AND a.entity_id = p.id
        ORDER BY a.id FOR JSON PATH) AS materials,
       (SELECT COUNT(*) FROM [trn].[training_session] s WHERE s.training_program_id = p.id) AS sessions,
       (SELECT COUNT(*) FROM [trn].[training_session] s WHERE s.training_program_id = p.id AND s.status = N'scheduled'
          AND s.end_date >= CAST(SYSUTCDATETIME() AS DATE)) AS upcoming_sessions,
       p.created_at, p.updated_at, p.row_version
FROM [trn].[training_program] p
LEFT JOIN [trn].[training_category] c ON c.id = p.training_category_id
WHERE p.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [trn].[fn_session_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT s.id, s.training_program_id, p.title AS program_title, p.training_category_id, s.title, s.start_date, s.end_date,
       DATEDIFF(DAY, s.start_date, s.end_date) + 1 AS session_days, s.start_time, s.end_time, s.delivery_mode, s.venue,
       s.online_link, s.trainer_type, s.trainer_employee_id,
       COALESCE(CASE WHEN t.id IS NOT NULL THEN CONCAT(t.first_name, N' ', t.last_name) END, s.trainer_name) AS trainer_display_name,
       s.trainer_name, s.capacity, s.nomination_deadline, s.status, s.cost, s.cancel_reason, s.completed_at, s.cancelled_at,
       ISNULL(n.seats_taken, 0) AS seats_taken, ISNULL(n.requested, 0) AS requested,
       CASE WHEN s.capacity IS NULL THEN NULL WHEN s.capacity - ISNULL(n.seats_taken, 0) < 0 THEN 0
            ELSE s.capacity - ISNULL(n.seats_taken, 0) END AS seats_left,
       fb.average_rating, ISNULL(fb.feedback_count, 0) AS feedback_count,
       s.created_at, s.updated_at, s.row_version
FROM [trn].[training_session] s
JOIN [trn].[training_program] p ON p.id = s.training_program_id
LEFT JOIN [hr].[employee] t ON t.id = s.trainer_employee_id
OUTER APPLY (SELECT SUM(CASE WHEN e.status IN (N'enrolled', N'completed', N'not_completed') THEN 1 ELSE 0 END) AS seats_taken,
                    SUM(CASE WHEN e.status = N'requested' THEN 1 ELSE 0 END) AS requested
             FROM [trn].[training_enrolment] e WHERE e.training_session_id = s.id) n
OUTER APPLY (SELECT CAST(AVG(CAST(f.overall_rating AS DECIMAL(9,4))) AS DECIMAL(5,2)) AS average_rating, COUNT(*) AS feedback_count
             FROM [trn].[training_feedback] f JOIN [trn].[training_enrolment] e ON e.id = f.training_enrolment_id
             WHERE e.training_session_id = s.id) fb
WHERE s.company_id = @company_id;
GO

CREATE OR ALTER FUNCTION [trn].[fn_enrolment_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT en.id, en.training_session_id, s.title AS session_title, s.start_date, s.end_date, s.status AS session_status,
       s.training_program_id, p.title AS program_title, en.employee_id, e.code AS employee_code,
       CONCAT(e.first_name, N' ', e.last_name) AS employee_name, e.department_id, d.name AS department_name,
       en.status, en.nomination_source, en.nominated_by_user_id, en.decided_by_user_id, en.decided_at, en.decision_remarks,
       ISNULL(at.present_days, 0) AS present_days, DATEDIFF(DAY, s.start_date, s.end_date) + 1 AS session_days,
       CAST(ISNULL(at.present_days, 0) * 100.0 / (DATEDIFF(DAY, s.start_date, s.end_date) + 1) AS DECIMAL(5,2)) AS attendance_to_date,
       en.attendance_percent, en.score, en.result_remarks, en.completed_at,
       en.certificate_file_id, cf.name AS certificate_file_name, en.certificate_no, en.certificate_issued_date,
       en.certificate_expiry_date, fb.overall_rating AS feedback_rating,
       en.created_at, en.updated_at, en.row_version
FROM [trn].[training_enrolment] en
JOIN [trn].[training_session] s ON s.id = en.training_session_id
JOIN [trn].[training_program] p ON p.id = s.training_program_id
JOIN [hr].[employee] e ON e.id = en.employee_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
LEFT JOIN [core].[stored_file] cf ON cf.id = en.certificate_file_id
LEFT JOIN [trn].[training_feedback] fb ON fb.training_enrolment_id = en.id
OUTER APPLY (SELECT COUNT(*) AS present_days FROM [trn].[training_attendance] a
             WHERE a.training_enrolment_id = en.id AND a.status = N'present') at
WHERE en.company_id = @company_id;
