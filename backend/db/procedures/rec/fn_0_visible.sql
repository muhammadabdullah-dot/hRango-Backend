-- Recruitment scope. A job opening belongs to a department and a station, so a permission reaches
-- openings the way Manpower's records are reached: company scope sees every opening; department scope
-- the openings of the holder's department and its sub-departments; branch scope their station;
-- selected_units the departments / branches ticked on the role. own reaches the openings the holder is
-- hiring manager for, team also those of their reports. Applications, interviews and offers follow
-- their opening. Interviewers also reach the interviews they sit on, and an applicant is also reached
-- by whoever added them. This file is named fn_0_* so it is created before the row functions.

CREATE OR ALTER FUNCTION [rec].[fn_visible_openings] (@company_id BIGINT, @user_id BIGINT, @permission_code NVARCHAR(150))
RETURNS TABLE
AS RETURN
WITH g AS (
    SELECT scope, role_id, permission_id
    FROM [auth].[fn_effective_grants](@company_id, @user_id)
    WHERE code = @permission_code
),
me AS (
    SELECT e.id, e.department_id, e.branch_id
    FROM [auth].[user_account] u
    JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.id = @user_id
),
team AS (
    SELECT e.id FROM [hr].[employee] e JOIN me ON e.line_manager_id = me.id
    UNION ALL
    SELECT e.id FROM [hr].[employee] e JOIN team t ON e.line_manager_id = t.id
),
dept AS (
    SELECT d.id FROM [org].[department] d JOIN me ON d.id = me.department_id
    UNION ALL
    SELECT d.id FROM [org].[department] d JOIN dept x ON d.parent_id = x.id
)
SELECT o.id AS job_opening_id
FROM [rec].[job_opening] o
WHERE o.company_id = @company_id
  AND (
        EXISTS (SELECT 1 FROM g WHERE g.scope = N'company')
     OR (o.hiring_manager_id IN (SELECT id FROM me) AND EXISTS (SELECT 1 FROM g))
     OR (o.hiring_manager_id IN (SELECT id FROM team) AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'team'))
     OR (o.department_id IN (SELECT id FROM dept) AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'department'))
     OR (o.branch_id IN (SELECT branch_id FROM me) AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'branch'))
     OR EXISTS (
            SELECT 1
            FROM g
            JOIN [auth].[role_permission_unit] pu ON pu.role_id = g.role_id AND pu.permission_id = g.permission_id
            WHERE g.scope = N'selected_units'
              AND (   (pu.unit_type = N'branch' AND pu.unit_id = o.branch_id)
                   OR (pu.unit_type = N'department' AND pu.unit_id = o.department_id)))
  );
GO

-- The interviews a user reaches through one permission: those of the openings they reach, and those
-- they sit on as an interviewer (holding the permission with any scope).
CREATE OR ALTER FUNCTION [rec].[fn_visible_interviews] (@company_id BIGINT, @user_id BIGINT, @permission_code NVARCHAR(150))
RETURNS TABLE
AS RETURN
SELECT i.id AS interview_id
FROM [rec].[interview] i
JOIN [rec].[application] a ON a.id = i.application_id
WHERE i.company_id = @company_id
  AND (   a.job_opening_id IN (SELECT job_opening_id FROM [rec].[fn_visible_openings](@company_id, @user_id, @permission_code))
       OR (EXISTS (SELECT 1 FROM [auth].[fn_effective_grants](@company_id, @user_id) g WHERE g.code = @permission_code)
           AND EXISTS (SELECT 1 FROM [rec].[interview_interviewer] ii
                       JOIN [auth].[user_account] u ON u.employee_id = ii.employee_id AND u.id = @user_id
                       WHERE ii.interview_id = i.id)));
GO

-- The applicants a user reaches through one permission: everyone with company scope; otherwise those
-- who applied to an opening they reach, and those they added themselves.
CREATE OR ALTER FUNCTION [rec].[fn_visible_applicants] (@company_id BIGINT, @user_id BIGINT, @permission_code NVARCHAR(150))
RETURNS TABLE
AS RETURN
SELECT p.id AS applicant_id
FROM [rec].[applicant] p
WHERE p.company_id = @company_id
  AND (   EXISTS (SELECT 1 FROM [auth].[fn_effective_grants](@company_id, @user_id) g
                  WHERE g.code = @permission_code AND g.scope = N'company')
       OR (p.created_by = @user_id
           AND EXISTS (SELECT 1 FROM [auth].[fn_effective_grants](@company_id, @user_id) g WHERE g.code = @permission_code))
       OR EXISTS (SELECT 1 FROM [rec].[application] a
                  JOIN [rec].[fn_visible_openings](@company_id, @user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
                  WHERE a.applicant_id = p.id));
GO

-- The name shown for a user in "added by" / "changed by": their employee name, else the display name.
CREATE OR ALTER FUNCTION [rec].[fn_user_name] (@user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS name
FROM [auth].[user_account] u
LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
WHERE u.id = @user_id;
