-- Short task codes per workspace (ONB-12 instead of HR000000011): a key on every workspace (2 to 5
-- capitals, unique in the company, editable) and a counter per workspace. Tasks made before keep their
-- codes.
-- Every step checks first, so this also runs cleanly on a database whose baseline was rebuilt from the
-- ERD and already has the columns and the table.
-- The counter has its own table: adding a task must not change the workspace's row version, or every
-- Workspace Settings save open at the time would be refused.

IF COL_LENGTH(N'pm.workspace', N'task_key') IS NULL
    ALTER TABLE [pm].[workspace] ADD [task_key] NVARCHAR(5) NULL;
GO

IF OBJECT_ID(N'pm.workspace_task_sequence', N'U') IS NULL
    CREATE TABLE [pm].[workspace_task_sequence] (
        [workspace_id] BIGINT NOT NULL,
        [next_number] INT NOT NULL,
        [created_at] DATETIME2(0) NOT NULL CONSTRAINT [DF_workspace_task_sequence_created_at] DEFAULT SYSUTCDATETIME(),
        [created_by] BIGINT NULL,
        [updated_at] DATETIME2(0) NULL,
        [updated_by] BIGINT NULL,
        [row_version] ROWVERSION,
        CONSTRAINT [PK_workspace_task_sequence] PRIMARY KEY CLUSTERED ([workspace_id]),
        CONSTRAINT [FK_workspace_task_sequence_workspace_id] FOREIGN KEY ([workspace_id]) REFERENCES [pm].[workspace] ([id])
    );
GO

-- The same key functions as db/procedures/pm/fn_workspace_key.sql (which replaces them right after, on
-- every seed run). Needed here because migrations run before the procedures.
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

-- A key for every workspace that has none, oldest first, so the older workspace keeps the plain key
-- and a later one with the same initials gets a letter more.
DECLARE @id BIGINT = (SELECT MIN(id) FROM [pm].[workspace] WHERE task_key IS NULL);
WHILE @id IS NOT NULL
BEGIN
    UPDATE w SET task_key = k.task_key
    FROM [pm].[workspace] w
    CROSS APPLY [pm].[fn_workspace_key_free](w.company_id, [pm].[fn_workspace_key_base](w.name), w.id) k
    WHERE w.id = @id;
    SET @id = (SELECT MIN(id) FROM [pm].[workspace] WHERE task_key IS NULL AND id > @id);
END
GO

-- Each workspace counts on from its current number of tasks (or from the highest <key>-n code in the
-- company, should one already exist), so the first new code does not collide with anything.
INSERT [pm].[workspace_task_sequence] (workspace_id, next_number)
SELECT w.id, 1 + CASE WHEN ISNULL(u.top_number, 0) > c.task_count THEN u.top_number ELSE c.task_count END
FROM [pm].[workspace] w
CROSS APPLY (SELECT COUNT(*) AS task_count FROM [pm].[task] t WHERE t.workspace_id = w.id) c
OUTER APPLY (SELECT MAX(TRY_CONVERT(INT, SUBSTRING(t.code, LEN(w.task_key) + 2, 20))) AS top_number
             FROM [pm].[task] t WHERE t.company_id = w.company_id AND t.code LIKE w.task_key + N'-%') u
WHERE NOT EXISTS (SELECT 1 FROM [pm].[workspace_task_sequence] s WHERE s.workspace_id = w.id);
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'pm.workspace') AND name = N'task_key' AND is_nullable = 1)
    ALTER TABLE [pm].[workspace] ALTER COLUMN [task_key] NVARCHAR(5) NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'pm.workspace') AND name = N'UQ_workspace_company_id_task_key')
    ALTER TABLE [pm].[workspace] ADD CONSTRAINT [UQ_workspace_company_id_task_key] UNIQUE ([company_id], [task_key]);
GO
