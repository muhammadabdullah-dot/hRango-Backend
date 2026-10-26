-- Deletes a workspace and all its content (BRD: permanent, after confirmation). Workspace admins only.
CREATE OR ALTER PROCEDURE [pm].[usp_workspace_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rank INT;
    SELECT @rank = role_rank FROM [pm].[fn_workspace_access](@company_id, @actor_user_id) WHERE workspace_id = @id;
    IF @rank IS NULL
        THROW 50404, N'Workspace not found', 1;
    IF @rank < 5
        THROW 50403, N'Only a workspace admin can delete the workspace.', 1;
    IF (SELECT row_version FROM [pm].[workspace] WHERE id = @id) <> @row_version
        THROW 50409, N'Someone else changed this workspace. Reload it and try again', 1;

    CREATE TABLE #purge (task_id BIGINT PRIMARY KEY);
    INSERT #purge SELECT id FROM [pm].[task] WHERE workspace_id = @id;

    BEGIN TRAN;
        EXEC [pm].[usp_task_purge];

        DELETE m FROM [pm].[share_member] m JOIN [pm].[share_link] s ON s.id = m.share_link_id WHERE s.workspace_id = @id;
        DELETE [pm].[share_link] WHERE workspace_id = @id;
        DELETE [pm].[reminder] WHERE workspace_id = @id;
        DELETE [pm].[favorite] WHERE (entity_type = N'workspace' AND entity_id = @id)
            OR (entity_type = N'folder' AND entity_id IN (SELECT id FROM [pm].[folder] WHERE workspace_id = @id))
            OR (entity_type = N'task_list' AND entity_id IN (SELECT id FROM [pm].[task_list] WHERE workspace_id = @id));
        DELETE [pm].[list_view] WHERE workspace_id = @id;
        DELETE [pm].[column_permission] WHERE workspace_id = @id;
        DELETE [pm].[custom_field] WHERE workspace_id = @id;
        DELETE [pm].[tag] WHERE workspace_id = @id;
        DELETE [pm].[sprint] WHERE workspace_id = @id;
        DELETE [pm].[doc] WHERE workspace_id = @id;
        DELETE m FROM [pm].[task_list_member] m JOIN [pm].[task_list] l ON l.id = m.task_list_id WHERE l.workspace_id = @id;
        DELETE [pm].[task_list] WHERE workspace_id = @id;
        DELETE [pm].[folder] WHERE workspace_id = @id;
        DELETE [pm].[workspace_feature] WHERE workspace_id = @id;
        DELETE [pm].[workspace_status] WHERE workspace_id = @id;
        DELETE [pm].[workspace_member] WHERE workspace_id = @id;
        DELETE [pm].[workspace] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pm.workspace', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
