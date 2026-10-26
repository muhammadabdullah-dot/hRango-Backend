-- Payrolls (Monthly and Daily Wages): the run header, its pay items and its employees.

-- Result set 1: total. Result set 2: the page. Totals are over all the run's payslips.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_list]
    @company_id   BIGINT,
    @kind         NVARCHAR(30) = N'monthly',
    @search       NVARCHAR(200) = NULL,
    @status       NVARCHAR(30) = NULL,
    @month        DATE = NULL,
    @from_date    DATE = NULL,
    @to_date      DATE = NULL,
    @time_slot_id BIGINT = NULL,
    @page         INT = 1,
    @page_size    INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    IF @month IS NOT NULL SET @month = DATEFROMPARTS(YEAR(@month), MONTH(@month), 1);

    SELECT COUNT(*) AS total
    FROM [pay].[payroll] p
    WHERE p.company_id = @company_id AND p.kind = @kind
      AND (@pattern IS NULL OR p.name LIKE @pattern OR p.code LIKE @pattern)
      AND (@status IS NULL OR p.status = @status)
      AND (@month IS NULL OR p.payroll_month = @month)
      AND (@from_date IS NULL OR p.work_date >= @from_date) AND (@to_date IS NULL OR p.work_date <= @to_date)
      AND (@time_slot_id IS NULL OR p.time_slot_id = @time_slot_id)
    OPTION (RECOMPILE);

    SELECT p.id, p.code, p.name, p.kind, p.payroll_month, p.work_date, p.time_slot_id, ts.name AS time_slot_name,
           p.currency, p.tax_structure_id, t.name AS tax_structure_name, p.tax_applicable, p.processing_mode,
           p.processing_date, p.applicable_days, p.fixed_days, p.disbursement_bank_id, b.bank_name AS disbursement_bank_name,
           p.description, p.status, p.last_run_at, p.closed_at, p.closed_by_user_id,
           (SELECT COUNT(*) FROM [pay].[payroll_employee] pe WHERE pe.payroll_id = p.id) AS employee_count,
           s.payslip_count, s.total_earnings, s.total_deductions, s.net_payable,
           p.created_at, p.updated_at, p.row_version
    FROM [pay].[payroll] p
    LEFT JOIN [sch].[time_slot] ts ON ts.id = p.time_slot_id
    LEFT JOIN [pay].[tax_structure] t ON t.id = p.tax_structure_id
    LEFT JOIN [pay].[disbursement_bank] b ON b.id = p.disbursement_bank_id
    OUTER APPLY (SELECT COUNT(*) AS payslip_count, ISNULL(SUM(ps.total_earnings), 0) AS total_earnings,
                        ISNULL(SUM(ps.total_deductions), 0) AS total_deductions, ISNULL(SUM(ps.net_payable), 0) AS net_payable
                 FROM [pay].[payslip] ps WHERE ps.payroll_id = p.id) s
    WHERE p.company_id = @company_id AND p.kind = @kind
      AND (@pattern IS NULL OR p.name LIKE @pattern OR p.code LIKE @pattern)
      AND (@status IS NULL OR p.status = @status)
      AND (@month IS NULL OR p.payroll_month = @month)
      AND (@from_date IS NULL OR p.work_date >= @from_date) AND (@to_date IS NULL OR p.work_date <= @to_date)
      AND (@time_slot_id IS NULL OR p.time_slot_id = @time_slot_id)
    ORDER BY ISNULL(p.payroll_month, p.work_date) DESC, p.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Result set 1: the payroll. Result set 2: its pay items.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_get]
    @company_id BIGINT,
    @id         BIGINT,
    @kind       NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND (@kind IS NULL OR kind = @kind))
        THROW 50404, N'Payroll not found', 1;

    SELECT p.id, p.code, p.name, p.kind, p.payroll_month, p.work_date, p.time_slot_id, ts.name AS time_slot_name,
           p.currency, p.tax_structure_id, t.name AS tax_structure_name, p.tax_applicable, p.processing_mode,
           p.processing_date, p.applicable_days, p.fixed_days, p.disbursement_bank_id, b.bank_name AS disbursement_bank_name,
           p.description, p.status, p.last_run_at, p.closed_at, p.closed_by_user_id,
           (SELECT COUNT(*) FROM [pay].[payroll_employee] pe WHERE pe.payroll_id = p.id) AS employee_count,
           s.payslip_count, s.total_earnings, s.total_deductions, s.net_payable,
           p.created_at, p.updated_at, p.row_version
    FROM [pay].[payroll] p
    LEFT JOIN [sch].[time_slot] ts ON ts.id = p.time_slot_id
    LEFT JOIN [pay].[tax_structure] t ON t.id = p.tax_structure_id
    LEFT JOIN [pay].[disbursement_bank] b ON b.id = p.disbursement_bank_id
    OUTER APPLY (SELECT COUNT(*) AS payslip_count, ISNULL(SUM(ps.total_earnings), 0) AS total_earnings,
                        ISNULL(SUM(ps.total_deductions), 0) AS total_deductions, ISNULL(SUM(ps.net_payable), 0) AS net_payable
                 FROM [pay].[payslip] ps WHERE ps.payroll_id = p.id) s
    WHERE p.id = @id;

    SELECT ppi.pay_item_id, pi.name AS pay_item_name, pi.item_type, pi.system_code, ppi.is_taxable,
           ppi.arrear_applicable, ppi.final_settlement, ppi.calculate_only
    FROM [pay].[payroll_pay_item] ppi
    JOIN [pay].[pay_item] pi ON pi.id = ppi.pay_item_id
    WHERE ppi.payroll_id = @id
    ORDER BY CASE WHEN pi.system_code IS NULL THEN 1 ELSE 0 END, pi.id;
