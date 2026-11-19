-- The request types the caller has approvals of (ACC-13: through the flow or a delegation, whatever
-- their list permissions reach), for the web app's menus: an approver named by a flow opens that
-- type's Approvals although their role has no permission for the type itself (a Department Head on a
-- promotion). Counts what the Approvals boxes list (requested, delegates, consents, cancellations),
-- never the caller's own requests. One row per type: total requests, and how many wait for the caller.
CREATE OR ALTER PROCEDURE [req].[usp_request_approval_summary]
    @company_id    BIGINT,
    @actor_user_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    DECLARE @mine TABLE (request_id BIGINT PRIMARY KEY, waiting BIT);
    INSERT @mine (request_id, waiting)
    SELECT a.request_id, MAX(CASE WHEN s.action_taken = N'pending' THEN 1 ELSE 0 END)
    FROM [req].[fn_actor_steps](@company_id, @me) a
    JOIN [req].[request_step] s ON s.id = a.step_id
    GROUP BY a.request_id;

    SELECT t.code AS request_type, t.name AS request_type_name, COUNT(*) AS total,
           SUM(CASE WHEN m.waiting = 1 AND r.status IN (N'pending', N'cancelling') THEN 1 ELSE 0 END) AS waiting
    FROM @mine m
    JOIN [req].[request] r ON r.id = m.request_id AND r.company_id = @company_id AND r.is_deleted = 0
    JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.employee_id <> ISNULL(@me, 0)
    GROUP BY t.code, t.name, t.sort_order
    ORDER BY t.sort_order, t.code;
END
