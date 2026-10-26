-- "Update Information" (Benefits Employees tab, SRS M14 self-service): an employee asks for their
-- personal details to change; HR approves or rejects; approval writes hr.employee. The fields an
-- employee may ask for: date_of_birth, marital_status, phone_1, phone_2, home_address, home_city_id.
-- Codes: employees.update_requests.view / create / cancel / approve / reject, through
-- auth.fn_visible_employees. Nobody approves or rejects their own request.

CREATE OR ALTER FUNCTION [hr].[fn_change_request_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT r.id, r.company_id, r.employee_id, e.code AS employee_code,
       LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))) AS employee_name, r.status, r.changes, r.previous_values,
       r.remarks, r.decided_by_user_id, du.display_name AS decided_by_name, r.decided_at, r.decision_remarks,
       r.created_at, r.created_by AS created_by_user_id, cu.display_name AS created_by_name, r.updated_at, r.row_version
FROM [hr].[employee_change_request] r
JOIN [hr].[employee] e ON e.id = r.employee_id
LEFT JOIN [auth].[user_account] du ON du.id = r.decided_by_user_id
LEFT JOIN [auth].[user_account] cu ON cu.id = r.created_by
WHERE r.company_id = @company_id;
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_change_request_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @permission_code NVARCHAR(150) = N'employees.update_requests.view'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee_change_request] r
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
                   WHERE r.id = @id AND r.company_id = @company_id)
        THROW 50404, N'Update request not found', 1;

    SELECT r.* FROM [hr].[fn_change_request_rows](@company_id) r WHERE r.id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_change_request_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT = NULL,
    @status        NVARCHAR(30) = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT r.id
    FROM [hr].[employee_change_request] r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.update_requests.view') v ON v.employee_id = r.employee_id
    WHERE r.company_id = @company_id
      AND (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@status IS NULL OR r.status = @status)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM @ids;

    SELECT r.*
    FROM @ids i
    JOIN [hr].[fn_change_request_rows](@company_id) r ON r.id = i.id
    ORDER BY r.created_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Files a request. @changes is JSON with snake_case keys among the six fields; one pending request per
