-- Overdue settings of a workspace (Backend Dependencies T5): the story point penalty for tasks closed late
-- (pm.fn_task_rows works out story_points_penalty / story_points_effective from it) and how many extension
-- requests a task may have (pm.usp_task_extension_request). A workspace without a row uses 0 % and 1.

CREATE OR ALTER PROCEDURE [pm].[usp_workspace_overdue_setting_get]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @workspace_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id)
        THROW 50404, N'Workspace not found', 1;

    SELECT @workspace_id AS workspace_id, ISNULL(s.penalty_percent, 0) AS penalty_percent, ISNULL(s.max_extensions, 1) AS max_extensions,
           s.row_version
    FROM (SELECT 1 AS one) x
    LEFT JOIN [pm].[workspace_overdue_setting] s ON s.workspace_id = @workspace_id;
END
GO

-- HR and workspace admins change them. The first save needs no rowVersion; later ones do.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_overdue_setting_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @workspace_id    BIGINT,
    @penalty_percent DECIMAL(5, 2),
    @max_extensions  INT,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @workspace_id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 4
        THROW 50403, N'Only workspace admins and HR can change the overdue settings.', 1;
    IF @penalty_percent IS NULL OR @penalty_percent < 0 OR @penalty_percent > 100
        THROW 50400, N'penaltyPercent|The penalty is 0 to 100 percent.', 1;
    IF @max_extensions IS NULL OR @max_extensions < 0 OR @max_extensions > 10
        THROW 50400, N'maxExtensions|Allow 0 to 10 extension requests per task.', 1;

    DECLARE @rv BINARY(8), @exists BIT = 0, @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @rv = row_version, @exists = 1 FROM [pm].[workspace_overdue_setting] WHERE workspace_id = @workspace_id;
    IF @exists = 1 AND @rv <> ISNULL(@row_version, 0x)
        THROW 50409, N'Someone else changed the overdue settings. Reload them and try again', 1;

    BEGIN TRAN;
        IF @exists = 0
            INSERT [pm].[workspace_overdue_setting] (workspace_id, penalty_percent, max_extensions, created_by)
            VALUES (@workspace_id, @penalty_percent, @max_extensions, @actor_user_id);
        ELSE
            UPDATE [pm].[workspace_overdue_setting]
            SET penalty_percent = @penalty_percent, max_extensions = @max_extensions, updated_at = @now, updated_by = @actor_user_id
            WHERE workspace_id = @workspace_id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @workspace_id, N'overdue_settings',
                CONCAT(N'penalty ', @penalty_percent, N'%, ', @max_extensions, N' extension(s)'), N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_workspace_overdue_setting_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @workspace_id = @workspace_id;
END
