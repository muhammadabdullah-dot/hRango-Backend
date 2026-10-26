-- The employees whose records a user may reach through one permission, by the scopes they hold
-- it with: own (themselves), team (direct and indirect reports), department (their department
-- and its sub-departments), branch (their branch), selected_units (the branches, departments or
-- locations ticked on the role), company (everyone in the company).
--
-- Use it in any procedure that lists or changes employee-owned records:
--   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'attendance.time_sheet.view') v
--     ON v.employee_id = t.employee_id
CREATE OR ALTER FUNCTION [auth].[fn_visible_employees] (@company_id BIGINT, @user_id BIGINT, @permission_code NVARCHAR(150))
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
    JOIN [hr].[employee] e ON e.id = u.employee_id
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
SELECT e.id AS employee_id
FROM [hr].[employee] e
WHERE e.company_id = @company_id
  AND (
        EXISTS (SELECT 1 FROM g WHERE g.scope = N'company')
     OR (e.id IN (SELECT id FROM me) AND EXISTS (SELECT 1 FROM g))
     OR (e.id IN (SELECT id FROM team) AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'team'))
     OR (e.department_id IN (SELECT id FROM dept) AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'department'))
     OR (e.branch_id IN (SELECT branch_id FROM me) AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'branch'))
     OR EXISTS (
            SELECT 1
            FROM g
            JOIN [auth].[role_permission_unit] pu ON pu.role_id = g.role_id AND pu.permission_id = g.permission_id
            WHERE g.scope = N'selected_units'
              AND (   (pu.unit_type = N'branch' AND pu.unit_id = e.branch_id)
                   OR (pu.unit_type = N'department' AND pu.unit_id = e.department_id)
                   OR (pu.unit_type = N'location' AND pu.unit_id = e.location_id)))
  );
