-- Attendance settings kept in core.company_setting: module 'attendance' (Settings -> Basic), module
-- 'scheduling' (Settings -> Scheduling) and module 'overtime' (Overtime -> Settings). The keys and their types are checked in app/services/attendance_service.py.
-- The form's rowVersion is the newest row_version of the module's rows (NULL before the first save).

-- Result set 1: the version; result set 2: the saved keys and values.
CREATE OR ALTER PROCEDURE [att].[usp_setting_get]
    @company_id BIGINT,
    @module     NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    IF @module NOT IN (N'attendance', N'overtime', N'scheduling')
        THROW 50404, N'Settings not found', 1;

    SELECT MAX(row_version) AS row_version
    FROM [core].[company_setting] WHERE company_id = @company_id AND module = @module;

    SELECT setting_key, setting_value
    FROM [core].[company_setting] WHERE company_id = @company_id AND module = @module
    ORDER BY setting_key;
END
GO

-- Saves the given keys ({"key": "value", ...}); keys not given are left alone. One audit row per changed key.
CREATE OR ALTER PROCEDURE [att].[usp_setting_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @module        NVARCHAR(30),
    @settings      NVARCHAR(MAX),
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @module NOT IN (N'attendance', N'overtime', N'scheduling')
        THROW 50404, N'Settings not found', 1;
    IF @settings IS NULL OR ISJSON(@settings) = 0
        THROW 50400, N'Settings are not valid', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRAN;
        DECLARE @current BINARY(8) = (SELECT MAX(row_version) FROM [core].[company_setting] WITH (UPDLOCK, HOLDLOCK)
                                      WHERE company_id = @company_id AND module = @module);
        IF (@current IS NULL AND @row_version IS NOT NULL)
           OR (@current IS NOT NULL AND (@row_version IS NULL OR @current <> @row_version))
            THROW 50409, N'Someone else changed these settings. Reload them and try again', 1;

        DECLARE @new TABLE (setting_key NVARCHAR(100) PRIMARY KEY, setting_value NVARCHAR(MAX));
        INSERT @new (setting_key, setting_value)
        SELECT [key], [value] FROM OPENJSON(@settings);

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'core.company_setting', @company_id, @module + N'.' + n.setting_key, s.setting_value, n.setting_value,
               N'update', @actor_user_id, @now
        FROM @new n
        LEFT JOIN [core].[company_setting] s ON s.company_id = @company_id AND s.module = @module AND s.setting_key = n.setting_key
        WHERE EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);

        UPDATE s SET setting_value = n.setting_value, updated_at = @now, updated_by = @actor_user_id
        FROM [core].[company_setting] s
        JOIN @new n ON n.setting_key = s.setting_key
        WHERE s.company_id = @company_id AND s.module = @module
          AND EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);

        INSERT [core].[company_setting] (company_id, module, setting_key, setting_value, created_by)
        SELECT @company_id, @module, n.setting_key, n.setting_value, @actor_user_id
        FROM @new n
        WHERE NOT EXISTS (SELECT 1 FROM [core].[company_setting] s
                          WHERE s.company_id = @company_id AND s.module = @module AND s.setting_key = n.setting_key);
    COMMIT;

    EXEC [att].[usp_setting_get] @company_id = @company_id, @module = @module;
END
