-- Plan limits (roadmap 1.3), called by the procedures that add a counted employee: a new employee
-- (hr.usp_employee_save), switching one back on (hr.usp_employee_active_set) and a rehire
-- (sep.usp_end_of_employment_rehire). @adding is how many the change would add.
CREATE OR ALTER PROCEDURE [plat].[usp_plan_employee_check]
    @company_id BIGINT,
    @adding     INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @limit INT, @used INT, @plan NVARCHAR(200);
    SELECT @limit = employee_limit, @used = employees_used, @plan = plan_name
    FROM [plat].[fn_plan_allowance](@company_id);
    IF @limit IS NOT NULL AND @used + @adding > @limit
    BEGIN
        DECLARE @message NVARCHAR(400) = CONCAT(N'employee|PLAN_EMPLOYEE_LIMIT|Your ', @plan, N' plan covers ', @limit,
            N' employees and ', @used, N' are on it now. Ask your Account Owner to move to a larger plan, or switch off ',
            N'people who have left.');
        THROW 50409, @message, 1;
    END
END
GO

-- Plan and usage for the customer's own screens (Settings > Subscription): employees used of the limit.
CREATE OR ALTER PROCEDURE [plat].[usp_plan_usage]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.plan_id, a.plan_name, a.employee_limit, a.employees_used, a.subscription_status,
           (SELECT COUNT(*) FROM [plat].[customer_company] x WHERE x.customer_id = a.customer_id) AS company_count
    FROM [plat].[fn_plan_allowance](@company_id) a;
END
GO
