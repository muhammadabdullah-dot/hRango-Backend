-- The requisition's effect, run by the request engine inside the final approval's transaction.
-- A requisition is approval only: nothing in HRango stocks or buys items. On approval the people
-- who fulfil it are told: holders of the IT Administrator authority for IT equipment, of the Admin
-- Manager authority for everything else (Request Settings -> Authorities, matched on the request
-- type, branch and department like a flow node). The requests.approved event carries the request
-- for a purchasing system to pick up. No revert: cancelling an approved requisition only tells
-- the same people (through requests.cancelled).
CREATE OR ALTER PROCEDURE [req].[usp_request_apply_requisition]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @code NVARCHAR(30), @type_id BIGINT, @employee_id BIGINT, @branch_id BIGINT, @department_id BIGINT,
            @title NVARCHAR(200), @rq_type NVARCHAR(30), @needed DATE, @who_name NVARCHAR(400);
    SELECT @code = r.code, @type_id = r.request_type_id, @employee_id = r.employee_id, @branch_id = e.branch_id,
           @department_id = e.department_id, @title = q.title, @rq_type = q.requisition_type, @needed = q.needed_by_date,
           @who_name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')
    FROM [req].[request] r
    JOIN [req].[req_requisition] q ON q.request_id = r.id
    JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.id = @request_id AND r.company_id = @company_id;
    IF @code IS NULL
        RETURN;

    DECLARE @authority NVARCHAR(30) = CASE WHEN @rq_type = N'it_equipment' THEN N'it_administrator' ELSE N'admin_manager' END;
    DECLARE @to TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @to (employee_id)
    SELECT DISTINCT a.employee_id
    FROM [req].[approval_authority] a
    JOIN [hr].[employee] ae ON ae.id = a.employee_id AND ae.status <> N'left'
    WHERE a.company_id = @company_id AND a.authority = @authority AND a.is_active = 1
      AND (a.request_type_id IS NULL OR a.request_type_id = @type_id)
      AND (a.branch_id IS NULL OR a.branch_id = @branch_id)
      AND (a.department_id IS NULL OR a.department_id = @department_id)
      AND a.employee_id <> @employee_id;

    DECLARE @who BIGINT = (SELECT MIN(employee_id) FROM @to),
            @n_title NVARCHAR(200) = LEFT(N'Requisition ' + @code + N' approved: ' + ISNULL(@title, N''), 200),
            @n_body NVARCHAR(MAX) = ISNULL(@who_name, N'An employee') + N' needs it by ' + CONVERT(NVARCHAR(10), @needed, 23) + N'.',
            @link NVARCHAR(500) = N'/requests/requisition/' + CONVERT(NVARCHAR(30), @request_id);
    WHILE @who IS NOT NULL
    BEGIN
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @who,
             @title = @n_title, @body = @n_body, @notification_type = N'request_fulfil', @link = @link,
             @entity_type = N'req.request', @entity_id = @request_id;
        SET @who = (SELECT MIN(employee_id) FROM @to WHERE employee_id > @who);
    END
END
