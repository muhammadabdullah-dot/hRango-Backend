CREATE OR ALTER PROCEDURE [org].[usp_employment_type_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[employment_type] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Employment type not found', 1;

    SELECT x.id, x.name, 
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.employment_type_id = x.id AND e.status NOT IN (N'left', N'inactive')) AS employee_count,
           x.created_at, x.updated_at, x.row_version
    FROM [org].[employment_type] x
    WHERE x.id = @id AND x.company_id = @company_id;
END
