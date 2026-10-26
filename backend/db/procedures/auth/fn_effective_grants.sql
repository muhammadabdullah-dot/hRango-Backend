-- Everything a user may do in a company: every permission from their active roles in that
-- company, plus their own grants in that company, minus their own denials there (a denial always wins). A system
-- administrator holds every permission with company scope. One row per grant, so a code held
-- through two roles appears twice, possibly with different scopes.
CREATE OR ALTER FUNCTION [auth].[fn_effective_grants] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
WITH u AS (
    SELECT id, is_system_admin FROM [auth].[user_account] WHERE id = @user_id AND is_active = 1
),
g AS (
    SELECT rp.permission_id, rp.scope, rp.role_id
    FROM u
    JOIN [auth].[user_role] ur ON ur.user_account_id = u.id
    JOIN [auth].[role] r ON r.id = ur.role_id AND r.company_id = @company_id AND r.is_active = 1
    JOIN [auth].[role_permission] rp ON rp.role_id = r.id
    UNION ALL
    SELECT o.permission_id, ISNULL(o.scope, N'own'), CAST(NULL AS BIGINT)
    FROM u
    JOIN [auth].[user_permission_override] o ON o.user_account_id = u.id AND o.company_id = @company_id AND o.effect = N'grant'
    UNION ALL
    SELECT p.id, N'company', CAST(NULL AS BIGINT)
    FROM u CROSS JOIN [auth].[permission] p
    WHERE u.is_system_admin = 1
)
SELECT g.permission_id, p.code, g.scope, g.role_id
FROM g
JOIN [auth].[permission] p ON p.id = g.permission_id
WHERE NOT EXISTS (SELECT 1 FROM [auth].[user_permission_override] d
                  WHERE d.user_account_id = @user_id AND d.company_id = @company_id
                    AND d.permission_id = g.permission_id AND d.effect = N'deny');
