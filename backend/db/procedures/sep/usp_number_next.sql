-- Next code for a prefix in a company (AITP-00001, AST-00001, ECL-00001), from core.number_sequence.
-- Call inside the caller's transaction so a rolled-back save does not use up a number.
CREATE OR ALTER PROCEDURE [sep].[usp_number_next]
    @company_id BIGINT,
    @prefix     NVARCHAR(10),
    @code       NVARCHAR(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @n INT;
    UPDATE [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK)
    SET @n = next_number, next_number = next_number + 1
    WHERE company_id = @company_id AND prefix = @prefix;

    IF @n IS NULL
    BEGIN
        INSERT [core].[number_sequence] (company_id, prefix, next_number) VALUES (@company_id, @prefix, 2);
        SET @n = 1;
    END

    DECLARE @digits NVARCHAR(10) = CAST(@n AS NVARCHAR(10));
    SET @code = @prefix + N'-' + CASE WHEN LEN(@digits) >= 5 THEN @digits ELSE RIGHT(N'0000' + @digits, 5) END;
END
