CREATE OR ALTER PROCEDURE [org].[usp_department_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Department not found', 1;

    SELECT d.id, d.name, d.parent_id, p.name AS parent_name,
           d.head_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS head_name,
           d.created_at, d.updated_at, d.row_version
    FROM [org].[department] d
    LEFT JOIN [org].[department] p ON p.id = d.parent_id
    LEFT JOIN [hr].[employee] e ON e.id = d.head_id
    WHERE d.id = @id AND d.company_id = @company_id;
END
