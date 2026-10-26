-- Request Settings -> Delegation. An active delegation lets the delegatee approve, reject or cancel
-- the delegator's requests of one type on their behalf (Functional Requirements pp. 2-4).
CREATE OR ALTER PROCEDURE [req].[usp_delegation_list]
    @company_id   BIGINT,
    @delegator_id BIGINT = NULL,
    @delegatee_id BIGINT = NULL,
    @type_code    NVARCHAR(30) = NULL,
    @is_active    BIT = NULL,
    @search       NVARCHAR(200) = NULL,
    @page         INT = 1,
    @page_size    INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    WITH x AS (
        SELECT d.id, d.delegator_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS delegator_name,
               d.delegatee_id, NULLIF(CONCAT(b.first_name, N' ', b.last_name), N' ') AS delegatee_name,
               t.code AS request_type, t.name AS request_type_name, d.description, d.is_active,
               d.created_at, d.updated_at, d.row_version
        FROM [req].[delegation] d
        JOIN [hr].[employee] a ON a.id = d.delegator_id
        JOIN [hr].[employee] b ON b.id = d.delegatee_id
        JOIN [req].[request_type] t ON t.id = d.request_type_id
        WHERE d.company_id = @company_id
          AND (@delegator_id IS NULL OR d.delegator_id = @delegator_id)
          AND (@delegatee_id IS NULL OR d.delegatee_id = @delegatee_id)
          AND (@type_code IS NULL OR t.code = @type_code)
          AND (@is_active IS NULL OR d.is_active = @is_active)
    )
    SELECT COUNT(*) AS total FROM x
    WHERE @pattern IS NULL OR x.delegator_name LIKE @pattern OR x.delegatee_name LIKE @pattern OR x.description LIKE @pattern
    OPTION (RECOMPILE);

    SELECT d.id, d.delegator_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS delegator_name,
           d.delegatee_id, NULLIF(CONCAT(b.first_name, N' ', b.last_name), N' ') AS delegatee_name,
           t.code AS request_type, t.name AS request_type_name, d.description, d.is_active,
           d.created_at, d.updated_at, d.row_version
    FROM [req].[delegation] d
    JOIN [hr].[employee] a ON a.id = d.delegator_id
    JOIN [hr].[employee] b ON b.id = d.delegatee_id
    JOIN [req].[request_type] t ON t.id = d.request_type_id
    WHERE d.company_id = @company_id
      AND (@delegator_id IS NULL OR d.delegator_id = @delegator_id)
      AND (@delegatee_id IS NULL OR d.delegatee_id = @delegatee_id)
      AND (@type_code IS NULL OR t.code = @type_code)
      AND (@is_active IS NULL OR d.is_active = @is_active)
      AND (@pattern IS NULL OR CONCAT(a.first_name, N' ', a.last_name) LIKE @pattern
           OR CONCAT(b.first_name, N' ', b.last_name) LIKE @pattern OR d.description LIKE @pattern)
    ORDER BY d.is_active DESC, d.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_delegation_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [req].[delegation] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Delegation not found', 1;
    SELECT d.id, d.delegator_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS delegator_name,
           d.delegatee_id, NULLIF(CONCAT(b.first_name, N' ', b.last_name), N' ') AS delegatee_name,
           t.code AS request_type, t.name AS request_type_name, d.description, d.is_active,
           d.created_at, d.updated_at, d.row_version
    FROM [req].[delegation] d
    JOIN [hr].[employee] a ON a.id = d.delegator_id
    JOIN [hr].[employee] b ON b.id = d.delegatee_id
    JOIN [req].[request_type] t ON t.id = d.request_type_id
    WHERE d.id = @id;
END
GO

