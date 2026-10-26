CREATE OR ALTER PROCEDURE [org].[usp_division_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[division] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Division not found', 1;

    SELECT x.id, x.name, 
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.division_id = x.id AND e.status NOT IN (N'left', N'inactive')) AS employee_count,
           x.created_at, x.updated_at, x.row_version
    FROM [org].[division] x
    WHERE x.id = @id AND x.company_id = @company_id;
END
