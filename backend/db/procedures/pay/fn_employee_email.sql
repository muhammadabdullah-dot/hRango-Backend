-- Where payroll e-mails to a person go: the employee record's e-mail, else their active sign-in account's.
CREATE OR ALTER FUNCTION [pay].[fn_employee_email] (@employee_id BIGINT)
RETURNS NVARCHAR(254)
AS
BEGIN
    RETURN COALESCE(
        (SELECT NULLIF(LTRIM(RTRIM(email)), N'') FROM [hr].[employee] WHERE id = @employee_id),
        (SELECT TOP 1 email FROM [auth].[user_account] WHERE employee_id = @employee_id AND is_active = 1 ORDER BY id));
END
