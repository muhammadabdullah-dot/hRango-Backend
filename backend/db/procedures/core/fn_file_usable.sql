-- For modules: a file id given in a form must be one of this company's uploads.
--   IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
--       THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
CREATE OR ALTER FUNCTION [core].[fn_file_usable] (@company_id BIGINT, @file_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT f.id FROM [core].[stored_file] f WHERE f.id = @file_id AND f.company_id = @company_id;
