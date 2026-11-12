-- Workspace keys: the 2 to 5 capitals in front of a task code (ONB-12). Migration
-- 0002_pm_workspace_task_key.sql made the same functions to fill in keys for older workspaces.

-- The key a name suggests: the initials of two or more words (HR Onboarding -> HO), or the first three
-- letters of one word (Onboarding -> ONB). Words are runs of the letters A to Z; anything else (spaces,
-- digits, accents, punctuation) separates them. WS when the name has no usable letters.
CREATE OR ALTER FUNCTION [pm].[fn_workspace_key_base] (@name NVARCHAR(200))
RETURNS NVARCHAR(5)
AS
BEGIN
    DECLARE @text NVARCHAR(200) = UPPER(ISNULL(@name, N'')), @i INT = 1, @c INT, @in_word BIT = 0,
            @words INT = 0, @initials NVARCHAR(5) = N'', @first NVARCHAR(5) = N'';
    WHILE @i <= LEN(@text)
    BEGIN
        SET @c = UNICODE(SUBSTRING(@text, @i, 1));
        IF @c BETWEEN 65 AND 90
        BEGIN
            IF @in_word = 0
            BEGIN
                SET @words += 1;
                IF LEN(@initials) < 5
                    SET @initials += NCHAR(@c);
            END
            IF @words = 1 AND LEN(@first) < 5
                SET @first += NCHAR(@c);
            SET @in_word = 1;
        END
        ELSE
            SET @in_word = 0;
        SET @i += 1;
    END
    RETURN CASE WHEN @words >= 2 THEN @initials
                WHEN LEN(@first) >= 2 THEN LEFT(@first, 3)
                ELSE N'WS' END;
END
GO

-- The first key no other workspace of the company uses: @base itself, else @base with one more letter
-- (HOA ... HOZ), else with two (HOAA ...). Keys stay capitals only, so they always pass the 2 to 5 A-Z
-- rule an edit checks. @workspace_id: the workspace being keyed (its own key does not count).
CREATE OR ALTER FUNCTION [pm].[fn_workspace_key_free] (@company_id BIGINT, @base NVARCHAR(5), @workspace_id BIGINT)
RETURNS TABLE
AS RETURN
WITH letters AS (
    SELECT n FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16),
                          (17), (18), (19), (20), (21), (22), (23), (24), (25), (26)) v (n)
),
candidates AS (
    SELECT CASE WHEN a.n = 0 THEN @base
                WHEN b.n = 0 THEN LEFT(@base, 4) + NCHAR(64 + a.n)
                ELSE LEFT(@base, 3) + NCHAR(64 + a.n) + NCHAR(64 + b.n) END AS task_key,
           CASE WHEN a.n = 0 THEN 0 WHEN b.n = 0 THEN 1 ELSE 2 END AS extra, a.n AS a, b.n AS b
    FROM letters a CROSS JOIN letters b
    WHERE NOT (a.n = 0 AND b.n > 0)
)
SELECT TOP 1 c.task_key
FROM candidates c
WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace] w
                  WHERE w.company_id = @company_id AND w.task_key = c.task_key AND w.id <> ISNULL(@workspace_id, 0))
ORDER BY c.extra, c.a, c.b;
GO

-- The highest number a task code of the company already has with this key (0 when none). A key freed by
-- a rename and taken by another workspace carries on above it, so codes never repeat.
CREATE OR ALTER FUNCTION [pm].[fn_task_key_top] (@company_id BIGINT, @task_key NVARCHAR(5))
RETURNS TABLE
AS RETURN
SELECT ISNULL(MAX(TRY_CONVERT(INT, SUBSTRING(t.code, LEN(@task_key) + 2, 20))), 0) AS top_number
FROM [pm].[task] t
WHERE t.company_id = @company_id AND t.code LIKE @task_key + N'-%';
