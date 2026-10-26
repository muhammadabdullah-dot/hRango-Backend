-- Punches: the Attendance Log list, manual entries, imports from devices and files, ignoring device punches.
-- Every write re-processes the employee's days around the punch (att.usp_timesheet_process).

CREATE OR ALTER PROCEDURE [att].[usp_punch_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @permission_code NVARCHAR(150) = NULL,
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM [att].[punch] p
        WHERE p.id = @id AND p.company_id = @company_id
          AND (@permission_code IS NULL OR p.employee_id IN (
                SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code))))
        THROW 50404, N'Punch not found', 1;

    SELECT p.id, p.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           p.punched_at, p.punch_type, p.break_type_id, bt.name AS break_type_name, p.source,
           p.device_id, dv.code AS device_code, dv.name AS device_name, p.latitude, p.longitude, p.ip_address,
           p.photo_file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = p.photo_file_id) AS photo_file_name,
           p.request_id, p.remarks, p.is_manually_updated, p.is_ignored,
           p.created_at, p.updated_at, p.row_version
    FROM [att].[punch] p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    LEFT JOIN [sch].[break_type] bt ON bt.id = p.break_type_id
    LEFT JOIN [att].[device] dv ON dv.id = p.device_id
    WHERE p.id = @id AND p.company_id = @company_id;
END
GO

-- Attendance Log list. Result set 1: total; result set 2: the page.
CREATE OR ALTER PROCEDURE [att].[usp_punch_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @from_date       DATE,
    @to_date         DATE,
    @employee_id     BIGINT = NULL,
    @punch_type      NVARCHAR(30) = NULL,
    @source          NVARCHAR(30) = NULL,
    @device_id       BIGINT = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @from DATETIME2(0) = @from_date, @to DATETIME2(0) = DATEADD(DAY, 1, CAST(@to_date AS DATETIME2(0)));

    SELECT COUNT(*) AS total
    FROM [att].[punch] p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE p.company_id = @company_id AND p.punched_at >= @from AND p.punched_at < @to
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@punch_type IS NULL OR p.punch_type = @punch_type)
      AND (@source IS NULL OR p.source = @source)
      AND (@device_id IS NULL OR p.device_id = @device_id)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT p.id, p.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           p.punched_at, p.punch_type, p.break_type_id, bt.name AS break_type_name, p.source,
           p.device_id, dv.code AS device_code, dv.name AS device_name, p.latitude, p.longitude, p.ip_address,
           p.photo_file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = p.photo_file_id) AS photo_file_name,
           p.request_id, p.remarks, p.is_manually_updated, p.is_ignored,
           p.created_at, p.updated_at, p.row_version
    FROM [att].[punch] p
    JOIN [hr].[employee] e ON e.id = p.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    LEFT JOIN [sch].[break_type] bt ON bt.id = p.break_type_id
    LEFT JOIN [att].[device] dv ON dv.id = p.device_id
    WHERE p.company_id = @company_id AND p.punched_at >= @from AND p.punched_at < @to
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@punch_type IS NULL OR p.punch_type = @punch_type)
      AND (@source IS NULL OR p.source = @source)
      AND (@device_id IS NULL OR p.device_id = @device_id)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    ORDER BY p.punched_at DESC, p.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Re-processes one employee's days around one or two punch times (a punch can belong to the day before
-- or after its calendar date with overnight shifts).
CREATE OR ALTER PROCEDURE [att].[usp_punch_reprocess]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @employee_id   BIGINT,
    @at_1          DATETIME2(0),
    @at_2          DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @lo DATE = CAST(CASE WHEN @at_2 < @at_1 THEN @at_2 ELSE @at_1 END AS DATE);
    DECLARE @hi DATE = CAST(CASE WHEN @at_2 > @at_1 THEN @at_2 ELSE @at_1 END AS DATE);
    DECLARE @ids NVARCHAR(50) = N'[' + CONVERT(NVARCHAR(30), @employee_id) + N']';
    DECLARE @from DATE = DATEADD(DAY, -1, @lo), @to DATE = DATEADD(DAY, 1, @hi);
    IF DATEDIFF(DAY, @from, @to) > 366
    BEGIN
        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @at_1, NULL;
        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @at_2, NULL;
        RETURN;
    END
    EXEC [att].[usp_timesheet_process] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @from_date = @from, @to_date = @to, @employee_ids = @ids, @quiet = 1;
END
GO


