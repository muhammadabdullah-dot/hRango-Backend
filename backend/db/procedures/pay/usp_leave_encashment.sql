-- Leave Encashment: unused leave days paid out, for one leave type and leave year, to everyone or to
-- chosen people. Writes lv.leave_encashment(_employee) (tables of the leave module) and debits the days
-- in lv.leave_ledger (reason 'encashed') so they cannot be paid twice. Mode 'payroll' pays through the
-- next monthly run (Leave Encashment pay item); 'manual' is paid outside payroll.

CREATE OR ALTER PROCEDURE [pay].[usp_leave_encashment_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @leave_type_id   BIGINT = NULL,
    @fiscal_year     INT = NULL,
    @employee_id     BIGINT = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT r.id INTO #ids
    FROM [lv].[leave_encashment_employee] r
    JOIN [lv].[leave_encashment] h ON h.id = r.leave_encashment_id AND h.company_id = @company_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    JOIN [hr].[employee] e ON e.id = r.employee_id
    JOIN [lv].[leave_type] lt ON lt.id = h.leave_type_id
    WHERE (@leave_type_id IS NULL OR h.leave_type_id = @leave_type_id)
      AND (@fiscal_year IS NULL OR h.fiscal_year = @fiscal_year)
      AND (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern OR lt.title LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT r.id, r.leave_encashment_id, h.leave_type_id, lt.title AS leave_type_name, r.employee_id, e.code AS employee_code,
           CONCAT(e.first_name, N' ', e.last_name) AS employee_name, h.fiscal_year, h.encashment_date, h.basis, h.mode,
           CAST(CASE WHEN r.days = 0 THEN 0 ELSE r.amount / r.days END AS DECIMAL(18,2)) AS amount_per_leave,
           r.days, r.amount, r.payslip_id, CAST(CASE WHEN r.payslip_id IS NULL THEN 0 ELSE 1 END AS BIT) AS is_paid,
           h.row_version
    FROM #ids i
    JOIN [lv].[leave_encashment_employee] r ON r.id = i.id
    JOIN [lv].[leave_encashment] h ON h.id = r.leave_encashment_id
    JOIN [lv].[leave_type] lt ON lt.id = h.leave_type_id
    JOIN [hr].[employee] e ON e.id = r.employee_id
    ORDER BY h.encashment_date DESC, h.id DESC, e.first_name
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

-- Result set 1: the encashment. Result set 2: its people.
CREATE OR ALTER PROCEDURE [pay].[usp_leave_encashment_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [lv].[leave_encashment] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Leave encashment not found', 1;
    SELECT h.id, h.leave_type_id, lt.title AS leave_type_name, h.fiscal_year, h.encashment_date, h.applies_to_all, h.basis,
           h.amount_per_leave, h.mode,
           (SELECT SUM(r.days) FROM [lv].[leave_encashment_employee] r WHERE r.leave_encashment_id = h.id) AS total_days,
           (SELECT SUM(r.amount) FROM [lv].[leave_encashment_employee] r WHERE r.leave_encashment_id = h.id) AS total_amount,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [lv].[leave_encashment_employee] r WHERE r.leave_encashment_id = h.id AND r.payslip_id IS NOT NULL)
                     THEN 1 ELSE 0 END AS BIT) AS is_paid,
           h.created_at, h.updated_at, h.row_version
    FROM [lv].[leave_encashment] h
    JOIN [lv].[leave_type] lt ON lt.id = h.leave_type_id
    WHERE h.id = @id;

    SELECT r.id, r.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name, r.days, r.amount,
           CAST(CASE WHEN r.days = 0 THEN 0 ELSE r.amount / r.days END AS DECIMAL(18,2)) AS amount_per_leave, r.payslip_id
    FROM [lv].[leave_encashment_employee] r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    JOIN [hr].[employee] e ON e.id = r.employee_id
    WHERE r.leave_encashment_id = @id
    ORDER BY e.first_name, e.last_name;
END
GO

-- Adds an encashment (@id NULL) or redoes one nobody has been paid for yet. Days are each person's balance
-- of the leave type for @fiscal_year (lv.fn_leave_balance's available days; when redoing, the ledger sum
-- with this encashment given back), within the type's encashment minimum and maximum. The rate per day is
-- @amount_per_leave, or for basis 'earned_salary' with no amount, a day's salary (monthly salary / 30).
CREATE OR ALTER PROCEDURE [pay].[usp_leave_encashment_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT,
    @permission_code  NVARCHAR(150),
    @id               BIGINT = NULL,
    @leave_type_id    BIGINT,
    @fiscal_year      INT,
    @all_employees    BIT = 0,
    @employee_ids     NVARCHAR(MAX) = N'[]',
    @mode             NVARCHAR(30),
    @basis            NVARCHAR(30),
    @amount_per_leave DECIMAL(18,2) = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @min DECIMAL(6,2), @max DECIMAL(6,2), @allowed BIT;
    SELECT @allowed = allow_encashment, @min = encashment_min, @max = encashment_max
    FROM [lv].[leave_type] WHERE id = @leave_type_id AND company_id = @company_id;
    IF @allowed IS NULL
        THROW 50400, N'leaveTypeId|Leave type not found.', 1;
    IF @allowed = 0
        THROW 50400, N'leaveTypeId|This leave type does not allow encashment.', 1;
    IF @amount_per_leave IS NULL AND @basis <> N'earned_salary'
        THROW 50400, N'amountPerLeave|Give the amount per leave for this basis.', 1;

    IF @id IS NOT NULL
    BEGIN
        DECLARE @rv BINARY(8) = (SELECT row_version FROM [lv].[leave_encashment] WHERE id = @id AND company_id = @company_id);
        IF @rv IS NULL
            THROW 50404, N'Leave encashment not found', 1;
        IF @rv <> @row_version
            THROW 50409, N'Someone else changed this leave encashment. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [lv].[leave_encashment_employee] WHERE leave_encashment_id = @id AND payslip_id IS NOT NULL)
            THROW 50409, N'status|ENCASHMENT_PAID|This encashment was paid through payroll. It cannot be changed', 1;
    END

    CREATE TABLE #b (employee_id BIGINT PRIMARY KEY, balance DECIMAL(6,2), salary DECIMAL(18,2));
    IF @all_employees = 1
        INSERT #b (employee_id)
        SELECT e.id FROM [hr].[employee] e
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
        WHERE e.company_id = @company_id AND e.status <> N'left'
          -- Nobody encashes their own leave.
          AND e.id <> ISNULL((SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id), 0);
    ELSE
    BEGIN
        INSERT #b (employee_id)
        SELECT DISTINCT TRY_CONVERT(BIGINT, [value]) FROM OPENJSON(ISNULL(@employee_ids, N'[]')) WHERE TRY_CONVERT(BIGINT, [value]) IS NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM #b)
            THROW 50400, N'employeeIds|Pick the employees, or All Employees.', 1;
        IF EXISTS (SELECT 1 FROM #b b WHERE NOT EXISTS (
            SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v WHERE v.employee_id = b.employee_id))
            THROW 50400, N'employeeIds|An employee was not found.', 1;
    END

    -- Balances: the ledger, the encashment being redone given back.
    UPDATE b SET balance = ISNULL((SELECT SUM(l.days) FROM [lv].[leave_ledger] l
                                   WHERE l.employee_id = b.employee_id AND l.leave_type_id = @leave_type_id AND l.fiscal_year = @fiscal_year
                                     AND (@id IS NULL OR ISNULL(l.leave_encashment_id, 0) <> @id)), 0),
                 salary = (SELECT TOP 1 s.amount FROM [hr].[employee_salary] s WHERE s.employee_id = b.employee_id
                           AND s.effective_date <= SYSUTCDATETIME() ORDER BY s.effective_date DESC, s.id DESC)
    FROM #b b;
    -- A new encashment takes what is available in that leave year (pending requests held back).
    IF @id IS NULL
    BEGIN
        DECLARE @year_start DATE = DATEFROMPARTS(@fiscal_year, ISNULL((SELECT CASE WHEN fiscal_year_start_month BETWEEN 1 AND 12
                                   THEN fiscal_year_start_month END FROM [org].[company] WHERE id = @company_id), 1), 1);
        UPDATE b SET balance = ISNULL(lb.available, 0)
        FROM #b b
        OUTER APPLY [lv].[fn_leave_balance](@company_id, b.employee_id, @leave_type_id, @year_start) lb;
    END

    DELETE #b WHERE balance <= 0 OR (@min IS NOT NULL AND balance < @min);
    UPDATE #b SET balance = @max WHERE @max IS NOT NULL AND balance > @max;
    IF @amount_per_leave IS NULL
        DELETE #b WHERE salary IS NULL;
    IF NOT EXISTS (SELECT 1 FROM #b)
        THROW 50400, N'employeeIds|Nobody chosen has leave days to encash.', 1;

    DECLARE @rate DECIMAL(18,2) = ISNULL(@amount_per_leave, (SELECT CAST(AVG(salary / 30.0) AS DECIMAL(18,2)) FROM #b));
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSUTCDATETIME() AS DATE);

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [lv].[leave_encashment] (company_id, leave_type_id, fiscal_year, encashment_date, applies_to_all, basis,
                                            amount_per_leave, mode, created_by)
            VALUES (@company_id, @leave_type_id, @fiscal_year, @today, @all_employees, @basis, @rate, @mode, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            DELETE [lv].[leave_ledger] WHERE leave_encashment_id = @id;
            DELETE [lv].[leave_encashment_employee] WHERE leave_encashment_id = @id;
            UPDATE [lv].[leave_encashment]
            SET leave_type_id = @leave_type_id, fiscal_year = @fiscal_year, applies_to_all = @all_employees, basis = @basis,
                amount_per_leave = @rate, mode = @mode, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this leave encashment. Reload it and try again', 1;
        END

        INSERT [lv].[leave_encashment_employee] (leave_encashment_id, employee_id, days, amount, created_by)
        SELECT @id, employee_id, balance, ROUND(balance * ISNULL(@amount_per_leave, salary / 30.0), 2), @actor_user_id FROM #b;

        INSERT [lv].[leave_ledger] (employee_id, leave_type_id, fiscal_year, entry_date, days, reason, remarks, leave_encashment_id, created_by)
        SELECT employee_id, @leave_type_id, @fiscal_year, @today, -balance, N'encashed', N'Leave encashment', @id, @actor_user_id FROM #b;

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'lv.leave_encashment', @id, CASE WHEN @row_version IS NULL THEN N'create' ELSE N'update' END, @actor_user_id, @now);
    COMMIT;

    EXEC [pay].[usp_leave_encashment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_leave_encashment_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
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
        THROW 50409, N'status|ENCASHMENT_PAID|This encashment was paid through payroll. It cannot be deleted', 1;
    BEGIN TRAN;
        DELETE [lv].[leave_ledger] WHERE leave_encashment_id = @id;
        DELETE [lv].[leave_encashment_employee] WHERE leave_encashment_id = @id;
        DELETE [lv].[leave_encashment] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'lv.leave_encashment', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
