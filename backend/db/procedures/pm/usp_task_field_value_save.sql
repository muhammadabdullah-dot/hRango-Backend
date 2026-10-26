-- Sets (or clears, @field_value NULL) one custom field value on a task, checked against the field's
-- type and settings (BRD "Task Custom Fields"). Team leaders and above, or the task's creator,
-- unless the field's column permission says can_view or private.
CREATE OR ALTER PROCEDURE [pm].[usp_task_field_value_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @task_id         BIGINT,
    @custom_field_id BIGINT,
    @field_value     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @task_id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND EXISTS (SELECT 1 FROM [pm].[task] WHERE id = @task_id AND created_by = @actor_user_id))
        THROW 50403, N'Only team leaders and above, or the task''s creator, can fill in fields.', 1;

    DECLARE @type NVARCHAR(30), @config NVARCHAR(MAX), @field_name NVARCHAR(200);
    SELECT @type = field_type, @config = config, @field_name = name FROM [pm].[custom_field] WHERE id = @custom_field_id AND workspace_id = @ws;
    IF @type IS NULL
        THROW 50404, N'Custom field not found', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = CONCAT(N'cf_', @custom_field_id)
               AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change this field (column permission).', 1;

    SET @field_value = NULLIF(LTRIM(RTRIM(@field_value)), N'');
    IF @field_value IS NOT NULL
    BEGIN
        DECLARE @num DECIMAL(38, 10) = TRY_CONVERT(DECIMAL(38, 10), @field_value);
        DECLARE @min DECIMAL(38, 10) = TRY_CONVERT(DECIMAL(38, 10), JSON_VALUE(@config, '$.min'));
        DECLARE @max DECIMAL(38, 10) = TRY_CONVERT(DECIMAL(38, 10), JSON_VALUE(@config, '$.max'));
        DECLARE @end INT = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@config, '$.end')), 100);
        IF @type = N'text' AND LEN(@field_value) > 255
            THROW 50400, N'value|Text must be within 255 characters.', 1;
        IF @type = N'long_text' AND LEN(@field_value) > 5000
            THROW 50400, N'value|Text must be within 5000 characters.', 1;
        IF @type IN (N'number', N'money') AND (@num IS NULL OR @num < @min OR @num > @max)
            THROW 50400, N'value|Enter a valid number within the allowed range.', 1;
        IF @type = N'date' AND TRY_CONVERT(DATE, @field_value, 23) IS NULL
            THROW 50400, N'value|Enter a date as YYYY-MM-DD.', 1;
        IF @type = N'checkbox' AND @field_value NOT IN (N'true', N'false')
            THROW 50400, N'value|A checkbox is either checked or unchecked.', 1;
        IF @type = N'email' AND (@field_value NOT LIKE N'%_@_%._%' OR @field_value LIKE N'% %')
            THROW 50400, N'value|Enter a valid email address.', 1;
        IF @type = N'phone' AND (PATINDEX(N'%[^0-9+ ()-]%', @field_value) > 0 OR LEN(@field_value) NOT BETWEEN 7 AND 20)
            THROW 50400, N'value|Enter a valid phone number.', 1;
        IF @type = N'website' AND @field_value NOT LIKE N'http://_%' AND @field_value NOT LIKE N'https://_%'
            THROW 50400, N'value|A link must begin with http:// or https://.', 1;
        IF @type = N'rating' AND (TRY_CONVERT(INT, @field_value) IS NULL
                                  OR TRY_CONVERT(INT, @field_value) NOT BETWEEN 1 AND ISNULL(TRY_CONVERT(INT, JSON_VALUE(@config, '$.max')), 5))
            THROW 50400, N'value|Choose a rating within the scale.', 1;
        IF @type = N'progress_manual' AND (TRY_CONVERT(INT, @field_value) IS NULL OR TRY_CONVERT(INT, @field_value) NOT BETWEEN 0 AND @end)
            THROW 50400, N'value|Progress must be within the scale.', 1;
        IF @type = N'dropdown' AND NOT EXISTS (SELECT 1 FROM OPENJSON(@config, '$.options') WHERE value = @field_value)
            THROW 50400, N'value|Choose one of the options.', 1;
        IF @type IN (N'labels', N'people') AND ISJSON(@field_value) = 0
            THROW 50400, N'value|Choose from the list.', 1;
        IF @type = N'labels' AND EXISTS (SELECT 1 FROM OPENJSON(@field_value) v
                                         WHERE NOT EXISTS (SELECT 1 FROM OPENJSON(@config, '$.options') o WHERE o.value = v.value))
            THROW 50400, N'value|Choose from the options.', 1;
        IF @type = N'people' AND EXISTS (SELECT 1 FROM OPENJSON(@field_value) v
                                         WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m
                                                           WHERE m.workspace_id = @ws AND m.employee_id = TRY_CONVERT(BIGINT, v.value)))
            THROW 50400, N'value|People must be members of the workspace.', 1;
    END

    DECLARE @old NVARCHAR(MAX) = (SELECT field_value FROM [pm].[task_field_value] WHERE task_id = @task_id AND custom_field_id = @custom_field_id);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE [pm].[task_field_value] WHERE task_id = @task_id AND custom_field_id = @custom_field_id;
        IF @field_value IS NOT NULL
            INSERT [pm].[task_field_value] (task_id, custom_field_id, field_value, created_by)
            VALUES (@task_id, @custom_field_id, @field_value, @actor_user_id);
        UPDATE [pm].[task] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @task_id;
        IF EXISTS (SELECT @old EXCEPT SELECT @field_value)
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @task_id, @field_name, @old, @field_value, N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @task_id;
END
