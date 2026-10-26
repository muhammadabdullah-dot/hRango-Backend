-- The Benefits stats row: Plan Years, Plans (active), Enrollment Windows (open), Employees (the people
-- the user reaches through Employee Elections).
CREATE OR ALTER PROCEDURE [ben].[usp_benefit_summary]
    @company_id    BIGINT,
    @actor_user_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SELECT (SELECT COUNT(*) FROM [ben].[plan_year] WHERE company_id = @company_id) AS plan_years,
           (SELECT COUNT(*) FROM [ben].[benefit_plan] WHERE company_id = @company_id AND status = N'active') AS plans,
           (SELECT COUNT(*) FROM [ben].[enrollment_window] WHERE company_id = @company_id AND closes_on >= @today) AS enrollment_windows,
           (SELECT COUNT(DISTINCT v.employee_id)
            FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'benefits.elections.view') v
            JOIN [hr].[employee] em ON em.id = v.employee_id AND em.status <> N'left') AS employees;
END
