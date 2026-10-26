-- The masters a new company starts with (employment types named in the ERD). Run once, when the
-- company is created; afterwards the customer owns them, so renames and deletes stick.
CREATE OR ALTER PROCEDURE [org].[usp_company_defaults_apply]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[employment_type] WHERE company_id = @company_id)
        INSERT [org].[employment_type] (company_id, name)
        VALUES (@company_id, N'Permanent'), (@company_id, N'Contractual'), (@company_id, N'Daily Wager'),
               (@company_id, N'Management Trainee');
END
