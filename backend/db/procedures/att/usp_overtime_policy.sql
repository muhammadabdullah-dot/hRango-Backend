-- Overtime Policy (design: Overtime -> Overtime Policy): a daily or monthly policy whose slabs turn overtime
-- minutes into a full day or a leave. Slabs are saved with the policy:
-- @slabs = [{"minMinutes": 60, "maxMinutes": 239, "encashmentType": "leave", "leaveTypeId": 4}, ...]

CREATE OR ALTER PROCEDURE [att].[usp_overtime_policy_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [att].[overtime_policy] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Overtime policy not found', 1;

    SELECT p.id, p.name, p.period, p.description, p.is_active, p.created_at, p.updated_at, p.row_version
    FROM [att].[overtime_policy] p WHERE p.id = @id;

    SELECT s.id, s.min_minutes, s.max_minutes, s.encashment_type, s.leave_type_id, lt.title AS leave_type_name
    FROM [att].[overtime_policy_slab] s
    LEFT JOIN [lv].[leave_type] lt ON lt.id = s.leave_type_id
    WHERE s.overtime_policy_id = @id
    ORDER BY s.min_minutes, s.id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_overtime_policy_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @period     NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [att].[overtime_policy] p
    WHERE p.company_id = @company_id AND (@pattern IS NULL OR p.name LIKE @pattern) AND (@period IS NULL OR p.period = @period)
    OPTION (RECOMPILE);

    SELECT p.id, p.name, p.period, p.description, p.is_active,
           (SELECT COUNT(*) FROM [att].[overtime_policy_slab] s WHERE s.overtime_policy_id = p.id) AS slab_count,
           p.created_at, p.updated_at, p.row_version
    FROM [att].[overtime_policy] p
    WHERE p.company_id = @company_id AND (@pattern IS NULL OR p.name LIKE @pattern) AND (@period IS NULL OR p.period = @period)
    ORDER BY p.name, p.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_overtime_policy_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @period        NVARCHAR(30),
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @slabs         NVARCHAR(MAX) = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Policy name is required.', 1;
    IF @period NOT IN (N'daily', N'monthly')
        THROW 50400, N'period|Period must be daily or monthly.', 1;
    IF EXISTS (SELECT 1 FROM [att].[overtime_policy] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|OVERTIME_POLICY_DUPLICATE|An overtime policy with this name already exists.', 1;
    IF @slabs IS NOT NULL AND ISJSON(@slabs) = 0
        THROW 50400, N'slabs|Slabs are not valid.', 1;

    DECLARE @s TABLE (n INT IDENTITY, min_minutes INT, max_minutes INT, encashment_type NVARCHAR(30), leave_type_id BIGINT);
    INSERT @s (min_minutes, max_minutes, encashment_type, leave_type_id)
    SELECT min_minutes, max_minutes, encashment_type, leave_type_id
    FROM OPENJSON(ISNULL(@slabs, N'[]')) WITH (min_minutes INT '$.minMinutes', max_minutes INT '$.maxMinutes',
        encashment_type NVARCHAR(30) '$.encashmentType', leave_type_id BIGINT '$.leaveTypeId');

    IF EXISTS (SELECT 1 FROM @s WHERE min_minutes IS NULL OR max_minutes IS NULL OR min_minutes < 0 OR max_minutes < min_minutes)
        THROW 50400, N'slabs|Each slab needs minimum and maximum minutes, the maximum not below the minimum.', 1;
    IF EXISTS (SELECT 1 FROM @s WHERE ISNULL(encashment_type, N'') NOT IN (N'full_day', N'leave'))
        THROW 50400, N'slabs|Encashment type must be full day or leave.', 1;
    IF EXISTS (SELECT 1 FROM @s WHERE encashment_type = N'leave' AND leave_type_id IS NULL)
        THROW 50400, N'slabs|Choose the leave type a slab converts to.', 1;
    IF EXISTS (SELECT 1 FROM @s x WHERE x.leave_type_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [lv].[leave_type] t WHERE t.id = x.leave_type_id AND t.company_id = @company_id))
        THROW 50400, N'slabs|Leave type not found.', 1;
    IF EXISTS (SELECT 1 FROM @s a JOIN @s b ON a.n < b.n AND a.min_minutes <= b.max_minutes AND b.min_minutes <= a.max_minutes)
        THROW 50400, N'slabs|Slabs overlap.', 1;
    UPDATE @s SET leave_type_id = NULL WHERE encashment_type = N'full_day';

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @n_slabs NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(min_minutes, N'-', max_minutes, N' ', encashment_type, N' ', leave_type_id), N'; ')
                                                WITHIN GROUP (ORDER BY min_minutes) FROM @s);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [att].[overtime_policy] (company_id, name, period, description, is_active, created_by)
            VALUES (@company_id, @name, @period, @description, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [att].[overtime_policy_slab] (overtime_policy_id, min_minutes, max_minutes, encashment_type, leave_type_id, created_by)
            SELECT @id, min_minutes, max_minutes, encashment_type, leave_type_id, @actor_user_id FROM @s;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'att.overtime_policy', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8), @o_name NVARCHAR(200), @o_period NVARCHAR(30), @o_desc NVARCHAR(MAX), @o_active BIT;
        SELECT @rv = row_version, @o_name = name, @o_period = period, @o_desc = description, @o_active = is_active
        FROM [att].[overtime_policy] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Overtime policy not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this overtime policy. Reload it and try again', 1;
        DECLARE @o_slabs NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(min_minutes, N'-', max_minutes, N' ', encashment_type, N' ', leave_type_id), N'; ')
                                                    WITHIN GROUP (ORDER BY min_minutes)
                                          FROM [att].[overtime_policy_slab] WHERE overtime_policy_id = @id);

        BEGIN TRAN;
            UPDATE [att].[overtime_policy]
            SET name = @name, period = @period, description = @description, is_active = @is_active,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this overtime policy. Reload it and try again', 1;
            DELETE [att].[overtime_policy_slab] WHERE overtime_policy_id = @id;
            INSERT [att].[overtime_policy_slab] (overtime_policy_id, min_minutes, max_minutes, encashment_type, leave_type_id, created_by)
            SELECT @id, min_minutes, max_minutes, encashment_type, leave_type_id, @actor_user_id FROM @s;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'att.overtime_policy', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES (N'name', @o_name, @name), (N'period', @o_period, @period), (N'description', @o_desc, @description),
                         (N'is_active', CONVERT(NVARCHAR(1), @o_active), CONVERT(NVARCHAR(1), @is_active)),
                         (N'slabs', @o_slabs, @n_slabs)
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [att].[usp_overtime_policy_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_overtime_policy_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [att].[overtime_policy] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Overtime policy not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this overtime policy. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [att].[overtime_policy_slab] WHERE overtime_policy_id = @id;
        DELETE [att].[overtime_policy] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'att.overtime_policy', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
