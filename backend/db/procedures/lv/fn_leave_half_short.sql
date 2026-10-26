-- The "Half leave & Short leave" policy that applies to one employee: an active half_short policy they
-- are enrolled in (employee level) first, else the company-level one. No row when there is none, and
-- then half-day and short leave follow the leave type alone (its is_short_leave).
--   allow_half_day     half_day requests (0.5 day)
--   allow_short_leave  quarter_day requests (short leave)
CREATE OR ALTER FUNCTION [lv].[fn_leave_half_short] (@company_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT TOP (1) p.id AS leave_policy_id, p.allow_half_day, p.allow_short_leave
FROM [lv].[leave_policy] p
LEFT JOIN [lv].[leave_policy_employee] pe ON pe.leave_policy_id = p.id AND pe.employee_id = @employee_id
WHERE p.company_id = @company_id AND p.policy_kind = N'half_short' AND p.is_active = 1
  AND (p.policy_level = N'company' OR pe.employee_id IS NOT NULL)
ORDER BY CASE p.policy_level WHEN N'employee' THEN 0 ELSE 1 END, p.id;
