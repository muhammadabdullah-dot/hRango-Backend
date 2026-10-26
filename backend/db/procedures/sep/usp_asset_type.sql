-- Assets -> Asset Types. Codes AITP-00001 (the FRD's example code).
CREATE OR ALTER PROCEDURE [sep].[usp_asset_type_list]
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
    FROM [sep].[asset_type] t
    WHERE t.company_id = @company_id
      AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
      AND (@is_active IS NULL OR t.is_active = @is_active)
    OPTION (RECOMPILE);

    SELECT t.id, t.code, t.name, t.description, t.is_active,
           (SELECT COUNT(*) FROM [sep].[asset] a WHERE a.asset_type_id = t.id) AS asset_count,
           t.created_at, t.updated_at, t.row_version
    FROM [sep].[asset_type] t
    WHERE t.company_id = @company_id
      AND (@pattern IS NULL OR t.name LIKE @pattern OR t.code LIKE @pattern)
      AND (@is_active IS NULL OR t.is_active = @is_active)
    ORDER BY t.name, t.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [sep].[usp_asset_type_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[asset_type] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Asset type not found', 1;

    SELECT t.id, t.code, t.name, t.description, t.is_active,
           (SELECT COUNT(*) FROM [sep].[asset] a WHERE a.asset_type_id = t.id) AS asset_count,
           t.created_at, t.updated_at, t.row_version
    FROM [sep].[asset_type] t
    WHERE t.id = @id AND t.company_id = @company_id;
END
GO

-- Adds an asset type (@id NULL) or edits one (@id and the @row_version last read).
CREATE OR ALTER PROCEDURE [sep].[usp_asset_type_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @description   NVARCHAR(MAX) = NULL,
    @is_active     BIT = 1,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Asset type name is required.', 1;
    IF EXISTS (SELECT 1 FROM [sep].[asset_type] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|ASSET_TYPE_DUPLICATE|An asset type with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            EXEC [sep].[usp_number_next] @company_id = @company_id, @prefix = N'AITP', @code = @code OUTPUT;
            INSERT [sep].[asset_type] (company_id, code, name, description, is_active, created_by)
            VALUES (@company_id, @code, @name, @description, ISNULL(@is_active, 1), @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an asset type.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [sep].[asset_type] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Asset type not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this asset type. Reload it and try again', 1;

        UPDATE [sep].[asset_type]
        SET name = @name, description = @description, is_active = ISNULL(@is_active, 1),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this asset type. Reload it and try again', 1;
    END

    EXEC [sep].[usp_asset_type_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [sep].[usp_asset_type_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [sep].[asset_type] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Asset type not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this asset type. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [sep].[asset] WHERE asset_type_id = @id)
        THROW 50409, N'id|ASSET_TYPE_IN_USE|Assets of this type exist, so it cannot be deleted. Deactivate the type instead.', 1;

    DELETE [sep].[asset_type] WHERE id = @id AND company_id = @company_id;
END
