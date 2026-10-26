-- Attachments on a request (core.attachment, entity 'req.request'): files uploaded first
-- (POST /api/files) and attached by id. Added and removed by the requester side while the request
-- is pending. Removing an attachment leaves the file; its uploader may delete it.
CREATE OR ALTER PROCEDURE [req].[usp_request_attachment_add]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @type_code       NVARCHAR(30),
    @permission_code NVARCHAR(150),
    @file_id         BIGINT,
    @label           NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @status NVARCHAR(30), @employee_id BIGINT;
    SELECT @status = r.status, @employee_id = r.employee_id
    FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.id = @id AND r.company_id = @company_id AND r.is_deleted = 0 AND t.code = @type_code;
    IF @status IS NULL OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                                      WHERE v.employee_id = @employee_id)
        THROW 50404, N'Request not found', 1;
    IF @status <> N'pending'
        THROW 50409, N'Attachments can be changed only while the request is pending.', 1;
    IF @file_id IS NULL OR NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF EXISTS (SELECT 1 FROM [core].[attachment] WHERE entity_type = N'req.request' AND entity_id = @id AND file_id = @file_id)
        THROW 50409, N'fileId|This file is already attached.', 1;

    DECLARE @attachment_id BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [core].[attachment] (company_id, entity_type, entity_id, file_id, label, created_by)
        VALUES (@company_id, N'req.request', @id, @file_id, NULLIF(LTRIM(RTRIM(@label)), N''), @actor_user_id);
        SET @attachment_id = SCOPE_IDENTITY();
        UPDATE [req].[request] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'attachment', CONVERT(NVARCHAR(30), @file_id), N'create', @actor_user_id, @now);
    COMMIT;

    SELECT a.id, a.file_id, f.name, f.mime_type, f.size_bytes, a.label, f.uploaded_by_user_id, a.created_at
    FROM [core].[attachment] a JOIN [core].[stored_file] f ON f.id = a.file_id WHERE a.id = @attachment_id;
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_request_attachment_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @type_code       NVARCHAR(30),
    @permission_code NVARCHAR(150),
    @attachment_id   BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @status NVARCHAR(30), @employee_id BIGINT;
    SELECT @status = r.status, @employee_id = r.employee_id
    FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id
    WHERE r.id = @id AND r.company_id = @company_id AND r.is_deleted = 0 AND t.code = @type_code;
    IF @status IS NULL OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                                      WHERE v.employee_id = @employee_id)
        THROW 50404, N'Request not found', 1;
    IF NOT EXISTS (SELECT 1 FROM [core].[attachment] WHERE id = @attachment_id AND company_id = @company_id AND entity_type = N'req.request' AND entity_id = @id)
        THROW 50404, N'Attachment not found', 1;
    IF @status <> N'pending'
        THROW 50409, N'Attachments can be changed only while the request is pending.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        DELETE [core].[attachment] WHERE id = @attachment_id;
        UPDATE [req].[request] SET updated_at = @now, updated_by = @actor_user_id WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'attachment', CONVERT(NVARCHAR(30), @attachment_id), N'delete', @actor_user_id, @now);
    COMMIT;
END
