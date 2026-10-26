-- Assets -> Company Assets. Status is what the asset is (active, damaged, lost, decommissioned);
-- availability adds who holds it: allocated (an open allocation), available (active, nobody holds
-- it) or unavailable. Every change goes to core.audit_log for the History popup.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_list]
    @company_id    BIGINT,
    @search        NVARCHAR(200) = NULL,
    @status        NVARCHAR(30) = NULL,
    @availability  NVARCHAR(30) = NULL,
    @asset_type_id BIGINT = NULL,
    @page          INT = 1,
    @page_size     INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    WITH x AS (
        SELECT a.id, a.name, a.code, a.identification_no, a.status, a.asset_type_id,
               CASE WHEN h.employee_id IS NOT NULL THEN N'allocated'
                    WHEN a.status = N'active' THEN N'available' ELSE N'unavailable' END AS availability
        FROM [sep].[asset] a
        OUTER APPLY (SELECT TOP 1 al.employee_id FROM [sep].[asset_allocation] al
                     WHERE al.asset_id = a.id AND al.deallocated_on IS NULL) h
        WHERE a.company_id = @company_id
    )
    SELECT COUNT(*) AS total
    FROM x
    WHERE (@pattern IS NULL OR x.name LIKE @pattern OR x.code LIKE @pattern OR x.identification_no LIKE @pattern)
      AND (@status IS NULL OR x.status = @status)
      AND (@availability IS NULL OR x.availability = @availability)
      AND (@asset_type_id IS NULL OR x.asset_type_id = @asset_type_id)
    OPTION (RECOMPILE);

    WITH x AS (
        SELECT a.*, h.employee_id AS holder_id,
               CASE WHEN h.employee_id IS NOT NULL THEN N'allocated'
                    WHEN a.status = N'active' THEN N'available' ELSE N'unavailable' END AS availability
        FROM [sep].[asset] a
        OUTER APPLY (SELECT TOP 1 al.employee_id FROM [sep].[asset_allocation] al
                     WHERE al.asset_id = a.id AND al.deallocated_on IS NULL) h
        WHERE a.company_id = @company_id
    )
    SELECT x.id, x.code, x.name, x.asset_type_id, t.name AS asset_type_name, x.identification_no, x.is_taxable,
           x.asset_condition, x.manufacturer, x.model, x.current_value, x.acquired_date, x.description,
           x.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = x.file_id) AS file_name,
           x.status, x.availability, x.holder_id, e.code AS holder_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS holder_name,
           x.created_at, x.updated_at, x.row_version
    FROM x
    JOIN [sep].[asset_type] t ON t.id = x.asset_type_id
    LEFT JOIN [hr].[employee] e ON e.id = x.holder_id
    WHERE (@pattern IS NULL OR x.name LIKE @pattern OR x.code LIKE @pattern OR x.identification_no LIKE @pattern)
      AND (@status IS NULL OR x.status = @status)
      AND (@availability IS NULL OR x.availability = @availability)
      AND (@asset_type_id IS NULL OR x.asset_type_id = @asset_type_id)
    ORDER BY x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [sep].[usp_asset_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[asset] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Asset not found', 1;

    SELECT a.id, a.code, a.name, a.asset_type_id, t.name AS asset_type_name, a.identification_no, a.is_taxable,
           a.asset_condition, a.manufacturer, a.model, a.current_value, a.acquired_date, a.description,
           a.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = a.file_id) AS file_name,
           a.status,
           CASE WHEN h.employee_id IS NOT NULL THEN N'allocated'
                WHEN a.status = N'active' THEN N'available' ELSE N'unavailable' END AS availability,
           h.employee_id AS holder_id, e.code AS holder_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS holder_name,
           a.created_at, a.updated_at, a.row_version
    FROM [sep].[asset] a
    JOIN [sep].[asset_type] t ON t.id = a.asset_type_id
    OUTER APPLY (SELECT TOP 1 al.employee_id FROM [sep].[asset_allocation] al
                 WHERE al.asset_id = a.id AND al.deallocated_on IS NULL) h
    LEFT JOIN [hr].[employee] e ON e.id = h.employee_id
    WHERE a.id = @id AND a.company_id = @company_id;
END
GO

