-- Warning -> Policy and Penalty (owned by the leaves-and-warning module; tables in the att schema).
-- A policy watches one thing (applies_to) over a period, with one rule per clock event and the
-- penalty rules that price the n-th warning. Rules and penalties travel as JSON.
CREATE OR ALTER FUNCTION [att].[fn_warning_policy_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.title, p.applies_to, p.period, p.grace_minutes, p.week_start_day, p.week_end_day, p.is_active,
       (SELECT r.clock_event, r.minutes, r.occurrence_count FROM [att].[warning_policy_rule] r
        WHERE r.warning_policy_id = p.id ORDER BY r.clock_event FOR JSON PATH) AS rules,
       (SELECT x.id, x.after_count, x.period, x.penalty_type, x.percentage, x.deduction, x.leave_type_id,
               t.title AS leave_type_title
        FROM [att].[penalty_rule] x LEFT JOIN [lv].[leave_type] t ON t.id = x.leave_type_id
        WHERE x.warning_policy_id = p.id ORDER BY x.period, x.after_count FOR JSON PATH) AS penalties,
       (SELECT COUNT(*) FROM [att].[warning] w WHERE w.warning_policy_id = p.id) AS warning_count,
       p.created_at, p.updated_at, p.row_version
FROM [att].[warning_policy] p
WHERE p.company_id = @company_id;
GO

CREATE OR ALTER PROCEDURE [att].[usp_warning_policy_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @applies_to NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [att].[warning_policy] p
    WHERE p.company_id = @company_id
      AND (@pattern IS NULL OR p.title LIKE @pattern)
      AND (@applies_to IS NULL OR p.applies_to = @applies_to)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [att].[fn_warning_policy_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.title LIKE @pattern)
      AND (@applies_to IS NULL OR r.applies_to = @applies_to)
    ORDER BY r.title, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_warning_policy_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [att].[warning_policy] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Warning policy not found', 1;

    SELECT r.* FROM [att].[fn_warning_policy_rows](@company_id) r WHERE r.id = @id;
END
GO

-- @rules: JSON [{"clockEvent": "clock_in", "minutes": 10, "occurrenceCount": 3}].
CREATE OR ALTER PROCEDURE [att].[usp_warning_policy_save]
    @company_id     BIGINT,
    @actor_user_id  BIGINT = NULL,
    @id             BIGINT = NULL,
    @title          NVARCHAR(200),
    @applies_to     NVARCHAR(30),
    @period         NVARCHAR(30),
    @grace_minutes  INT = NULL,
    @week_start_day NVARCHAR(30) = NULL,
    @week_end_day   NVARCHAR(30) = NULL,
    @is_active      BIT = 1,
    @rules          NVARCHAR(MAX),
    @row_version    BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Title is required.', 1;
    IF @rules IS NULL OR ISJSON(@rules) = 0
        THROW 50400, N'rules|Add at least one rule.', 1;

    DECLARE @r TABLE (clock_event NVARCHAR(30), minutes INT, occurrence_count INT);
    INSERT @r SELECT j.clock_event, ISNULL(j.minutes, 0), ISNULL(j.occurrence_count, 1)
    FROM OPENJSON(@rules) WITH (clock_event NVARCHAR(30) '$.clockEvent', minutes INT '$.minutes',
                                occurrence_count INT '$.occurrenceCount') j;
    IF NOT EXISTS (SELECT 1 FROM @r)
        THROW 50400, N'rules|Add at least one rule.', 1;
    IF EXISTS (SELECT clock_event FROM @r GROUP BY clock_event HAVING COUNT(*) > 1)
        THROW 50400, N'rules|One rule per clock event.', 1;
    IF EXISTS (SELECT 1 FROM [att].[warning_policy] WHERE company_id = @company_id AND title = @title AND (@id IS NULL OR id <> @id))
        THROW 50409, N'title|WARNING_POLICY_DUPLICATE|A warning policy with this title already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @old NVARCHAR(MAX), @new NVARCHAR(MAX);

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a warning policy', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [att].[warning_policy] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Warning policy not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this warning policy. Reload it and try again', 1;
        SET @old = (SELECT r.title, r.applies_to, r.period, r.grace_minutes, r.week_start_day, r.week_end_day, r.is_active, r.rules
                    FROM [att].[fn_warning_policy_rows](@company_id) r WHERE r.id = @id
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        IF EXISTS (SELECT 1 FROM [att].[warning] w JOIN [att].[warning_policy_rule] x ON x.id = w.warning_policy_rule_id
                   WHERE x.warning_policy_id = @id AND x.clock_event NOT IN (SELECT clock_event FROM @r))
            THROW 50409, N'rules|Warnings were raised under a rule you removed. Keep the rule or make the policy inactive.', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [att].[warning_policy] (company_id, title, applies_to, period, grace_minutes, week_start_day, week_end_day, is_active, created_by)
            VALUES (@company_id, @title, @applies_to, @period, @grace_minutes, @week_start_day, @week_end_day, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'att.warning_policy', @id, N'title', @title, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [att].[warning_policy]
            SET title = @title, applies_to = @applies_to, period = @period, grace_minutes = @grace_minutes,
                week_start_day = @week_start_day, week_end_day = @week_end_day, is_active = @is_active,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this warning policy. Reload it and try again', 1;
        END

        -- Rules keep their ids (warnings point at them): update, add, and remove the ones no longer sent.
        UPDATE x SET minutes = r.minutes, occurrence_count = r.occurrence_count, updated_at = @now, updated_by = @actor_user_id
        FROM [att].[warning_policy_rule] x JOIN @r r ON r.clock_event = x.clock_event
        WHERE x.warning_policy_id = @id AND (x.minutes <> r.minutes OR x.occurrence_count <> r.occurrence_count);

        INSERT [att].[warning_policy_rule] (warning_policy_id, clock_event, minutes, occurrence_count, created_by)
        SELECT @id, r.clock_event, r.minutes, r.occurrence_count, @actor_user_id
        FROM @r r
        WHERE NOT EXISTS (SELECT 1 FROM [att].[warning_policy_rule] x WHERE x.warning_policy_id = @id AND x.clock_event = r.clock_event);

        DELETE [att].[warning_policy_rule] WHERE warning_policy_id = @id AND clock_event NOT IN (SELECT clock_event FROM @r);

        IF @old IS NOT NULL
        BEGIN
            SET @new = (SELECT r.title, r.applies_to, r.period, r.grace_minutes, r.week_start_day, r.week_end_day, r.is_active, r.rules
                        FROM [att].[fn_warning_policy_rows](@company_id) r WHERE r.id = @id
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'att.warning_policy', @id, n.[key], o.value, n.value, N'update', @actor_user_id, @now
            FROM OPENJSON(@new) n
            LEFT JOIN OPENJSON(@old) o ON o.[key] = n.[key]
            WHERE EXISTS (SELECT o.value EXCEPT SELECT n.value);
        END
    COMMIT;

    EXEC [att].[usp_warning_policy_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [att].[usp_warning_policy_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @title NVARCHAR(200);
    SELECT @rv = row_version, @title = title FROM [att].[warning_policy] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Warning policy not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this warning policy. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [att].[warning] WHERE warning_policy_id = @id)
        THROW 50409, N'Warnings have been raised under this policy. Make it inactive instead', 1;

    BEGIN TRAN;
        DELETE [att].[penalty_rule] WHERE warning_policy_id = @id;
        DELETE [att].[warning_policy_rule] WHERE warning_policy_id = @id;
        DELETE [att].[warning_policy] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'att.warning_policy', @id, N'title', @title, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Warning -> Penalty: replaces a policy's penalty rules.
-- @penalties: JSON [{"afterCount": 3, "period": "month", "penaltyType": "half_day", "percentage": 50,
--                    "deduction": "leave", "leaveTypeId": "7"}].
CREATE OR ALTER PROCEDURE [att].[usp_warning_penalty_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @penalties     NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @penalties IS NULL OR ISJSON(@penalties) = 0
        THROW 50400, N'penalties|Penalties are not valid.', 1;

    DECLARE @p TABLE (after_count INT, period NVARCHAR(30), penalty_type NVARCHAR(30), percentage DECIMAL(5,2),
                      deduction NVARCHAR(30), leave_type_id BIGINT);
    INSERT @p SELECT j.after_count, j.period, j.penalty_type, j.percentage, j.deduction, j.leave_type_id
    FROM OPENJSON(@penalties) WITH (after_count INT '$.afterCount', period NVARCHAR(30) '$.period',
                                    penalty_type NVARCHAR(30) '$.penaltyType', percentage DECIMAL(5,2) '$.percentage',
                                    deduction NVARCHAR(30) '$.deduction', leave_type_id BIGINT '$.leaveTypeId') j;

    IF EXISTS (SELECT period, after_count FROM @p GROUP BY period, after_count HAVING COUNT(*) > 1)
        THROW 50400, N'penalties|Two penalties have the same count and period.', 1;
    IF EXISTS (SELECT 1 FROM @p x WHERE x.leave_type_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [lv].[leave_type] t WHERE t.id = x.leave_type_id AND t.company_id = @company_id))
        THROW 50400, N'penalties|Leave type not found.', 1;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [att].[warning_policy] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Warning policy not found', 1;
    IF @row_version IS NULL OR @rv <> @row_version
        THROW 50409, N'Someone else changed this warning policy. Reload it and try again', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @old NVARCHAR(MAX) = (SELECT penalties FROM [att].[fn_warning_policy_rows](@company_id) WHERE id = @id);

    BEGIN TRAN;
        UPDATE [att].[warning_policy] SET updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this warning policy. Reload it and try again', 1;

        -- Warnings already raised keep their penalty figures; their link to a removed rule is dropped.
        UPDATE w SET penalty_rule_id = NULL
        FROM [att].[warning] w JOIN [att].[penalty_rule] x ON x.id = w.penalty_rule_id
        WHERE x.warning_policy_id = @id;
        DELETE [att].[penalty_rule] WHERE warning_policy_id = @id;

        INSERT [att].[penalty_rule] (warning_policy_id, after_count, period, penalty_type, percentage, deduction, leave_type_id, created_by)
        SELECT @id, after_count, period, penalty_type, percentage, deduction, leave_type_id, @actor_user_id FROM @p;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'att.warning_policy', @id, N'penalties', @old, r.penalties, N'update', @actor_user_id, @now
        FROM [att].[fn_warning_policy_rows](@company_id) r
        WHERE r.id = @id AND EXISTS (SELECT @old EXCEPT SELECT r.penalties);
    COMMIT;

    EXEC [att].[usp_warning_policy_get] @company_id = @company_id, @id = @id;
END
GO

-- The Penalty list: every penalty rule with its policy.
CREATE OR ALTER PROCEDURE [att].[usp_warning_penalty_list]
    @company_id BIGINT,
    @policy_id  BIGINT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [att].[penalty_rule] x
    JOIN [att].[warning_policy] p ON p.id = x.warning_policy_id AND p.company_id = @company_id
    WHERE (@policy_id IS NULL OR p.id = @policy_id)
    OPTION (RECOMPILE);

    SELECT x.id, x.warning_policy_id, p.title AS policy_title, p.applies_to, x.after_count, x.period, x.penalty_type,
           x.percentage, x.deduction, x.leave_type_id, t.title AS leave_type_title, x.created_at
    FROM [att].[penalty_rule] x
    JOIN [att].[warning_policy] p ON p.id = x.warning_policy_id AND p.company_id = @company_id
    LEFT JOIN [lv].[leave_type] t ON t.id = x.leave_type_id
    WHERE (@policy_id IS NULL OR p.id = @policy_id)
    ORDER BY p.title, x.period, x.after_count, x.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
