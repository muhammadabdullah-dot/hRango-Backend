-- Helpers for the Users, Roles, Grants and Sessions screens (Mini SRS 3.1). This file sorts
-- before the other usp_access_* files so the procedures there find these functions.

-- What a user holds in a company, one row per permission, with the widest scope as a rank:
-- own 1, team 2, department / branch / selected_units 3, company 4. ACC-11: nobody grants a
-- permission they do not hold, or with a wider scope than they hold it with.
CREATE OR ALTER FUNCTION [auth].[fn_access_held] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT g.permission_id, g.code,
       MAX(CASE g.scope WHEN N'company' THEN 4 WHEN N'department' THEN 3 WHEN N'branch' THEN 3
                        WHEN N'selected_units' THEN 3 WHEN N'team' THEN 2 ELSE 1 END) AS max_rank
FROM [auth].[fn_effective_grants](@company_id, @user_id) g
GROUP BY g.permission_id, g.code;
GO

-- A row when @actor_id may not change @target_id's account (password, details, roles, grants, sessions), so nobody
-- can reset an administrator's password and sign in as them:
--   the Account Owner is changed by nobody but themselves;
--   other administrators (who hold access.users.edit) answer to the Account Owner, not to each other;
--   and nobody touches an account holding user or role administration they do not hold as widely.
CREATE OR ALTER FUNCTION [auth].[fn_access_outranks] (@company_id BIGINT, @target_id BIGINT, @actor_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT TOP 1 x.code
FROM (
    SELECT CAST(N'account_owner' AS NVARCHAR(150)) AS code
    FROM [auth].[user_account] u WHERE u.id = @target_id AND u.is_account_owner = 1
    UNION ALL
    SELECT t.code
    FROM [auth].[fn_access_held](@company_id, @target_id) t
    WHERE t.code = N'access.users.edit'
      AND NOT EXISTS (SELECT 1 FROM [auth].[user_account] a WHERE a.id = @actor_id AND a.is_account_owner = 1)
    UNION ALL
    SELECT t.code
    FROM [auth].[fn_access_held](@company_id, @target_id) t
    WHERE t.code LIKE N'access.%'
      AND NOT EXISTS (SELECT 1 FROM [auth].[fn_access_held](@company_id, @actor_id) a
                      WHERE a.permission_id = t.permission_id AND a.max_rank >= t.max_rank)
) x
WHERE @target_id <> @actor_id;
GO

-- The sign-in accounts that belong to a company: its home users and those given access to it.
CREATE OR ALTER FUNCTION [auth].[fn_access_company_users] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT u.id
FROM [auth].[user_account] u
WHERE u.company_id = @company_id
   OR EXISTS (SELECT 1 FROM [auth].[user_company] uc WHERE uc.user_account_id = u.id AND uc.company_id = @company_id);
