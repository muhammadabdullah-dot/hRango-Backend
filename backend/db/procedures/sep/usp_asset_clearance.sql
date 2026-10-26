-- Assets -> Asset Clearance Form. One form per leaver at a time, an item per allocation being
-- cleared. In progress until approved (bulk); approving ends each allocation on the clearance date,
-- marks damaged assets damaged and unreturned ones lost, and may complete the end of employment.
-- Unapproving puts everything back while the asset has not gone to someone else.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_list]
    @company_id           BIGINT,
    @actor_user_id        BIGINT,
    @search               NVARCHAR(200) = NULL,
    @status               NVARCHAR(30) = NULL,
    @employee_id          BIGINT = NULL,
    @department_id        BIGINT = NULL,
    @end_of_employment_id BIGINT = NULL,
    @page                 INT = 1,
    @page_size            INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sep].[asset_clearance] c
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.clearance.view') v ON v.employee_id = c.employee_id
    JOIN [hr].[employee] e ON e.id = c.employee_id
    WHERE c.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@status IS NULL OR c.status = @status)
      AND (@employee_id IS NULL OR c.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@end_of_employment_id IS NULL OR c.end_of_employment_id = @end_of_employment_id)
    OPTION (RECOMPILE);

    SELECT c.id, c.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.department_id, d.name AS department_name, c.end_of_employment_id, c.clearance_date, c.approval_date, c.status,
           (SELECT COUNT(*) FROM [sep].[asset_clearance_item] i WHERE i.asset_clearance_id = c.id) AS item_count,
           c.created_at, c.updated_at, c.row_version
    FROM [sep].[asset_clearance] c
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.clearance.view') v ON v.employee_id = c.employee_id
    JOIN [hr].[employee] e ON e.id = c.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE c.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@status IS NULL OR c.status = @status)
      AND (@employee_id IS NULL OR c.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@end_of_employment_id IS NULL OR c.end_of_employment_id = @end_of_employment_id)
    ORDER BY c.clearance_date DESC, c.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One form. Result set 1: the form. Result set 2: its items.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @permission_code NVARCHAR(150) = N'assets.clearance.view'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[asset_clearance] c
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = c.employee_id
                   WHERE c.id = @id AND c.company_id = @company_id)
        THROW 50404, N'Clearance form not found', 1;

    SELECT c.id, c.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.department_id, d.name AS department_name, c.end_of_employment_id, c.clearance_date,
           c.checked_by_id, NULLIF(CONCAT(cb.first_name, N' ', cb.last_name), N' ') AS checked_by_name,
           c.approved_by_id, NULLIF(CONCAT(ab.first_name, N' ', ab.last_name), N' ') AS approved_by_name,
           c.approval_date, c.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = c.file_id) AS file_name,
           c.status,
           (SELECT COUNT(*) FROM [sep].[asset_clearance_item] i WHERE i.asset_clearance_id = c.id) AS item_count,
           c.created_at, c.updated_at, c.row_version
    FROM [sep].[asset_clearance] c
    JOIN [hr].[employee] e ON e.id = c.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [hr].[employee] cb ON cb.id = c.checked_by_id
    LEFT JOIN [hr].[employee] ab ON ab.id = c.approved_by_id
    WHERE c.id = @id AND c.company_id = @company_id;

    SELECT i.id, i.asset_allocation_id, al.asset_id, a.code AS asset_code, a.name AS asset_name, a.identification_no,
           al.allocated_on, i.condition_at_clearance, i.reason, i.return_status, i.comments
    FROM [sep].[asset_clearance_item] i
    JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
    JOIN [sep].[asset] a ON a.id = al.asset_id
    WHERE i.asset_clearance_id = @id
    ORDER BY i.id;
END
GO

