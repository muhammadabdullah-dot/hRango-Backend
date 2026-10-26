-- Assignees with their story points, and tags, of one task. Both return the task.

-- @assignees: [{"employee_id", "story_points"}]. Team leaders and above (BRD: only team leads and
-- above assign work). Assignees must be workspace members; one only unless "Multiple Assignees" is on.
CREATE OR ALTER PROCEDURE [pm].[usp_task_assignees_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @assignees     NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 2
        THROW 50403, N'Only team leaders and above can assign tasks.', 1;

    DECLARE @as TABLE (employee_id BIGINT PRIMARY KEY, story_points INT);
    INSERT @as SELECT j.employee_id, MAX(j.story_points)
    FROM OPENJSON(ISNULL(@assignees, N'[]')) WITH (employee_id BIGINT '$.employee_id', story_points INT '$.story_points') j
    WHERE j.employee_id IS NOT NULL GROUP BY j.employee_id;

    IF EXISTS (SELECT 1 FROM @as a WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_member] m WHERE m.workspace_id = @ws AND m.employee_id = a.employee_id))
        THROW 50400, N'assignees|Assignees must be members of the workspace.', 1;
    IF EXISTS (SELECT 1 FROM @as WHERE story_points < 0 OR story_points > 100)
        THROW 50400, N'assignees|Story points run from 0 to 100.', 1;
    IF (SELECT COUNT(*) FROM @as) > 1
       AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @ws AND feature_code = N'multiple_assignees')
        THROW 50409, N'assignees|FEATURE_OFF|This workspace allows one assignee per task.', 1;
    IF EXISTS (SELECT 1 FROM @as WHERE story_points IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @ws AND feature_code = N'story_points')
        THROW 50409, N'assignees|FEATURE_OFF|Story points are switched off for this workspace.', 1;

    DECLARE @old NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(employee_id, N':', story_points), N',') WITHIN GROUP (ORDER BY employee_id)
                                  FROM [pm].[task_assignee] WHERE task_id = @id);
    DECLARE @new NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(employee_id, N':', story_points), N',') WITHIN GROUP (ORDER BY employee_id) FROM @as);
    DECLARE @people_changed BIT = CASE
        WHEN EXISTS (SELECT employee_id FROM [pm].[task_assignee] WHERE task_id = @id EXCEPT SELECT employee_id FROM @as) THEN 1
        WHEN EXISTS (SELECT employee_id FROM @as EXCEPT SELECT employee_id FROM [pm].[task_assignee] WHERE task_id = @id) THEN 1
        ELSE 0 END;
    DECLARE @points_changed BIT = CASE WHEN EXISTS (
        SELECT a.employee_id FROM @as a JOIN [pm].[task_assignee] t ON t.task_id = @id AND t.employee_id = a.employee_id
        WHERE EXISTS (SELECT a.story_points EXCEPT SELECT t.story_points)) THEN 1 ELSE 0 END;
    IF (@people_changed = 1 AND EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'assignees' AND permission_level IN (N'can_view', N'private')))
       OR ((@points_changed = 1 OR EXISTS (SELECT 1 FROM @as s WHERE s.story_points IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] a WHERE a.task_id = @id AND a.employee_id = s.employee_id)))
           AND EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'story_points' AND permission_level IN (N'can_view', N'private')))
        THROW 50403, N'You can view but not change the assignees or story points (column permission).', 1;

    -- People newly assigned are told (projects.task_assigned).
    DECLARE @added NVARCHAR(MAX) = (
        SELECT CONCAT(N'[', STRING_AGG(CONVERT(NVARCHAR(MAX), s.employee_id), N','), N']') FROM @as s
        WHERE NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] a WHERE a.task_id = @id AND a.employee_id = s.employee_id));

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE a FROM [pm].[task_assignee] a WHERE a.task_id = @id AND NOT EXISTS (SELECT 1 FROM @as s WHERE s.employee_id = a.employee_id);
        UPDATE a SET story_points = s.story_points, updated_at = @now, updated_by = @actor_user_id
        FROM [pm].[task_assignee] a JOIN @as s ON s.employee_id = a.employee_id
        WHERE a.task_id = @id AND EXISTS (SELECT a.story_points EXCEPT SELECT s.story_points);
        INSERT [pm].[task_assignee] (task_id, employee_id, story_points, created_by)
        SELECT @id, s.employee_id, s.story_points, @actor_user_id FROM @as s
        WHERE NOT EXISTS (SELECT 1 FROM [pm].[task_assignee] a WHERE a.task_id = @id AND a.employee_id = s.employee_id);
        UPDATE [pm].[task] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;

        IF EXISTS (SELECT @old EXCEPT SELECT @new)
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @id, N'assignees', @old, @new, N'assign', @actor_user_id, @now);

        EXEC [pm].[usp_task_announce_assigned] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @task_id = @id, @employee_ids = @added;
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
GO