END
GO

-- Adds a monthly payroll (@id NULL) or edits one. @pay_items: JSON [{"payItemId","isTaxable","arrearApplicable",
-- "finalSettlement","calculateOnly"}]; NULL keeps the current list (on add: every pay item of the company).
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_save]
    @company_id           BIGINT,
    @actor_user_id        BIGINT = NULL,
    @id                   BIGINT = NULL,
    @name                 NVARCHAR(200),
    @payroll_month        DATE,
    @currency             CHAR(3) = NULL,
    @tax_structure_id     BIGINT = NULL,
    @tax_applicable       BIT = 0,
    @processing_mode      NVARCHAR(30) = NULL,
    @processing_date      DATE = NULL,
    @applicable_days      NVARCHAR(30) = N'actual',
    @fixed_days           INT = NULL,
    @disbursement_bank_id BIGINT = NULL,
    @description          NVARCHAR(MAX) = NULL,
    @pay_items            NVARCHAR(MAX) = NULL,
    @row_version          BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @name = LTRIM(RTRIM(@name));
    SET @payroll_month = DATEFROMPARTS(YEAR(@payroll_month), MONTH(@payroll_month), 1);
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Name is required.', 1;
    IF @tax_structure_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[tax_structure] WHERE id = @tax_structure_id AND company_id = @company_id)
        THROW 50400, N'taxStructureId|Tax structure not found.', 1;
    IF @disbursement_bank_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [pay].[disbursement_bank] WHERE id = @disbursement_bank_id AND company_id = @company_id)
        THROW 50400, N'disbursementBankId|Disbursement bank not found.', 1;
    IF EXISTS (SELECT 1 FROM [pay].[payroll] WHERE company_id = @company_id AND kind = N'monthly' AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|PAYROLL_DUPLICATE|A payroll with this name already exists.', 1;

    DECLARE @items TABLE (pay_item_id BIGINT PRIMARY KEY, is_taxable BIT, arrear_applicable BIT, final_settlement BIT, calculate_only BIT);
    IF @pay_items IS NOT NULL
    BEGIN
        IF ISJSON(@pay_items) <> 1
            THROW 50400, N'payItems|Pay items are not valid.', 1;
        IF EXISTS (SELECT pay_item_id FROM OPENJSON(@pay_items) WITH (pay_item_id BIGINT '$.payItemId') GROUP BY pay_item_id HAVING COUNT(*) > 1)
            THROW 50400, N'payItems|A pay item is listed twice.', 1;
        INSERT @items
        SELECT j.pay_item_id, ISNULL(j.is_taxable, 0), ISNULL(j.arrear_applicable, 0), ISNULL(j.final_settlement, 0), ISNULL(j.calculate_only, 0)
        FROM OPENJSON(@pay_items) WITH (pay_item_id BIGINT '$.payItemId', is_taxable BIT '$.isTaxable',
             arrear_applicable BIT '$.arrearApplicable', final_settlement BIT '$.finalSettlement', calculate_only BIT '$.calculateOnly') j;
        IF EXISTS (SELECT 1 FROM @items i WHERE NOT EXISTS (SELECT 1 FROM [pay].[pay_item] p WHERE p.id = i.pay_item_id AND p.company_id = @company_id))
            THROW 50400, N'payItems|A pay item was not found.', 1;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @code NVARCHAR(30);
    IF @id IS NULL
    BEGIN
        IF @pay_items IS NULL OR NOT EXISTS (SELECT 1 FROM @items)
        BEGIN
            EXEC [pay].[usp_pay_item_system_ensure] @company_id = @company_id;
            DELETE @items;
            INSERT @items SELECT id, is_taxable, 0, 0, 0 FROM [pay].[pay_item] WHERE company_id = @company_id;
        END
        BEGIN TRAN;
            EXEC [pay].[usp_sequence_next] @company_id, N'PR-', 5, @code OUTPUT;
            INSERT [pay].[payroll] (company_id, code, name, kind, payroll_month, currency, tax_structure_id, tax_applicable,
                                    processing_mode, processing_date, applicable_days, fixed_days, disbursement_bank_id,
                                    description, status, created_by)
            VALUES (@company_id, @code, @name, N'monthly', @payroll_month, @currency, @tax_structure_id, @tax_applicable,
                    @processing_mode, @processing_date, @applicable_days, @fixed_days, @disbursement_bank_id,
                    @description, N'open', @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [pay].[payroll_pay_item] (payroll_id, pay_item_id, is_taxable, arrear_applicable, final_settlement, calculate_only, created_by)
            SELECT @id, pay_item_id, is_taxable, arrear_applicable, final_settlement, calculate_only, @actor_user_id FROM @items;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.payroll', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @rv BINARY(8), @status NVARCHAR(30), @old_month DATE;
        SELECT @rv = row_version, @status = status, @old_month = payroll_month
        FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = N'monthly';
        IF @rv IS NULL
            THROW 50404, N'Payroll not found', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;
        IF @status = N'closed'
            THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. It cannot be changed', 1;
        IF @old_month <> @payroll_month AND EXISTS (SELECT 1 FROM [pay].[payslip] WHERE payroll_id = @id)
            THROW 50409, N'payrollMonth|This payroll has been run. Its month cannot change', 1;
        IF @old_month <> @payroll_month AND EXISTS (
            SELECT 1 FROM [pay].[payroll_employee] pe
            JOIN [pay].[payroll_employee] o ON o.employee_id = pe.employee_id AND o.payroll_id <> @id
            JOIN [pay].[payroll] op ON op.id = o.payroll_id AND op.kind = N'monthly' AND op.payroll_month = @payroll_month
            WHERE pe.payroll_id = @id)
            THROW 50409, N'payrollMonth|Some of the employees are already in another payroll for that month.', 1;

        BEGIN TRAN;
            UPDATE [pay].[payroll]
            SET name = @name, payroll_month = @payroll_month, currency = @currency, tax_structure_id = @tax_structure_id,
                tax_applicable = @tax_applicable, processing_mode = @processing_mode, processing_date = @processing_date,
                applicable_days = @applicable_days, fixed_days = @fixed_days, disbursement_bank_id = @disbursement_bank_id,
                description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;
            IF @pay_items IS NOT NULL
            BEGIN
                DELETE [pay].[payroll_pay_item] WHERE payroll_id = @id;
                INSERT [pay].[payroll_pay_item] (payroll_id, pay_item_id, is_taxable, arrear_applicable, final_settlement, calculate_only, created_by)
                SELECT @id, pay_item_id, is_taxable, arrear_applicable, final_settlement, calculate_only, @actor_user_id FROM @items;
            END
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.payroll', @id, N'update', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [pay].[usp_payroll_get] @company_id = @company_id, @id = @id;
END
GO

-- Deletes a payroll that is not closed, with its payslips. Not when any payslip was released or paid,
-- or vouchers were made from it.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @kind          NVARCHAR(30),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = row_version, @status = status FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id AND kind = @kind;
    IF @rv IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this payroll. Reload it and try again', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. It cannot be deleted', 1;
    IF EXISTS (SELECT 1 FROM [pay].[payslip] WHERE payroll_id = @id AND status = N'released')
        THROW 50409, N'Payslips of this payroll were released. It cannot be deleted', 1;
    IF EXISTS (SELECT 1 FROM [pay].[voucher] WHERE payroll_id = @id)
        THROW 50409, N'Vouchers were made from this payroll. It cannot be deleted', 1;

    BEGIN TRAN;
        DELETE [pay].[employee_account_entry] WHERE payslip_id IN (SELECT id FROM [pay].[payslip] WHERE payroll_id = @id) AND pay_rule_id IS NOT NULL;
        DELETE [pay].[payslip_line] WHERE payslip_id IN (SELECT id FROM [pay].[payslip] WHERE payroll_id = @id);
        DELETE [pay].[payslip] WHERE payroll_id = @id;
        DELETE [pay].[payroll_run_error] WHERE payroll_run_log_id IN (SELECT id FROM [pay].[payroll_run_log] WHERE payroll_id = @id);
        DELETE [pay].[payroll_run_log] WHERE payroll_id = @id;
        DELETE [pay].[payroll_employee] WHERE payroll_id = @id;
        DELETE [pay].[payroll_pay_item] WHERE payroll_id = @id;
        DELETE [pay].[payroll] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.payroll', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- The people in a run ("View Employments").
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_employee_list]
    @company_id BIGINT,
    @id         BIGINT,
    @search     NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Payroll not found', 1;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT e.id AS employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           d.name AS designation_name, dp.name AS department_name, b.name AS branch_name, e.status AS employee_status,
           ep.joining_date, ps.id AS payslip_id, ps.status AS payslip_status, ps.net_payable
    FROM [pay].[payroll_employee] pe
    JOIN [hr].[employee] e ON e.id = pe.employee_id
    LEFT JOIN [org].[designation] d ON d.id = e.designation_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    OUTER APPLY (SELECT TOP 1 joining_date FROM [hr].[employment_period] x WHERE x.employee_id = e.id ORDER BY x.joining_date DESC) ep
    LEFT JOIN [pay].[payslip] ps ON ps.payroll_id = pe.payroll_id AND ps.employee_id = e.id
    WHERE pe.payroll_id = @id
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
    ORDER BY e.first_name, e.last_name, e.id;
END
GO

-- Replaces the people in a run (@mode 'replace') or adds to them (@mode 'add'). @employee_ids: JSON array.
-- Someone already in another run of the same month (monthly) or day (daily wages) is refused; people
-- removed lose their payslip unless it was released.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_employee_set]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @employee_ids    NVARCHAR(MAX),
    @mode            NVARCHAR(10) = N'replace'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @kind NVARCHAR(30), @status NVARCHAR(30), @month DATE, @work_date DATE;
    SELECT @kind = kind, @status = status, @month = payroll_month, @work_date = work_date
    FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id;
    IF @kind IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. Its employees cannot change', 1;
    IF ISJSON(@employee_ids) <> 1
        THROW 50400, N'employeeIds|Employees are not valid.', 1;

    DECLARE @ids TABLE (employee_id BIGINT PRIMARY KEY);
    INSERT @ids SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) FROM OPENJSON(@employee_ids) WHERE TRY_CONVERT(BIGINT, [value]) IS NOT NULL;

    IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (
        SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = i.employee_id))
        THROW 50400, N'employeeIds|An employee was not found.', 1;

    DECLARE @clash NVARCHAR(400) = (
        SELECT TOP 1 CONCAT(e.first_name, N' ', e.last_name, N' is already in ', op.name, N' (', op.code, N').')
        FROM @ids i
        JOIN [pay].[payroll_employee] o ON o.employee_id = i.employee_id AND o.payroll_id <> @id
        JOIN [pay].[payroll] op ON op.id = o.payroll_id AND op.kind = @kind
             AND ((@kind = N'monthly' AND op.payroll_month = @month) OR (@kind = N'daily_wage' AND op.work_date = @work_date))
        JOIN [hr].[employee] e ON e.id = i.employee_id);
    IF @clash IS NOT NULL
    BEGIN
        SET @clash = N'employeeIds|PAYROLL_EMPLOYEE_CONFLICT|' + @clash;
        THROW 50409, @clash, 1;
    END

    IF @mode = N'replace' AND EXISTS (
        SELECT 1 FROM [pay].[payslip] ps
        WHERE ps.payroll_id = @id AND ps.status = N'released' AND ps.employee_id NOT IN (SELECT employee_id FROM @ids))
        THROW 50409, N'employeeIds|A person whose payslip was released cannot be removed.', 1;

    BEGIN TRAN;
        IF @mode = N'replace'
        BEGIN
            DECLARE @gone TABLE (payslip_id BIGINT);
            INSERT @gone SELECT ps.id FROM [pay].[payslip] ps
            WHERE ps.payroll_id = @id AND ps.employee_id NOT IN (SELECT employee_id FROM @ids);
            DELETE [pay].[employee_account_entry] WHERE payslip_id IN (SELECT payslip_id FROM @gone) AND pay_rule_id IS NOT NULL;
            DELETE [pay].[payslip_line] WHERE payslip_id IN (SELECT payslip_id FROM @gone);
            DELETE [pay].[payslip] WHERE id IN (SELECT payslip_id FROM @gone);
            DELETE [pay].[payroll_employee] WHERE payroll_id = @id AND employee_id NOT IN (SELECT employee_id FROM @ids);
        END
        INSERT [pay].[payroll_employee] (payroll_id, employee_id, created_by)
        SELECT @id, i.employee_id, @actor_user_id FROM @ids i
        WHERE NOT EXISTS (SELECT 1 FROM [pay].[payroll_employee] x WHERE x.payroll_id = @id AND x.employee_id = i.employee_id);
        UPDATE [pay].[payroll] SET updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    SELECT COUNT(*) AS employee_count FROM [pay].[payroll_employee] WHERE payroll_id = @id;
