-- Leave encashment: unused days of a leave type paid out for a leave year (Payroll -> Leave
-- Encashment). Each person gets the days available in that year, skipped below the type's Encashment
-- Min Limit and capped at its Max Limit; the days are debited from the balance ('encashed').
-- Mode 'payroll': payroll picks the lines up (payslip_id is set when a payslip pays them);
-- 'manual': paid outside payroll. Once a line is on a payslip the encashment cannot change.

CREATE OR ALTER FUNCTION [lv].[fn_leave_encashment_rows] (@company_id BIGINT, @actor_user_id BIGINT, @permission_code NVARCHAR(150))
RETURNS TABLE
AS RETURN
SELECT x.id, x.leave_type_id, t.title AS leave_type_title, t.short_code, x.fiscal_year, x.encashment_date,
       x.applies_to_all, x.basis, x.amount_per_leave, x.mode, s.employee_count, s.total_days, s.total_amount,
       s.paid_count, x.created_at, x.updated_at, x.row_version
FROM [lv].[leave_encashment] x
JOIN [lv].[leave_type] t ON t.id = x.leave_type_id
CROSS APPLY (SELECT COUNT(*) AS employee_count, ISNULL(SUM(l.days), 0) AS total_days, ISNULL(SUM(l.amount), 0) AS total_amount,
                    SUM(CASE WHEN l.payslip_id IS NOT NULL THEN 1 ELSE 0 END) AS paid_count
             FROM [lv].[leave_encashment_employee] l
             JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = l.employee_id
             WHERE l.leave_encashment_id = x.id) s
WHERE x.company_id = @company_id AND s.employee_count > 0;
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_encashment_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @leave_type_id   BIGINT = NULL,
    @fiscal_year     SMALLINT = NULL,
    @employee_id     BIGINT = NULL,
    @mode            NVARCHAR(30) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS total
    FROM [lv].[fn_leave_encashment_rows](@company_id, @actor_user_id, @permission_code) r
    WHERE (@leave_type_id IS NULL OR r.leave_type_id = @leave_type_id)
      AND (@fiscal_year IS NULL OR r.fiscal_year = @fiscal_year)
      AND (@mode IS NULL OR r.mode = @mode)
      AND (@employee_id IS NULL OR EXISTS (SELECT 1 FROM [lv].[leave_encashment_employee] l
                                           WHERE l.leave_encashment_id = r.id AND l.employee_id = @employee_id))
    OPTION (RECOMPILE);

    SELECT r.*
    FROM [lv].[fn_leave_encashment_rows](@company_id, @actor_user_id, @permission_code) r
    WHERE (@leave_type_id IS NULL OR r.leave_type_id = @leave_type_id)
      AND (@fiscal_year IS NULL OR r.fiscal_year = @fiscal_year)
      AND (@mode IS NULL OR r.mode = @mode)
      AND (@employee_id IS NULL OR EXISTS (SELECT 1 FROM [lv].[leave_encashment_employee] l
                                           WHERE l.leave_encashment_id = r.id AND l.employee_id = @employee_id))
    ORDER BY r.encashment_date DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Result set 1: the encashment. Result set 2: its lines (the people the actor reaches).
CREATE OR ALTER PROCEDURE [lv].[usp_leave_encashment_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [lv].[fn_leave_encashment_rows](@company_id, @actor_user_id, @permission_code) r WHERE r.id = @id)
        THROW 50404, N'Leave encashment not found', 1;

    SELECT r.* FROM [lv].[fn_leave_encashment_rows](@company_id, @actor_user_id, @permission_code) r WHERE r.id = @id;

    SELECT l.id, l.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           d.name AS department_name, l.days, l.amount, l.payslip_id
    FROM [lv].[leave_encashment_employee] l
    JOIN [hr].[employee] e ON e.id = l.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = l.employee_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE l.leave_encashment_id = @id
    ORDER BY e.first_name, e.last_name, e.id;
END
GO

