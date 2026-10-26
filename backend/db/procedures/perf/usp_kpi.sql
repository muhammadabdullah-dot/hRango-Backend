-- Performance -> KPIs: the KPI library, grouped by key result area. Forms rate KPIs as criteria and
-- goals may track one; a KPI in use cannot be deleted.

CREATE OR ALTER PROCEDURE [perf].[usp_kpi_list]
    @company_id      BIGINT,
    @search          NVARCHAR(200) = NULL,
    @key_result_area NVARCHAR(200) = NULL,
    @department_id   BIGINT = NULL,
    @is_active       BIT = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total FROM [perf].[kpi] k
    WHERE k.company_id = @company_id
      AND (@pattern IS NULL OR k.name LIKE @pattern OR k.key_result_area LIKE @pattern)
      AND (@key_result_area IS NULL OR k.key_result_area = @key_result_area)
      AND (@department_id IS NULL OR k.department_id = @department_id)
      AND (@is_active IS NULL OR k.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT r.* FROM [perf].[fn_kpi_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern OR r.key_result_area LIKE @pattern)
      AND (@key_result_area IS NULL OR r.key_result_area = @key_result_area)
      AND (@department_id IS NULL OR r.department_id = @department_id)
      AND (@is_active IS NULL OR r.is_active = @is_active)
    ORDER BY r.key_result_area, r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_kpi_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [perf].[kpi] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'KPI not found', 1;
    SELECT r.* FROM [perf].[fn_kpi_rows](@company_id) r WHERE r.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_kpi_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @key_result_area NVARCHAR(200) = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @measure_type    NVARCHAR(30),
    @target_value    DECIMAL(18,2) = NULL,
    @unit            NVARCHAR(30) = NULL,
    @default_weight  DECIMAL(5,2) = NULL,
    @department_id   BIGINT = NULL,
    @job_title_id    BIGINT = NULL,
    @is_active       BIT,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    SET @key_result_area = NULLIF(LTRIM(RTRIM(@key_result_area)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50400, N'jobTitleId|Job title not found.', 1;
    IF EXISTS (SELECT 1 FROM [perf].[kpi] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|KPI_DUPLICATE|A KPI with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [perf].[kpi] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'KPI not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this KPI. Reload it and try again', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [perf].[kpi] (company_id, name, key_result_area, description, measure_type, target_value, unit, default_weight,
                                 department_id, job_title_id, is_active, created_by)
            VALUES (@company_id, @name, @key_result_area, @description, @measure_type, @target_value, @unit, @default_weight,
                    @department_id, @job_title_id, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'perf.kpi', @id, N'name', @name, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [perf].[kpi]
            SET name = @name, key_result_area = @key_result_area, description = @description, measure_type = @measure_type,
                target_value = @target_value, unit = @unit, default_weight = @default_weight, department_id = @department_id,
                job_title_id = @job_title_id, is_active = @is_active, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this KPI. Reload it and try again', 1;
        END
    COMMIT;

    EXEC [perf].[usp_kpi_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_kpi_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @name NVARCHAR(200);
    SELECT @rv = row_version, @name = name FROM [perf].[kpi] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'KPI not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this KPI. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [perf].[appraisal_criterion] WHERE kpi_id = @id) OR EXISTS (SELECT 1 FROM [perf].[goal] WHERE kpi_id = @id)
        THROW 50409, N'id|KPI_IN_USE|An appraisal form or a goal uses this KPI. Make it inactive instead', 1;
    BEGIN TRAN;
        DELETE [perf].[kpi] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.kpi', @id, N'name', @name, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
