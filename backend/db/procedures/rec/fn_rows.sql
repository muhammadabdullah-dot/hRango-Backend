-- Recruitment rows as the screens show them, with the names of what they point to. Scope is applied by
-- the procedures (rec.fn_visible_*), not here.

-- Job openings with their pipeline counts. remaining_vacancies = vacancies not yet filled by a hire.
CREATE OR ALTER FUNCTION [rec].[fn_opening_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT o.id, o.code, o.title, o.status,
       o.open_position_id, op.title AS open_position_title, op.total_positions AS open_position_seats,
       o.job_title_id, jt.name AS job_title_name, o.designation_id, dg.name AS designation_name,
       o.department_id, dp.name AS department_name, o.branch_id, br.name AS branch_name,
       o.employment_type_id, et.name AS employment_type_name,
       o.hiring_manager_id, CASE WHEN hm.id IS NOT NULL THEN CONCAT(hm.first_name, N' ', hm.last_name) END AS hiring_manager_name,
       o.city_id, ct.name AS city_name, st.id AS state_id, st.name AS state_name,
       o.work_mode, o.experience_from_years, o.experience_to_years, o.vacancies,
       ISNULL(c.hired_count, 0) AS hired_count,
       o.vacancies - ISNULL(c.hired_count, 0) AS remaining_vacancies,
       ISNULL(c.application_count, 0) AS application_count,
       ISNULL(c.active_count, 0) AS active_application_count,
       o.posted_on, o.apply_by, o.close_on, o.salary_from, o.salary_to, o.is_salary_visible,
       o.description, o.requirements, o.published_at, o.closed_at,
       o.created_at, cb.name AS created_by_name, o.updated_at, o.row_version
FROM [rec].[job_opening] o
LEFT JOIN [mp].[open_position] op ON op.id = o.open_position_id
LEFT JOIN [org].[job_title] jt ON jt.id = o.job_title_id
LEFT JOIN [org].[designation] dg ON dg.id = o.designation_id
LEFT JOIN [org].[department] dp ON dp.id = o.department_id
LEFT JOIN [org].[branch] br ON br.id = o.branch_id
LEFT JOIN [org].[employment_type] et ON et.id = o.employment_type_id
LEFT JOIN [hr].[employee] hm ON hm.id = o.hiring_manager_id
LEFT JOIN [org].[city] ct ON ct.id = o.city_id
LEFT JOIN [org].[state] st ON st.id = ct.state_id
OUTER APPLY (SELECT COUNT(*) AS application_count,
                    SUM(CASE WHEN a.stage = N'hired' THEN 1 ELSE 0 END) AS hired_count,
                    SUM(CASE WHEN a.stage NOT IN (N'hired', N'rejected', N'withdrawn') THEN 1 ELSE 0 END) AS active_count
             FROM [rec].[application] a WHERE a.job_opening_id = o.id) c
OUTER APPLY [rec].[fn_user_name](o.created_by) cb
WHERE o.company_id = @company_id;
GO

-- Applicants with the CV file and how many applications they have.
CREATE OR ALTER FUNCTION [rec].[fn_applicant_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.first_name, p.last_name, CONCAT(p.first_name, N' ', p.last_name) AS full_name, p.email, p.phone,
       p.gender, p.date_of_birth, p.city_id, ct.name AS city_name, st.name AS state_name, cn.name AS country_name,
       p.address, p.current_employer, p.current_job_title, p.experience_years, p.current_salary,
       p.expected_salary, p.notice_period_days, p.highest_education, p.linkedin_url, p.source,
       p.referred_by_employee_id,
       CASE WHEN rf.id IS NOT NULL THEN CONCAT(rf.first_name, N' ', rf.last_name) END AS referred_by_name,
       p.cv_file_id, f.name AS cv_file_name, p.notes,
       (SELECT COUNT(*) FROM [rec].[application] a WHERE a.applicant_id = p.id) AS application_count,
       p.created_at, cb.name AS created_by_name, p.updated_at, p.row_version
FROM [rec].[applicant] p
LEFT JOIN [org].[city] ct ON ct.id = p.city_id
LEFT JOIN [org].[state] st ON st.id = ct.state_id
LEFT JOIN [org].[country] cn ON cn.id = st.country_id
LEFT JOIN [hr].[employee] rf ON rf.id = p.referred_by_employee_id
LEFT JOIN [core].[stored_file] f ON f.id = p.cv_file_id
OUTER APPLY [rec].[fn_user_name](p.created_by) cb
WHERE p.company_id = @company_id;
GO

-- Applications with the applicant, the opening, interviews, the average evaluation and the latest offer.
CREATE OR ALTER FUNCTION [rec].[fn_application_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT a.id, a.job_opening_id, o.code AS job_opening_code, o.title AS job_opening_title,
       o.department_id, dp.name AS department_name, o.branch_id, br.name AS branch_name,
       a.applicant_id, CONCAT(p.first_name, N' ', p.last_name) AS applicant_name, p.email AS applicant_email,
       p.phone AS applicant_phone, p.current_job_title AS applicant_current_job_title, ct.name AS applicant_city_name,
       p.cv_file_id, f.name AS cv_file_name,
       a.applied_on, a.source, a.cover_letter, a.stage, a.stage_changed_at,
       a.rejection_reason_id, rr.name AS rejection_reason_name, a.rejected_stage, a.remarks,
       a.employee_id, e.code AS employee_code, a.hired_at,
       ISNULL(iv.interview_count, 0) AS interview_count, iv.next_interview_at,
       ev.average_rating, ev.evaluation_count,
       lo.id AS latest_offer_id, lo.status AS latest_offer_status,
       a.created_at, cb.name AS created_by_name, a.updated_at, a.row_version
FROM [rec].[application] a
JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
JOIN [rec].[applicant] p ON p.id = a.applicant_id
LEFT JOIN [org].[department] dp ON dp.id = o.department_id
LEFT JOIN [org].[branch] br ON br.id = o.branch_id
LEFT JOIN [org].[city] ct ON ct.id = p.city_id
LEFT JOIN [core].[stored_file] f ON f.id = p.cv_file_id
LEFT JOIN [rec].[rejection_reason] rr ON rr.id = a.rejection_reason_id
LEFT JOIN [hr].[employee] e ON e.id = a.employee_id
OUTER APPLY (SELECT COUNT(*) AS interview_count,
                    MIN(CASE WHEN i.status = N'scheduled' THEN i.scheduled_at END) AS next_interview_at
             FROM [rec].[interview] i WHERE i.application_id = a.id AND i.status <> N'cancelled') iv
OUTER APPLY (SELECT CAST(AVG(CAST(x.rating AS DECIMAL(5,2))) AS DECIMAL(5,2)) AS average_rating, COUNT(*) AS evaluation_count
             FROM [rec].[interview_evaluation] x JOIN [rec].[interview] i ON i.id = x.interview_id
             WHERE i.application_id = a.id) ev
OUTER APPLY (SELECT TOP 1 x.id, x.status FROM [rec].[offer] x WHERE x.application_id = a.id ORDER BY x.id DESC) lo
OUTER APPLY [rec].[fn_user_name](a.created_by) cb
WHERE a.company_id = @company_id;
GO

-- Interviews with the candidate, the opening and the panel.
CREATE OR ALTER FUNCTION [rec].[fn_interview_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT i.id, i.application_id, a.stage AS application_stage, a.job_opening_id, o.title AS job_opening_title,
       a.applicant_id, CONCAT(p.first_name, N' ', p.last_name) AS applicant_name, p.email AS applicant_email,
       p.phone AS applicant_phone, ct.name AS applicant_city_name, p.cv_file_id,
       i.round_no, i.title, i.mode, i.scheduled_at, i.duration_minutes,
       DATEADD(MINUTE, i.duration_minutes, i.scheduled_at) AS ends_at, i.venue, i.status, i.result, i.remarks,
       (SELECT STRING_AGG(CONCAT(e.first_name, N' ', e.last_name), N', ') WITHIN GROUP (ORDER BY e.first_name, e.last_name)
        FROM [rec].[interview_interviewer] ii JOIN [hr].[employee] e ON e.id = ii.employee_id
        WHERE ii.interview_id = i.id) AS interviewer_names,
       (SELECT COUNT(*) FROM [rec].[interview_interviewer] ii WHERE ii.interview_id = i.id) AS interviewer_count,
       ev.evaluation_count, ev.average_rating,
       i.created_at, cb.name AS created_by_name, i.updated_at, i.row_version
FROM [rec].[interview] i
JOIN [rec].[application] a ON a.id = i.application_id
JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
JOIN [rec].[applicant] p ON p.id = a.applicant_id
LEFT JOIN [org].[city] ct ON ct.id = p.city_id
OUTER APPLY (SELECT COUNT(*) AS evaluation_count, CAST(AVG(CAST(x.rating AS DECIMAL(5,2))) AS DECIMAL(5,2)) AS average_rating
             FROM [rec].[interview_evaluation] x WHERE x.interview_id = i.id) ev
OUTER APPLY [rec].[fn_user_name](i.created_by) cb
WHERE i.company_id = @company_id;
GO

-- Offers with the candidate, the opening and the placement offered.
CREATE OR ALTER FUNCTION [rec].[fn_offer_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT x.id, x.application_id, a.stage AS application_stage, a.job_opening_id, o.title AS job_opening_title,
       a.applicant_id, CONCAT(p.first_name, N' ', p.last_name) AS applicant_name, p.email AS applicant_email,
       x.job_title_id, jt.name AS job_title_name, x.designation_id, dg.name AS designation_name,
       x.department_id, dp.name AS department_name, x.branch_id, br.name AS branch_name,
       x.employment_type_id, et.name AS employment_type_name,
       x.offered_salary, x.salary_frequency, x.joining_date, x.probation_months, x.expires_on,
       x.offer_letter_file_id, f.name AS offer_letter_file_name,
       x.status, x.sent_at, x.responded_at, x.response_remarks, x.remarks,
       x.created_at, cb.name AS created_by_name, x.updated_at, x.row_version
FROM [rec].[offer] x
JOIN [rec].[application] a ON a.id = x.application_id
JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
JOIN [rec].[applicant] p ON p.id = a.applicant_id
LEFT JOIN [org].[job_title] jt ON jt.id = x.job_title_id
LEFT JOIN [org].[designation] dg ON dg.id = x.designation_id
LEFT JOIN [org].[department] dp ON dp.id = x.department_id
LEFT JOIN [org].[branch] br ON br.id = x.branch_id
LEFT JOIN [org].[employment_type] et ON et.id = x.employment_type_id
LEFT JOIN [core].[stored_file] f ON f.id = x.offer_letter_file_id
OUTER APPLY [rec].[fn_user_name](x.created_by) cb
WHERE x.company_id = @company_id;
