-- Settings -> Rejection reasons: the reasons offered when an application is rejected
-- ("Not qualified", "Salary expectation too high" ...). Company-wide records.

CREATE OR ALTER PROCEDURE [rec].[usp_rejection_reason_list]
    @company_id  BIGINT,
    @search      NVARCHAR(200) = NULL,
    @active_only BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SELECT r.id, r.name, r.is_active, ISNULL(r.sort_order, 0) AS sort_order,
           (SELECT COUNT(*) FROM [rec].[application] a WHERE a.rejection_reason_id = r.id) AS usage_count,
           r.created_at, r.updated_at, r.row_version
    FROM [rec].[rejection_reason] r
    WHERE r.company_id = @company_id
      AND (@pattern IS NULL OR r.name LIKE @pattern)
      AND (ISNULL(@active_only, 0) = 0 OR r.is_active = 1)
    ORDER BY ISNULL(r.sort_order, 0), r.name;
END
GO

CREATE OR ALTER PROCEDURE [rec].[usp_rejection_reason_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @is_active     BIT = 1,
    @sort_order    INT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF EXISTS (SELECT 1 FROM [rec].[rejection_reason] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|REJECTION_REASON_DUPLICATE|A rejection reason with this name already exists.', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NULL
    BEGIN
        INSERT [rec].[rejection_reason] (company_id, name, is_active, sort_order, created_by)
        VALUES (@company_id, @name, ISNULL(@is_active, 1), @sort_order, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [rec].[rejection_reason] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Rejection reason not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this rejection reason. Reload it and try again', 1;
        UPDATE [rec].[rejection_reason]
        SET name = @name, is_active = ISNULL(@is_active, 1), sort_order = @sort_order, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this rejection reason. Reload it and try again', 1;
    END
    SELECT r.id, r.name, r.is_active, ISNULL(r.sort_order, 0) AS sort_order,
           (SELECT COUNT(*) FROM [rec].[application] a WHERE a.rejection_reason_id = r.id) AS usage_count,
           r.created_at, r.updated_at, r.row_version
    FROM [rec].[rejection_reason] r WHERE r.id = @id;
END
GO

-- A reason used on applications cannot be deleted; switch it off instead.
CREATE OR ALTER PROCEDURE [rec].[usp_rejection_reason_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8) = (SELECT row_version FROM [rec].[rejection_reason] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Rejection reason not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required to delete a rejection reason.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this rejection reason. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [rec].[application] WHERE rejection_reason_id = @id)
        THROW 50409, N'id|REJECTION_REASON_IN_USE|This reason is used on applications. Switch it off instead.', 1;
    DELETE FROM [rec].[rejection_reason] WHERE id = @id AND row_version = @row_version;
END
GO