-- @tag_ids: JSON array. Team leaders and above, or the task's creator.
CREATE OR ALTER PROCEDURE [pm].[usp_task_tags_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @tag_ids       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ws BIGINT, @rank INT, @me BIGINT;
    SELECT @ws = workspace_id, @rank = role_rank, @me = employee_id FROM [pm].[fn_task_access](@company_id, @actor_user_id) WHERE task_id = @id;
    IF @ws IS NULL
        THROW 50404, N'Task not found', 1;
    IF @rank < 2 AND NOT (@rank >= 1 AND EXISTS (SELECT 1 FROM [pm].[task] WHERE id = @id AND created_by = @actor_user_id))
        THROW 50403, N'Only team leaders and above, or the task''s creator, can tag this task.', 1;
    IF EXISTS (SELECT 1 FROM [pm].[fn_column_levels](@ws, @me) WHERE column_key = N'tags' AND permission_level IN (N'can_view', N'private'))
        THROW 50403, N'You can view but not change the tags (column permission).', 1;

    DECLARE @tg TABLE (tag_id BIGINT PRIMARY KEY);
    INSERT @tg SELECT DISTINCT CAST(value AS BIGINT) FROM OPENJSON(ISNULL(@tag_ids, N'[]'));
    IF EXISTS (SELECT 1 FROM @tg) AND NOT EXISTS (SELECT 1 FROM [pm].[workspace_feature] WHERE workspace_id = @ws AND feature_code = N'tags')
        THROW 50409, N'tagIds|FEATURE_OFF|Tags are switched off for this workspace.', 1;
    IF EXISTS (SELECT 1 FROM @tg g WHERE NOT EXISTS (SELECT 1 FROM [pm].[tag] t WHERE t.id = g.tag_id AND t.workspace_id = @ws))
        THROW 50400, N'tagIds|Tag not found in this workspace.', 1;

    DECLARE @old NVARCHAR(MAX) = (SELECT STRING_AGG(g.name, N', ') WITHIN GROUP (ORDER BY g.name) FROM [pm].[task_tag] x JOIN [pm].[tag] g ON g.id = x.tag_id WHERE x.task_id = @id);
    DECLARE @new NVARCHAR(MAX) = (SELECT STRING_AGG(g.name, N', ') WITHIN GROUP (ORDER BY g.name) FROM @tg x JOIN [pm].[tag] g ON g.id = x.tag_id);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE x FROM [pm].[task_tag] x WHERE x.task_id = @id AND x.tag_id NOT IN (SELECT tag_id FROM @tg);
        INSERT [pm].[task_tag] (task_id, tag_id, created_by)
        SELECT @id, g.tag_id, @actor_user_id FROM @tg g WHERE NOT EXISTS (SELECT 1 FROM [pm].[task_tag] x WHERE x.task_id = @id AND x.tag_id = g.tag_id);
        UPDATE [pm].[task] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
        IF EXISTS (SELECT @old EXCEPT SELECT @new)
            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'pm.task', @id, N'tags', @old, @new, N'update', @actor_user_id, @now);
    COMMIT;

    EXEC [pm].[usp_task_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
END
