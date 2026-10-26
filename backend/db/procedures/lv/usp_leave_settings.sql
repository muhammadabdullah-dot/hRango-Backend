-- Leaves -> Settings -> General Settings, kept in core.company_setting (module 'leave').
-- The row version of the form is the newest row version of the module's rows (NULL before the first save).
CREATE OR ALTER PROCEDURE [lv].[usp_leave_settings_get]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL(MAX(CASE WHEN s.setting_key = N'final_approval_by' THEN s.setting_value END), N'hr_manager') AS final_approval_by,
           ISNULL(MAX(CASE WHEN s.setting_key = N'approve_on_status' THEN s.setting_value END), N'approved') AS approve_on_status,
           CAST(ISNULL(MAX(CASE WHEN s.setting_key = N'post_deadline' THEN s.setting_value END), N'0') AS BIT) AS post_deadline,
           MAX(s.row_version) AS row_version
    FROM [core].[company_setting] s
    WHERE s.company_id = @company_id AND s.module = N'leave';
END
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_settings_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @final_approval_by NVARCHAR(30),
    @approve_on_status NVARCHAR(30),
    @post_deadline     BIT,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @final_approval_by IS NULL OR @final_approval_by NOT IN (N'hr_manager', N'line_manager', N'department_head')
        THROW 50400, N'finalApprovalBy|Choose who gives the final approval.', 1;
    IF @approve_on_status IS NULL OR @approve_on_status NOT IN (N'approved', N'pending')
        THROW 50400, N'approveOnStatus|Choose approved or pending.', 1;

    DECLARE @current BINARY(8) = (SELECT MAX(row_version) FROM [core].[company_setting]
                                  WHERE company_id = @company_id AND module = N'leave');
    IF @current IS NOT NULL AND (@row_version IS NULL OR @row_version <> @current)
        THROW 50409, N'Someone else changed the leave settings. Reload them and try again', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @new TABLE (setting_key NVARCHAR(100), setting_value NVARCHAR(MAX));
    INSERT @new VALUES (N'final_approval_by', @final_approval_by), (N'approve_on_status', @approve_on_status),
                       (N'post_deadline', CASE WHEN @post_deadline = 1 THEN N'1' ELSE N'0' END);

    BEGIN TRAN;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'lv.settings', @company_id, n.setting_key, s.setting_value, n.setting_value, N'update', @actor_user_id, @now
        FROM @new n
        LEFT JOIN [core].[company_setting] s ON s.company_id = @company_id AND s.module = N'leave' AND s.setting_key = n.setting_key
        WHERE EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);

        UPDATE s SET setting_value = n.setting_value, updated_at = @now, updated_by = @actor_user_id
        FROM [core].[company_setting] s
        JOIN @new n ON n.setting_key = s.setting_key
        WHERE s.company_id = @company_id AND s.module = N'leave'
          AND EXISTS (SELECT s.setting_value EXCEPT SELECT n.setting_value);

        INSERT [core].[company_setting] (company_id, module, setting_key, setting_value, created_by)
        SELECT @company_id, N'leave', n.setting_key, n.setting_value, @actor_user_id
        FROM @new n
        WHERE NOT EXISTS (SELECT 1 FROM [core].[company_setting] s
                          WHERE s.company_id = @company_id AND s.module = N'leave' AND s.setting_key = n.setting_key);
    COMMIT;

    EXEC [lv].[usp_leave_settings_get] @company_id = @company_id;
END
