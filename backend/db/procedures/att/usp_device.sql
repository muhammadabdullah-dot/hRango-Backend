-- Biometric devices (Settings -> Biometric devices) and the employees enrolled on each.

CREATE OR ALTER PROCEDURE [att].[usp_device_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [att].[device] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Device not found', 1;

    SELECT d.id, d.code, d.name, d.model, d.serial_no, d.ip_address, d.port, d.branch_id, b.name AS branch_name,
           d.address, d.status, d.last_synced_at,
           (SELECT COUNT(*) FROM [att].[device_enrolment] x WHERE x.device_id = d.id) AS enrolled_count,
           d.created_at, d.updated_at, d.row_version
    FROM [att].[device] d
    LEFT JOIN [org].[branch] b ON b.id = d.branch_id
    WHERE d.id = @id AND d.company_id = @company_id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_device_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @branch_id  BIGINT = NULL,
    @status     NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [att].[device] d
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.name LIKE @pattern OR d.code LIKE @pattern OR d.serial_no LIKE @pattern)
      AND (@branch_id IS NULL OR d.branch_id = @branch_id)
      AND (@status IS NULL OR d.status = @status)
    OPTION (RECOMPILE);

    SELECT d.id, d.code, d.name, d.model, d.serial_no, d.ip_address, d.port, d.branch_id, b.name AS branch_name,
           d.address, d.status, d.last_synced_at,
           (SELECT COUNT(*) FROM [att].[device_enrolment] x WHERE x.device_id = d.id) AS enrolled_count,
           d.created_at, d.updated_at, d.row_version
    FROM [att].[device] d
    LEFT JOIN [org].[branch] b ON b.id = d.branch_id
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.name LIKE @pattern OR d.code LIKE @pattern OR d.serial_no LIKE @pattern)
      AND (@branch_id IS NULL OR d.branch_id = @branch_id)
      AND (@status IS NULL OR d.status = @status)
    ORDER BY d.code, d.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_device_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @model         NVARCHAR(100) = NULL,
    @serial_no     NVARCHAR(50) = NULL,
    @ip_address    NVARCHAR(45) = NULL,
    @port          INT = NULL,
    @branch_id     BIGINT = NULL,
    @address       NVARCHAR(500) = NULL,
    @status        NVARCHAR(30) = N'active',
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @serial_no = NULLIF(LTRIM(RTRIM(@serial_no)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Device name is required.', 1;
    IF @status NOT IN (N'active', N'inactive')
        THROW 50400, N'status|Status must be active or inactive.', 1;
    IF @branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Branch not found.', 1;
    IF EXISTS (SELECT 1 FROM [att].[device] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|DEVICE_DUPLICATE|A device with this name already exists.', 1;
    IF @serial_no IS NOT NULL AND EXISTS (SELECT 1 FROM [att].[device] WHERE company_id = @company_id AND serial_no = @serial_no AND (@id IS NULL OR id <> @id))
        THROW 50409, N'serialNo|DEVICE_SERIAL_DUPLICATE|A device with this serial number already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            EXEC [att].[usp_code_next] @company_id = @company_id, @prefix = N'MCH-', @code = @code OUTPUT;
            INSERT [att].[device] (company_id, code, name, model, serial_no, ip_address, port, branch_id, address, status, created_by)
            VALUES (@company_id, @code, @name, @model, @serial_no, @ip_address, @port, @branch_id, @address, @status, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'att.device', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a device.', 1;

        DECLARE @old TABLE (name NVARCHAR(200), model NVARCHAR(100), serial_no NVARCHAR(50), ip_address NVARCHAR(45),
                            port INT, branch_id BIGINT, address NVARCHAR(500), status NVARCHAR(30), rv BINARY(8));
        INSERT @old SELECT name, model, serial_no, ip_address, port, branch_id, address, status, row_version
        FROM [att].[device] WHERE id = @id AND company_id = @company_id;

        IF NOT EXISTS (SELECT 1 FROM @old)
            THROW 50404, N'Device not found', 1;
        IF (SELECT rv FROM @old) <> @row_version
            THROW 50409, N'Someone else changed this device. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [att].[device]
            SET name = @name, model = @model, serial_no = @serial_no, ip_address = @ip_address, port = @port,
                branch_id = @branch_id, address = @address, status = @status, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this device. Reload it and try again', 1;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'att.device', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM @old o
            CROSS APPLY (VALUES
                (N'name', o.name, @name), (N'model', o.model, @model), (N'serial_no', o.serial_no, @serial_no),
                (N'ip_address', o.ip_address, @ip_address), (N'port', CONVERT(NVARCHAR(30), o.port), CONVERT(NVARCHAR(30), @port)),
                (N'branch_id', CONVERT(NVARCHAR(30), o.branch_id), CONVERT(NVARCHAR(30), @branch_id)),
                (N'address', o.address, @address), (N'status', o.status, @status)
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [att].[usp_device_get] @company_id = @company_id, @id = @id;
END
GO

-- A device with punches cannot be deleted (set it inactive instead); its enrolments go with it.
CREATE OR ALTER PROCEDURE [att].[usp_device_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [att].[device] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Device not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this device. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [att].[punch] WHERE device_id = @id)
        THROW 50409, N'id|DEVICE_IN_USE|Punches came from this device. Set it inactive instead', 1;

    BEGIN TRAN;
        DELETE [att].[device_enrolment] WHERE device_id = @id;
        DELETE [att].[device] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'att.device', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_device_enrolment_list]
    @company_id BIGINT,
    @device_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [att].[device] WHERE id = @device_id AND company_id = @company_id)
        THROW 50404, N'Device not found', 1;

    SELECT x.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           x.device_user_no, x.created_at
    FROM [att].[device_enrolment] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    WHERE x.device_id = @device_id
    ORDER BY e.code;
END
GO

-- Replaces the device's enrolment list: @enrolments = [{"employeeId": 1, "deviceUserNo": "1001"}, ...].
-- The device's rowVersion guards against two people editing the list at once.
CREATE OR ALTER PROCEDURE [att].[usp_device_enrolment_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @device_id     BIGINT,
    @enrolments    NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [att].[device] WHERE id = @device_id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Device not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this device. Reload it and try again', 1;
    IF @enrolments IS NULL OR ISJSON(@enrolments) = 0
        THROW 50400, N'enrolments|Enrolments are not valid.', 1;

    DECLARE @rows TABLE (employee_id BIGINT, device_user_no NVARCHAR(30));
    INSERT @rows (employee_id, device_user_no)
    SELECT employee_id, LTRIM(RTRIM(device_user_no))
    FROM OPENJSON(@enrolments) WITH (employee_id BIGINT '$.employeeId', device_user_no NVARCHAR(30) '$.deviceUserNo');

    IF EXISTS (SELECT 1 FROM @rows WHERE employee_id IS NULL OR NULLIF(device_user_no, N'') IS NULL)
        THROW 50400, N'enrolments|Each enrolment needs an employee and a device user number.', 1;
    IF EXISTS (SELECT 1 FROM @rows r WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] e WHERE e.id = r.employee_id AND e.company_id = @company_id))
        THROW 50400, N'enrolments|Employee not found.', 1;
    IF EXISTS (SELECT employee_id FROM @rows GROUP BY employee_id HAVING COUNT(*) > 1)
        THROW 50400, N'enrolments|An employee is listed twice.', 1;
    IF EXISTS (SELECT device_user_no FROM @rows GROUP BY device_user_no HAVING COUNT(*) > 1)
        THROW 50409, N'enrolments|ENROLMENT_DUPLICATE|Two employees have the same device user number.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        UPDATE [att].[device] SET updated_at = @now, updated_by = @actor_user_id
        WHERE id = @device_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this device. Reload it and try again', 1;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'att.device', @device_id, N'enrolment', CONVERT(NVARCHAR(30), ISNULL(o.employee_id, n.employee_id)) + N':' + ISNULL(o.device_user_no, N''),
               CONVERT(NVARCHAR(30), ISNULL(n.employee_id, o.employee_id)) + N':' + ISNULL(n.device_user_no, N''),
               CASE WHEN o.employee_id IS NULL THEN N'enroll' WHEN n.employee_id IS NULL THEN N'unenroll' ELSE N'update' END,
               @actor_user_id, @now
        FROM (SELECT employee_id, device_user_no FROM [att].[device_enrolment] WHERE device_id = @device_id) o
        FULL JOIN @rows n ON n.employee_id = o.employee_id
        WHERE o.employee_id IS NULL OR n.employee_id IS NULL OR o.device_user_no <> n.device_user_no;

        DELETE x FROM [att].[device_enrolment] x
        WHERE x.device_id = @device_id
          AND NOT EXISTS (SELECT 1 FROM @rows r WHERE r.employee_id = x.employee_id AND r.device_user_no = x.device_user_no);

        INSERT [att].[device_enrolment] (device_id, employee_id, device_user_no, created_by)
        SELECT @device_id, r.employee_id, r.device_user_no, @actor_user_id
        FROM @rows r
        WHERE NOT EXISTS (SELECT 1 FROM [att].[device_enrolment] x WHERE x.device_id = @device_id AND x.employee_id = r.employee_id);
    COMMIT;

    EXEC [att].[usp_device_get] @company_id = @company_id, @id = @device_id;
END