-- Adds a manual punch (@id NULL) or edits a manual or imported one. Device, dashboard and request punches
-- cannot be edited; they can be ignored (usp_punch_ignore).
CREATE OR ALTER PROCEDURE [att].[usp_punch_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @punched_at      DATETIME2(0),
    @punch_type      NVARCHAR(30),
    @break_type_id   BIGINT = NULL,
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @employee_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @punched_at IS NULL
        THROW 50400, N'punchedAt|Punch time is required.', 1;
    IF @punched_at > DATEADD(MINUTE, 5, [att].[fn_company_now](@company_id))
        THROW 50400, N'punchedAt|A punch cannot be in the future.', 1;
    IF @punch_type NOT IN (N'check_in', N'check_out', N'break_out', N'break_in')
        THROW 50400, N'punchType|Punch type must be check in, check out, break out or break in.', 1;
    IF @break_type_id IS NOT NULL AND @punch_type NOT IN (N'break_out', N'break_in')
        THROW 50400, N'breakTypeId|A break type goes with a break out or break in punch.', 1;
    IF @break_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [sch].[break_type] WHERE id = @break_type_id AND company_id = @company_id)
        THROW 50400, N'breakTypeId|Break type not found.', 1;
    IF EXISTS (SELECT 1 FROM [att].[punch] WHERE employee_id = @employee_id AND punched_at = @punched_at
               AND punch_type = @punch_type AND (@id IS NULL OR id <> @id))
        THROW 50409, N'punchedAt|PUNCH_DUPLICATE|This employee already has this punch at this time.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @old_at DATETIME2(0), @old_type NVARCHAR(30), @old_emp BIGINT, @old_break BIGINT, @old_remarks NVARCHAR(MAX),
            @old_source NVARCHAR(30), @old_rv BINARY(8);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [att].[punch] (company_id, employee_id, punched_at, punch_type, break_type_id, source, remarks, created_by)
            VALUES (@company_id, @employee_id, @punched_at, @punch_type, @break_type_id, N'manual', @remarks, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'att.punch', @id, N'create', @actor_user_id, @now);
        COMMIT;
        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @punched_at;
    END
    ELSE
    BEGIN
        SELECT @old_at = punched_at, @old_type = punch_type, @old_emp = employee_id, @old_break = break_type_id,
               @old_remarks = remarks, @old_source = source, @old_rv = row_version
        FROM [att].[punch] p
        WHERE p.id = @id AND p.company_id = @company_id
          AND p.employee_id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code));

        IF @old_rv IS NULL
            THROW 50404, N'Punch not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a punch.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this punch. Reload it and try again', 1;
        IF @old_source NOT IN (N'manual', N'import_file')
            THROW 50409, N'source|PUNCH_READ_ONLY|Only manual and imported punches can be edited. Ignore this punch instead.', 1;
        IF @old_emp <> @employee_id
            THROW 50400, N'employeeId|A punch cannot be moved to another employee.', 1;

        BEGIN TRAN;
            UPDATE [att].[punch]
            SET punched_at = @punched_at, punch_type = @punch_type, break_type_id = @break_type_id, remarks = @remarks,
                is_manually_updated = 1, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this punch. Reload it and try again', 1;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'att.punch', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'punched_at', CONVERT(NVARCHAR(30), @old_at, 126), CONVERT(NVARCHAR(30), @punched_at, 126)),
                (N'punch_type', @old_type, @punch_type),
                (N'break_type_id', CONVERT(NVARCHAR(30), @old_break), CONVERT(NVARCHAR(30), @break_type_id)),
                (N'remarks', @old_remarks, @remarks)
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @employee_id, @old_at, @punched_at;
    END

    EXEC [att].[usp_punch_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a manual or imported punch.
CREATE OR ALTER PROCEDURE [att].[usp_punch_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @source NVARCHAR(30), @emp BIGINT, @at DATETIME2(0);
    SELECT @rv = row_version, @source = source, @emp = employee_id, @at = punched_at
    FROM [att].[punch] p
    WHERE p.id = @id AND p.company_id = @company_id
      AND p.employee_id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code));

    IF @rv IS NULL
        THROW 50404, N'Punch not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this punch. Reload it and try again', 1;
    IF @source NOT IN (N'manual', N'import_file')
        THROW 50409, N'source|PUNCH_READ_ONLY|Only manual and imported punches can be deleted. Ignore this punch instead.', 1;

    BEGIN TRAN;
        DELETE [att].[punch] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'att.punch', @id, N'punched_at', CONVERT(NVARCHAR(30), @at, 126), N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
    EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @emp, @at;
END
GO

