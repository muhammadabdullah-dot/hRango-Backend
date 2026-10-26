-- Performance -> Settings: Rating Scales and Appraisal Forms. Levels and criteria travel with their parent
-- as JSON. A scale or form that a launched cycle uses keeps its levels and criteria (appraisals rated on
-- them would change meaning); its name and switches may still change.

CREATE OR ALTER PROCEDURE [perf].[usp_rating_scale_list]
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

    SELECT COUNT(*) AS total FROM [perf].[rating_scale] s
    WHERE s.company_id = @company_id AND (@pattern IS NULL OR s.name LIKE @pattern)
      AND (@is_active IS NULL OR s.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT r.* FROM [perf].[fn_rating_scale_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern) AND (@is_active IS NULL OR r.is_active = @is_active)
    ORDER BY r.is_default DESC, r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_rating_scale_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [perf].[rating_scale] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Rating scale not found', 1;
    SELECT r.* FROM [perf].[fn_rating_scale_rows](@company_id) r WHERE r.id = @id;
END
GO

-- @levels: [{"score", "label", "description"}]; the service checks there are at least two and scores differ.
CREATE OR ALTER PROCEDURE [perf].[usp_rating_scale_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @is_default    BIT,
    @is_active     BIT,
    @levels        NVARCHAR(MAX),
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF ISJSON(@levels) = 0
        THROW 50400, N'levels|Levels are not valid.', 1;
    IF EXISTS (SELECT 1 FROM [perf].[rating_scale] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|RATING_SCALE_DUPLICATE|A rating scale with this name already exists.', 1;

    DECLARE @new TABLE (score DECIMAL(5,2), label NVARCHAR(100), description NVARCHAR(MAX));
    INSERT @new SELECT j.score, LTRIM(RTRIM(j.label)), j.description
    FROM OPENJSON(@levels) WITH (score DECIMAL(5,2) '$.score', label NVARCHAR(100) '$.label',
                                 description NVARCHAR(MAX) '$.description') j;

    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [perf].[rating_scale] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Rating scale not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this rating scale. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [perf].[appraisal_form] f JOIN [perf].[appraisal_cycle] c ON c.appraisal_form_id = f.id
                   WHERE f.rating_scale_id = @id AND c.status <> N'draft')
           AND (EXISTS (SELECT score, label FROM @new EXCEPT SELECT score, label FROM [perf].[rating_scale_level] WHERE rating_scale_id = @id)
                OR EXISTS (SELECT score, label FROM [perf].[rating_scale_level] WHERE rating_scale_id = @id EXCEPT SELECT score, label FROM @new))
            THROW 50409, N'levels|SCALE_IN_USE|A launched appraisal cycle rates on this scale. Its levels cannot change.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @is_default = 1
            UPDATE [perf].[rating_scale] SET is_default = 0, updated_at = @now, updated_by = @actor_user_id
            WHERE company_id = @company_id AND is_default = 1 AND (@id IS NULL OR id <> @id);
        IF @id IS NULL
        BEGIN
            INSERT [perf].[rating_scale] (company_id, name, is_default, is_active, created_by)
            VALUES (@company_id, @name, @is_default, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'perf.rating_scale', @id, N'name', @name, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [perf].[rating_scale]
            SET name = @name, is_default = @is_default, is_active = @is_active, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this rating scale. Reload it and try again', 1;
        END
        -- Levels are matched on their score, so unchanged levels keep their rows.
        DELETE l FROM [perf].[rating_scale_level] l
        WHERE l.rating_scale_id = @id AND NOT EXISTS (SELECT 1 FROM @new n WHERE n.score = l.score);
        UPDATE l SET label = n.label, description = n.description, updated_at = @now, updated_by = @actor_user_id
        FROM [perf].[rating_scale_level] l JOIN @new n ON n.score = l.score
        WHERE l.rating_scale_id = @id;
        INSERT [perf].[rating_scale_level] (rating_scale_id, score, label, description, created_by)
        SELECT @id, n.score, n.label, n.description, @actor_user_id FROM @new n
        WHERE NOT EXISTS (SELECT 1 FROM [perf].[rating_scale_level] l WHERE l.rating_scale_id = @id AND l.score = n.score);
    COMMIT;

    EXEC [perf].[usp_rating_scale_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_rating_scale_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @name NVARCHAR(200);
    SELECT @rv = row_version, @name = name FROM [perf].[rating_scale] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Rating scale not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this rating scale. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [perf].[appraisal_form] WHERE rating_scale_id = @id)
        THROW 50409, N'id|SCALE_IN_USE|An appraisal form uses this scale. Make it inactive instead', 1;
    BEGIN TRAN;
        DELETE [perf].[rating_scale_level] WHERE rating_scale_id = @id;
        DELETE [perf].[rating_scale] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.rating_scale', @id, N'name', @name, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_form_list]
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

    SELECT COUNT(*) AS total FROM [perf].[appraisal_form] f
    WHERE f.company_id = @company_id AND (@pattern IS NULL OR f.name LIKE @pattern)
      AND (@is_active IS NULL OR f.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT r.* FROM [perf].[fn_appraisal_form_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.name LIKE @pattern) AND (@is_active IS NULL OR r.is_active = @is_active)
    ORDER BY r.name, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_form_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [perf].[appraisal_form] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Appraisal form not found', 1;
    SELECT r.* FROM [perf].[fn_appraisal_form_rows](@company_id) r WHERE r.id = @id;
END
GO

-- @criteria: [{"kpiId", "name", "description", "weight"}] in display order. The service checks that the
-- criteria weights and the goals weight make 100.
CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_form_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT = NULL,
    @id              BIGINT = NULL,
    @name            NVARCHAR(200),
    @description     NVARCHAR(MAX) = NULL,
    @rating_scale_id BIGINT,
    @goals_weight    DECIMAL(5,2),
    @has_self_review BIT,
    @is_active       BIT,
    @criteria        NVARCHAR(MAX),
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF ISJSON(@criteria) = 0
        THROW 50400, N'criteria|Criteria are not valid.', 1;
    IF NOT EXISTS (SELECT 1 FROM [perf].[rating_scale] WHERE id = @rating_scale_id AND company_id = @company_id)
        THROW 50400, N'ratingScaleId|Rating scale not found.', 1;
    IF (SELECT COUNT(*) FROM [perf].[rating_scale_level] WHERE rating_scale_id = @rating_scale_id) < 2
        THROW 50400, N'ratingScaleId|The rating scale needs at least two levels.', 1;
    IF EXISTS (SELECT 1 FROM [perf].[appraisal_form] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|APPRAISAL_FORM_DUPLICATE|An appraisal form with this name already exists.', 1;

    DECLARE @new TABLE (seq INT, kpi_id BIGINT, name NVARCHAR(200), description NVARCHAR(MAX), weight DECIMAL(5,2));
    INSERT @new
    SELECT CONVERT(INT, j.[key]) + 1, x.kpi_id, LTRIM(RTRIM(x.name)), x.description, x.weight
    FROM OPENJSON(@criteria) j
    CROSS APPLY OPENJSON(j.[value]) WITH (kpi_id BIGINT '$.kpiId', name NVARCHAR(200) '$.name',
                                          description NVARCHAR(MAX) '$.description', weight DECIMAL(5,2) '$.weight') x;
    IF EXISTS (SELECT 1 FROM @new n WHERE n.kpi_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM [perf].[kpi] k WHERE k.id = n.kpi_id AND k.company_id = @company_id))
        THROW 50400, N'criteria|A KPI on the form was not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8), @old_scale BIGINT, @old_gw DECIMAL(5,2), @old_self BIT;
        SELECT @rv = row_version, @old_scale = rating_scale_id, @old_gw = goals_weight, @old_self = has_self_review
        FROM [perf].[appraisal_form] WHERE id = @id AND company_id = @company_id;
        IF @rv IS NULL
            THROW 50404, N'Appraisal form not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this appraisal form. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] WHERE appraisal_form_id = @id AND status <> N'draft')
           AND (@old_scale <> @rating_scale_id OR @old_gw <> @goals_weight OR @old_self <> @has_self_review
                OR EXISTS (SELECT ISNULL(kpi_id, 0), name, weight FROM @new
                           EXCEPT SELECT ISNULL(kpi_id, 0), name, weight FROM [perf].[appraisal_criterion] WHERE appraisal_form_id = @id)
                OR EXISTS (SELECT ISNULL(kpi_id, 0), name, weight FROM [perf].[appraisal_criterion] WHERE appraisal_form_id = @id
                           EXCEPT SELECT ISNULL(kpi_id, 0), name, weight FROM @new))
            THROW 50409, N'criteria|FORM_IN_USE|A launched appraisal cycle uses this form. Its scale, weights and criteria cannot change.', 1;
    END

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [perf].[appraisal_form] (company_id, name, description, rating_scale_id, goals_weight, has_self_review, is_active, created_by)
            VALUES (@company_id, @name, @description, @rating_scale_id, @goals_weight, @has_self_review, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'perf.appraisal_form', @id, N'name', @name, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [perf].[appraisal_form]
            SET name = @name, description = @description, rating_scale_id = @rating_scale_id, goals_weight = @goals_weight,
                has_self_review = @has_self_review, is_active = @is_active, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this appraisal form. Reload it and try again', 1;
        END
        -- Criteria are kept when only their wording or order changes (ratings point at them).
        IF NOT EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] WHERE appraisal_form_id = @id AND status <> N'draft')
        BEGIN
            DELETE [perf].[appraisal_criterion] WHERE appraisal_form_id = @id;
            INSERT [perf].[appraisal_criterion] (appraisal_form_id, kpi_id, name, description, weight, sort_order, created_by)
            SELECT @id, n.kpi_id, n.name, n.description, n.weight, n.seq, @actor_user_id FROM @new n;
        END
        ELSE
            UPDATE c SET description = n.description, sort_order = n.seq, updated_at = @now, updated_by = @actor_user_id
            FROM [perf].[appraisal_criterion] c
            JOIN @new n ON n.name = c.name AND ISNULL(n.kpi_id, 0) = ISNULL(c.kpi_id, 0) AND n.weight = c.weight
            WHERE c.appraisal_form_id = @id;
    COMMIT;

    EXEC [perf].[usp_appraisal_form_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_appraisal_form_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @name NVARCHAR(200);
    SELECT @rv = row_version, @name = name FROM [perf].[appraisal_form] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Appraisal form not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this appraisal form. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [perf].[appraisal_cycle] WHERE appraisal_form_id = @id)
        THROW 50409, N'id|FORM_IN_USE|An appraisal cycle uses this form. Make it inactive instead', 1;
    BEGIN TRAN;
        DELETE [perf].[appraisal_criterion] WHERE appraisal_form_id = @id;
        DELETE [perf].[appraisal_form] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.appraisal_form', @id, N'name', @name, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
