-- The organisation's logo (General Settings): shown in the app's sidebar for everyone in the company.
-- @file_id NULL removes it. The file is an upload of this company (core.fn_file_usable).
CREATE OR ALTER PROCEDURE [org].[usp_company_logo_set]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @file_id       BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[stored_file]
                                            WHERE id = @file_id AND extension IN (N'png', N'jpg', N'jpeg', N'gif', N'webp'))
        THROW 50400, N'fileId|LOGO_NOT_IMAGE|The logo must be an image (PNG, JPG, GIF or WEBP).', 1;

    DECLARE @old BIGINT = (SELECT logo_file_id FROM [org].[company] WHERE id = @company_id);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [org].[company] SET logo_file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @company_id;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name,
                                   performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.company', @company_id, N'logo_file_id', CONVERT(NVARCHAR(30), @old),
                CONVERT(NVARCHAR(30), @file_id), N'update', @actor_user_id, @now);
    COMMIT;
    EXEC [org].[usp_company_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @company_id;
END