-- Adds a delegation (@id NULL), or edits one: description and Active / In-active (Disable, Enable).
-- Delegator and delegatee must differ; one active delegation per delegator and request type.
CREATE OR ALTER PROCEDURE [req].[usp_delegation_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @delegator_id  BIGINT = NULL,
    @delegatee_id  BIGINT = NULL,
    @type_code     NVARCHAR(30) = NULL,
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @type_id BIGINT;
    IF @id IS NULL
    BEGIN
        SET @type_id = (SELECT id FROM [req].[request_type] WHERE code = @type_code AND is_active = 1);
        IF @delegator_id IS NULL OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @delegator_id AND company_id = @company_id)
            THROW 50400, N'delegatorId|Delegator is required.', 1;
        IF @delegatee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @delegatee_id AND company_id = @company_id AND status <> N'left')
            THROW 50400, N'delegateeId|Delegatee is required.', 1;
        IF @delegator_id = @delegatee_id
            THROW 50400, N'delegateeId|The delegator and the delegatee cannot be the same person.', 1;
        IF @type_id IS NULL
            THROW 50400, N'requestType|Request type is required.', 1;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8);
        SELECT @rv = row_version, @delegator_id = delegator_id, @type_id = request_type_id
        FROM [req].[delegation] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Delegation not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this delegation. Reload it and try again', 1;
    END
    IF ISNULL(@is_active, 1) = 1 AND EXISTS (SELECT 1 FROM [req].[delegation] WHERE company_id = @company_id
               AND delegator_id = @delegator_id AND request_type_id = @type_id AND is_active = 1 AND (@id IS NULL OR id <> @id))
        THROW 50409, N'requestType|DELEGATION_DUPLICATE|This person already has an active delegation for this request type.', 1;

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [req].[delegation] (company_id, delegator_id, delegatee_id, request_type_id, description, is_active, created_by)
            VALUES (@company_id, @delegator_id, @delegatee_id, @type_id, NULLIF(LTRIM(RTRIM(@description)), N''),
                    ISNULL(@is_active, 1), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'req.delegation', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @old_active BIT, @old_desc NVARCHAR(MAX);
            SELECT @old_active = is_active, @old_desc = description FROM [req].[delegation] WHERE id = @id;
            UPDATE [req].[delegation]
            SET description = NULLIF(LTRIM(RTRIM(@description)), N''), is_active = ISNULL(@is_active, is_active),
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this delegation. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'req.delegation', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES (N'is_active', CONVERT(NVARCHAR(5), @old_active), CONVERT(NVARCHAR(5), ISNULL(@is_active, @old_active))),
                         (N'description', @old_desc, NULLIF(LTRIM(RTRIM(@description)), N''))) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        END
    COMMIT;

    EXEC [req].[usp_delegation_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a delegation (with the @row_version last read). Decisions a delegatee already took keep
-- their history (request_step.is_delegate); pending steps stop reaching the delegatee at once.
CREATE OR ALTER PROCEDURE [req].[usp_delegation_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [req].[delegation] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Delegation not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this delegation. Reload it and try again', 1;
    BEGIN TRAN;
        DELETE [req].[delegation] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.delegation', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Request Settings -> Request Flows: who holds an authority (HR Manager, Finance Manager ...) for a
-- request type, branch or department ("Select Request Type, Select Authority, Select Employee").
CREATE OR ALTER PROCEDURE [req].[usp_approval_authority_list]
    @company_id BIGINT,
    @authority  NVARCHAR(30) = NULL,
    @type_code  NVARCHAR(30) = NULL,
    @employee_id BIGINT = NULL,
    @page       INT = 1,
    @page_size  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [req].[approval_authority] a
    LEFT JOIN [req].[request_type] t ON t.id = a.request_type_id
    WHERE a.company_id = @company_id AND (@authority IS NULL OR a.authority = @authority)
      AND (@type_code IS NULL OR t.code = @type_code) AND (@employee_id IS NULL OR a.employee_id = @employee_id)
    OPTION (RECOMPILE);

    SELECT a.id, a.authority, a.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.code AS employee_code, ds.name AS designation_name, eb.name AS employee_branch_name,
           t.code AS request_type, t.name AS request_type_name, a.branch_id, b.name AS branch_name,
           a.department_id, d.name AS department_name, a.description, a.is_active, a.created_at, a.updated_at, a.row_version
    FROM [req].[approval_authority] a
    JOIN [hr].[employee] e ON e.id = a.employee_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[branch] eb ON eb.id = e.branch_id
    LEFT JOIN [req].[request_type] t ON t.id = a.request_type_id
    LEFT JOIN [org].[branch] b ON b.id = a.branch_id
    LEFT JOIN [org].[department] d ON d.id = a.department_id
    WHERE a.company_id = @company_id AND (@authority IS NULL OR a.authority = @authority)
      AND (@type_code IS NULL OR t.code = @type_code) AND (@employee_id IS NULL OR a.employee_id = @employee_id)
    ORDER BY a.authority, t.sort_order, a.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL) or edits an authority holder. No two active holders of one authority for the
-- same request type, branch and department ("prevent double assignments for the same request type").
CREATE OR ALTER PROCEDURE [req].[usp_approval_authority_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @authority     NVARCHAR(30),
    @employee_id   BIGINT,
    @type_code     NVARCHAR(30) = NULL,
    @branch_id     BIGINT = NULL,
    @department_id BIGINT = NULL,
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @type_id BIGINT = NULL, @now DATETIME2(0) = SYSUTCDATETIME();
    IF @type_code IS NOT NULL
    BEGIN
        SET @type_id = (SELECT id FROM [req].[request_type] WHERE code = @type_code);
        IF @type_id IS NULL
            THROW 50400, N'requestType|Request type not found.', 1;
    END
    IF @employee_id IS NULL OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id AND status <> N'left')
        THROW 50400, N'employeeId|Employee is required.', 1;
    IF @branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Branch not found.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF ISNULL(@is_active, 1) = 1 AND EXISTS (
            SELECT 1 FROM [req].[approval_authority]
            WHERE company_id = @company_id AND authority = @authority AND is_active = 1 AND (@id IS NULL OR id <> @id)
              AND ISNULL(request_type_id, 0) = ISNULL(@type_id, 0) AND ISNULL(branch_id, 0) = ISNULL(@branch_id, 0)
              AND ISNULL(department_id, 0) = ISNULL(@department_id, 0))
        THROW 50409, N'authority|AUTHORITY_DUPLICATE|Someone already holds this authority for this request type and unit. Change or disable that one first.', 1;

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [req].[approval_authority] (company_id, authority, employee_id, request_type_id, branch_id, department_id,
                                               description, is_active, created_by)
            VALUES (@company_id, @authority, @employee_id, @type_id, @branch_id, @department_id,
                    NULLIF(LTRIM(RTRIM(@description)), N''), ISNULL(@is_active, 1), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'req.approval_authority', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @rv BINARY(8) = (SELECT row_version FROM [req].[approval_authority] WHERE id = @id AND company_id = @company_id);
            IF @rv IS NULL
                THROW 50404, N'Authority not found', 1;
            IF @row_version IS NULL OR @rv <> @row_version
                THROW 50409, N'Someone else changed this authority. Reload it and try again', 1;
            UPDATE [req].[approval_authority]
            SET authority = @authority, employee_id = @employee_id, request_type_id = @type_id, branch_id = @branch_id,
                department_id = @department_id, description = NULLIF(LTRIM(RTRIM(@description)), N''),
                is_active = ISNULL(@is_active, 1), updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'req.approval_authority', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    SELECT a.id, a.authority, a.employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.code AS employee_code, ds.name AS designation_name, eb.name AS employee_branch_name,
           t.code AS request_type, t.name AS request_type_name, a.branch_id, b.name AS branch_name,
           a.department_id, d.name AS department_name, a.description, a.is_active, a.created_at, a.updated_at, a.row_version
    FROM [req].[approval_authority] a
    JOIN [hr].[employee] e ON e.id = a.employee_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [org].[branch] eb ON eb.id = e.branch_id
    LEFT JOIN [req].[request_type] t ON t.id = a.request_type_id
    LEFT JOIN [org].[branch] b ON b.id = a.branch_id
    LEFT JOIN [org].[department] d ON d.id = a.department_id
    WHERE a.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_approval_authority_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [req].[approval_authority] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Authority not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this authority. Reload it and try again', 1;
    BEGIN TRAN;
        DELETE [req].[approval_authority] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.approval_authority', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
