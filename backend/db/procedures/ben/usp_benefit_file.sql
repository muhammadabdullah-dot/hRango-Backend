-- Benefits -> Files: the attachments of benefit plans (core.attachment, entity_type ben.benefit_plan).
-- The file is uploaded first (POST /api/files); these link it to a plan. The API adds signed download links.

-- Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_file_list]
    @company_id   BIGINT,
    @search       NVARCHAR(200) = NULL,
    @plan_id      BIGINT = NULL,
    @plan_year_id BIGINT = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [core].[attachment] a
    JOIN [ben].[benefit_plan] b ON b.id = a.entity_id AND b.company_id = @company_id
    JOIN [core].[stored_file] f ON f.id = a.file_id
    WHERE a.company_id = @company_id AND a.entity_type = N'ben.benefit_plan'
      AND (@pattern IS NULL OR f.name LIKE @pattern OR b.name LIKE @pattern)
      AND (@plan_id IS NULL OR b.id = @plan_id)
      AND (@plan_year_id IS NULL OR EXISTS (SELECT 1 FROM [ben].[plan_year_plan] pp WHERE pp.plan_year_id = @plan_year_id AND pp.benefit_plan_id = b.id))
    OPTION (RECOMPILE);

    SELECT a.id, a.file_id, f.name AS file_name, f.mime_type, f.size_bytes, b.id AS plan_id, b.name AS plan_name,
           b.category, a.created_at, a.row_version
    FROM [core].[attachment] a
    JOIN [ben].[benefit_plan] b ON b.id = a.entity_id AND b.company_id = @company_id
    JOIN [core].[stored_file] f ON f.id = a.file_id
    WHERE a.company_id = @company_id AND a.entity_type = N'ben.benefit_plan'
      AND (@pattern IS NULL OR f.name LIKE @pattern OR b.name LIKE @pattern)
      AND (@plan_id IS NULL OR b.id = @plan_id)
      AND (@plan_year_id IS NULL OR EXISTS (SELECT 1 FROM [ben].[plan_year_plan] pp WHERE pp.plan_year_id = @plan_year_id AND pp.benefit_plan_id = b.id))
    ORDER BY a.created_at DESC, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Attaches an uploaded file to a plan. Returns the file row.
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_file_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @plan_id       BIGINT,
    @file_id       BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [ben].[benefit_plan] WHERE id = @plan_id AND company_id = @company_id)
        THROW 50404, N'Plan not found', 1;
    IF @file_id IS NULL OR NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF EXISTS (SELECT 1 FROM [core].[attachment] WHERE entity_type = N'ben.benefit_plan' AND entity_id = @plan_id AND file_id = @file_id)
        THROW 50409, N'fileId|FILE_DUPLICATE|This file is already attached to the plan.', 1;

    DECLARE @id BIGINT;
    BEGIN TRAN;
        INSERT [core].[attachment] (company_id, entity_type, entity_id, file_id, created_by)
        VALUES (@company_id, N'ben.benefit_plan', @plan_id, @file_id, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.benefit_plan', @plan_id, N'file', CAST(@file_id AS NVARCHAR(30)), N'attach', @actor_user_id, SYSUTCDATETIME());
    COMMIT;

    SELECT a.id, a.file_id, f.name AS file_name, f.mime_type, f.size_bytes, b.id AS plan_id, b.name AS plan_name,
           b.category, a.created_at, a.row_version
    FROM [core].[attachment] a
    JOIN [ben].[benefit_plan] b ON b.id = a.entity_id
    JOIN [core].[stored_file] f ON f.id = a.file_id
    WHERE a.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [ben].[usp_benefit_file_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @plan_id BIGINT, @file_id BIGINT;
    SELECT @rv = a.row_version, @plan_id = a.entity_id, @file_id = a.file_id
    FROM [core].[attachment] a
    JOIN [ben].[benefit_plan] b ON b.id = a.entity_id AND b.company_id = @company_id
    WHERE a.id = @id AND a.company_id = @company_id AND a.entity_type = N'ben.benefit_plan';
    IF @rv IS NULL
        THROW 50404, N'File not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this file. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [core].[attachment] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'ben.benefit_plan', @plan_id, N'file', CAST(@file_id AS NVARCHAR(30)), N'detach', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
