-- The Approvals screen: requests the caller is part of through the flow or a delegation (ACC-13),
-- whatever their list permissions reach. @box picks the tab:
--   requested      steps the caller holds (directly or through a role)
--   delegates      steps of people who delegated that request type to the caller (@delegator_id narrows)
--   consents       consent steps the caller is asked for
--   cancellations  steps of cancellation flows
-- @status 'pending' means waiting for the caller; other values filter the request's status.
-- Result sets: the total; the page; counts for the status tabs.
CREATE OR ALTER PROCEDURE [req].[usp_request_approval_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @box           NVARCHAR(20) = N'requested',
    @type_code     NVARCHAR(30) = NULL,
    @status        NVARCHAR(30) = NULL,
    @delegator_id  BIGINT = NULL,
    @search        NVARCHAR(200) = NULL,
    @employee_id   BIGINT = NULL,
    @department_id BIGINT = NULL,
    @branch_id     BIGINT = NULL,
    @location_id   BIGINT = NULL,
    @date_from     DATE = NULL,
    @date_to       DATE = NULL,
    @page          INT = 1,
    @page_size     INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    DECLARE @mine TABLE (request_id BIGINT PRIMARY KEY, waiting BIT, delegator_id BIGINT, status NVARCHAR(30));
    INSERT @mine (request_id, waiting, delegator_id)
    SELECT a.request_id, MAX(CASE WHEN s.action_taken = N'pending' THEN 1 ELSE 0 END), MAX(a.delegator_id)
    FROM [req].[fn_actor_steps](@company_id, @me) a
    JOIN [req].[request_step] s ON s.id = a.step_id
    WHERE (@box = N'requested' AND a.is_delegate = 0 AND s.is_consent = 0 AND s.purpose = N'request')
       OR (@box = N'delegates' AND a.is_delegate = 1 AND (@delegator_id IS NULL OR a.delegator_id = @delegator_id))
       OR (@box = N'consents' AND a.is_delegate = 0 AND s.is_consent = 1)
       OR (@box = N'cancellations' AND s.purpose = N'cancellation' AND s.is_consent = 0)
    GROUP BY a.request_id;

    DELETE m
    FROM @mine m
    LEFT JOIN [req].[fn_request_rows](@company_id) r ON r.id = m.request_id
    WHERE r.id IS NULL
       OR r.employee_id = @me
       OR NOT ((@type_code IS NULL OR r.request_type = @type_code)
           AND (@pattern IS NULL OR r.code LIKE @pattern OR r.employee_name LIKE @pattern OR r.employee_code LIKE @pattern)
           AND (@employee_id IS NULL OR r.employee_id = @employee_id)
           AND (@department_id IS NULL OR r.department_id = @department_id)
           AND (@branch_id IS NULL OR r.branch_id = @branch_id)
           AND (@location_id IS NULL OR r.location_id = @location_id)
           AND (@date_from IS NULL OR ISNULL(r.to_date, r.from_date) >= @date_from)
           AND (@date_to IS NULL OR r.from_date <= @date_to));
    UPDATE m SET status = r.status FROM @mine m JOIN [req].[request] r ON r.id = m.request_id;

    SELECT COUNT(*) AS total FROM @mine
    WHERE @status IS NULL OR (@status = N'pending' AND waiting = 1) OR (@status <> N'pending' AND status = @status);

    SELECT r.*, [req].[fn_request_details](r.id) AS details_json, m.waiting AS is_waiting,
           m.delegator_id, NULLIF(CONCAT(dg.first_name, N' ', dg.last_name), N' ') AS delegator_name
    FROM @mine m
    JOIN [req].[fn_request_rows](@company_id) r ON r.id = m.request_id
    LEFT JOIN [hr].[employee] dg ON dg.id = m.delegator_id
    WHERE @status IS NULL OR (@status = N'pending' AND m.waiting = 1) OR (@status <> N'pending' AND m.status = @status)
    ORDER BY m.waiting DESC, r.submitted_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);

    SELECT s.status, COUNT(m.request_id) AS total
    FROM (VALUES (N'pending'), (N'approved'), (N'rejected'), (N'cancelling'), (N'cancelled')) s (status)
    LEFT JOIN @mine m ON (s.status = N'pending' AND m.waiting = 1) OR (s.status <> N'pending' AND m.status = s.status)
    GROUP BY s.status;
END
