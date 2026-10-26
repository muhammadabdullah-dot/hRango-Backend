-- The name shown for a user in "added by" / "approved by": their employee name, else the display name.
CREATE OR ALTER FUNCTION [mp].[fn_actor_name] (@user_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS name
FROM [auth].[user_account] u
LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
WHERE u.id = @user_id;
