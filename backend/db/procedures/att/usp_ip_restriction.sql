-- Settings -> IP Restrictions. The address formats are checked in app/services/attendance_service.py.
-- Targets: @targets = [{"targetType": "branch", "targetId": 3}, {"targetType": "religion", "targetValue": "Islam"}].

CREATE OR ALTER PROCEDURE [att].[usp_ip_restriction_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [att].[ip_restriction] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'IP restriction not found', 1;

    SELECT r.id, r.code, r.ipv4, r.ipv6, r.netmask, r.range_start, r.range_end, r.applies_to_all, r.is_active,
           r.created_at, r.updated_at, r.row_version
    FROM [att].[ip_restriction] r WHERE r.id = @id;

    SELECT t.target_type, t.target_id, t.target_value
    FROM [att].[ip_restriction_target] t WHERE t.ip_restriction_id = @id ORDER BY t.target_type, t.id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_ip_restriction_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_active  BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [att].[ip_restriction] r
    WHERE r.company_id = @company_id
      AND (@pattern IS NULL OR r.code LIKE @pattern OR r.ipv4 LIKE @pattern OR r.ipv6 LIKE @pattern
           OR r.range_start LIKE @pattern OR r.range_end LIKE @pattern)
      AND (@is_active IS NULL OR r.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT r.id, r.code, r.ipv4, r.ipv6, r.netmask, r.range_start, r.range_end, r.applies_to_all, r.is_active,
           (SELECT COUNT(*) FROM [att].[ip_restriction_target] t WHERE t.ip_restriction_id = r.id) AS target_count,
           r.created_at, r.updated_at, r.row_version
    FROM [att].[ip_restriction] r
    WHERE r.company_id = @company_id
      AND (@pattern IS NULL OR r.code LIKE @pattern OR r.ipv4 LIKE @pattern OR r.ipv6 LIKE @pattern
           OR r.range_start LIKE @pattern OR r.range_end LIKE @pattern)
      AND (@is_active IS NULL OR r.is_active = @is_active)
    ORDER BY r.code, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_ip_restriction_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT = NULL,
    @id             BIGINT = NULL,
    @ipv4           NVARCHAR(45) = NULL,
    @ipv6           NVARCHAR(45) = NULL,
    @netmask        NVARCHAR(45) = NULL,
    @range_start    NVARCHAR(45) = NULL,
    @range_end      NVARCHAR(45) = NULL,
    @applies_to_all BIT = 1,
    @is_active      BIT = 1,
    @targets        NVARCHAR(MAX) = NULL,
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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
    IF @applies_to_all = 0 AND NOT EXISTS (SELECT 1 FROM @t)
        THROW 50400, N'targets|Choose who the restriction applies to, or apply it to all employees.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            EXEC [att].[usp_code_next] @company_id = @company_id, @prefix = N'IPR-', @code = @code OUTPUT;
            INSERT [att].[ip_restriction] (company_id, code, ipv4, ipv6, netmask, range_start, range_end, applies_to_all, is_active, created_by)
            VALUES (@company_id, @code, @ipv4, @ipv6, @netmask, @range_start, @range_end, @applies_to_all, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [att].[ip_restriction_target] (ip_restriction_id, target_type, target_id, target_value, created_by)
            SELECT @id, target_type, target_id, target_value, @actor_user_id FROM @t;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'att.ip_restriction', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8), @o_ipv4 NVARCHAR(45), @o_ipv6 NVARCHAR(45), @o_mask NVARCHAR(45), @o_rs NVARCHAR(45),
                @o_re NVARCHAR(45), @o_all BIT, @o_active BIT;
        SELECT @rv = row_version, @o_ipv4 = ipv4, @o_ipv6 = ipv6, @o_mask = netmask, @o_rs = range_start, @o_re = range_end,
               @o_all = applies_to_all, @o_active = is_active
        FROM [att].[ip_restriction] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'IP restriction not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this IP restriction. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [att].[ip_restriction]
            SET ipv4 = @ipv4, ipv6 = @ipv6, netmask = @netmask, range_start = @range_start, range_end = @range_end,
                applies_to_all = @applies_to_all, is_active = @is_active, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this IP restriction. Reload it and try again', 1;
            DELETE [att].[ip_restriction_target] WHERE ip_restriction_id = @id;
            INSERT [att].[ip_restriction_target] (ip_restriction_id, target_type, target_id, target_value, created_by)
            SELECT @id, target_type, target_id, target_value, @actor_user_id FROM @t;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'att.ip_restriction', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES (N'ipv4', @o_ipv4, @ipv4), (N'ipv6', @o_ipv6, @ipv6), (N'netmask', @o_mask, @netmask),
                         (N'range_start', @o_rs, @range_start), (N'range_end', @o_re, @range_end),
                         (N'applies_to_all', CONVERT(NVARCHAR(1), @o_all), CONVERT(NVARCHAR(1), @applies_to_all)),
                         (N'is_active', CONVERT(NVARCHAR(1), @o_active), CONVERT(NVARCHAR(1), @is_active))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [att].[usp_ip_restriction_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_ip_restriction_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [att].[ip_restriction] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'IP restriction not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this IP restriction. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [att].[ip_restriction_target] WHERE ip_restriction_id = @id;
        DELETE [att].[ip_restriction] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'att.ip_restriction', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
