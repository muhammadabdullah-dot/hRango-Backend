-- Performance: tells an employee's accounts in the inbox. core.usp_notification_add_employee is called
-- with @quiet = 1, so the calling procedure's own result set stays the first one.
CREATE OR ALTER PROCEDURE [perf].[usp_notify_employee]
    @company_id  BIGINT,
    @employee_id BIGINT,
    @title       NVARCHAR(200),
    @body        NVARCHAR(MAX) = NULL,
    @link        NVARCHAR(500) = NULL,
    @entity_type NVARCHAR(50) = NULL,
    @entity_id   BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @employee_id IS NULL
        RETURN;
    EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id, @title = @title,
         @body = @body, @notification_type = N'performance', @link = @link, @entity_type = @entity_type,
         @entity_id = @entity_id;
END
GO

-- Places the goal achievement on the rating scale and recomputes the weighted self and manager scores:
-- (sum of criterion weight x rating + goals weight x goal score) / (weights of what is rated). Nothing rated
-- yet = no score. Goal achievement only counts when the form gives goals a weight and the person has goals.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_rescore]
    @id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @scale BIGINT, @gw DECIMAL(18,6), @min DECIMAL(18,6), @max DECIMAL(18,6), @pct DECIMAL(18,6),
            @gs DECIMAL(18,6), @sw DECIMAL(18,6), @sww DECIMAL(18,6), @mw DECIMAL(18,6), @mww DECIMAL(18,6);
    SELECT @scale = f.rating_scale_id, @gw = f.goals_weight
    FROM [perf].[appraisal] a
    JOIN [perf].[appraisal_cycle] c ON c.id = a.appraisal_cycle_id
    JOIN [perf].[appraisal_form] f ON f.id = c.appraisal_form_id
    WHERE a.id = @id;
    SELECT @min = MIN(score), @max = MAX(score) FROM [perf].[rating_scale_level] WHERE rating_scale_id = @scale;

    SET @pct = [perf].[fn_goal_achievement](@id);
    SET @gs = CASE WHEN @gw > 0 AND @pct IS NOT NULL THEN ROUND(@min + (@max - @min) * @pct / 100.0, 2) END;

    -- Rated criteria only (filtered, not aggregated over NULLs: warning 8153 would precede a later THROW).
    SELECT @sw = SUM(c.weight * r.self_rating), @sww = SUM(c.weight)
    FROM [perf].[appraisal_rating] r
    JOIN [perf].[appraisal_criterion] c ON c.id = r.appraisal_criterion_id
    WHERE r.appraisal_id = @id AND r.self_rating IS NOT NULL;
    SELECT @mw = SUM(c.weight * r.manager_rating), @mww = SUM(c.weight)
    FROM [perf].[appraisal_rating] r
    JOIN [perf].[appraisal_criterion] c ON c.id = r.appraisal_criterion_id
    WHERE r.appraisal_id = @id AND r.manager_rating IS NOT NULL;

    DECLARE @g_part DECIMAL(18,6) = CASE WHEN @gs IS NULL THEN 0 ELSE @gw * @gs END,
            @g_weight DECIMAL(18,6) = CASE WHEN @gs IS NULL THEN 0 ELSE @gw END;
    UPDATE [perf].[appraisal]
    SET goals_score = @gs,
        self_score = CASE WHEN @sww IS NULL OR @sww + @g_weight = 0 THEN NULL
                          ELSE ROUND((@sw + @g_part) / (@sww + @g_weight), 2) END,
        manager_score = CASE WHEN @mww IS NULL OR @mww + @g_weight = 0 THEN NULL
                             ELSE ROUND((@mw + @g_part) / (@mww + @g_weight), 2) END
    WHERE id = @id;
END
