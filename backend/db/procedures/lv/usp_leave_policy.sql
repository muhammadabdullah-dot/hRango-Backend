-- Leaves -> Settings -> Leave Policies.
-- A policy is a "Leave Distribution Policy" (policy_kind 'distribution': which leave types, with what
-- allowance) or a "Half leave & Short leave" policy ('half_short': whether half-day and short leave are
-- allowed). A company-level policy covers everyone; an employee-level one covers the people enrolled
-- in it and outranks the company-level one. One active company-level policy per kind; a person is
-- enrolled in at most one active employee-level policy per kind.

-- Which leave types each employee has, with the allowance their covering distribution policy gives.
-- When the company has no active distribution policy at all, every leave type applies to everyone
-- at the type's own allowance.
CREATE OR ALTER FUNCTION [lv].[fn_leave_coverage] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
WITH cover AS (
    SELECT e.id AS employee_id, COALESCE(ep.id, cp.id) AS leave_policy_id
    FROM [hr].[employee] e
    OUTER APPLY (SELECT TOP (1) p.id FROM [lv].[leave_policy_employee] pe
                 JOIN [lv].[leave_policy] p ON p.id = pe.leave_policy_id
                 WHERE pe.employee_id = e.id AND p.company_id = @company_id AND p.policy_kind = N'distribution'
                   AND p.policy_level = N'employee' AND p.is_active = 1 ORDER BY p.id) ep
    OUTER APPLY (SELECT TOP (1) p.id FROM [lv].[leave_policy] p
                 WHERE p.company_id = @company_id AND p.policy_kind = N'distribution'
                   AND p.policy_level = N'company' AND p.is_active = 1 ORDER BY p.id) cp
    WHERE e.company_id = @company_id
)
SELECT c.employee_id, pt.leave_type_id, COALESCE(pt.allowance, t.allowance) AS allowance, c.leave_policy_id
FROM cover c
JOIN [lv].[leave_policy_type] pt ON pt.leave_policy_id = c.leave_policy_id
JOIN [lv].[leave_type] t ON t.id = pt.leave_type_id
UNION ALL
SELECT e.id, t.id, t.allowance, NULL
FROM [hr].[employee] e
JOIN [lv].[leave_type] t ON t.company_id = e.company_id
WHERE e.company_id = @company_id
  AND NOT EXISTS (SELECT 1 FROM [lv].[leave_policy] p
                  WHERE p.company_id = @company_id AND p.policy_kind = N'distribution' AND p.is_active = 1);
GO

CREATE OR ALTER FUNCTION [lv].[fn_leave_policy_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.title, p.policy_kind, p.policy_level, p.allow_half_day, p.allow_short_leave, p.is_active,
       (SELECT SUM(COALESCE(pt.allowance, t.allowance)) FROM [lv].[leave_policy_type] pt
        JOIN [lv].[leave_type] t ON t.id = pt.leave_type_id WHERE pt.leave_policy_id = p.id) AS total_leaves,
       CASE WHEN p.policy_level = N'company'
            THEN (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.company_id = @company_id AND e.status <> N'left')
            ELSE (SELECT COUNT(*) FROM [lv].[leave_policy_employee] pe WHERE pe.leave_policy_id = p.id) END AS enrolled_count,
       (SELECT pt.leave_type_id, t.title AS leave_type_title, t.short_code, pt.allowance,
               COALESCE(pt.allowance, t.allowance) AS effective_allowance
        FROM [lv].[leave_policy_type] pt JOIN [lv].[leave_type] t ON t.id = pt.leave_type_id
        WHERE pt.leave_policy_id = p.id ORDER BY t.title FOR JSON PATH) AS types,
       p.created_at, p.updated_at, p.row_version
FROM [lv].[leave_policy] p
WHERE p.company_id = @company_id;
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @kind       NVARCHAR(30) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [lv].[leave_policy] p
    WHERE p.company_id = @company_id
      AND (@pattern IS NULL OR p.title LIKE @pattern)
      AND (@kind IS NULL OR p.policy_kind = @kind)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [lv].[fn_leave_policy_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.title LIKE @pattern)
      AND (@kind IS NULL OR r.policy_kind = @kind)
    ORDER BY r.title, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_policy] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Leave policy not found', 1;

    SELECT r.* FROM [lv].[fn_leave_policy_rows](@company_id) r WHERE r.id = @id;
END
GO