-- employee at a time. HR users who may approve it for this employee get an inbox notification.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_change_request_submit]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @changes       NVARCHAR(MAX),
    @remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.update_requests.create';

    IF ISJSON(@changes) = 0 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@changes))
        THROW 50400, N'changes|Give at least one detail to change.', 1;
    IF EXISTS (SELECT 1 FROM OPENJSON(@changes)
               WHERE [key] NOT IN (N'date_of_birth', N'marital_status', N'phone_1', N'phone_2', N'home_address', N'home_city_id'))
        THROW 50400, N'changes|Only date of birth, marital status, phones and home address can be asked for.', 1;
    DECLARE @dob DATE = TRY_CAST(JSON_VALUE(@changes, '$.date_of_birth') AS DATE),
            @marital NVARCHAR(30) = JSON_VALUE(@changes, '$.marital_status'),
            @city BIGINT = TRY_CAST(JSON_VALUE(@changes, '$.home_city_id') AS BIGINT);
    IF @dob > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'dateOfBirth|Date of birth is in the future.', 1;
    IF @marital IS NOT NULL AND @marital NOT IN (N'single', N'married', N'divorced', N'widowed')
        THROW 50400, N'maritalStatus|Choose single, married, divorced or widowed.', 1;
    IF @city IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[city] WHERE id = @city)
        THROW 50400, N'homeCityId|City not found.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_change_request] WHERE employee_id = @employee_id AND status = N'pending')
        THROW 50409, N'changes|UPDATE_REQUEST_PENDING|An Update Information request is already waiting for HR. Cancel it or wait for the decision.', 1;

    DECLARE @current NVARCHAR(MAX) = (
        SELECT date_of_birth, marital_status, phone_1, phone_2, home_address, home_city_id
        FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
    IF NOT EXISTS (SELECT 1 FROM OPENJSON(@changes) c JOIN OPENJSON(@current) o ON o.[key] = c.[key]
                   WHERE EXISTS (SELECT c.value EXCEPT SELECT o.value))
        THROW 50400, N'changes|These are already your details.', 1;

    DECLARE @id BIGINT, @payload NVARCHAR(MAX), @title NVARCHAR(200), @who BIGINT;
    DECLARE @approvers TABLE (id BIGINT PRIMARY KEY);
    BEGIN TRAN;
        INSERT [hr].[employee_change_request] (company_id, employee_id, status, changes, previous_values, remarks, created_by)
        VALUES (@company_id, @employee_id, N'pending', @changes, @current, @remarks, @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee_change_request', @id, N'create', N'pending', @actor_user_id, SYSUTCDATETIME());

        SET @payload = (SELECT CONVERT(NVARCHAR(30), @id) AS changeRequestId, CONVERT(NVARCHAR(30), @employee_id) AS employeeId,
                               N'pending' AS status, JSON_QUERY(@changes) AS changes,
                               CONVERT(NVARCHAR(30), @actor_user_id) AS actorUserId
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'employees.update_requested',
             @entity_type = N'hr.employee_change_request', @entity_id = @id, @payload = @payload;

        -- Tell the people who may approve it for this employee (not the employee themselves).
        INSERT @approvers
        SELECT u.id
        FROM [auth].[user_account] u
        WHERE u.is_active = 1 AND ISNULL(u.employee_id, 0) <> @employee_id
          AND (EXISTS (SELECT 1 FROM [auth].[user_role] ur JOIN [auth].[role] ro ON ro.id = ur.role_id
                       WHERE ur.user_account_id = u.id AND ro.company_id = @company_id)
               OR EXISTS (SELECT 1 FROM [auth].[user_permission_override] o
                          WHERE o.user_account_id = u.id AND o.company_id = @company_id AND o.effect = N'grant'))
          AND EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, u.id, N'employees.update_requests.approve') v
                      WHERE v.employee_id = @employee_id);
        SET @title = (SELECT CONCAT(LTRIM(RTRIM(CONCAT(first_name, N' ', last_name))), N' asked to update their details')
                      FROM [hr].[employee] WHERE id = @employee_id);
        SET @who = (SELECT MIN(id) FROM @approvers);
        WHILE @who IS NOT NULL
        BEGIN
            EXEC [core].[usp_notification_add] @quiet = 1, @company_id = @company_id, @user_account_id = @who, @title = @title,
                 @notification_type = N'employee_update_request', @link = N'/employees/update-requests',
                 @entity_type = N'hr.employee_change_request', @entity_id = @id;
            SET @who = (SELECT MIN(id) FROM @approvers WHERE id > @who);
        END
    COMMIT;

    EXEC [hr].[usp_employee_change_request_get] @company_id, @actor_user_id, @id, N'employees.update_requests.create';
END
GO

-- @decision approved (employees.update_requests.approve), rejected (.reject) or cancelled (.cancel).
-- Approval writes the asked values to hr.employee (one History row per changed field). The employee
-- is told of an approval or rejection.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_change_request_decide]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @decision      NVARCHAR(30),
    @remarks       NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');
    DECLARE @code NVARCHAR(150) = CASE @decision WHEN N'approved' THEN N'employees.update_requests.approve'
                                                 WHEN N'rejected' THEN N'employees.update_requests.reject'
                                                 WHEN N'cancelled' THEN N'employees.update_requests.cancel' END;
    IF @code IS NULL
        THROW 50400, N'decision|Approve, reject or cancel.', 1;

    DECLARE @employee_id BIGINT, @status NVARCHAR(30), @rv BINARY(8), @changes NVARCHAR(MAX);
    SELECT @employee_id = r.employee_id, @status = r.status, @rv = r.row_version, @changes = r.changes
    FROM [hr].[employee_change_request] r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @code) v ON v.employee_id = r.employee_id
    WHERE r.id = @id AND r.company_id = @company_id;

    IF @employee_id IS NULL
        THROW 50404, N'Update request not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this request. Reload it and try again', 1;
    IF @status <> N'pending'
        THROW 50409, N'status|UPDATE_REQUEST_DECIDED|This request has already been decided.', 1;
    IF @decision <> N'cancelled' AND EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @actor_user_id AND employee_id = @employee_id)
        THROW 50403, N'You cannot decide your own request.', 1;
    IF @decision = N'approved' AND TRY_CAST(JSON_VALUE(@changes, '$.home_city_id') AS BIGINT) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [org].[city] WHERE id = TRY_CAST(JSON_VALUE(@changes, '$.home_city_id') AS BIGINT))
        THROW 50409, N'The city asked for no longer exists. Reject the request.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @payload NVARCHAR(MAX), @title NVARCHAR(200);
    BEGIN TRAN;
        UPDATE [hr].[employee_change_request]
        SET status = @decision, decided_by_user_id = @actor_user_id, decided_at = @now, decision_remarks = @remarks,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this request. Reload it and try again', 1;

        IF @decision = N'approved'
        BEGIN
            DECLARE @keys TABLE ([key] NVARCHAR(50) PRIMARY KEY);
            INSERT @keys SELECT [key] FROM OPENJSON(@changes);
            DECLARE @before NVARCHAR(MAX) = (
                SELECT date_of_birth, marital_status, phone_1, phone_2, home_address, home_city_id
                FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

            UPDATE [hr].[employee]
            SET date_of_birth = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = N'date_of_birth')
                                     THEN TRY_CAST(JSON_VALUE(@changes, '$.date_of_birth') AS DATE) ELSE date_of_birth END,
                marital_status = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = N'marital_status')
                                      THEN JSON_VALUE(@changes, '$.marital_status') ELSE marital_status END,
                phone_1 = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = N'phone_1')
                               THEN NULLIF(LTRIM(RTRIM(JSON_VALUE(@changes, '$.phone_1'))), N'') ELSE phone_1 END,
                phone_2 = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = N'phone_2')
                               THEN NULLIF(LTRIM(RTRIM(JSON_VALUE(@changes, '$.phone_2'))), N'') ELSE phone_2 END,
                home_address = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = N'home_address')
                                    THEN NULLIF(LTRIM(RTRIM(JSON_VALUE(@changes, '$.home_address'))), N'') ELSE home_address END,
                home_city_id = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = N'home_city_id')
                                    THEN TRY_CAST(JSON_VALUE(@changes, '$.home_city_id') AS BIGINT) ELSE home_city_id END,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @employee_id;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'hr.employee', @employee_id, b.[key], b.value, a.value, N'update_request', @actor_user_id, @now
            FROM OPENJSON(@before) b
            JOIN OPENJSON((SELECT date_of_birth, marital_status, phone_1, phone_2, home_address, home_city_id
                           FROM [hr].[employee] WHERE id = @employee_id
                           FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) a ON a.[key] = b.[key]
            WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);

            EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @employee_id,
                 @event_type = N'employees.updated', @change = N'update_request', @actor_user_id = @actor_user_id;
        END

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'hr.employee_change_request', @id, N'status', N'pending', @decision, @decision, @actor_user_id, @now);

        SET @payload = (SELECT CONVERT(NVARCHAR(30), @id) AS changeRequestId, CONVERT(NVARCHAR(30), @employee_id) AS employeeId,
                               @decision AS status, CONVERT(NVARCHAR(30), @actor_user_id) AS actorUserId
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'employees.update_decided',
             @entity_type = N'hr.employee_change_request', @entity_id = @id, @payload = @payload;

        IF @decision IN (N'approved', N'rejected')
        BEGIN
            SET @title = CONCAT(N'Your Update Information request was ', @decision);
            EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
                 @title = @title, @body = @remarks, @notification_type = N'employee_update_request',
                 @link = N'/profile', @entity_type = N'hr.employee_change_request', @entity_id = @id;
        END
    COMMIT;

    EXEC [hr].[usp_employee_change_request_get] @company_id, @actor_user_id, @id, @code;
END
