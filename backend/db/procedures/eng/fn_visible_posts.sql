-- The posts a signed-in user may read: those whose audience they are in (eng.fn_post_audience) unless
-- hidden, their own posts (hidden or not), and every post whose author they moderate: the employees
-- auth.fn_visible_employees gives for engagement.moderation.view (company scope: everyone).
-- can_moderate: the user may pin, hide or delete it (engagement.moderation.edit over its author).
CREATE OR ALTER FUNCTION [eng].[fn_visible_posts] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT (SELECT u.employee_id
            FROM [auth].[user_account] u
            JOIN [hr].[employee] e ON e.id = u.employee_id AND e.company_id = @company_id
            WHERE u.id = @user_id) AS employee_id
),
moderated AS (
    SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @user_id, N'engagement.moderation.view')
)
SELECT p.id AS post_id
FROM [eng].[post] p
CROSS JOIN me
WHERE p.company_id = @company_id AND p.is_deleted = 0
  AND (   p.author_id = me.employee_id
       OR p.author_id IN (SELECT employee_id FROM moderated)
       OR (p.is_hidden = 0 AND p.id IN (SELECT a.post_id FROM [eng].[fn_post_audience](@company_id, me.employee_id) a)));
