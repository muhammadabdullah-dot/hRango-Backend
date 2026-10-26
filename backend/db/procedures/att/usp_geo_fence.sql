-- Settings -> Geo Fencing. A fence is a circle (centre and radius) or a polygon (points), and applies to
-- everyone or to the employees its targets select. Targets as for IP restrictions:
-- @targets = [{"targetType": "branch", "targetId": 3}, {"targetType": "religion", "targetValue": "Islam"}].

CREATE OR ALTER PROCEDURE [att].[usp_geo_fence_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [att].[geo_fence] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Geo fence not found', 1;

    SELECT f.id, f.code, f.name, f.shape, f.center_lat, f.center_lng, f.radius_m, f.polygon_points, f.applies_to_all,
           f.joining_from_date, f.joining_to_date, f.is_for_shift, f.is_active, f.created_at, f.updated_at, f.row_version
    FROM [att].[geo_fence] f WHERE f.id = @id;

    SELECT t.target_type, t.target_id, t.target_value
    FROM [att].[geo_fence_target] t WHERE t.geo_fence_id = @id ORDER BY t.target_type, t.id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_geo_fence_list]
    @company_id   BIGINT,
    @search       NVARCHAR(200) = NULL,
    @is_active    BIT = NULL,
    @is_for_shift BIT = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [att].[geo_fence] f
    WHERE f.company_id = @company_id
      AND (@pattern IS NULL OR f.code LIKE @pattern OR f.name LIKE @pattern)
      AND (@is_active IS NULL OR f.is_active = @is_active)
      AND (@is_for_shift IS NULL OR f.is_for_shift = @is_for_shift)
    OPTION (RECOMPILE);

    SELECT f.id, f.code, f.name, f.shape, f.center_lat, f.center_lng, f.radius_m, f.polygon_points, f.applies_to_all,
           f.joining_from_date, f.joining_to_date, f.is_for_shift, f.is_active,
           (SELECT COUNT(*) FROM [att].[geo_fence_target] t WHERE t.geo_fence_id = f.id) AS target_count,
           f.created_at, f.updated_at, f.row_version
    FROM [att].[geo_fence] f
    WHERE f.company_id = @company_id
      AND (@pattern IS NULL OR f.code LIKE @pattern OR f.name LIKE @pattern)
      AND (@is_active IS NULL OR f.is_active = @is_active)
      AND (@is_for_shift IS NULL OR f.is_for_shift = @is_for_shift)
    ORDER BY f.code, f.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_geo_fence_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @id                BIGINT = NULL,
    @name              NVARCHAR(200),
    @shape             NVARCHAR(30),
    @center_lat        DECIMAL(9,6) = NULL,
    @center_lng        DECIMAL(9,6) = NULL,
    @radius_m          INT = NULL,
    @polygon_points    NVARCHAR(MAX) = NULL,
    @applies_to_all    BIT = 1,
    @joining_from_date DATE = NULL,
    @joining_to_date   DATE = NULL,
    @is_for_shift      BIT = 0,
    @is_active         BIT = 1,
    @targets           NVARCHAR(MAX) = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Geo fence name is required.', 1;
    IF @shape NOT IN (N'circle', N'polygon')
        THROW 50400, N'shape|Shape must be circle or polygon.', 1;
    IF @shape = N'circle' AND (@center_lat IS NULL OR @center_lng IS NULL)
        THROW 50400, N'centerLat|A circle needs a centre.', 1;
    IF @shape = N'circle' AND ISNULL(@radius_m, 0) <= 0
        THROW 50400, N'radiusM|A circle needs a radius above zero.', 1;
    IF @shape = N'polygon' AND (@polygon_points IS NULL OR ISJSON(@polygon_points) = 0)
        THROW 50400, N'polygonPoints|A polygon needs at least three points.', 1;
    IF @shape = N'polygon'
        IF (SELECT COUNT(*) FROM OPENJSON(@polygon_points)) < 3
            THROW 50400, N'polygonPoints|A polygon needs at least three points.', 1;
    IF @joining_to_date < @joining_from_date
        THROW 50400, N'joiningToDate|The joining end date is before the start date.', 1;
    IF EXISTS (SELECT 1 FROM [att].[geo_fence] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|GEO_FENCE_DUPLICATE|A geo fence with this name already exists.', 1;
    IF @shape = N'circle'
        SET @polygon_points = NULL;
    ELSE
        SELECT @center_lat = NULL, @center_lng = NULL, @radius_m = NULL;

    IF @targets IS NOT NULL AND ISJSON(@targets) = 0
        THROW 50400, N'targets|Targets are not valid.', 1;
    DECLARE @t TABLE (target_type NVARCHAR(30), target_id BIGINT, target_value NVARCHAR(200));
    INSERT @t SELECT target_type, target_id, NULLIF(LTRIM(RTRIM(target_value)), N'')
    FROM OPENJSON(ISNULL(@targets, N'[]')) WITH (target_type NVARCHAR(30) '$.targetType', target_id BIGINT '$.targetId',
                                                 target_value NVARCHAR(200) '$.targetValue');
    IF EXISTS (SELECT 1 FROM @t WHERE ISNULL(target_type, N'') NOT IN (N'employee', N'country', N'location', N'branch', N'area',
               N'department', N'designation', N'grade', N'job_title', N'religion', N'nationality'))
        THROW 50400, N'targets|A target type is not known.', 1;
    IF EXISTS (SELECT 1 FROM @t WHERE (target_type IN (N'religion', N'nationality') AND target_value IS NULL)
                                   OR (target_type NOT IN (N'religion', N'nationality') AND target_id IS NULL))
        THROW 50400, N'targets|Each target needs a value.', 1;
    IF @applies_to_all = 0 AND NOT EXISTS (SELECT 1 FROM @t) AND @joining_from_date IS NULL AND @joining_to_date IS NULL
        THROW 50400, N'targets|Choose who the fence applies to, or apply it to all employees.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            EXEC [att].[usp_code_next] @company_id = @company_id, @prefix = N'GF-', @code = @code OUTPUT;
            INSERT [att].[geo_fence] (company_id, code, name, shape, center_lat, center_lng, radius_m, polygon_points,
                                      applies_to_all, joining_from_date, joining_to_date, is_for_shift, is_active, created_by)
            VALUES (@company_id, @code, @name, @shape, @center_lat, @center_lng, @radius_m, @polygon_points,
                    @applies_to_all, @joining_from_date, @joining_to_date, @is_for_shift, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [att].[geo_fence_target] (geo_fence_id, target_type, target_id, target_value, created_by)
            SELECT @id, target_type, target_id, target_value, @actor_user_id FROM @t;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'att.geo_fence', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8), @o_name NVARCHAR(200), @o_shape NVARCHAR(30), @o_active BIT, @o_all BIT;
        SELECT @rv = row_version, @o_name = name, @o_shape = shape, @o_active = is_active, @o_all = applies_to_all
        FROM [att].[geo_fence] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Geo fence not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this geo fence. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [att].[geo_fence]
            SET name = @name, shape = @shape, center_lat = @center_lat, center_lng = @center_lng, radius_m = @radius_m,
                polygon_points = @polygon_points, applies_to_all = @applies_to_all, joining_from_date = @joining_from_date,
                joining_to_date = @joining_to_date, is_for_shift = @is_for_shift, is_active = @is_active,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this geo fence. Reload it and try again', 1;
            DELETE [att].[geo_fence_target] WHERE geo_fence_id = @id;
            INSERT [att].[geo_fence_target] (geo_fence_id, target_type, target_id, target_value, created_by)
            SELECT @id, target_type, target_id, target_value, @actor_user_id FROM @t;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'att.geo_fence', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES (N'name', @o_name, @name), (N'shape', @o_shape, @shape),
                         (N'applies_to_all', CONVERT(NVARCHAR(1), @o_all), CONVERT(NVARCHAR(1), @applies_to_all)),
                         (N'is_active', CONVERT(NVARCHAR(1), @o_active), CONVERT(NVARCHAR(1), @is_active))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [att].[usp_geo_fence_get] @company_id = @company_id, @id = @id;
END
GO

-- A fence that shifts use cannot be deleted; set it inactive instead.
CREATE OR ALTER PROCEDURE [att].[usp_geo_fence_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [att].[geo_fence] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Geo fence not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this geo fence. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sch].[schedule] WHERE geo_fence_id = @id)
       OR EXISTS (SELECT 1 FROM [sch].[schedule_batch] WHERE geo_fence_id = @id)
        THROW 50409, N'id|GEO_FENCE_IN_USE|Shifts use this geo fence. Set it inactive instead', 1;

    BEGIN TRAN;
        DELETE [att].[geo_fence_target] WHERE geo_fence_id = @id;
        DELETE [att].[geo_fence] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'att.geo_fence', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
