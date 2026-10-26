-- An employee's managers, from the employee up: depth 0 is the employee, 1 their line manager,
-- 2 that manager's manager ... Stops at 50 levels, so a bad chain cannot loop forever.
-- Saving a line manager refuses one whose chain already contains the employee (no cycles, which
-- auth.fn_visible_employees relies on for team scope).
CREATE OR ALTER FUNCTION [hr].[fn_manager_chain] (@employee_id BIGINT)
RETURNS TABLE
AS RETURN
WITH up AS (
    SELECT id, line_manager_id, 0 AS depth FROM [hr].[employee] WHERE id = @employee_id
    UNION ALL
    SELECT e.id, e.line_manager_id, up.depth + 1
    FROM [hr].[employee] e
    JOIN up ON e.id = up.line_manager_id
    WHERE up.depth < 50
)
SELECT id, depth FROM up;
GO

-- Every employee of a company with the names of everything they point at, for lists and cards.
-- The CNIC is not here: callers add it only for users who hold employees.identity.view.
-- Personal tab extras: home address, photo (the API turns photo_file_id into a signed photoUrl),
-- tenure in whole months of the current employment period, and the primary emergency contact.
CREATE OR ALTER FUNCTION [hr].[fn_employee_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT e.id, e.company_id, e.code, e.first_name, e.last_name,
       LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))) AS name,
       e.parent_name, e.gender, e.marital_status, e.religion, e.nationality, e.date_of_birth,
       e.email, e.phone_1, e.phone_2, e.home_address, e.home_city_id, hc.name AS home_city_name, e.photo_file_id,
       e.branch_id, b.name AS branch_name, e.location_id, l.name AS location_name, e.area_id, a.name AS area_name,
       e.department_id, d.name AS department_name, e.division_id, dv.name AS division_name,
       e.cost_center_id, cc.name AS cost_center_name, e.designation_id, ds.name AS designation_name,
       e.job_title_id, jt.name AS job_title_name, e.grade_id, g.name AS grade_name,
       e.job_level_id, jl.name AS job_level_name, e.employee_group_id, eg.name AS employee_group_name,
       e.employment_type_id, et.name AS employment_type_name,
       e.line_manager_id, NULLIF(LTRIM(RTRIM(CONCAT(lm.first_name, N' ', lm.last_name))), N'') AS line_manager_name,
       e.final_authority_id, NULLIF(LTRIM(RTRIM(CONCAT(fa.first_name, N' ', fa.last_name))), N'') AS final_authority_name,
       e.status, e.salary_frequency,
       p.joining_date, p.confirmation_date, p.probation_end_date, p.end_date,
       CASE WHEN p.joining_date IS NULL OR p.joining_date > t.today THEN NULL
            ELSE DATEDIFF(MONTH, p.joining_date, ISNULL(p.end_date, t.today))
                 - CASE WHEN DAY(ISNULL(p.end_date, t.today)) < DAY(p.joining_date) THEN 1 ELSE 0 END END AS tenure_months,
       ec.name AS emergency_contact_name, ec.phone AS emergency_contact_phone,
       (SELECT COUNT(*) FROM [hr].[employee] r WHERE r.line_manager_id = e.id AND r.status NOT IN (N'left', N'inactive')) AS direct_report_count,
       e.created_at, e.updated_at, e.row_version
FROM [hr].[employee] e
JOIN [org].[branch] b ON b.id = e.branch_id
LEFT JOIN [org].[location] l ON l.id = e.location_id
LEFT JOIN [org].[area] a ON a.id = e.area_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
LEFT JOIN [org].[division] dv ON dv.id = e.division_id
LEFT JOIN [org].[cost_center] cc ON cc.id = e.cost_center_id
LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
LEFT JOIN [org].[grade] g ON g.id = e.grade_id
LEFT JOIN [org].[job_level] jl ON jl.id = e.job_level_id
LEFT JOIN [org].[employee_group] eg ON eg.id = e.employee_group_id
LEFT JOIN [org].[employment_type] et ON et.id = e.employment_type_id
LEFT JOIN [hr].[employee] lm ON lm.id = e.line_manager_id
LEFT JOIN [hr].[employee] fa ON fa.id = e.final_authority_id
LEFT JOIN [org].[city] hc ON hc.id = e.home_city_id
CROSS APPLY (SELECT CAST(SYSUTCDATETIME() AS DATE) AS today) t
OUTER APPLY (SELECT TOP 1 c.name, c.phone FROM [hr].[employee_emergency_contact] c WHERE c.employee_id = e.id
             ORDER BY c.is_primary DESC, c.id) ec
OUTER APPLY (SELECT TOP 1 ep.joining_date, ep.confirmation_date, ep.probation_end_date, ep.end_date
             FROM [hr].[employment_period] ep WHERE ep.employee_id = e.id
             ORDER BY ep.joining_date DESC, ep.id DESC) p
WHERE e.company_id = @company_id;