-- What a new form starts with: the employee, then their open allocations as items.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_prefill]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.clearance.create') v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    SELECT e.id AS employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.department_id, d.name AS department_name,
           (SELECT TOP 1 x.id FROM [sep].[end_of_employment] x
            WHERE x.employee_id = e.id AND x.status = N'pending' ORDER BY x.id DESC) AS end_of_employment_id
    FROM [hr].[employee] e
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE e.id = @employee_id;

    SELECT al.id AS asset_allocation_id, al.asset_id, a.code AS asset_code, a.name AS asset_name, a.identification_no,
           al.allocated_on
    FROM [sep].[asset_allocation] al
    JOIN [sep].[asset] a ON a.id = al.asset_id
    WHERE al.employee_id = @employee_id AND al.company_id = @company_id AND al.deallocated_on IS NULL
    ORDER BY al.allocated_on, al.id;
END
GO

-- Adds a form (@id NULL) or edits one in progress. @items is a JSON array of
-- {"asset_allocation_id", "condition_at_clearance", "reason", "return_status", "comments"}.
-- Without @end_of_employment_id the form is linked to the employee's pending end of employment, if any.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_save]
    @company_id           BIGINT,
    @actor_user_id        BIGINT,
    @id                   BIGINT = NULL,
    @employee_id          BIGINT,
    @end_of_employment_id BIGINT = NULL,
    @clearance_date       DATE,
    @checked_by_id        BIGINT = NULL,
    @approved_by_id       BIGINT = NULL,
    @approval_date        DATE = NULL,
    @file_id              BIGINT = NULL,
    @items                NVARCHAR(MAX) = N'[]',
    @row_version          BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @code NVARCHAR(150) = CASE WHEN @id IS NULL THEN N'assets.clearance.create' ELSE N'assets.clearance.edit' END;
    DECLARE @msg NVARCHAR(2048), @bad INT, @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @code) v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @employee_id = @actor_employee_id
        THROW 50403, N'You cannot make or change your own clearance form.', 1;
    IF @clearance_date IS NULL
        THROW 50400, N'clearanceDate|Clearance date is required.', 1;
    IF @checked_by_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @checked_by_id AND company_id = @company_id)
        THROW 50400, N'checkedById|Employee not found.', 1;
    IF @approved_by_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @approved_by_id AND company_id = @company_id)
        THROW 50400, N'approvedById|Employee not found.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    IF @end_of_employment_id IS NULL
        SET @end_of_employment_id = (SELECT TOP 1 id FROM [sep].[end_of_employment]
                                     WHERE company_id = @company_id AND employee_id = @employee_id AND status = N'pending'
                                     ORDER BY id DESC);
    ELSE IF NOT EXISTS (SELECT 1 FROM [sep].[end_of_employment] WHERE id = @end_of_employment_id AND company_id = @company_id
                        AND employee_id = @employee_id AND status = N'pending')
        THROW 50400, N'endOfEmploymentId|No pending end of employment for this employee.', 1;

    IF @id IS NOT NULL
    BEGIN
        DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30), @old_employee BIGINT;
        SELECT @old_rv = row_version, @old_status = status, @old_employee = employee_id
        FROM [sep].[asset_clearance] WHERE id = @id AND company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Clearance form not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a clearance form.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this clearance form. Reload it and try again', 1;
        IF @old_status <> N'in_progress'
            THROW 50409, N'status|CLEARANCE_APPROVED|This clearance form is approved. Unapprove it first.', 1;
        IF @old_employee <> @employee_id
            THROW 50400, N'employeeId|The employee of a clearance form cannot be changed.', 1;
    END

    IF EXISTS (SELECT 1 FROM [sep].[asset_clearance] WHERE company_id = @company_id AND employee_id = @employee_id
               AND status = N'in_progress' AND (@id IS NULL OR id <> @id))
        THROW 50409, N'employeeId|CLEARANCE_OPEN|This employee already has a clearance form in progress.', 1;

    IF ISJSON(ISNULL(@items, N'[]')) = 0
        THROW 50400, N'items|Items are not valid.', 1;

    DECLARE @it TABLE (idx INT, asset_allocation_id BIGINT, condition_at_clearance NVARCHAR(30), reason NVARCHAR(MAX),
                       return_status NVARCHAR(30), comments NVARCHAR(MAX));
    INSERT @it
    SELECT CAST(j.[key] AS INT), x.asset_allocation_id, NULLIF(x.condition_at_clearance, N''), x.reason,
           NULLIF(x.return_status, N''), x.comments
    FROM OPENJSON(ISNULL(@items, N'[]')) j
    CROSS APPLY OPENJSON(j.value) WITH (
        asset_allocation_id BIGINT '$.asset_allocation_id', condition_at_clearance NVARCHAR(30) '$.condition_at_clearance',
        reason NVARCHAR(MAX) '$.reason', return_status NVARCHAR(30) '$.return_status', comments NVARCHAR(MAX) '$.comments') x;

    SELECT TOP 1 @bad = i.idx FROM @it i
    WHERE NOT EXISTS (SELECT 1 FROM [sep].[asset_allocation] al WHERE al.id = i.asset_allocation_id
                      AND al.company_id = @company_id AND al.employee_id = @employee_id AND al.deallocated_on IS NULL)
    ORDER BY i.idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'items.', @bad, N'.assetAllocationId|This asset is not currently allocated to the employee.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = i.idx FROM @it i
    WHERE EXISTS (SELECT 1 FROM @it o WHERE o.asset_allocation_id = i.asset_allocation_id AND o.idx < i.idx)
    ORDER BY i.idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'items.', @bad, N'.assetAllocationId|This asset is listed twice.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = i.idx FROM @it i
    JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
    WHERE al.allocated_on > @clearance_date
    ORDER BY i.idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'items.', @bad, N'.assetAllocationId|The asset was allocated after the clearance date.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = idx FROM @it
    WHERE condition_at_clearance IS NULL OR condition_at_clearance NOT IN (N'good', N'fair', N'damaged')
    ORDER BY idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'items.', @bad, N'.conditionAtClearance|Condition must be good, fair or damaged.');
        THROW 50400, @msg, 1;
    END
    SELECT TOP 1 @bad = idx FROM @it
    WHERE return_status IS NULL OR return_status NOT IN (N'complete', N'partial', N'not_returned')
    ORDER BY idx;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'items.', @bad, N'.returnStatus|Return status must be complete, partial or not returned.');
        THROW 50400, @msg, 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [sep].[asset_clearance] (company_id, employee_id, end_of_employment_id, clearance_date, checked_by_id,
                                            approved_by_id, approval_date, file_id, status, created_by)
            VALUES (@company_id, @employee_id, @end_of_employment_id, @clearance_date, @checked_by_id,
                    @approved_by_id, @approval_date, @file_id, N'in_progress', @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [sep].[asset_clearance]
            SET end_of_employment_id = @end_of_employment_id, clearance_date = @clearance_date,
                checked_by_id = @checked_by_id, approved_by_id = @approved_by_id, approval_date = @approval_date,
                file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this clearance form. Reload it and try again', 1;
            DELETE [sep].[asset_clearance_item] WHERE asset_clearance_id = @id;
        END

        INSERT [sep].[asset_clearance_item] (asset_clearance_id, asset_allocation_id, condition_at_clearance, reason,
                                             return_status, comments, created_by)
        SELECT @id, asset_allocation_id, condition_at_clearance, reason, return_status, comments, @actor_user_id
        FROM @it ORDER BY idx;
    COMMIT;

    EXEC [sep].[usp_asset_clearance_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = @code;
END
GO

CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = c.row_version, @status = c.status
    FROM [sep].[asset_clearance] c
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.clearance.delete') v ON v.employee_id = c.employee_id
    WHERE c.id = @id AND c.company_id = @company_id;

    IF @rv IS NULL
        THROW 50404, N'Clearance form not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this clearance form. Reload it and try again', 1;
    IF @status <> N'in_progress'
        THROW 50409, N'status|CLEARANCE_APPROVED|This clearance form is approved. Unapprove it first.', 1;

    BEGIN TRAN;
        DELETE [sep].[asset_clearance_item] WHERE asset_clearance_id = @id;
        DELETE [sep].[asset_clearance] WHERE id = @id;
    COMMIT;
END
GO

-- Bulk Approve. @forms is a JSON array of {"id", "row_version"} (row_version as 16 hex characters).
-- All or nothing. Returns the forms as the list shows them.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_approve]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @forms         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSDATETIME() AS DATE);

    IF ISJSON(ISNULL(@forms, N'')) = 0
        THROW 50400, N'forms|Choose at least one clearance form.', 1;
    DECLARE @f TABLE (id BIGINT PRIMARY KEY, rv BINARY(8));
    INSERT @f SELECT DISTINCT x.id, CONVERT(BINARY(8), x.rv, 2)
    FROM OPENJSON(@forms) WITH (id BIGINT '$.id', rv NVARCHAR(16) '$.row_version') x;
    IF NOT EXISTS (SELECT 1 FROM @f)
        THROW 50400, N'forms|Choose at least one clearance form.', 1;

    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM @f f WHERE NOT EXISTS (
                SELECT 1 FROM [sep].[asset_clearance] c WITH (UPDLOCK, HOLDLOCK)
                JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.clearance.approve') v ON v.employee_id = c.employee_id
                WHERE c.id = f.id AND c.company_id = @company_id))
            THROW 50404, N'Clearance form not found', 1;
        IF EXISTS (SELECT 1 FROM @f f JOIN [sep].[asset_clearance] c ON c.id = f.id WHERE c.row_version <> f.rv OR f.rv IS NULL)
            THROW 50409, N'Someone else changed a clearance form. Reload and try again', 1;
        IF EXISTS (SELECT 1 FROM @f f JOIN [sep].[asset_clearance] c ON c.id = f.id WHERE c.status <> N'in_progress')
            THROW 50409, N'status|CLEARANCE_APPROVED|A chosen clearance form is already approved.', 1;
        IF EXISTS (SELECT 1 FROM @f f JOIN [sep].[asset_clearance] c ON c.id = f.id WHERE c.employee_id = @actor_employee_id)
            THROW 50403, N'You cannot approve your own clearance form.', 1;
        IF EXISTS (SELECT 1 FROM @f f
                   JOIN [sep].[asset_clearance_item] i ON i.asset_clearance_id = f.id
                   JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
                   WHERE al.deallocated_on IS NOT NULL)
            THROW 50409, N'An asset on a chosen form has already been deallocated. Edit the form first.', 1;

        -- Assets: history, then status (damaged when returned damaged, lost when not returned).
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'sep.asset', al.asset_id, N'holder', CONCAT(e.first_name, N' ', e.last_name, N' - ', e.code),
               i.return_status, N'clearance', @actor_user_id, @now
        FROM @f f
        JOIN [sep].[asset_clearance_item] i ON i.asset_clearance_id = f.id
        JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
        JOIN [hr].[employee] e ON e.id = al.employee_id;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'sep.asset', a.id, N'status', a.status,
               CASE WHEN i.return_status = N'not_returned' THEN N'lost' ELSE N'damaged' END, N'clearance', @actor_user_id, @now
        FROM @f f
        JOIN [sep].[asset_clearance_item] i ON i.asset_clearance_id = f.id
        JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
        JOIN [sep].[asset] a ON a.id = al.asset_id
        WHERE a.status = N'active' AND (i.return_status = N'not_returned' OR i.condition_at_clearance = N'damaged');

        UPDATE a
        SET status = CASE WHEN i.return_status = N'not_returned' THEN N'lost' ELSE N'damaged' END,
            updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[asset] a
        JOIN [sep].[asset_allocation] al ON al.asset_id = a.id
        JOIN [sep].[asset_clearance_item] i ON i.asset_allocation_id = al.id
        JOIN @f f ON f.id = i.asset_clearance_id
        WHERE a.status = N'active' AND (i.return_status = N'not_returned' OR i.condition_at_clearance = N'damaged');

        UPDATE al
        SET deallocated_on = c.clearance_date, status = N'deallocated', return_condition = i.condition_at_clearance,
            asset_clearance_id = c.id, updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[asset_allocation] al
        JOIN [sep].[asset_clearance_item] i ON i.asset_allocation_id = al.id
        JOIN [sep].[asset_clearance] c ON c.id = i.asset_clearance_id
        JOIN @f f ON f.id = c.id;

        UPDATE c
        SET status = N'approved', approval_date = ISNULL(c.approval_date, @today),
            approved_by_id = ISNULL(c.approved_by_id, @actor_employee_id), updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[asset_clearance] c JOIN @f f ON f.id = c.id;

        -- One assets.clearance_approved event per form, with the assets it closed.
        DECLARE @form BIGINT = (SELECT MIN(id) FROM @f), @payload NVARCHAR(MAX);
        WHILE @form IS NOT NULL
        BEGIN
            SET @payload = (
                SELECT CONVERT(NVARCHAR(30), c.id) AS clearanceId, CONVERT(NVARCHAR(30), c.employee_id) AS employeeId,
                       e.code AS employeeCode, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employeeName,
                       CONVERT(NVARCHAR(30), c.end_of_employment_id) AS endOfEmploymentId,
                       CONVERT(NVARCHAR(10), c.clearance_date, 23) AS clearanceDate,
                       CONVERT(NVARCHAR(10), c.approval_date, 23) AS approvalDate,
                       (SELECT CONVERT(NVARCHAR(30), al.id) AS allocationId, CONVERT(NVARCHAR(30), a.id) AS assetId,
                               a.code AS assetCode, a.name AS assetName, i.condition_at_clearance AS [condition],
                               i.return_status AS returnStatus
                        FROM [sep].[asset_clearance_item] i
                        JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
                        JOIN [sep].[asset] a ON a.id = al.asset_id
                        WHERE i.asset_clearance_id = c.id
                        ORDER BY i.id
                        FOR JSON PATH) AS items
                FROM [sep].[asset_clearance] c JOIN [hr].[employee] e ON e.id = c.employee_id
                WHERE c.id = @form
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'assets.clearance_approved',
                 @entity_type = N'sep.asset_clearance', @entity_id = @form, @payload = @payload;
            SET @form = (SELECT MIN(id) FROM @f WHERE id > @form);
        END

        -- The end of employment records these forms belong to may now be complete.
        DECLARE @eoe BIGINT;
        DECLARE eoe_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT c.end_of_employment_id FROM [sep].[asset_clearance] c JOIN @f f ON f.id = c.id
            WHERE c.end_of_employment_id IS NOT NULL;
        OPEN eoe_cur;
        FETCH NEXT FROM eoe_cur INTO @eoe;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [sep].[usp_end_of_employment_try_complete] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @eoe;
            FETCH NEXT FROM eoe_cur INTO @eoe;
        END
        CLOSE eoe_cur;
        DEALLOCATE eoe_cur;
    COMMIT;

    SELECT c.id, c.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.department_id, d.name AS department_name, c.end_of_employment_id, c.clearance_date, c.approval_date, c.status,
           (SELECT COUNT(*) FROM [sep].[asset_clearance_item] i WHERE i.asset_clearance_id = c.id) AS item_count,
           c.created_at, c.updated_at, c.row_version
    FROM [sep].[asset_clearance] c
    JOIN @f f ON f.id = c.id
    JOIN [hr].[employee] e ON e.id = c.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    ORDER BY c.id;
END
GO

-- Bulk Unapprove: the forms go back to in progress and the assets back to the leaver, unless an
-- asset has been given to someone else since or the end of employment has completed.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_clearance_unapprove]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @forms         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF ISJSON(ISNULL(@forms, N'')) = 0
        THROW 50400, N'forms|Choose at least one clearance form.', 1;
    DECLARE @f TABLE (id BIGINT PRIMARY KEY, rv BINARY(8));
    INSERT @f SELECT DISTINCT x.id, CONVERT(BINARY(8), x.rv, 2)
    FROM OPENJSON(@forms) WITH (id BIGINT '$.id', rv NVARCHAR(16) '$.row_version') x;
    IF NOT EXISTS (SELECT 1 FROM @f)
        THROW 50400, N'forms|Choose at least one clearance form.', 1;

    BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM @f f WHERE NOT EXISTS (
                SELECT 1 FROM [sep].[asset_clearance] c WITH (UPDLOCK, HOLDLOCK)
                JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.clearance.approve') v ON v.employee_id = c.employee_id
                WHERE c.id = f.id AND c.company_id = @company_id))
            THROW 50404, N'Clearance form not found', 1;
        IF EXISTS (SELECT 1 FROM @f f JOIN [sep].[asset_clearance] c ON c.id = f.id WHERE c.row_version <> f.rv OR f.rv IS NULL)
            THROW 50409, N'Someone else changed a clearance form. Reload and try again', 1;
        IF EXISTS (SELECT 1 FROM @f f JOIN [sep].[asset_clearance] c ON c.id = f.id WHERE c.status <> N'approved')
            THROW 50409, N'status|CLEARANCE_NOT_APPROVED|A chosen clearance form is not approved.', 1;
        IF EXISTS (SELECT 1 FROM @f f JOIN [sep].[asset_clearance] c ON c.id = f.id
                   JOIN [sep].[end_of_employment] x ON x.id = c.end_of_employment_id WHERE x.status = N'completed')
            THROW 50409, N'status|END_OF_EMPLOYMENT_COMPLETED|The end of employment for a chosen form is completed.', 1;
        IF EXISTS (SELECT 1 FROM @f f
                   JOIN [sep].[asset_allocation] al ON al.asset_clearance_id = f.id
                   WHERE EXISTS (SELECT 1 FROM [sep].[asset_allocation] o
                                 WHERE o.asset_id = al.asset_id AND o.id > al.id))  -- made after the allocation this form closed
            THROW 50409, N'An asset on a chosen form has been allocated again since.', 1;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'sep.asset', a.id, N'status', a.status, N'active', N'unapprove clearance', @actor_user_id, @now
        FROM @f f
        JOIN [sep].[asset_clearance_item] i ON i.asset_clearance_id = f.id
        JOIN [sep].[asset_allocation] al ON al.id = i.asset_allocation_id
        JOIN [sep].[asset] a ON a.id = al.asset_id
        WHERE a.status IN (N'damaged', N'lost') AND (i.return_status = N'not_returned' OR i.condition_at_clearance = N'damaged');

        UPDATE a SET status = N'active', updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[asset] a
        JOIN [sep].[asset_allocation] al ON al.asset_id = a.id
        JOIN [sep].[asset_clearance_item] i ON i.asset_allocation_id = al.id
        JOIN @f f ON f.id = i.asset_clearance_id
        WHERE a.status IN (N'damaged', N'lost') AND (i.return_status = N'not_returned' OR i.condition_at_clearance = N'damaged');

        UPDATE al
        SET deallocated_on = NULL, status = N'allocated', return_condition = NULL, asset_clearance_id = NULL,
            updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[asset_allocation] al JOIN @f f ON f.id = al.asset_clearance_id;

        UPDATE c SET status = N'in_progress', updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[asset_clearance] c JOIN @f f ON f.id = c.id;
    COMMIT;

    SELECT c.id, c.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.department_id, d.name AS department_name, c.end_of_employment_id, c.clearance_date, c.approval_date, c.status,
           (SELECT COUNT(*) FROM [sep].[asset_clearance_item] i WHERE i.asset_clearance_id = c.id) AS item_count,
           c.created_at, c.updated_at, c.row_version
    FROM [sep].[asset_clearance] c
    JOIN @f f ON f.id = c.id
    JOIN [hr].[employee] e ON e.id = c.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    ORDER BY c.id;
END
