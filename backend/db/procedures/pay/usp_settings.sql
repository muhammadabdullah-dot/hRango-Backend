-- Payroll Settings -> General: the 22 payroll options and the leave configuration, kept as
-- core.company_setting rows (module 'payroll'). Result set 1: the stored values. Result set 2: the
-- version to send back on save (the newest row version of the company's payroll settings).
CREATE OR ALTER PROCEDURE [pay].[usp_settings_get]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT setting_key, setting_value
    FROM [core].[company_setting]
    WHERE company_id = @company_id AND module = N'payroll';

    SELECT MAX(row_version) AS row_version
    FROM [core].[company_setting]
    WHERE company_id = @company_id AND module = N'payroll';
END
GO

-- Saves the settings given as a JSON object {"key": "value", ...}. @row_version is the one last read
-- (NULL while nothing has been saved yet). Each changed key is written to core.audit_log.
CREATE OR ALTER PROCEDURE [pay].[usp_settings_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @settings_json NVARCHAR(MAX),
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISJSON(@settings_json) <> 1
        THROW 50400, N'Settings are not valid.', 1;

    DECLARE @current BINARY(8) = (SELECT MAX(row_version) FROM [core].[company_setting]
                                  WHERE company_id = @company_id AND module = N'payroll');
    IF @current IS NOT NULL AND (@row_version IS NULL OR @row_version <> @current)
        THROW 50409, N'Someone else changed the payroll settings. Reload them and try again', 1;

    -- Values arrive JSON-encoded ("12", true, null).
    DECLARE @cpl NVARCHAR(MAX) = NULLIF(REPLACE(JSON_VALUE(@settings_json, N'$.cpl_leave_type_id'), N'"', N''), N'null');
    IF NULLIF(@cpl, N'') IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM [lv].[leave_type] WHERE id = TRY_CONVERT(BIGINT, @cpl) AND company_id = @company_id)
        THROW 50400, N'cplLeaveTypeId|Leave type not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @changes TABLE (setting_key NVARCHAR(100), old_value NVARCHAR(MAX), new_value NVARCHAR(MAX));

    BEGIN TRAN;
        MERGE [core].[company_setting] AS t
        USING (SELECT [key] COLLATE DATABASE_DEFAULT AS setting_key, [value] COLLATE DATABASE_DEFAULT AS setting_value
               FROM OPENJSON(@settings_json)) AS s
            ON t.company_id = @company_id AND t.module = N'payroll' AND t.setting_key = s.setting_key
        WHEN MATCHED AND EXISTS (SELECT t.setting_value EXCEPT SELECT s.setting_value) THEN
            UPDATE SET setting_value = s.setting_value, updated_at = @now, updated_by = @actor_user_id
        WHEN NOT MATCHED THEN
            INSERT (company_id, module, setting_key, setting_value, created_by)
            VALUES (@company_id, N'payroll', s.setting_key, s.setting_value, @actor_user_id)
        OUTPUT inserted.setting_key, deleted.setting_value, inserted.setting_value INTO @changes;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'pay.settings', @company_id, setting_key, old_value, new_value, N'update', @actor_user_id, @now
        FROM @changes;
    COMMIT;

    EXEC [pay].[usp_settings_get] @company_id = @company_id;
END
