-- Removes uploads nothing uses any more (a replaced cover or JD, a detached attachment, a file uploaded
-- for a form that was never saved), once they are older than @older_than_days. "Used" means any
-- foreign key to core.stored_file or a core.attachment row points at it; the foreign keys are read from
-- the database itself, so a module that adds a file column is covered without changing this.
-- Returns the storage paths of the rows it deleted; the caller removes those files from disk.
CREATE OR ALTER PROCEDURE [core].[usp_file_purge_unused]
    @company_id      BIGINT,
    @older_than_days INT = 7,
    @batch           INT = 500
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @refs NVARCHAR(MAX) = N'';
    SELECT @refs = @refs + N' AND NOT EXISTS (SELECT 1 FROM ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
                         + N' x WHERE x.' + QUOTENAME(c.name) + N' = f.id)'
    FROM sys.foreign_key_columns fkc
    JOIN sys.tables t ON t.object_id = fkc.parent_object_id
    JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
    WHERE fkc.referenced_object_id = OBJECT_ID(N'core.stored_file');

    DECLARE @sql NVARCHAR(MAX) = N'
        DELETE TOP (@batch) f
        OUTPUT deleted.storage_path
        FROM [core].[stored_file] f
        WHERE f.company_id = @company_id
          AND f.created_at < DATEADD(DAY, -@older_than_days, SYSUTCDATETIME())' + @refs + N';';

    EXEC sys.sp_executesql @sql, N'@company_id BIGINT, @older_than_days INT, @batch INT',
         @company_id = @company_id, @older_than_days = @older_than_days, @batch = @batch;
END
