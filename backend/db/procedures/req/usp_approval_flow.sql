-- Request Settings -> Request Flows and the node editor (Figma "Request Flow Edit"; Mini SRS APR-1..3).
-- A flow is saved as a new version each time, so requests already on the way keep the nodes they
-- started with; only the current version is listed.
CREATE OR ALTER PROCEDURE [req].[usp_approval_flow_list]
    @company_id BIGINT,
    @type_code  NVARCHAR(30) = NULL,
    @purpose    NVARCHAR(30) = NULL,
    @scope_type NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [req].[approval_flow] f JOIN [req].[request_type] t ON t.id = f.request_type_id
    WHERE f.company_id = @company_id AND f.is_current = 1 AND (@type_code IS NULL OR t.code = @type_code)
      AND (@purpose IS NULL OR f.purpose = @purpose) AND (@scope_type IS NULL OR f.scope_type = @scope_type)
    OPTION (RECOMPILE);

    SELECT f.id, t.code AS request_type, t.name AS request_type_name, f.purpose, f.name, f.scope_type, f.scope_id,
           COALESCE(b.name, d.name, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')) AS scope_name,
           f.description, f.is_active,
           (SELECT COUNT(*) FROM [req].[approval_node] n WHERE n.approval_flow_id = f.id) AS node_count,
           f.created_at, f.updated_at, f.row_version
    FROM [req].[approval_flow] f
    JOIN [req].[request_type] t ON t.id = f.request_type_id
    LEFT JOIN [org].[branch] b ON f.scope_type = N'branch' AND b.id = f.scope_id
    LEFT JOIN [org].[department] d ON f.scope_type = N'department' AND d.id = f.scope_id
    LEFT JOIN [hr].[employee] e ON f.scope_type = N'employee' AND e.id = f.scope_id
    WHERE f.company_id = @company_id AND f.is_current = 1 AND (@type_code IS NULL OR t.code = @type_code)
      AND (@purpose IS NULL OR f.purpose = @purpose) AND (@scope_type IS NULL OR f.scope_type = @scope_type)
    ORDER BY t.sort_order, f.purpose, CASE f.scope_type WHEN N'company' THEN 1 WHEN N'branch' THEN 2
                                                         WHEN N'department' THEN 3 ELSE 4 END, f.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One flow version. Result sets: the flow; its nodes (Next / If True / If False as node numbers).
CREATE OR ALTER PROCEDURE [req].[usp_approval_flow_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [req].[approval_flow] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Approval flow not found', 1;

    SELECT f.id, t.code AS request_type, t.name AS request_type_name, f.purpose, f.name, f.scope_type, f.scope_id,
           COALESCE(b.name, d.name, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')) AS scope_name,
           f.description, f.is_active, f.is_current,
           (SELECT COUNT(*) FROM [req].[approval_node] n WHERE n.approval_flow_id = f.id) AS node_count,
           f.created_at, f.updated_at, f.row_version
    FROM [req].[approval_flow] f
    JOIN [req].[request_type] t ON t.id = f.request_type_id
    LEFT JOIN [org].[branch] b ON f.scope_type = N'branch' AND b.id = f.scope_id
    LEFT JOIN [org].[department] d ON f.scope_type = N'department' AND d.id = f.scope_id
    LEFT JOIN [hr].[employee] e ON f.scope_type = N'employee' AND e.id = f.scope_id
    WHERE f.id = @id;

    SELECT n.id, n.step_no, n.approver_kind, n.approver_employee_id,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS approver_employee_name,
           n.role_id, r.name AS role_name, n.is_condition, n.expression, n.condition_field, n.condition_operator,
           n.condition_value, nx.step_no AS next_step, tn.step_no AS true_step, fn.step_no AS false_step,
           n.can_edit, n.can_disagree, n.is_observer
    FROM [req].[approval_node] n
    LEFT JOIN [hr].[employee] e ON e.id = n.approver_employee_id
    LEFT JOIN [auth].[role] r ON r.id = n.role_id
    LEFT JOIN [req].[approval_node] nx ON nx.id = n.next_node_id
    LEFT JOIN [req].[approval_node] tn ON tn.id = n.true_node_id
    LEFT JOIN [req].[approval_node] fn ON fn.id = n.false_node_id
    WHERE n.approval_flow_id = @id
    ORDER BY n.step_no;
END
GO

-- Adds a flow (@id NULL) or saves a new version of one (@id and the @row_version last read).
-- @nodes: JSON array of {step_no, approver_kind, approver_employee_id, role_id, is_condition,
-- expression, condition_field, condition_operator, condition_value, next_step, true_step,
-- false_step, can_edit, can_disagree, is_observer}; shapes, kinds, expressions and loops are checked
-- by the service before this runs. Last result set: the id of the saved version.
CREATE OR ALTER PROCEDURE [req].[usp_approval_flow_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @type_code     NVARCHAR(30),
    @purpose       NVARCHAR(30),
    @name          NVARCHAR(200),
    @scope_type    NVARCHAR(30),
    @scope_id      BIGINT = NULL,
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @nodes         NVARCHAR(MAX),
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @type_id BIGINT = (SELECT id FROM [req].[request_type] WHERE code = @type_code);
    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    IF @type_id IS NULL
        THROW 50400, N'requestType|Request type is required.', 1;
    IF @name IS NULL
        THROW 50400, N'name|Flow name is required.', 1;
    IF @scope_type = N'company'
        SET @scope_id = NULL;
    ELSE IF @scope_id IS NULL
         OR (@scope_type = N'branch' AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @scope_id AND company_id = @company_id))
         OR (@scope_type = N'department' AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @scope_id AND company_id = @company_id))
         OR (@scope_type = N'employee' AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @scope_id AND company_id = @company_id))
        THROW 50400, N'scopeId|Choose the branch, department or employee this flow is for.', 1;
    IF ISJSON(@nodes) = 0
        THROW 50400, N'nodes|Nodes are not valid.', 1;

    DECLARE @n TABLE (step_no INT PRIMARY KEY, approver_kind NVARCHAR(30), approver_employee_id BIGINT, role_id BIGINT,
                      is_condition BIT, expression NVARCHAR(MAX), condition_field NVARCHAR(200), condition_operator NVARCHAR(2),
                      condition_value DECIMAL(18,4), next_step INT, true_step INT, false_step INT, can_edit BIT,
                      can_disagree BIT, is_observer BIT, id BIGINT NULL);
    INSERT @n (step_no, approver_kind, approver_employee_id, role_id, is_condition, expression, condition_field,
               condition_operator, condition_value, next_step, true_step, false_step, can_edit, can_disagree, is_observer)
    SELECT step_no, approver_kind, approver_employee_id, role_id, ISNULL(is_condition, 0), expression, condition_field,
           condition_operator, condition_value, next_step, true_step, false_step, ISNULL(can_edit, 0),
           ISNULL(can_disagree, 0), ISNULL(is_observer, 0)
    FROM OPENJSON(@nodes) WITH (
        step_no INT N'$.step_no', approver_kind NVARCHAR(30) N'$.approver_kind', approver_employee_id BIGINT N'$.approver_employee_id',
        role_id BIGINT N'$.role_id', is_condition BIT N'$.is_condition', expression NVARCHAR(MAX) N'$.expression',
        condition_field NVARCHAR(200) N'$.condition_field', condition_operator NVARCHAR(2) N'$.condition_operator',
        condition_value DECIMAL(18,4) N'$.condition_value', next_step INT N'$.next_step', true_step INT N'$.true_step',
        false_step INT N'$.false_step', can_edit BIT N'$.can_edit', can_disagree BIT N'$.can_disagree', is_observer BIT N'$.is_observer');

    IF NOT EXISTS (SELECT 1 FROM @n)
        THROW 50400, N'nodes|Add at least one node.', 1;
    IF EXISTS (SELECT 1 FROM @n WHERE approver_kind = N'employee' AND is_condition = 0
               AND NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = approver_employee_id AND e.company_id = @company_id))
        THROW 50400, N'nodes|An approver employee was not found.', 1;
    IF EXISTS (SELECT 1 FROM @n WHERE approver_kind = N'role' AND is_condition = 0
               AND NOT EXISTS (SELECT 1 FROM [auth].[role] r WHERE r.id = role_id AND r.company_id = @company_id))
        THROW 50400, N'nodes|An approver role was not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @old_id BIGINT = @id;
    IF @old_id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8), @current BIT;
        SELECT @rv = row_version, @current = is_current FROM [req].[approval_flow] WHERE id = @old_id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Approval flow not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version OR @current = 0
            THROW 50409, N'Someone else changed this flow. Reload it and try again', 1;
    END
    IF EXISTS (SELECT 1 FROM [req].[approval_flow]
               WHERE company_id = @company_id AND request_type_id = @type_id AND purpose = @purpose AND scope_type = @scope_type
                 AND ISNULL(scope_id, 0) = ISNULL(@scope_id, 0) AND is_current = 1 AND (@old_id IS NULL OR id <> @old_id))
        THROW 50409, N'scopeType|FLOW_DUPLICATE|This request type already has a flow for this purpose and scope. Edit that one.', 1;

    BEGIN TRAN;
        IF @old_id IS NOT NULL
        BEGIN
            UPDATE [req].[approval_flow] SET is_current = 0, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @old_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this flow. Reload it and try again', 1;
        END

        INSERT [req].[approval_flow] (company_id, request_type_id, purpose, name, scope_type, scope_id, description,
                                      is_active, is_current, created_by)
        VALUES (@company_id, @type_id, @purpose, @name, @scope_type, @scope_id, NULLIF(LTRIM(RTRIM(@description)), N''),
                ISNULL(@is_active, 1), 1, @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        DECLARE @ids TABLE (id BIGINT, step_no INT);
        INSERT [req].[approval_node] (approval_flow_id, step_no, approver_kind, approver_employee_id, role_id, is_condition,
                                      expression, condition_field, condition_operator, condition_value, can_edit,
                                      can_disagree, is_observer, created_by)
        OUTPUT INSERTED.id, INSERTED.step_no INTO @ids
        SELECT @id, step_no, CASE WHEN is_condition = 1 THEN NULL ELSE approver_kind END,
               CASE WHEN is_condition = 0 AND approver_kind = N'employee' THEN approver_employee_id END,
               CASE WHEN is_condition = 0 AND approver_kind = N'role' THEN role_id END, is_condition,
               expression, condition_field, condition_operator, condition_value,
               can_edit, can_disagree, is_observer, @actor_user_id
        FROM @n;

        UPDATE n
        SET next_node_id = nx.id, true_node_id = tn.id, false_node_id = fn.id
        FROM [req].[approval_node] n
        JOIN @n s ON s.step_no = n.step_no
        LEFT JOIN @ids nx ON nx.step_no = s.next_step
        LEFT JOIN @ids tn ON tn.step_no = s.true_step
        LEFT JOIN @ids fn ON fn.step_no = s.false_step
        WHERE n.approval_flow_id = @id;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.approval_flow', @id, CASE WHEN @old_id IS NULL THEN NULL ELSE N'previous_version' END,
                CONVERT(NVARCHAR(30), @old_id), CASE WHEN @old_id IS NULL THEN N'create' ELSE N'update' END, @actor_user_id, @now);
    COMMIT;

    SELECT @id AS id;
END
GO

-- Deletes a flow: its current version stops being used. Requests already on it carry on.
CREATE OR ALTER PROCEDURE [req].[usp_approval_flow_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @current BIT;
    SELECT @rv = row_version, @current = is_current FROM [req].[approval_flow] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL OR @current = 0
        THROW 50404, N'Approval flow not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this flow. Reload it and try again', 1;

    BEGIN TRAN;
        UPDATE [req].[approval_flow] SET is_current = 0, is_active = 0, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
        WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.approval_flow', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
