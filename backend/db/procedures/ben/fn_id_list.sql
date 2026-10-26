-- Ids from a JSON list such as ["12", 15] (strings or numbers), without repeats. Values that are not
-- whole numbers come back as NULL so the caller can refuse them.
CREATE OR ALTER FUNCTION [ben].[fn_id_list] (@json NVARCHAR(MAX))
RETURNS TABLE
AS RETURN
SELECT DISTINCT TRY_CAST(j.value AS BIGINT) AS id
FROM OPENJSON(CASE WHEN ISJSON(@json) = 1 THEN @json ELSE N'[]' END) j;
