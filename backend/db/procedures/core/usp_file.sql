-- Uploaded files (core.stored_file). The bytes are on disk (app/core/files.py); these keep the record.
-- Modules store a file id in their own tables or attach it with core.attachment; a file still used
-- anywhere cannot be deleted (its foreign keys refuse with error 547).

CREATE OR ALTER PROCEDURE [core].[usp_file_create]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @module        NVARCHAR(30),
    @name          NVARCHAR(255),
    @extension     NVARCHAR(20),
    @mime_type     NVARCHAR(100),
    @size_bytes    BIGINT,
    @sha256        CHAR(64),
    @storage_path  NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT [core].[stored_file] (company_id, module, name, extension, mime_type, size_bytes, sha256, storage_path,
                                 uploaded_by_user_id, created_by)
    VALUES (@company_id, @module, @name, @extension, @mime_type, @size_bytes, @sha256, @storage_path,
            @actor_user_id, @actor_user_id);
    DECLARE @id BIGINT = SCOPE_IDENTITY();
    EXEC [core].[usp_file_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [core].[usp_file_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.id, f.company_id, f.module, f.name, f.extension, f.mime_type, f.size_bytes, f.sha256, f.storage_path,
           f.uploaded_by_user_id, f.created_at
    FROM [core].[stored_file] f
    WHERE f.id = @id AND f.company_id = @company_id;
END
GO

-- Deletes a file nothing uses any more. Only the person who uploaded it (or a system administrator).
-- Returns the storage path so the caller removes the bytes after the row is gone.
CREATE OR ALTER PROCEDURE [core].[usp_file_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @path NVARCHAR(500), @owner BIGINT;
    SELECT @path = storage_path, @owner = uploaded_by_user_id
    FROM [core].[stored_file] WHERE id = @id AND company_id = @company_id;
    IF @path IS NULL
        THROW 50404, N'File not found', 1;
    IF ISNULL(@owner, 0) <> @actor_user_id
       AND NOT EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @actor_user_id AND is_system_admin = 1)
        THROW 50403, N'Only the person who uploaded a file can delete it.', 1;
    IF EXISTS (SELECT 1 FROM [core].[attachment] WHERE file_id = @id)
        THROW 50409, N'file|FILE_IN_USE|This file is attached to a record. Remove it there first.', 1;

    DELETE [core].[stored_file] WHERE id = @id;   -- 547 when another record still points at it
    SELECT @path AS storage_path;
END
