-- Self-service dropdowns of the request forms (/api/requests/options/...). Staff filling a request
-- hold the request kind's create permission, not the settings permissions that guard the full lists,
-- so these give only what a form needs: ids, names and the rules the form shows.

-- Leave types one employee may apply for: the active types their leave policy gives them
-- (lv.fn_leave_coverage), with the balance on @as_of (lv.fn_leave_balance) and the half-day / short
-- leave / attachment / date rules of the Apply Leave form. @permission_code (the leave create code)
-- must reach the employee, else 404.
CREATE OR ALTER PROCEDURE [req].[usp_request_option_leave_types]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @permission_code NVARCHAR(150),
    @as_of           DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @employee_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                      WHERE v.employee_id = @employee_id)
        THROW 50404, N'employeeId|Employee not found', 1;
    SET @as_of = ISNULL(@as_of, CAST(SYSUTCDATETIME() AS DATE));

    DECLARE @half BIT, @short BIT;
    SELECT @half = h.allow_half_day, @short = h.allow_short_leave
    FROM [lv].[fn_leave_half_short](@company_id, @employee_id) h;

    SELECT t.id, t.title AS name, t.short_code AS code, t.is_deductible, t.is_short_leave,
           CAST(CASE WHEN t.is_short_leave = 1 AND ISNULL(@half, 1) = 1 THEN 1 ELSE 0 END AS BIT) AS allow_half_day,
           CAST(CASE WHEN t.is_short_leave = 1 AND ISNULL(@short, 1) = 1 THEN 1 ELSE 0 END AS BIT) AS allow_short_leave,
           t.attachment_required, ISNULL(t.attachment_rule, N'refuse') AS attachment_rule,
           t.allow_back_date, t.back_date_limit_days,
           CASE WHEN t.has_future_limit = 1 THEN t.future_limit_days END AS future_limit_days,
           b.entitled, b.used, b.pending, b.available
    FROM [lv].[leave_type] t
    CROSS APPLY [lv].[fn_leave_balance](@company_id, @employee_id, t.id, @as_of) b
    WHERE t.company_id = @company_id AND t.is_active = 1
      AND EXISTS (SELECT 1 FROM [lv].[fn_leave_coverage](@company_id) c
                  WHERE c.employee_id = @employee_id AND c.leave_type_id = t.id)
    ORDER BY t.title, t.id;
END
GO

-- Active loan types with their terms. eligible: the employee's contract type is one the type allows
-- (a type with no contract types allows everyone); NULL when no employee is given.
CREATE OR ALTER PROCEDURE [req].[usp_request_option_loan_types]
    @company_id  BIGINT,
    @employee_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @employment_type_id BIGINT = (SELECT employment_type_id FROM [hr].[employee]
                                          WHERE id = @employee_id AND company_id = @company_id);
    SELECT t.id, t.name, t.guarantor_required, t.non_payable, t.min_experience_months, t.gap_between_requests_months,
           t.installments, t.gap_between_installments_months, t.description,
           CAST(CASE WHEN @employee_id IS NULL THEN NULL
                     WHEN NOT EXISTS (SELECT 1 FROM [loan].[loan_type_employment_type] x WHERE x.loan_type_id = t.id) THEN 1
                     WHEN EXISTS (SELECT 1 FROM [loan].[loan_type_employment_type] x
                                  WHERE x.loan_type_id = t.id AND x.employment_type_id = @employment_type_id) THEN 1
                     ELSE 0 END AS BIT) AS eligible
    FROM [loan].[loan_type] t
    WHERE t.company_id = @company_id AND t.is_active = 1
    ORDER BY t.name, t.id;
END
GO

CREATE OR ALTER PROCEDURE [req].[usp_request_option_loan_categories]
    @company_id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.id, c.name, c.description
    FROM [loan].[loan_category] c
    WHERE c.company_id = @company_id AND c.is_active = 1
    ORDER BY c.name, c.id;
END
GO

-- Colleagues to swap a shift with: the company's employees who have not left, without the requester.
-- Names and units only. Result set 1: total. Result set 2: the page.
CREATE OR ALTER PROCEDURE [req].[usp_request_option_colleagues]
    @company_id  BIGINT,
    @employee_id BIGINT = NULL,
    @search      NVARCHAR(200) = NULL,
    @page        INT = 1,
    @page_size   INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @like NVARCHAR(410) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [hr].[employee] e
    WHERE e.company_id = @company_id AND e.status <> N'left' AND (@employee_id IS NULL OR e.id <> @employee_id)
      AND (@like IS NULL OR e.code LIKE @like OR CONCAT(e.first_name, N' ', e.last_name) LIKE @like)
    OPTION (RECOMPILE);

    SELECT e.id, e.code, NULLIF(LTRIM(RTRIM(CONCAT_WS(N' ', e.first_name, e.last_name))), N'') AS name,
           e.department_id, d.name AS department_name, e.branch_id, b.name AS branch_name
    FROM [hr].[employee] e
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    WHERE e.company_id = @company_id AND e.status <> N'left' AND (@employee_id IS NULL OR e.id <> @employee_id)
      AND (@like IS NULL OR e.code LIKE @like OR CONCAT(e.first_name, N' ', e.last_name) LIKE @like)
    ORDER BY e.first_name, e.last_name, e.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
