-- Picks the flow a request walks and stores it on the request (internal; called inside the
-- submit and cancel transactions). The most specific current, active flow for the request type
-- and purpose wins: the employee's own, then their department's, their branch's, the company's.
-- A cancellation with no cancellation flow walks the request flow. A company with no request flow
-- for a type gets the General Flow (Line Manager, then Final Authority), saved so it can be edited
-- under Request Settings.
CREATE OR ALTER PROCEDURE [req].[usp_request_flow_pick]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT,
    @purpose       NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @type_id BIGINT, @employee_id BIGINT, @department_id BIGINT, @branch_id BIGINT, @flow_id BIGINT;
    SELECT @type_id = r.request_type_id, @employee_id = r.employee_id, @department_id = e.department_id,
           @branch_id = e.branch_id
    FROM [req].[request] r JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    DECLARE @p NVARCHAR(30) = @purpose;
    WHILE @flow_id IS NULL AND @p IS NOT NULL
    BEGIN
        SELECT TOP (1) @flow_id = f.id
        FROM [req].[approval_flow] f
        WHERE f.company_id = @company_id AND f.request_type_id = @type_id AND f.purpose = @p
          AND f.is_current = 1 AND f.is_active = 1
          AND (   (f.scope_type = N'employee' AND f.scope_id = @employee_id)
               OR (f.scope_type = N'department' AND f.scope_id = @department_id)
               OR (f.scope_type = N'branch' AND f.scope_id = @branch_id)
               OR f.scope_type = N'company')
          AND EXISTS (SELECT 1 FROM [req].[approval_node] n WHERE n.approval_flow_id = f.id)
        ORDER BY CASE f.scope_type WHEN N'employee' THEN 1 WHEN N'department' THEN 2 WHEN N'branch' THEN 3 ELSE 4 END, f.id DESC;

        SET @p = CASE WHEN @p = N'cancellation' THEN N'request' END;
    END

    IF @flow_id IS NULL
    BEGIN
        -- Only when the company has never had a request flow for this type: a flow that was deleted
        -- or switched off is a choice, and the request is refused until one applies.
        IF EXISTS (SELECT 1 FROM [req].[approval_flow] f
                   WHERE f.company_id = @company_id AND f.request_type_id = @type_id AND f.purpose = N'request')
            THROW 50400, N'requestType|NO_FLOW|No active approval flow applies to this request. Set one under Request Settings.', 1;

        INSERT [req].[approval_flow] (company_id, request_type_id, purpose, name, scope_type, description,
                                      is_active, is_current, created_by)
        VALUES (@company_id, @type_id, N'request', N'General Flow', N'company',
                N'Line Manager, then Final Authority. Added automatically; edit it under Request Settings.',
                1, 1, @actor_user_id);
        SET @flow_id = SCOPE_IDENTITY();
        INSERT [req].[approval_node] (approval_flow_id, step_no, approver_kind, created_by)
        VALUES (@flow_id, 1, N'line_manager', @actor_user_id), (@flow_id, 2, N'final_authority', @actor_user_id);
    END

    UPDATE [req].[request]
    SET approval_flow_id = @flow_id, current_node_id = NULL, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @request_id;
END