-- Leaves a punch out of the time sheet (or takes it back in). Works for every source.
CREATE OR ALTER PROCEDURE [att].[usp_punch_ignore]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @is_ignored      BIT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @old BIT, @emp BIGINT, @at DATETIME2(0);
    SELECT @rv = row_version, @old = is_ignored, @emp = employee_id, @at = punched_at
    FROM [att].[punch] p
    WHERE p.id = @id AND p.company_id = @company_id
      AND p.employee_id IN (SELECT employee_id FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code));

    IF @rv IS NULL
        THROW 50404, N'Punch not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this punch. Reload it and try again', 1;

    IF @old <> @is_ignored
    BEGIN
        BEGIN TRAN;
            UPDATE [att].[punch] SET is_ignored = @is_ignored, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
            WHERE id = @id;
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'att.punch', @id, N'is_ignored', CONVERT(NVARCHAR(1), @old), CONVERT(NVARCHAR(1), @is_ignored), N'update',
                    @actor_user_id, SYSUTCDATETIME());
        COMMIT;
        EXEC [att].[usp_punch_reprocess] @company_id, @actor_user_id, @emp, @at;
    END

    EXEC [att].[usp_punch_get] @company_id = @company_id, @id = @id;
END
GO

-- Imports punches. From a device (@device_id): lines name the employee by "deviceUserNo" (its enrolment on
-- that device) and the punches are source biometric. From a file (@device_id NULL): lines name the employee
-- by "employeeCode" and the punches are source import_file.
--   @lines = [{"line": 1, "employeeCode": "E-001" | "deviceUserNo": "1001", "punchedAt": "2026-01-05T09:01:00",
--              "punchType": "check_in" | a break identifier}]
-- A line already imported (same employee, time and type) is skipped. Result set 1: counts; 2: the bad lines.
CREATE OR ALTER PROCEDURE [att].[usp_punch_import]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @device_id       BIGINT = NULL,
    @lines           NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @device_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [att].[device] WHERE id = @device_id AND company_id = @company_id)
        THROW 50404, N'Device not found', 1;
    IF @device_id IS NOT NULL AND EXISTS (SELECT 1 FROM [att].[device] WHERE id = @device_id AND status <> N'active')
        THROW 50409, N'deviceId|DEVICE_INACTIVE|This device is inactive.', 1;
    IF @lines IS NULL OR ISJSON(@lines) = 0
        THROW 50400, N'lines|The lines are not valid.', 1;

    DECLARE @ignore_type BIT = CASE WHEN [att].[fn_setting](@company_id, N'attendance', N'ignore_punch_type') IN (N'true', N'1') THEN 1 ELSE 0 END;
    DECLARE @source NVARCHAR(30) = CASE WHEN @device_id IS NULL THEN N'import_file' ELSE N'biometric' END;

    CREATE TABLE #imp (line INT NOT NULL, employee_code NVARCHAR(30) NULL, device_user_no NVARCHAR(30) NULL,
                       at_text NVARCHAR(40) NULL, type_text NVARCHAR(100) NULL, employee_id BIGINT NULL,
                       punched_at DATETIME2(0) NULL, punch_type NVARCHAR(30) NULL, break_type_id BIGINT NULL,
                       error NVARCHAR(400) NULL, dup BIT NOT NULL DEFAULT 0);

    INSERT #imp (line, employee_code, device_user_no, at_text, type_text)
    SELECT ISNULL(j.line, CONVERT(INT, k.[key]) + 1), LTRIM(RTRIM(j.employee_code)), LTRIM(RTRIM(j.device_user_no)),
           j.at_text, NULLIF(LTRIM(RTRIM(j.type_text)), N'')
    FROM OPENJSON(@lines) k
    CROSS APPLY OPENJSON(k.[value]) WITH (line INT '$.line', employee_code NVARCHAR(30) '$.employeeCode',
        device_user_no NVARCHAR(30) '$.deviceUserNo', at_text NVARCHAR(40) '$.punchedAt', type_text NVARCHAR(100) '$.punchType') j;

    UPDATE i SET employee_id = x.employee_id
    FROM #imp i
    JOIN [att].[device_enrolment] x ON x.device_id = @device_id AND x.device_user_no = i.device_user_no
    WHERE @device_id IS NOT NULL;

    UPDATE i SET employee_id = e.id
    FROM #imp i
    JOIN [hr].[employee] e ON e.company_id = @company_id AND e.code = i.employee_code
    WHERE i.employee_id IS NULL AND i.employee_code IS NOT NULL;

    UPDATE i SET employee_id = NULL
    FROM #imp i
    WHERE i.employee_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = i.employee_id);

    UPDATE #imp SET punched_at = TRY_CONVERT(DATETIME2(0), at_text, 126);
    UPDATE #imp SET punched_at = TRY_CONVERT(DATETIME2(0), at_text, 120) WHERE punched_at IS NULL;

    UPDATE i SET punch_type = t.punch_type, break_type_id = t.break_type_id
    FROM #imp i
    CROSS APPLY [att].[fn_punch_type_parse](@company_id, i.type_text) t
    WHERE i.type_text IS NOT NULL;
    UPDATE #imp SET punch_type = N'check_in' WHERE type_text IS NULL AND @ignore_type = 1;

    UPDATE #imp
    SET error = CASE
        WHEN employee_id IS NULL AND @device_id IS NOT NULL AND employee_code IS NULL
             THEN N'Device user number ' + ISNULL(device_user_no, N'(blank)') + N' is not enrolled on this device.'
        WHEN employee_id IS NULL THEN N'Employee ' + ISNULL(employee_code, ISNULL(device_user_no, N'(blank)')) + N' not found.'
        WHEN punched_at IS NULL THEN N'Punch time ' + ISNULL(at_text, N'(blank)') + N' is not a date and time (yyyy-mm-ddThh:mm:ss).'
        WHEN punch_type IS NULL THEN N'Punch type ' + ISNULL(type_text, N'(blank)') + N' is not known.'
        END;

    -- Already stored, or repeated in this import.
    UPDATE i SET dup = 1
    FROM #imp i
    WHERE i.error IS NULL AND EXISTS (SELECT 1 FROM [att].[punch] p
                                      WHERE p.employee_id = i.employee_id AND p.punched_at = i.punched_at AND p.punch_type = i.punch_type);
    ;WITH r AS (SELECT dup, ROW_NUMBER() OVER (PARTITION BY employee_id, punched_at, punch_type ORDER BY line) AS rn
                FROM #imp WHERE error IS NULL AND dup = 0)
    UPDATE r SET dup = 1 WHERE rn > 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        INSERT [att].[punch] (company_id, employee_id, punched_at, punch_type, break_type_id, source, device_id, created_by)
        SELECT @company_id, employee_id, punched_at, punch_type, break_type_id, @source, @device_id, @actor_user_id
        FROM #imp WHERE error IS NULL AND dup = 0;

        IF @device_id IS NOT NULL
            UPDATE [att].[device] SET last_synced_at = [att].[fn_company_now](@company_id) WHERE id = @device_id;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'att.punch_import', ISNULL(@device_id, 0), N'created', CONVERT(NVARCHAR(30), COUNT(*)), N'import', @actor_user_id, @now
        FROM #imp WHERE error IS NULL AND dup = 0;
    COMMIT;

    -- Re-process each employee over the span of their imported punches, at most a year at a time.
    DECLARE @emp BIGINT, @lo DATE, @hi DATE, @chunk_to DATE, @ids NVARCHAR(50);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT employee_id, DATEADD(DAY, -1, CAST(MIN(punched_at) AS DATE)), DATEADD(DAY, 1, CAST(MAX(punched_at) AS DATE))
        FROM #imp WHERE error IS NULL AND dup = 0 GROUP BY employee_id;
    OPEN c;
    FETCH NEXT FROM c INTO @emp, @lo, @hi;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ids = N'[' + CONVERT(NVARCHAR(30), @emp) + N']';
        WHILE @lo <= @hi
        BEGIN
            SET @chunk_to = CASE WHEN DATEADD(DAY, 365, @lo) < @hi THEN DATEADD(DAY, 365, @lo) ELSE @hi END;
            EXEC [att].[usp_timesheet_process] @company_id = @company_id, @actor_user_id = @actor_user_id,
                 @from_date = @lo, @to_date = @chunk_to, @employee_ids = @ids, @quiet = 1;
            SET @lo = DATEADD(DAY, 1, @chunk_to);
        END
        FETCH NEXT FROM c INTO @emp, @lo, @hi;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT SUM(CASE WHEN error IS NULL AND dup = 0 THEN 1 ELSE 0 END) AS created,
           SUM(CASE WHEN error IS NULL AND dup = 1 THEN 1 ELSE 0 END) AS skipped,
           SUM(CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END) AS failed
    FROM #imp;

    SELECT line, error AS message FROM #imp WHERE error IS NOT NULL ORDER BY line;
END