END
GO

-- Adds everyone the filters match (Employments -> Add with filters, or All Employees). People already
-- in another run of the same month or day are skipped and counted.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_employee_add_filtered]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @id                 BIGINT,
    @branch_id          BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @designation_id     BIGINT = NULL,
    @grade_id           BIGINT = NULL,
    @location_id        BIGINT = NULL,
    @employee_group_id  BIGINT = NULL,
    @employment_type_id BIGINT = NULL,
    @employee_status    NVARCHAR(30) = NULL,
    @joined_from        DATE = NULL,
    @joined_to          DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @kind NVARCHAR(30), @status NVARCHAR(30), @month DATE, @work_date DATE;
    SELECT @kind = kind, @status = status, @month = payroll_month, @work_date = work_date
    FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id;
    IF @kind IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @status = N'closed'
        THROW 50409, N'status|PAYROLL_CLOSED|This payroll is closed. Its employees cannot change', 1;

    DECLARE @match TABLE (employee_id BIGINT PRIMARY KEY, busy BIT);
    INSERT @match
    SELECT e.id,
           CASE WHEN EXISTS (SELECT 1 FROM [pay].[payroll_employee] o
                             JOIN [pay].[payroll] op ON op.id = o.payroll_id AND op.kind = @kind AND o.payroll_id <> @id
                                  AND ((@kind = N'monthly' AND op.payroll_month = @month) OR (@kind = N'daily_wage' AND op.work_date = @work_date))
                             WHERE o.employee_id = e.id) THEN 1 ELSE 0 END
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    OUTER APPLY (SELECT TOP 1 joining_date FROM [hr].[employment_period] x WHERE x.employee_id = e.id ORDER BY x.joining_date DESC) ep
    WHERE e.company_id = @company_id
      AND (@employee_status IS NULL OR e.status = @employee_status)
      AND (@employee_status IS NOT NULL OR e.status <> N'left')
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@designation_id IS NULL OR e.designation_id = @designation_id)
      AND (@grade_id IS NULL OR e.grade_id = @grade_id)
      AND (@location_id IS NULL OR e.location_id = @location_id)
      AND (@employee_group_id IS NULL OR e.employee_group_id = @employee_group_id)
      AND (@employment_type_id IS NULL OR e.employment_type_id = @employment_type_id)
      AND (@joined_from IS NULL OR ep.joining_date >= @joined_from)
      AND (@joined_to IS NULL OR ep.joining_date <= @joined_to)
    OPTION (RECOMPILE);

    DECLARE @added INT;
    BEGIN TRAN;
        INSERT [pay].[payroll_employee] (payroll_id, employee_id, created_by)
        SELECT @id, m.employee_id, @actor_user_id FROM @match m
        WHERE m.busy = 0 AND NOT EXISTS (SELECT 1 FROM [pay].[payroll_employee] x WHERE x.payroll_id = @id AND x.employee_id = m.employee_id);
        SET @added = @@ROWCOUNT;
        UPDATE [pay].[payroll] SET updated_at = SYSUTCDATETIME(), updated_by = @actor_user_id WHERE id = @id;
    COMMIT;

    SELECT @added AS added, (SELECT COUNT(*) FROM @match WHERE busy = 1) AS skipped,
           (SELECT COUNT(*) FROM [pay].[payroll_employee] WHERE payroll_id = @id) AS employee_count;
