-- Assets -> Asset Allocations. One row per hand-over; deallocated_on is NULL while the employee
-- holds the asset. Rows are employee-owned: lists and reads go through auth.fn_visible_employees.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_allocation_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @search        NVARCHAR(200) = NULL,
    @employee_id   BIGINT = NULL,
    @asset_type_id BIGINT = NULL,
    @asset_id      BIGINT = NULL,
    @status        NVARCHAR(30) = NULL,
    @from_date     DATE = NULL,
    @to_date       DATE = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sep].[asset_allocation] al
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.allocations.view') v ON v.employee_id = al.employee_id
    JOIN [sep].[asset] a ON a.id = al.asset_id
    JOIN [hr].[employee] e ON e.id = al.employee_id
    WHERE al.company_id = @company_id
      AND (@pattern IS NULL OR a.name LIKE @pattern OR a.code LIKE @pattern OR a.identification_no LIKE @pattern
           OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@employee_id IS NULL OR al.employee_id = @employee_id)
      AND (@asset_type_id IS NULL OR a.asset_type_id = @asset_type_id)
      AND (@asset_id IS NULL OR al.asset_id = @asset_id)
      AND (@status IS NULL OR al.status = @status)
      AND (@from_date IS NULL OR al.allocated_on >= @from_date)
      AND (@to_date IS NULL OR al.allocated_on <= @to_date)
    OPTION (RECOMPILE);

    SELECT al.id, al.employee_id, e.code AS employee_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, c.name AS company_name,
           al.asset_id, a.code AS asset_code, a.name AS asset_name, a.identification_no, a.asset_type_id,
           t.name AS asset_type_name, al.allocated_on, al.deallocated_on, al.status, al.description,
           al.return_condition, al.deallocation_remarks, al.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = al.file_id) AS file_name,
           al.asset_clearance_id,
           al.created_at, al.updated_at, al.row_version
    FROM [sep].[asset_allocation] al
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.allocations.view') v ON v.employee_id = al.employee_id
    JOIN [sep].[asset] a ON a.id = al.asset_id
    JOIN [sep].[asset_type] t ON t.id = a.asset_type_id
    JOIN [hr].[employee] e ON e.id = al.employee_id
    JOIN [org].[company] c ON c.id = al.company_id
    WHERE al.company_id = @company_id
      AND (@pattern IS NULL OR a.name LIKE @pattern OR a.code LIKE @pattern OR a.identification_no LIKE @pattern
           OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@employee_id IS NULL OR al.employee_id = @employee_id)
      AND (@asset_type_id IS NULL OR a.asset_type_id = @asset_type_id)
      AND (@asset_id IS NULL OR al.asset_id = @asset_id)
      AND (@status IS NULL OR al.status = @status)
      AND (@from_date IS NULL OR al.allocated_on >= @from_date)
      AND (@to_date IS NULL OR al.allocated_on <= @to_date)
    ORDER BY al.allocated_on DESC, al.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One allocation, if the caller may see the employee through @permission_code.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_allocation_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @permission_code NVARCHAR(150) = N'assets.allocations.view'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[asset_allocation] al
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = al.employee_id
                   WHERE al.id = @id AND al.company_id = @company_id)
        THROW 50404, N'Allocation not found', 1;

    SELECT al.id, al.employee_id, e.code AS employee_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, c.name AS company_name,
           al.asset_id, a.code AS asset_code, a.name AS asset_name, a.identification_no, a.asset_type_id,
           t.name AS asset_type_name, al.allocated_on, al.deallocated_on, al.status, al.description,
           al.return_condition, al.deallocation_remarks, al.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = al.file_id) AS file_name,
           al.asset_clearance_id,
           al.created_at, al.updated_at, al.row_version
    FROM [sep].[asset_allocation] al
    JOIN [sep].[asset] a ON a.id = al.asset_id
    JOIN [sep].[asset_type] t ON t.id = a.asset_type_id
    JOIN [hr].[employee] e ON e.id = al.employee_id
    JOIN [org].[company] c ON c.id = al.company_id
    WHERE al.id = @id AND al.company_id = @company_id;
