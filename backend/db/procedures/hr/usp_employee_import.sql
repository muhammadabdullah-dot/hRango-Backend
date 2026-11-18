-- Bulk employee import from a spreadsheet (roadmap 1.1): the names a file may use for the company's
-- set-up, so app/services/employee_import_service.py can turn "Lahore Head Office" into a branch id.
-- Result sets: branches, departments, designations, job titles, employment types, and existing employee
-- codes (for line managers named by code).
CREATE OR ALTER PROCEDURE [hr].[usp_employee_import_lookups]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, name FROM [org].[branch] WHERE company_id = @company_id;
    SELECT id, name FROM [org].[department] WHERE company_id = @company_id;
    SELECT id, name FROM [org].[designation] WHERE company_id = @company_id;
    SELECT id, name FROM [org].[job_title] WHERE company_id = @company_id;
    SELECT id, name FROM [org].[employment_type] WHERE company_id = @company_id;
    SELECT id, code FROM [hr].[employee] WHERE company_id = @company_id AND code IS NOT NULL;
END
GO

-- The import's second pass: a line manager who is new in the same file. Both are in the company, nobody
-- manages themselves, and the chain above the manager may not come back to the employee.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_import_manager_set]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @line_manager_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @id AND company_id = @company_id)
       OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @line_manager_id AND company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
    IF @id = @line_manager_id
        THROW 50400, N'lineManagerId|Nobody can be their own line manager.', 1;
    DECLARE @cycle BIT = 0;
    ;WITH chain AS (
        SELECT e.id, e.line_manager_id, 1 AS depth FROM [hr].[employee] e WHERE e.id = @line_manager_id
        UNION ALL
        SELECT e.id, e.line_manager_id, c.depth + 1 FROM [hr].[employee] e JOIN chain c ON e.id = c.line_manager_id
        WHERE c.depth < 50)
    SELECT @cycle = 1 FROM chain WHERE id = @id;
    IF @cycle = 1
        THROW 50400, N'lineManagerId|LINE_MANAGER_CYCLE|These line managers would manage each other in a circle.', 1;

    UPDATE [hr].[employee] SET line_manager_id = @line_manager_id, updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id
    WHERE id = @id AND company_id = @company_id;
END
GO
