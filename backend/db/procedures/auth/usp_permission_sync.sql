-- Syncs the permission catalogue shipped in app/core/permissions.py into auth.permission.
-- Adds new codes and refreshes labels. Codes no longer in the catalogue are kept (roles may still
-- reference them) and counted as retired.
CREATE OR ALTER PROCEDURE [auth].[usp_permission_sync]
    @catalogue NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @src TABLE (
        code NVARCHAR(150) PRIMARY KEY, module NVARCHAR(30), screen NVARCHAR(100),
        action_code NVARCHAR(50), label NVARCHAR(200), hint NVARCHAR(500), is_sensitive BIT, sort_order INT);

    INSERT @src
    SELECT code, module, screen, action_code, label, hint, is_sensitive, sort_order
    FROM OPENJSON(@catalogue) WITH (
        code NVARCHAR(150), module NVARCHAR(30), screen NVARCHAR(100), action_code NVARCHAR(50),
        label NVARCHAR(200), hint NVARCHAR(500), is_sensitive BIT, sort_order INT);

    DECLARE @added INT;

    BEGIN TRAN;
        UPDATE p
        SET module = s.module, screen = s.screen, action_code = s.action_code, label = s.label,
            hint = s.hint, is_sensitive = s.is_sensitive, sort_order = s.sort_order,
            updated_at = SYSUTCDATETIME()
        FROM [auth].[permission] p
        JOIN @src s ON s.code = p.code
        WHERE EXISTS (SELECT p.module, p.screen, p.action_code, p.label, p.hint, p.is_sensitive, p.sort_order
                      EXCEPT
                      SELECT s.module, s.screen, s.action_code, s.label, s.hint, s.is_sensitive, s.sort_order);

        INSERT [auth].[permission] (code, module, screen, action_code, label, hint, is_sensitive, sort_order)
        SELECT s.code, s.module, s.screen, s.action_code, s.label, s.hint, s.is_sensitive, s.sort_order
        FROM @src s
        WHERE NOT EXISTS (SELECT 1 FROM [auth].[permission] p WHERE p.code = s.code);
        SET @added = @@ROWCOUNT;
    COMMIT;

    SELECT (SELECT COUNT(*) FROM @src) AS total,
           @added AS added,
           (SELECT COUNT(*) FROM [auth].[permission] p WHERE NOT EXISTS (SELECT 1 FROM @src s WHERE s.code = p.code)) AS retired;
END