END
GO

-- Allocate: hands an active asset that nobody holds to an employee who has not left. Publishes
-- assets.allocated and tells the employee.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_allocation_allocate]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @asset_id      BIGINT,
    @employee_id   BIGINT,
    @allocated_on  DATE,
    @description   NVARCHAR(MAX) = NULL,
    @file_id       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @allocated_on IS NULL
        THROW 50400, N'allocatedOn|Allocation date is required.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    DECLARE @emp_status NVARCHAR(30) = (
        SELECT e.status FROM [hr].[employee] e
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.allocations.assign') v ON v.employee_id = e.id
        WHERE e.id = @employee_id AND e.company_id = @company_id);
    IF @emp_status IS NULL
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @emp_status = N'left'
        THROW 50400, N'employeeId|This employee has left.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @id BIGINT, @status NVARCHAR(30), @acquired DATE,
            @holder NVARCHAR(400), @last_end DATE, @emp_name NVARCHAR(400);

    BEGIN TRAN;
        -- Lock the asset so two people cannot allocate it at the same moment.
        SELECT @status = status, @acquired = acquired_date
        FROM [sep].[asset] WITH (UPDLOCK, HOLDLOCK)
        WHERE id = @asset_id AND company_id = @company_id;
        IF @status IS NULL
            THROW 50400, N'assetId|Asset not found.', 1;

        SELECT TOP 1 @holder = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ')
        FROM [sep].[asset_allocation] al JOIN [hr].[employee] e ON e.id = al.employee_id
        WHERE al.asset_id = @asset_id AND al.deallocated_on IS NULL;
        IF @@ROWCOUNT > 0
        BEGIN
            DECLARE @msg NVARCHAR(2048) = N'assetId|ASSET_ALLOCATED|This asset is already allocated to ' + ISNULL(@holder, N'someone') + N'.';
            THROW 50409, @msg, 1;
        END
        IF @status <> N'active'
            THROW 50409, N'assetId|ASSET_UNAVAILABLE|This asset is not active and cannot be allocated.', 1;
        IF @acquired IS NOT NULL AND @allocated_on < @acquired
            THROW 50400, N'allocatedOn|The allocation date is before the asset was acquired.', 1;
        SET @last_end = (SELECT MAX(deallocated_on) FROM [sep].[asset_allocation] WHERE asset_id = @asset_id);
        IF @last_end IS NOT NULL AND @allocated_on < @last_end
            THROW 50400, N'allocatedOn|The asset was still with someone else on that date.', 1;

        INSERT [sep].[asset_allocation] (company_id, asset_id, employee_id, allocated_on, status, description, file_id, created_by)
        VALUES (@company_id, @asset_id, @employee_id, @allocated_on, N'allocated', @description, @file_id, @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        SELECT @emp_name = CONCAT(first_name, N' ', last_name, N' - ', code) FROM [hr].[employee] WHERE id = @employee_id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.asset', @asset_id, N'holder', NULL, @emp_name, N'allocate', @actor_user_id, @now);

        EXEC [sep].[usp_asset_allocation_announce] @company_id = @company_id, @id = @id, @event_type = N'assets.allocated';
    COMMIT;

    EXEC [sep].[usp_asset_allocation_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'assets.allocations.assign';
END
GO

-- Deallocate: the employee gives the asset back on a date, in a condition. A damaged return marks
-- the asset damaged. Publishes assets.returned and tells the employee.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_allocation_deallocate]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @id               BIGINT,
    @deallocated_on   DATE,
    @return_condition NVARCHAR(30) = NULL,
    @remarks          NVARCHAR(500) = NULL,
    @row_version      BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @asset_id BIGINT, @allocated_on DATE, @closed DATE, @employee_id BIGINT;
    SELECT @rv = al.row_version, @asset_id = al.asset_id, @allocated_on = al.allocated_on,
           @closed = al.deallocated_on, @employee_id = al.employee_id
    FROM [sep].[asset_allocation] al
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'assets.allocations.assign') v ON v.employee_id = al.employee_id
    WHERE al.id = @id AND al.company_id = @company_id;

    IF @rv IS NULL
        THROW 50404, N'Allocation not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this allocation. Reload it and try again', 1;
    IF @closed IS NOT NULL
        THROW 50409, N'deallocatedOn|ALLOCATION_CLOSED|This asset has already been deallocated.', 1;
    IF @deallocated_on IS NULL
        THROW 50400, N'deallocatedOn|Deallocation date is required.', 1;
    IF @deallocated_on < @allocated_on
        THROW 50400, N'deallocatedOn|The deallocation date is before the allocation date.', 1;
    IF @return_condition IS NOT NULL AND @return_condition NOT IN (N'good', N'fair', N'damaged')
        THROW 50400, N'returnCondition|Condition must be good, fair or damaged.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @emp_name NVARCHAR(400);
    SELECT @emp_name = CONCAT(first_name, N' ', last_name, N' - ', code) FROM [hr].[employee] WHERE id = @employee_id;

    BEGIN TRAN;
        UPDATE [sep].[asset_allocation]
        SET deallocated_on = @deallocated_on, status = N'deallocated', return_condition = @return_condition,
            deallocation_remarks = @remarks, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this allocation. Reload it and try again', 1;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.asset', @asset_id, N'holder', @emp_name, NULL, N'deallocate', @actor_user_id, @now);

        IF @return_condition = N'damaged'
        BEGIN
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'sep.asset', id, N'status', status, N'damaged', N'deallocate', @actor_user_id, @now
            FROM [sep].[asset] WHERE id = @asset_id AND status = N'active';
            UPDATE [sep].[asset] SET status = N'damaged', updated_at = @now, updated_by = @actor_user_id
            WHERE id = @asset_id AND status = N'active';
        END

        EXEC [sep].[usp_asset_allocation_announce] @company_id = @company_id, @id = @id, @event_type = N'assets.returned';
    COMMIT;

    EXEC [sep].[usp_asset_allocation_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'assets.allocations.assign';
END
GO

-- Publishes assets.allocated / assets.returned for one allocation and notifies the employee. Called
-- inside the caller's transaction; returns no result set.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_allocation_announce]
    @company_id BIGINT,
    @id         BIGINT,
    @event_type NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @asset_name NVARCHAR(400), @payload NVARCHAR(MAX);
    SELECT @employee_id = al.employee_id, @asset_name = CONCAT(a.name, N' (', a.code, N')'),
           @payload = (SELECT CONVERT(NVARCHAR(30), al.id) AS allocationId, CONVERT(NVARCHAR(30), al.asset_id) AS assetId,
                              a.code AS assetCode, a.name AS assetName, a.identification_no AS identificationNo,
                              CONVERT(NVARCHAR(30), al.employee_id) AS employeeId, e.code AS employeeCode,
                              NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employeeName,
                              CONVERT(NVARCHAR(10), al.allocated_on, 23) AS allocatedOn,
                              CONVERT(NVARCHAR(10), al.deallocated_on, 23) AS deallocatedOn,
                              al.return_condition AS returnCondition,
                              CONVERT(NVARCHAR(30), al.asset_clearance_id) AS assetClearanceId
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM [sep].[asset_allocation] al
    JOIN [sep].[asset] a ON a.id = al.asset_id
    JOIN [hr].[employee] e ON e.id = al.employee_id
    WHERE al.id = @id AND al.company_id = @company_id;
    IF @employee_id IS NULL
        RETURN;

    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event_type,
         @entity_type = N'sep.asset_allocation', @entity_id = @id, @payload = @payload;

    DECLARE @title NVARCHAR(200) = LEFT(CASE @event_type WHEN N'assets.allocated' THEN N'An asset was handed to you: '
                                                         ELSE N'Asset return recorded: ' END + @asset_name, 200);
    EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
         @title = @title, @notification_type = N'asset', @link = N'/assets/allocations',
         @entity_type = N'sep.asset_allocation', @entity_id = @id;
END
