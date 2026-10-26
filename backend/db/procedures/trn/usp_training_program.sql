-- Training -> Programs: the courses, with their materials (uploaded files as core.attachment rows,
-- entity_type 'trn.training_program'). A program with sessions cannot be deleted.

CREATE OR ALTER PROCEDURE [trn].[usp_training_program_list]
    @company_id           BIGINT,
    @search               NVARCHAR(200) = NULL,
    @training_category_id BIGINT = NULL,
    @delivery_mode        NVARCHAR(30) = NULL,
    @is_active            BIT = NULL,
    @page                 INT = 1,
    @page_size            INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    SELECT COUNT(*) AS total FROM [trn].[training_program] p
    WHERE p.company_id = @company_id
      AND (@pattern IS NULL OR p.title LIKE @pattern OR p.provider_name LIKE @pattern)
      AND (@training_category_id IS NULL OR p.training_category_id = @training_category_id)
      AND (@delivery_mode IS NULL OR p.delivery_mode = @delivery_mode)
      AND (@is_active IS NULL OR p.is_active = @is_active)
    OPTION (RECOMPILE);
    SELECT r.* FROM [trn].[fn_program_rows](@company_id) r
    WHERE (@pattern IS NULL OR r.title LIKE @pattern OR r.provider_name LIKE @pattern)
      AND (@training_category_id IS NULL OR r.training_category_id = @training_category_id)
      AND (@delivery_mode IS NULL OR r.delivery_mode = @delivery_mode)
      AND (@is_active IS NULL OR r.is_active = @is_active)
    ORDER BY r.title, r.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_program_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [trn].[training_program] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Program not found', 1;
    SELECT r.* FROM [trn].[fn_program_rows](@company_id) r WHERE r.id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_program_save]
    @company_id                  BIGINT,
    @actor_user_id               BIGINT = NULL,
    @id                          BIGINT = NULL,
    @title                       NVARCHAR(200),
    @training_category_id        BIGINT = NULL,
    @description                 NVARCHAR(MAX) = NULL,
    @delivery_mode               NVARCHAR(30),
    @provider_type               NVARCHAR(30),
    @provider_name               NVARCHAR(200) = NULL,
    @duration_hours              DECIMAL(6,2) = NULL,
    @cost_per_head               DECIMAL(18,2) = NULL,
    @issues_certificate          BIT,
    @certificate_validity_months INT = NULL,
    @is_mandatory                BIT,
    @is_active                   BIT,
    @row_version                 BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @title = LTRIM(RTRIM(@title));
    IF @title IS NULL OR @title = N''
        THROW 50400, N'title|Title is required.', 1;
    IF @training_category_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [trn].[training_category] WHERE id = @training_category_id AND company_id = @company_id)
        THROW 50400, N'trainingCategoryId|Category not found.', 1;
    IF EXISTS (SELECT 1 FROM [trn].[training_program] WHERE company_id = @company_id AND title = @title AND (@id IS NULL OR id <> @id))
        THROW 50409, N'title|PROGRAM_DUPLICATE|A program with this title already exists.', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [trn].[training_program] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Program not found', 1;
        IF @row_version IS NULL OR @rv <> @row_version
            THROW 50409, N'Someone else changed this program. Reload it and try again', 1;
    END
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [trn].[training_program] (company_id, title, training_category_id, description, delivery_mode, provider_type,
                provider_name, duration_hours, cost_per_head, issues_certificate, certificate_validity_months, is_mandatory, is_active, created_by)
            VALUES (@company_id, @title, @training_category_id, @description, @delivery_mode, @provider_type, @provider_name,
                @duration_hours, @cost_per_head, @issues_certificate, @certificate_validity_months, @is_mandatory, @is_active, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'trn.training_program', @id, N'title', @title, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [trn].[training_program]
            SET title = @title, training_category_id = @training_category_id, description = @description, delivery_mode = @delivery_mode,
                provider_type = @provider_type, provider_name = @provider_name, duration_hours = @duration_hours,
                cost_per_head = @cost_per_head, issues_certificate = @issues_certificate,
                certificate_validity_months = @certificate_validity_months, is_mandatory = @is_mandatory, is_active = @is_active,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this program. Reload it and try again', 1;
        END
    COMMIT;
    EXEC [trn].[usp_training_program_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_program_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @title NVARCHAR(200);
    SELECT @rv = row_version, @title = title FROM [trn].[training_program] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Program not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this program. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [trn].[training_session] WHERE training_program_id = @id)
        THROW 50409, N'id|PROGRAM_IN_USE|This program has sessions. Make it inactive instead', 1;
    BEGIN TRAN;
        DELETE [core].[attachment] WHERE company_id = @company_id AND entity_type = N'trn.training_program' AND entity_id = @id;
        DELETE [trn].[training_program] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'trn.training_program', @id, N'title', @title, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Attaches an uploaded file as course material. Returns the program.
CREATE OR ALTER PROCEDURE [trn].[usp_training_material_add]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @file_id       BIGINT,
    @label         NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [trn].[training_program] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Program not found', 1;
    IF @file_id IS NULL OR NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF EXISTS (SELECT 1 FROM [core].[attachment] WHERE entity_type = N'trn.training_program' AND entity_id = @id AND file_id = @file_id)
        THROW 50409, N'fileId|MATERIAL_DUPLICATE|This file is already attached to the program.', 1;
    INSERT [core].[attachment] (company_id, entity_type, entity_id, file_id, label, created_by)
    VALUES (@company_id, N'trn.training_program', @id, @file_id, NULLIF(LTRIM(RTRIM(@label)), N''), @actor_user_id);
    EXEC [trn].[usp_training_program_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [trn].[usp_training_material_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @attachment_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DELETE [core].[attachment]
    WHERE id = @attachment_id AND company_id = @company_id AND entity_type = N'trn.training_program' AND entity_id = @id;
    IF @@ROWCOUNT = 0
        THROW 50404, N'Material not found', 1;
END