END
GO

-- Puts a whole run on hold (its ready payslips with it), or takes it off hold.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_hold]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @hold          BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30) = (SELECT status FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id);
    IF @status IS NULL
        THROW 50404, N'Payroll not found', 1;
    IF @hold = 1 AND @status <> N'running'
        THROW 50409, N'Only a payroll that has been run and is not closed can be put on hold', 1;
    IF @hold = 0 AND @status <> N'on_hold'
        THROW 50409, N'This payroll is not on hold', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [pay].[payroll] SET status = CASE WHEN @hold = 1 THEN N'on_hold' ELSE N'running' END,
               updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;
        UPDATE [pay].[payslip] SET status = CASE WHEN @hold = 1 THEN N'on_hold' ELSE N'ready' END, updated_at = @now, updated_by = @actor_user_id
        WHERE payroll_id = @id AND status = CASE WHEN @hold = 1 THEN N'ready' ELSE N'on_hold' END;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.payroll', @id, N'status', @status, CASE WHEN @hold = 1 THEN N'on_hold' ELSE N'running' END,
                CASE WHEN @hold = 1 THEN N'hold' ELSE N'unhold' END, @actor_user_id, @now);
    COMMIT;
    EXEC [pay].[usp_payroll_get] @company_id = @company_id, @id = @id;
