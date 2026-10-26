-- One request for the View, Flow and History popups. Readable when the caller's view permission
-- reaches the employee (@permission_code), or when the caller is part of its approval steps
-- (approver, role holder or delegatee). Result sets: the request, with what the caller may do on
-- it now; its steps in order (Flow and History); its attachments.
CREATE OR ALTER PROCEDURE [req].[usp_request_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @type_code       NVARCHAR(30) = NULL,
    @permission_code NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @employee_id BIGINT = (
        SELECT r.employee_id FROM [req].[fn_request_rows](@company_id) r
        WHERE r.id = @id AND (@type_code IS NULL OR r.request_type = @type_code));
    IF @employee_id IS NULL
       OR (    NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                           WHERE @permission_code IS NOT NULL AND v.employee_id = @employee_id)
           AND NOT EXISTS (SELECT 1 FROM [req].[fn_actor_steps](@company_id, @me) a WHERE a.request_id = @id))
        THROW 50404, N'Request not found', 1;

    -- The pending step the caller may act on: directly first, then through a role, then as a delegate.
    DECLARE @my_step BIGINT, @my_delegate BIT, @my_consent BIT, @my_can_edit BIT;
    SELECT TOP (1) @my_step = s.id, @my_delegate = a.is_delegate, @my_consent = s.is_consent,
           @my_can_edit = ISNULL(n.can_edit, 0)
    FROM [req].[fn_actor_steps](@company_id, @me) a
    JOIN [req].[request_step] s ON s.id = a.step_id AND s.action_taken = N'pending'
    LEFT JOIN [req].[approval_node] n ON n.id = s.approval_node_id
    WHERE a.request_id = @id AND @employee_id <> ISNULL(@me, 0)
    ORDER BY a.is_delegate, s.id;

    SELECT r.*, [req].[fn_request_details](r.id) AS details_json,
           @my_step AS my_step_id, ISNULL(@my_delegate, 0) AS my_step_is_delegate, ISNULL(@my_consent, 0) AS my_step_is_consent,
           ISNULL(@my_can_edit, 0) AS my_step_can_edit,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [req].[request_step] s WHERE s.request_id = r.id
                                  AND s.action_taken IN (N'approved', N'rejected', N'consented', N'disagreed', N'forwarded'))
                     THEN 1 ELSE 0 END AS BIT) AS has_decisions
    FROM [req].[fn_request_rows](@company_id) r
    WHERE r.id = @id;

    SELECT s.id, s.purpose, n.step_no, s.approver_kind, s.approver_id,
           COALESCE(NULLIF(CONCAT(ap.first_name, N' ', ap.last_name), N' '), ro.name) AS approver_name,
           s.acted_by_id, NULLIF(CONCAT(ac.first_name, N' ', ac.last_name), N' ') AS acted_by_name,
           s.is_delegate, s.is_consent, s.action_taken, s.remarks, s.acted_at, s.created_at
    FROM [req].[request_step] s
    LEFT JOIN [req].[approval_node] n ON n.id = s.approval_node_id
    LEFT JOIN [hr].[employee] ap ON ap.id = s.approver_id
    LEFT JOIN [auth].[role] ro ON ro.id = s.approver_role_id
    LEFT JOIN [hr].[employee] ac ON ac.id = s.acted_by_id
    WHERE s.request_id = @id
    ORDER BY s.id;

    SELECT a.id, a.file_id, f.name, f.mime_type, f.size_bytes, a.label, f.uploaded_by_user_id, a.created_at
    FROM [core].[attachment] a
    JOIN [core].[stored_file] f ON f.id = a.file_id
    WHERE a.company_id = @company_id AND a.entity_type = N'req.request' AND a.entity_id = @id
    ORDER BY a.id;
END
