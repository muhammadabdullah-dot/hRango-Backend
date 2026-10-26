-- Loans made by approved loan requests: My / All lists, one loan with its installment schedule
-- (the Repayment tab), the installments list and the approve popup's totals. Employee-owned:
-- filtered by auth.fn_visible_employees for the permission the endpoint required.
CREATE OR ALTER PROCEDURE [loan].[usp_loan_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @view            NVARCHAR(20) = N'all',
    @status          NVARCHAR(30) = NULL,
    @loan_type_id    BIGINT = NULL,
    @employee_id     BIGINT = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT l.id
    FROM [loan].[loan] l
    JOIN [hr].[employee] e ON e.id = l.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = l.employee_id
    LEFT JOIN [req].[request] r ON r.id = l.request_id
    WHERE l.company_id = @company_id
      AND (@view <> N'my' OR l.employee_id = @me)
      AND (@status IS NULL OR l.status = @status)
      AND (@loan_type_id IS NULL OR l.loan_type_id = @loan_type_id)
      AND (@employee_id IS NULL OR l.employee_id = @employee_id)
      AND (@pattern IS NULL OR e.code LIKE @pattern OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR r.code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM @ids;

    SELECT l.id, l.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           d.name AS department_name, l.request_id, r.code AS request_code, l.loan_type_id, t.name AS loan_type_name,
           l.loan_category_id, c.name AS loan_category_name, l.principal, l.installment_amount, l.installments,
           l.gap_between_installments_months, l.currency, l.payment_method, l.start_month, l.status, l.settled_at,
           ISNULL(p.paid, 0) AS paid_amount, l.principal - ISNULL(p.paid, 0) AS remaining_amount,
           l.created_at, l.updated_at, l.row_version
    FROM [loan].[loan] l
    JOIN @ids x ON x.id = l.id
    JOIN [hr].[employee] e ON e.id = l.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [req].[request] r ON r.id = l.request_id
    LEFT JOIN [loan].[loan_type] t ON t.id = l.loan_type_id
    LEFT JOIN [loan].[loan_category] c ON c.id = l.loan_category_id
    OUTER APPLY (SELECT SUM(ISNULL(i.paid_amount, 0)) AS paid FROM [loan].[loan_installment] i WHERE i.loan_id = l.id) p
    ORDER BY l.created_at DESC, l.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- One loan. Result sets: the loan; its installments; the guarantors from its request.
CREATE OR ALTER PROCEDURE [loan].[usp_loan_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [loan].[loan] l
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = l.employee_id
                   WHERE l.id = @id AND l.company_id = @company_id)
        THROW 50404, N'Loan not found', 1;

    SELECT l.id, l.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           d.name AS department_name, l.request_id, r.code AS request_code, l.loan_type_id, t.name AS loan_type_name,
           l.loan_category_id, c.name AS loan_category_name, l.principal, l.installment_amount, l.installments,
           l.gap_between_installments_months, l.currency, l.payment_method, l.start_month, l.status, l.settled_at,
           ISNULL(p.paid, 0) AS paid_amount, l.principal - ISNULL(p.paid, 0) AS remaining_amount,
           l.created_at, l.updated_at, l.row_version
    FROM [loan].[loan] l
    JOIN [hr].[employee] e ON e.id = l.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [req].[request] r ON r.id = l.request_id
    LEFT JOIN [loan].[loan_type] t ON t.id = l.loan_type_id
    LEFT JOIN [loan].[loan_category] c ON c.id = l.loan_category_id
    OUTER APPLY (SELECT SUM(ISNULL(i.paid_amount, 0)) AS paid FROM [loan].[loan_installment] i WHERE i.loan_id = l.id) p
    WHERE l.id = @id;

    SELECT i.id, i.loan_id, i.installment_no, i.due_month, i.amount, i.paid_amount, i.payslip_id, i.paid_at, i.status
    FROM [loan].[loan_installment] i WHERE i.loan_id = @id ORDER BY i.installment_no;

    SELECT g.id, g.name, g.cnic, g.known_since, g.relationship, g.extension_no, g.description, g.file_id,
           f.name AS file_name
    FROM [loan].[loan] l JOIN [req].[loan_guarantor] g ON g.request_id = l.request_id
    LEFT JOIN [core].[stored_file] f ON f.id = g.file_id
    WHERE l.id = @id ORDER BY g.id;
END
GO

-- Settings -> Repayment: installments of every visible loan, by due month.
CREATE OR ALTER PROCEDURE [loan].[usp_loan_installment_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @month_from      DATE = NULL,
    @month_to        DATE = NULL,
    @status          NVARCHAR(30) = NULL,
    @employee_id     BIGINT = NULL,
    @page            INT = 1,
    @page_size       INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ids TABLE (id BIGINT PRIMARY KEY);
    INSERT @ids
    SELECT i.id
    FROM [loan].[loan_installment] i
    JOIN [loan].[loan] l ON l.id = i.loan_id AND l.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = l.employee_id
    WHERE (@month_from IS NULL OR i.due_month >= @month_from) AND (@month_to IS NULL OR i.due_month <= @month_to)
      AND (@status IS NULL OR i.status = @status) AND (@employee_id IS NULL OR l.employee_id = @employee_id)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM @ids;

    SELECT i.id, i.loan_id, l.employee_id, e.code AS employee_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, t.name AS loan_type_name,
           i.installment_no, i.due_month, i.amount, i.paid_amount, i.payslip_id, i.paid_at, i.status
    FROM [loan].[loan_installment] i
    JOIN @ids x ON x.id = i.id
    JOIN [loan].[loan] l ON l.id = i.loan_id
    JOIN [hr].[employee] e ON e.id = l.employee_id
    LEFT JOIN [loan].[loan_type] t ON t.id = l.loan_type_id
    ORDER BY i.due_month, e.code, i.installment_no
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- The three totals on the loan approve popup: approved, repaid and remaining, for one employee.
CREATE OR ALTER PROCEDURE [loan].[usp_loan_summary]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                   WHERE v.employee_id = @employee_id)
        THROW 50404, N'Employee not found', 1;

    SELECT @employee_id AS employee_id,
           ISNULL(SUM(l.principal), 0) AS total_approved,
           ISNULL(SUM(p.paid), 0) AS total_repaid,
           ISNULL(SUM(CASE WHEN l.status = N'non_payable' THEN 0 ELSE l.principal - ISNULL(p.paid, 0) END), 0) AS total_remaining
    FROM [loan].[loan] l
    OUTER APPLY (SELECT SUM(ISNULL(i.paid_amount, 0)) AS paid FROM [loan].[loan_installment] i WHERE i.loan_id = l.id) p
    WHERE l.company_id = @company_id AND l.employee_id = @employee_id;
END