END
GO

-- Payrolls History: every run and close, newest first.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_history]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Payroll not found', 1;
    SELECT l.id, l.kind, l.started_at, l.finished_at, l.status, l.processed_count, l.error_count, l.run_by_user_id,
           COALESCE(NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '), u.display_name, u.email) AS run_by_name
    FROM [pay].[payroll_run_log] l
    LEFT JOIN [auth].[user_account] u ON u.id = l.run_by_user_id
    LEFT JOIN [hr].[employee] e ON e.id = u.employee_id
    WHERE l.payroll_id = @id
    ORDER BY l.id DESC;
END
GO

-- Payrolls History Error: the errors of one run (@run_log_id), or of the latest run.
CREATE OR ALTER PROCEDURE [pay].[usp_payroll_errors]
    @company_id BIGINT,
    @id         BIGINT,
    @run_log_id BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[payroll] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Payroll not found', 1;
    IF @run_log_id IS NULL
        SET @run_log_id = (SELECT MAX(id) FROM [pay].[payroll_run_log] WHERE payroll_id = @id AND kind IN (N'run', N'recalculate'));
    SELECT r.id, r.payroll_run_log_id, r.employee_id, e.code AS employee_code,
           NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name, r.message, l.started_at
    FROM [pay].[payroll_run_error] r
    JOIN [pay].[payroll_run_log] l ON l.id = r.payroll_run_log_id AND l.payroll_id = @id
    LEFT JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.payroll_run_log_id = @run_log_id
    ORDER BY r.id;
END
