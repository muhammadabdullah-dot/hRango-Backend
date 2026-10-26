-- Leaves -> Settings -> Leave Types. The slabs travel with their type as JSON
-- (experience_slabs, short_slabs). in_use counts ledger postings, leave requests and policies.
CREATE OR ALTER FUNCTION [lv].[fn_leave_type_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT t.id, t.title, t.short_code, t.allowance, t.is_active, t.is_probation_type, t.auto_allotment,
       t.auto_balance_on_joining, t.is_composite, t.is_short_leave, t.show_in_payslip, t.is_deductible,
       t.is_sandwich, t.sandwich_across_types, t.is_earned, t.allow_back_date, t.back_date_limit_days,
       t.has_future_limit, t.future_limit_days, t.attachment_required, t.attachment_rule, t.allow_encashment,
       t.encashment_min, t.encashment_max, t.carry_forward, t.pro_rated, t.gender, t.marital_status,
       t.allowed_in_probation, t.min_experience_months, t.max_applications, t.gap_between_applications_months,
       t.tenure, t.balance_basis, t.accumulative_count,
       (SELECT s.min_months, s.max_months, s.balance FROM [lv].[leave_type_experience_slab] s
        WHERE s.leave_type_id = t.id ORDER BY s.min_months, s.id FOR JSON PATH) AS experience_slabs,
       (SELECT s.name, s.balance, s.value_type, s.slab_value FROM [lv].[leave_type_short_slab] s
        WHERE s.leave_type_id = t.id ORDER BY s.id FOR JSON PATH) AS short_slabs,
       (SELECT COUNT(*) FROM [lv].[leave_ledger] g WHERE g.leave_type_id = t.id)
         + (SELECT COUNT(*) FROM [req].[req_leave] rl WHERE rl.leave_type_id = t.id)
         + (SELECT COUNT(*) FROM [lv].[leave_policy_type] pt WHERE pt.leave_type_id = t.id) AS in_use,
       t.created_at, t.updated_at, t.row_version
FROM [lv].[leave_type] t
WHERE t.company_id = @company_id;
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_type_list]
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
    FROM [lv].[leave_type] t
    WHERE t.company_id = @company_id
      AND (@pattern IS NULL OR t.title LIKE @pattern OR t.short_code LIKE @pattern)
      AND (@is_active IS NULL OR t.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [lv].[fn_leave_type_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.title LIKE @pattern OR r.short_code LIKE @pattern)
      AND (@is_active IS NULL OR r.is_active = @is_active)
    ORDER BY r.title, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_type_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Leave type not found', 1;

    SELECT r.* FROM [lv].[fn_leave_type_rows](@company_id) r WHERE r.id = @id;
END
GO

-- Adds a leave type (@id NULL) or edits one. Rules that do not need the data (dependent fields,
-- slab ranges) are checked in the service; this checks names and the row version.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_type_save]
    @company_id                      BIGINT,
    @actor_user_id                   BIGINT = NULL,
    @id                              BIGINT = NULL,
    @title                           NVARCHAR(200),
    @short_code                      NVARCHAR(10),
    @allowance                       DECIMAL(6,2),
    @is_active                       BIT,
    @is_probation_type               BIT,
    @auto_allotment                  BIT,
    @auto_balance_on_joining         BIT,
    @is_composite                    BIT,
    @is_short_leave                  BIT,
    @show_in_payslip                 BIT,
    @is_deductible                   BIT,
    @is_sandwich                     BIT,
    @sandwich_across_types           BIT,
    @is_earned                       BIT,
    @allow_back_date                 BIT,
    @back_date_limit_days            INT = NULL,
    @has_future_limit                BIT,
    @future_limit_days               INT = NULL,
    @attachment_required             BIT,
    @attachment_rule                 NVARCHAR(30) = NULL,
    @allow_encashment                BIT,
    @encashment_min                  DECIMAL(6,2) = NULL,
    @encashment_max                  DECIMAL(6,2) = NULL,
    @carry_forward                   BIT,
    @pro_rated                       BIT,
    @gender                          NVARCHAR(30),
    @marital_status                  NVARCHAR(30),
    @allowed_in_probation            BIT,
    @min_experience_months           INT = NULL,
    @max_applications                INT = NULL,
    @gap_between_applications_months INT = NULL,
    @tenure                          NVARCHAR(30),
    @balance_basis                   NVARCHAR(30),
    @accumulative_count              INT = NULL,
    @experience_slabs                NVARCHAR(MAX) = NULL,
    @short_slabs                     NVARCHAR(MAX) = NULL,
    @row_version                     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = LTRIM(RTRIM(@title));
    SET @short_code = UPPER(LTRIM(RTRIM(@short_code)));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Title is required.', 1;
    IF @short_code IS NULL OR @short_code = N''
        THROW 50400, N'shortCode|Short code is required.', 1;
    IF @experience_slabs IS NOT NULL AND ISJSON(@experience_slabs) = 0
        THROW 50400, N'experienceSlabs|Experience slabs are not valid.', 1;
    IF @short_slabs IS NOT NULL AND ISJSON(@short_slabs) = 0
        THROW 50400, N'shortSlabs|Short leave slabs are not valid.', 1;
    IF EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE company_id = @company_id AND title = @title AND (@id IS NULL OR id <> @id))
        THROW 50409, N'title|LEAVE_TYPE_DUPLICATE|A leave type with this title already exists.', 1;
    IF EXISTS (SELECT 1 FROM [lv].[leave_type] WHERE company_id = @company_id AND short_code = @short_code AND (@id IS NULL OR id <> @id))
        THROW 50409, N'shortCode|LEAVE_TYPE_DUPLICATE|A leave type with this short code already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @old NVARCHAR(MAX), @new NVARCHAR(MAX);

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a leave type', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [lv].[leave_type] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Leave type not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this leave type. Reload it and try again', 1;
        SET @old = (SELECT r.* FROM [lv].[fn_leave_type_rows](@company_id) r WHERE r.id = @id
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [lv].[leave_type] (company_id, title, short_code, allowance, is_active, is_probation_type, auto_allotment,
                auto_balance_on_joining, is_composite, is_short_leave, show_in_payslip, is_deductible, is_sandwich,
                sandwich_across_types, is_earned, allow_back_date, back_date_limit_days, has_future_limit, future_limit_days,
                attachment_required, attachment_rule, allow_encashment, encashment_min, encashment_max, carry_forward,
                pro_rated, gender, marital_status, allowed_in_probation, min_experience_months, max_applications,
                gap_between_applications_months, tenure, balance_basis, accumulative_count, created_by)
            VALUES (@company_id, @title, @short_code, @allowance, @is_active, @is_probation_type, @auto_allotment,
                @auto_balance_on_joining, @is_composite, @is_short_leave, @show_in_payslip, @is_deductible, @is_sandwich,
                @sandwich_across_types, @is_earned, @allow_back_date, @back_date_limit_days, @has_future_limit, @future_limit_days,
                @attachment_required, @attachment_rule, @allow_encashment, @encashment_min, @encashment_max, @carry_forward,
                @pro_rated, @gender, @marital_status, @allowed_in_probation, @min_experience_months, @max_applications,
                @gap_between_applications_months, @tenure, @balance_basis, @accumulative_count, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'lv.leave_type', @id, N'title', @title, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [lv].[leave_type]
            SET title = @title, short_code = @short_code, allowance = @allowance, is_active = @is_active,
                is_probation_type = @is_probation_type, auto_allotment = @auto_allotment,
                auto_balance_on_joining = @auto_balance_on_joining, is_composite = @is_composite,
                is_short_leave = @is_short_leave, show_in_payslip = @show_in_payslip, is_deductible = @is_deductible,
                is_sandwich = @is_sandwich, sandwich_across_types = @sandwich_across_types, is_earned = @is_earned,
                allow_back_date = @allow_back_date, back_date_limit_days = @back_date_limit_days,
                has_future_limit = @has_future_limit, future_limit_days = @future_limit_days,
                attachment_required = @attachment_required, attachment_rule = @attachment_rule,
                allow_encashment = @allow_encashment, encashment_min = @encashment_min, encashment_max = @encashment_max,
                carry_forward = @carry_forward, pro_rated = @pro_rated, gender = @gender, marital_status = @marital_status,
                allowed_in_probation = @allowed_in_probation, min_experience_months = @min_experience_months,
                max_applications = @max_applications, gap_between_applications_months = @gap_between_applications_months,
                tenure = @tenure, balance_basis = @balance_basis, accumulative_count = @accumulative_count,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this leave type. Reload it and try again', 1;

            DELETE [lv].[leave_type_experience_slab] WHERE leave_type_id = @id;
            DELETE [lv].[leave_type_short_slab] WHERE leave_type_id = @id;
        END

        INSERT [lv].[leave_type_experience_slab] (leave_type_id, min_months, max_months, balance, created_by)
        SELECT @id, j.min_months, j.max_months, j.balance, @actor_user_id
        FROM OPENJSON(@experience_slabs) WITH (min_months INT '$.minMonths', max_months INT '$.maxMonths',
                                               balance DECIMAL(6,2) '$.balance') j;

        INSERT [lv].[leave_type_short_slab] (leave_type_id, name, balance, value_type, slab_value, created_by)
        SELECT @id, j.name, j.balance, j.value_type, j.slab_value, @actor_user_id
        FROM OPENJSON(@short_slabs) WITH (name NVARCHAR(200) '$.name', balance DECIMAL(6,2) '$.balance',
                                          value_type NVARCHAR(30) '$.valueType', slab_value DECIMAL(9,2) '$.value') j;

        IF @old IS NOT NULL
        BEGIN
            SET @new = (SELECT r.* FROM [lv].[fn_leave_type_rows](@company_id) r WHERE r.id = @id
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'lv.leave_type', @id, n.[key], o.value, n.value, N'update', @actor_user_id, @now
            FROM OPENJSON(@new) n
            LEFT JOIN OPENJSON(@old) o ON o.[key] = n.[key]
            WHERE n.[key] NOT IN (N'id', N'in_use', N'created_at', N'updated_at', N'row_version')
              AND EXISTS (SELECT o.value EXCEPT SELECT n.value);
        END
    COMMIT;

    EXEC [lv].[usp_leave_type_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_type_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @title NVARCHAR(200);
    SELECT @rv = row_version, @title = title FROM [lv].[leave_type] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Leave type not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this leave type. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [lv].[leave_ledger] WHERE leave_type_id = @id)
       OR EXISTS (SELECT 1 FROM [req].[req_leave] WHERE leave_type_id = @id)
        THROW 50409, N'This leave type has balances or leave requests. Make it inactive instead', 1;
    IF EXISTS (SELECT 1 FROM [lv].[leave_policy_type] WHERE leave_type_id = @id)
        THROW 50409, N'A leave policy gives this leave type. Remove it from the policy first', 1;

    BEGIN TRAN;
        DELETE [lv].[leave_type_experience_slab] WHERE leave_type_id = @id;
        DELETE [lv].[leave_type_short_slab] WHERE leave_type_id = @id;
        -- Anything else still pointing here (overtime policy slabs, penalty rules) stops the delete with error 547.
        DELETE [lv].[leave_type] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'lv.leave_type', @id, N'title', @title, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