-- @types: JSON [{"leaveTypeId": "1", "allowance": 10}] (distribution policies; allowance NULL = the type's own).
CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @id                BIGINT = NULL,
    @title             NVARCHAR(200),
    @policy_kind       NVARCHAR(30),
    @policy_level      NVARCHAR(30),
    @allow_half_day    BIT = 0,
    @allow_short_leave BIT = 0,
    @is_active         BIT = 1,
    @types             NVARCHAR(MAX) = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Title is required.', 1;
    IF @types IS NOT NULL AND ISJSON(@types) = 0
        THROW 50400, N'types|Leave types are not valid.', 1;

    DECLARE @t TABLE (leave_type_id BIGINT, allowance DECIMAL(6,2));
    IF @policy_kind = N'distribution'
        INSERT @t SELECT j.leave_type_id, j.allowance
        FROM OPENJSON(@types) WITH (leave_type_id BIGINT '$.leaveTypeId', allowance DECIMAL(6,2) '$.allowance') j;

    IF @policy_kind = N'distribution' AND NOT EXISTS (SELECT 1 FROM @t)
        THROW 50400, N'types|Choose at least one leave type.', 1;
    IF EXISTS (SELECT 1 FROM @t x WHERE NOT EXISTS (SELECT 1 FROM [lv].[leave_type] lt WHERE lt.id = x.leave_type_id AND lt.company_id = @company_id))
        THROW 50400, N'types|Leave type not found.', 1;
    IF EXISTS (SELECT leave_type_id FROM @t GROUP BY leave_type_id HAVING COUNT(*) > 1)
        THROW 50400, N'types|A leave type is listed twice.', 1;
    IF EXISTS (SELECT 1 FROM [lv].[leave_policy] WHERE company_id = @company_id AND title = @title AND (@id IS NULL OR id <> @id))
        THROW 50409, N'title|LEAVE_POLICY_DUPLICATE|A leave policy with this title already exists.', 1;
    IF @is_active = 1 AND @policy_level = N'company'
       AND EXISTS (SELECT 1 FROM [lv].[leave_policy] WHERE company_id = @company_id AND policy_kind = @policy_kind
                   AND policy_level = N'company' AND is_active = 1 AND (@id IS NULL OR id <> @id))
        THROW 50409, N'policyLevel|LEAVE_POLICY_COMPANY_EXISTS|Another active company-level policy of this kind exists. Make it inactive first.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @old NVARCHAR(MAX), @new NVARCHAR(MAX);

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a leave policy', 1;
        DECLARE @old_rv BINARY(8), @old_kind NVARCHAR(30), @old_level NVARCHAR(30);
        SELECT @old_rv = row_version, @old_kind = policy_kind, @old_level = policy_level
        FROM [lv].[leave_policy] WHERE id = @id AND company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Leave policy not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this leave policy. Reload it and try again', 1;
        IF @old_level = N'employee' AND @policy_level <> N'employee'
           AND EXISTS (SELECT 1 FROM [lv].[leave_policy_employee] WHERE leave_policy_id = @id)
            THROW 50409, N'policyLevel|Employees are enrolled in this policy. Remove them before making it company level.', 1;
        IF @old_kind <> @policy_kind AND EXISTS (SELECT 1 FROM [lv].[leave_policy_employee] WHERE leave_policy_id = @id)
            THROW 50409, N'policyKind|Employees are enrolled in this policy. Remove them before changing what it decides.', 1;
        IF @is_active = 1 AND @policy_level = N'employee'
           AND EXISTS (SELECT 1 FROM [lv].[leave_policy_employee] pe
                       JOIN [lv].[leave_policy_employee] other ON other.employee_id = pe.employee_id AND other.leave_policy_id <> @id
                       JOIN [lv].[leave_policy] op ON op.id = other.leave_policy_id
                       WHERE pe.leave_policy_id = @id AND op.is_active = 1 AND op.policy_kind = @policy_kind)
            THROW 50409, N'isActive|Someone enrolled here is enrolled in another active policy of this kind.', 1;
        SET @old = (SELECT r.title, r.policy_kind, r.policy_level, r.allow_half_day, r.allow_short_leave, r.is_active, r.types
                    FROM [lv].[fn_leave_policy_rows](@company_id) r WHERE r.id = @id
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [lv].[leave_policy] (company_id, title, policy_kind, policy_level, allow_half_day, allow_short_leave, is_active, created_by)
            VALUES (@company_id, @title, @policy_kind, @policy_level, @allow_half_day, @allow_short_leave, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'lv.leave_policy', @id, N'title', @title, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [lv].[leave_policy]
            SET title = @title, policy_kind = @policy_kind, policy_level = @policy_level, allow_half_day = @allow_half_day,
                allow_short_leave = @allow_short_leave, is_active = @is_active, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this leave policy. Reload it and try again', 1;
            DELETE [lv].[leave_policy_type] WHERE leave_policy_id = @id;
        END

        INSERT [lv].[leave_policy_type] (leave_policy_id, leave_type_id, allowance, created_by)
        SELECT @id, leave_type_id, allowance, @actor_user_id FROM @t;

        IF @old IS NOT NULL
        BEGIN
            SET @new = (SELECT r.title, r.policy_kind, r.policy_level, r.allow_half_day, r.allow_short_leave, r.is_active, r.types
                        FROM [lv].[fn_leave_policy_rows](@company_id) r WHERE r.id = @id
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'lv.leave_policy', @id, n.[key], o.value, n.value, N'update', @actor_user_id, @now
            FROM OPENJSON(@new) n
            LEFT JOIN OPENJSON(@old) o ON o.[key] = n.[key]
            WHERE EXISTS (SELECT o.value EXCEPT SELECT n.value);
        END
    COMMIT;

    EXEC [lv].[usp_leave_policy_get] @company_id = @company_id, @id = @id;
END
GO

-- Deleting a policy removes its leave types and enrolments with it; balances already posted stay.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @title NVARCHAR(200);
    SELECT @rv = row_version, @title = title FROM [lv].[leave_policy] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Leave policy not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this leave policy. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [lv].[leave_policy_type] WHERE leave_policy_id = @id;
        DELETE [lv].[leave_policy_employee] WHERE leave_policy_id = @id;
        DELETE [lv].[leave_policy] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'lv.leave_policy', @id, N'title', @title, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- "Enroll Employee": the people enrolled in an employee-level policy.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_employee_list]
    @company_id BIGINT,
    @id         BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_policy] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Leave policy not found', 1;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [lv].[leave_policy_employee] pe
    JOIN [hr].[employee] e ON e.id = pe.employee_id AND e.company_id = @company_id
    WHERE pe.leave_policy_id = @id
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           d.name AS department_name, pe.created_at AS enrolled_at
    FROM [lv].[leave_policy_employee] pe
    JOIN [hr].[employee] e ON e.id = pe.employee_id AND e.company_id = @company_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE pe.leave_policy_id = @id
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern)
    ORDER BY e.first_name, e.last_name, e.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Enrols people (@employee_ids: JSON ["1", "2"]); people already enrolled here are left as they are.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_employee_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @employee_ids  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @level NVARCHAR(30), @kind NVARCHAR(30), @active BIT;
    SELECT @level = policy_level, @kind = policy_kind, @active = is_active
    FROM [lv].[leave_policy] WHERE id = @id AND company_id = @company_id;
    IF @level IS NULL
        THROW 50404, N'Leave policy not found', 1;
    IF @level <> N'employee'
        THROW 50400, N'employeeIds|A company-level policy covers everyone; nobody needs enrolling.', 1;
    IF @employee_ids IS NULL OR ISJSON(@employee_ids) = 0
        THROW 50400, N'employeeIds|Choose at least one employee.', 1;

    DECLARE @e TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @e SELECT DISTINCT TRY_CAST(j.value AS BIGINT) FROM OPENJSON(@employee_ids) j WHERE TRY_CAST(j.value AS BIGINT) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM @e)
        THROW 50400, N'employeeIds|Choose at least one employee.', 1;
    IF EXISTS (SELECT 1 FROM @e x WHERE NOT EXISTS (SELECT 1 FROM [hr].[employee] h WHERE h.id = x.employee_id AND h.company_id = @company_id))
        THROW 50400, N'employeeIds|Employee not found.', 1;
    IF @active = 1 AND EXISTS (
            SELECT 1 FROM @e x
            JOIN [lv].[leave_policy_employee] pe ON pe.employee_id = x.employee_id AND pe.leave_policy_id <> @id
            JOIN [lv].[leave_policy] p ON p.id = pe.leave_policy_id
            WHERE p.is_active = 1 AND p.policy_kind = @kind)
        THROW 50409, N'employeeIds|LEAVE_POLICY_ALREADY_ENROLLED|Someone chosen is already enrolled in another active policy of this kind.', 1;

    DELETE x FROM @e x
    WHERE EXISTS (SELECT 1 FROM [lv].[leave_policy_employee] pe WHERE pe.leave_policy_id = @id AND pe.employee_id = x.employee_id);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [lv].[leave_policy_employee] (leave_policy_id, employee_id, created_by)
        SELECT @id, x.employee_id, @actor_user_id FROM @e x;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'lv.leave_policy', @id, N'employee_id', CONVERT(NVARCHAR(30), x.employee_id), N'enroll', @actor_user_id, @now
        FROM @e x;

        UPDATE [lv].[leave_policy] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    EXEC [lv].[usp_leave_policy_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_policy_employee_remove]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @employee_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_policy] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Leave policy not found', 1;
    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_policy_employee] WHERE leave_policy_id = @id AND employee_id = @employee_id)
        THROW 50404, N'This employee is not enrolled in the policy', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE [lv].[leave_policy_employee] WHERE leave_policy_id = @id AND employee_id = @employee_id;
        UPDATE [lv].[leave_policy] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'lv.leave_policy', @id, N'employee_id', CONVERT(NVARCHAR(30), @employee_id), N'unenroll', @actor_user_id, @now);
    COMMIT;
END
