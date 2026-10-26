-- Next code for a prefix (MCH-, GF-, IPR-) from core.number_sequence: MCH-00001, MCH-00002 ...
-- Runs inside the caller's transaction; the row lock keeps two callers from getting the same number.
CREATE OR ALTER PROCEDURE [att].[usp_code_next]
    @company_id BIGINT,
    @prefix     NVARCHAR(10),
    @code       NVARCHAR(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n INT;
    UPDATE [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK)
    SET @n = next_number = ISNULL(next_number, 1) + 1
    WHERE company_id = @company_id AND prefix = @prefix;
    IF @n IS NULL
    BEGIN
        INSERT [core].[number_sequence] (company_id, prefix, next_number) VALUES (@company_id, @prefix, 2);
        SET @n = 2;
    END
    SET @code = @prefix + CASE WHEN @n - 1 > 99999 THEN CONVERT(NVARCHAR(10), @n - 1)
                               ELSE RIGHT(N'0000' + CONVERT(NVARCHAR(10), @n - 1), 5) END;
END