-- Adds an asset (@id NULL) or edits one (@id and the @row_version last read). Returns the saved row.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_save]
    @company_id        BIGINT,
    @actor_user_id     BIGINT = NULL,
    @id                BIGINT = NULL,
    @name              NVARCHAR(200),
    @asset_type_id     BIGINT,
    @identification_no NVARCHAR(100) = NULL,
    @is_taxable        BIT = 0,
    @asset_condition   NVARCHAR(30),
    @manufacturer      NVARCHAR(100) = NULL,
    @model             NVARCHAR(100) = NULL,
    @current_value     DECIMAL(18,2) = NULL,
    @acquired_date     DATE = NULL,
    @description       NVARCHAR(MAX) = NULL,
    @file_id           BIGINT = NULL,
    @row_version       BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @identification_no = NULLIF(LTRIM(RTRIM(@identification_no)), N'');
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Asset name is required.', 1;
    IF @asset_condition IS NULL OR @asset_condition NOT IN (N'old', N'new', N'fair')
        THROW 50400, N'assetCondition|Condition must be old, new or fair.', 1;
    IF @current_value < 0
        THROW 50400, N'currentValue|Current value cannot be negative.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    DECLARE @type_active BIT = (SELECT is_active FROM [sep].[asset_type] WHERE id = @asset_type_id AND company_id = @company_id);
    IF @type_active IS NULL
        THROW 50400, N'assetTypeId|Asset type not found.', 1;
    IF @type_active = 0 AND (@id IS NULL OR NOT EXISTS (SELECT 1 FROM [sep].[asset] WHERE id = @id AND asset_type_id = @asset_type_id))
        THROW 50400, N'assetTypeId|This asset type is inactive.', 1;
    IF @identification_no IS NOT NULL AND EXISTS (SELECT 1 FROM [sep].[asset] WHERE company_id = @company_id
            AND identification_no = @identification_no AND (@id IS NULL OR id <> @id))
        THROW 50409, N'identificationNo|ASSET_DUPLICATE|Another asset has this identification number.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            EXEC [sep].[usp_number_next] @company_id = @company_id, @prefix = N'AST', @code = @code OUTPUT;
            INSERT [sep].[asset] (company_id, code, asset_type_id, name, identification_no, is_taxable, asset_condition,
                                  manufacturer, model, current_value, acquired_date, description, status, file_id, created_by)
            VALUES (@company_id, @code, @asset_type_id, @name, @identification_no, ISNULL(@is_taxable, 0), @asset_condition,
                    @manufacturer, @model, @current_value, @acquired_date, @description, N'active', @file_id, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'sep.asset', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an asset.', 1;

        DECLARE @o_name NVARCHAR(200), @o_type BIGINT, @o_ident NVARCHAR(100), @o_tax BIT, @o_cond NVARCHAR(30),
                @o_manu NVARCHAR(100), @o_model NVARCHAR(100), @o_value DECIMAL(18,2), @o_acq DATE,
                @o_desc NVARCHAR(MAX), @o_file BIGINT, @o_rv BINARY(8);
        SELECT @o_name = name, @o_type = asset_type_id, @o_ident = identification_no, @o_tax = is_taxable,
               @o_cond = asset_condition, @o_manu = manufacturer, @o_model = model, @o_value = current_value,
               @o_acq = acquired_date, @o_desc = description, @o_file = file_id, @o_rv = row_version
        FROM [sep].[asset] WHERE id = @id AND company_id = @company_id;

        IF @o_rv IS NULL
            THROW 50404, N'Asset not found', 1;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed this asset. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [sep].[asset]
            SET name = @name, asset_type_id = @asset_type_id, identification_no = @identification_no,
                is_taxable = ISNULL(@is_taxable, 0), asset_condition = @asset_condition, manufacturer = @manufacturer,
                model = @model, current_value = @current_value, acquired_date = @acquired_date,
                description = @description, file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this asset. Reload it and try again', 1;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT N'sep.asset', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @o_name, @name),
                (N'asset_type_id', CONVERT(NVARCHAR(30), @o_type), CONVERT(NVARCHAR(30), @asset_type_id)),
                (N'identification_no', @o_ident, @identification_no),
                (N'is_taxable', CONVERT(NVARCHAR(5), @o_tax), CONVERT(NVARCHAR(5), ISNULL(@is_taxable, 0))),
                (N'asset_condition', @o_cond, @asset_condition),
                (N'manufacturer', @o_manu, @manufacturer),
                (N'model', @o_model, @model),
                (N'current_value', CONVERT(NVARCHAR(40), @o_value), CONVERT(NVARCHAR(40), @current_value)),
                (N'acquired_date', CONVERT(NVARCHAR(10), @o_acq, 23), CONVERT(NVARCHAR(10), @acquired_date, 23)),
                (N'description', @o_desc, @description),
                (N'file_id', CONVERT(NVARCHAR(30), @o_file), CONVERT(NVARCHAR(30), @file_id))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [sep].[usp_asset_get] @company_id = @company_id, @id = @id;
END
GO

-- Deactivate (@active = 0: decommissioned) or Activate (@active = 1: back to active).
CREATE OR ALTER PROCEDURE [sep].[usp_asset_set_active]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @active        BIT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @old NVARCHAR(30);
    SELECT @rv = row_version, @old = status FROM [sep].[asset] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Asset not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this asset. Reload it and try again', 1;

    DECLARE @new NVARCHAR(30) = CASE WHEN @active = 1 THEN N'active' ELSE N'decommissioned' END;
    IF @active = 0 AND EXISTS (SELECT 1 FROM [sep].[asset_allocation] WHERE asset_id = @id AND deallocated_on IS NULL)
        THROW 50409, N'status|ASSET_ALLOCATED|This asset is allocated. Deallocate it first.', 1;

    IF @new <> @old
    BEGIN
        DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
        BEGIN TRAN;
            UPDATE [sep].[asset] SET status = @new, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this asset. Reload it and try again', 1;

            INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (N'sep.asset', @id, N'status', @old, @new, CASE WHEN @active = 1 THEN N'activate' ELSE N'deactivate' END,
                    @actor_user_id, @now);
        COMMIT;
    END

    EXEC [sep].[usp_asset_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [sep].[usp_asset_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sep].[asset] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Asset not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this asset. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sep].[asset_allocation] WHERE asset_id = @id)
        THROW 50409, N'This asset has been allocated before. Deactivate it instead.', 1;

    BEGIN TRAN;
        DELETE [sep].[asset] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.asset', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Asset History: every audit row for the asset, newest first, with who did it.
CREATE OR ALTER PROCEDURE [sep].[usp_asset_history]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[asset] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Asset not found', 1;

    SELECT l.id, l.action_name, l.field_name, l.old_value, l.new_value, l.performed_at,
           l.performed_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS performed_by_name
    FROM [core].[audit_log] l
    LEFT JOIN [auth].[user_account] u ON u.id = l.performed_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE l.entity_type = N'sep.asset' AND l.entity_id = @id
    ORDER BY l.performed_at DESC, l.id DESC;
END