-- Makes an encashment (@id NULL) for @employee_ids (JSON ["1","2"]) or, with @applies_to_all, every
-- active employee the actor reaches. Editing (@id given) changes the date, basis, amount per leave
-- and mode only; to change the type, year or people, delete it and make it again.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_encashment_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @id               BIGINT = NULL,
    @leave_type_id    BIGINT = NULL,
    @fiscal_year      SMALLINT = NULL,
    @encashment_date  DATE,
    @applies_to_all   BIT = 0,
    @employee_ids     NVARCHAR(MAX) = NULL,
    @basis            NVARCHAR(30),
    @amount_per_leave DECIMAL(18,2),
    @mode             NVARCHAR(30),
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @encashment_date IS NULL
        THROW 50400, N'encashmentDate|Date is required.', 1;
    IF @amount_per_leave IS NULL OR @amount_per_leave < 0
        THROW 50400, N'amountPerLeave|Amount per leave is required.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion is required to edit a leave encashment', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [lv].[leave_encashment] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Leave encashment not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this leave encashment. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [lv].[leave_encashment_employee] WHERE leave_encashment_id = @id AND payslip_id IS NOT NULL)
            THROW 50409, N'This encashment has been paid in a payslip and can no longer change', 1;

        BEGIN TRAN;
            UPDATE [lv].[leave_encashment]
            SET encashment_date = @encashment_date, basis = @basis, amount_per_leave = @amount_per_leave, mode = @mode,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this leave encashment. Reload it and try again', 1;

            UPDATE [lv].[leave_encashment_employee]
            SET amount = ROUND(days * @amount_per_leave, 2), updated_at = @now, updated_by = @actor_user_id
            WHERE leave_encashment_id = @id;
            UPDATE [lv].[leave_ledger] SET entry_date = @encashment_date, updated_at = @now, updated_by = @actor_user_id
            WHERE leave_encashment_id = @id;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'lv.leave_encashment', @id, N'amount_per_leave', CONVERT(NVARCHAR(30), @amount_per_leave), N'update', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @allow BIT, @min DECIMAL(6,2), @max DECIMAL(6,2);
        SELECT @allow = allow_encashment, @min = encashment_min, @max = encashment_max
        FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id;
        IF @allow IS NULL
            THROW 50400, N'leaveTypeId|Leave type not found.', 1;
        IF @allow = 0
            THROW 50400, N'leaveTypeId|This leave type cannot be encashed.', 1;
        IF @fiscal_year IS NULL OR @fiscal_year NOT BETWEEN 2000 AND 2100
            THROW 50400, N'fiscalYear|Choose a year.', 1;
        IF ISNULL(@applies_to_all, 0) = 0 AND (@employee_ids IS NULL OR ISJSON(@employee_ids) = 0)
            THROW 50400, N'employeeIds|Choose the employees, or all employees.', 1;

        DECLARE @chosen TABLE (employee_id BIGINT PRIMARY KEY);
        IF ISNULL(@applies_to_all, 0) = 0
        BEGIN
            INSERT @chosen SELECT DISTINCT TRY_CAST(j.value AS BIGINT) FROM OPENJSON(@employee_ids) j WHERE TRY_CAST(j.value AS BIGINT) IS NOT NULL;
            IF NOT EXISTS (SELECT 1 FROM @chosen)
                THROW 50400, N'employeeIds|Choose the employees, or all employees.', 1;
            IF EXISTS (SELECT 1 FROM @chosen c WHERE NOT EXISTS (
                           SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                           JOIN [hr].[employee] e ON e.id = v.employee_id WHERE v.employee_id = c.employee_id))
                THROW 50400, N'employeeIds|Employee not found.', 1;
        END

        DECLARE @start_month INT = (SELECT MONTH(year_start) FROM [lv].[fn_leave_year](@company_id, DATEFROMPARTS(@fiscal_year, 12, 31)));
        DECLARE @ys DATE = DATEFROMPARTS(@fiscal_year, @start_month, 1);

        DECLARE @lines TABLE (employee_id BIGINT, days DECIMAL(6,2));
        INSERT @lines
        SELECT e.id, CASE WHEN @max IS NOT NULL AND b.available > @max THEN @max ELSE b.available END
        FROM [hr].[employee] e
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
        CROSS APPLY [lv].[fn_leave_balance](@company_id, e.id, @leave_type_id, @ys) b
        WHERE e.company_id = @company_id AND e.status <> N'left'
          AND (@applies_to_all = 1 OR e.id IN (SELECT employee_id FROM @chosen))
          AND b.available > 0
          AND (@min IS NULL OR b.available >= @min);

        IF NOT EXISTS (SELECT 1 FROM @lines)
            THROW 50400, N'employeeIds|Nobody chosen has enough days of this leave type to encash.', 1;

        BEGIN TRAN;
            DECLARE @res NVARCHAR(100) = CONCAT(N'lv.encashment.', @company_id);
            EXEC sp_getapplock @Resource = @res, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;

            INSERT [lv].[leave_encashment] (company_id, leave_type_id, fiscal_year, encashment_date, applies_to_all, basis,
                                            amount_per_leave, mode, created_by)
            VALUES (@company_id, @leave_type_id, @fiscal_year, @encashment_date, ISNULL(@applies_to_all, 0), @basis,
                    @amount_per_leave, @mode, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [lv].[leave_encashment_employee] (leave_encashment_id, employee_id, days, amount, created_by)
            SELECT @id, employee_id, days, ROUND(days * @amount_per_leave, 2), @actor_user_id FROM @lines;

            INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, leave_encashment_id, created_by)
            SELECT employee_id, @leave_type_id, @fiscal_year, @encashment_date, -days, N'encashed', @id, @actor_user_id FROM @lines;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'lv.leave_encashment', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END

    EXEC [lv].[usp_leave_encashment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Deleting gives the days back (the 'encashed' postings go with it).
CREATE OR ALTER PROCEDURE [lv].[usp_leave_encashment_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [lv].[leave_encashment] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Leave encashment not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this leave encashment. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [lv].[leave_encashment_employee] WHERE leave_encashment_id = @id AND payslip_id IS NOT NULL)
        THROW 50409, N'This encashment has been paid in a payslip and can no longer be deleted', 1;

    BEGIN TRAN;
        DELETE [lv].[leave_ledger] WHERE leave_encashment_id = @id;
        DELETE [lv].[leave_encashment_employee] WHERE leave_encashment_id = @id;
        DELETE [lv].[leave_encashment] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'lv.leave_encashment', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
