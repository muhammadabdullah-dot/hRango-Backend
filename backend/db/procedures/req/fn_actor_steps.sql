-- The approval steps one employee is part of, and how: as the named approver, as a holder of the
-- step's role, or as an active delegatee of the approver for that request type (ACC-13: who may
-- decide comes from the flow and delegations, not from a permission). Steps they once took as a
-- delegate stay listed after the delegation ends. Event rows (submitted, cancel requested) are left out.
CREATE OR ALTER FUNCTION [req].[fn_actor_steps] (@company_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
WITH s AS (
    SELECT s.id, s.request_id, s.approver_id, s.approver_role_id, s.acted_by_id, s.is_delegate, r.request_type_id
    FROM [req].[request_step] s
    JOIN [req].[request] r ON r.id = s.request_id AND r.company_id = @company_id AND r.is_deleted = 0
    WHERE s.action_taken NOT IN (N'submitted', N'cancel_requested', N'withdrawn')
)
SELECT s.id AS step_id, s.request_id, CAST(0 AS BIT) AS is_delegate, CAST(NULL AS BIGINT) AS delegator_id
FROM s WHERE s.approver_id = @employee_id
UNION ALL
SELECT s.id, s.request_id, CAST(0 AS BIT), CAST(NULL AS BIGINT)
FROM s
WHERE s.approver_id IS NULL AND s.approver_role_id IN (
        SELECT ur.role_id
        FROM [auth].[user_account] u
        JOIN [auth].[user_role] ur ON ur.user_account_id = u.id
        JOIN [auth].[role] ro ON ro.id = ur.role_id AND ro.company_id = @company_id AND ro.is_active = 1
        WHERE u.employee_id = @employee_id AND u.is_active = 1)
UNION ALL
SELECT s.id, s.request_id, CAST(1 AS BIT), d.delegator_id
FROM s
JOIN [req].[delegation] d ON d.company_id = @company_id AND d.delegator_id = s.approver_id
                         AND d.delegatee_id = @employee_id AND d.request_type_id = s.request_type_id
                         AND d.is_active = 1
UNION ALL
SELECT s.id, s.request_id, CAST(1 AS BIT), s.approver_id
FROM s
WHERE s.acted_by_id = @employee_id AND s.is_delegate = 1
  AND NOT EXISTS (SELECT 1 FROM [req].[delegation] d
                  WHERE d.company_id = @company_id AND d.delegator_id = s.approver_id AND d.delegatee_id = @employee_id
                    AND d.request_type_id = s.request_type_id AND d.is_active = 1);
