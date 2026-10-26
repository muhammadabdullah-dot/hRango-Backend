-- The organisation units a user reaches through one permission, for manpower records that belong to
-- a department or station rather than to an employee (plans, budgets, open positions).
-- Rows: (company, NULL) for company scope; (department, id) for their department and its
-- sub-departments; (branch, id) for their branch; the branches / departments ticked on the role for
-- selected_units. own and team scope reach no unit, so they see none of these records.
-- A record is visible when:
--   EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
--           WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = x.department_id)
--              OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id))
CREATE OR ALTER FUNCTION [mp].[fn_unit_reach] (@company_id BIGINT, @user_id BIGINT, @permission_code NVARCHAR(150))
RETURNS TABLE
AS RETURN
WITH g AS (
    SELECT scope, role_id, permission_id
    FROM [auth].[fn_effective_grants](@company_id, @user_id)
    WHERE code = @permission_code
),
me AS (
    SELECT e.department_id, e.branch_id
    FROM [auth].[user_account] u
    JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
    WHERE u.id = @user_id
),
dept AS (
    SELECT d.id FROM [org].[department] d JOIN me ON d.id = me.department_id
    UNION ALL
    SELECT d.id FROM [org].[department] d JOIN dept x ON d.parent_id = x.id
)
SELECT N'company' AS unit_type, CAST(NULL AS BIGINT) AS unit_id
WHERE EXISTS (SELECT 1 FROM g WHERE g.scope = N'company')
UNION ALL
SELECT N'department', dept.id FROM dept WHERE EXISTS (SELECT 1 FROM g WHERE g.scope = N'department')
UNION ALL
SELECT N'branch', me.branch_id FROM me WHERE me.branch_id IS NOT NULL AND EXISTS (SELECT 1 FROM g WHERE g.scope = N'branch')
UNION ALL
SELECT pu.unit_type, pu.unit_id
FROM g
JOIN [auth].[role_permission_unit] pu ON pu.role_id = g.role_id AND pu.permission_id = g.permission_id
WHERE g.scope = N'selected_units' AND pu.unit_type IN (N'department', N'branch');
