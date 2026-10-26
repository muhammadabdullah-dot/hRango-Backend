-- Vouchers and Employee Voucher: created (pending), approved or rejected by the manager, then verified by
-- Finance, which marks them processed. Daily-wage vouchers start approved (usp_daily_wage_vouchers).

CREATE OR ALTER PROCEDURE [pay].[usp_voucher_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @designation_id  BIGINT = NULL,
    @voucher_type    NVARCHAR(30) = NULL,
    @status          NVARCHAR(30) = NULL,
    @voucher_no      NVARCHAR(30) = NULL,
    @payroll_id      BIGINT = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @amount_from     DECIMAL(18,2) = NULL,
    @amount_to       DECIMAL(18,2) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    -- voucherCode: a contains search on the voucher number
    DECLARE @voucher_pattern NVARCHAR(100) = CASE WHEN NULLIF(LTRIM(RTRIM(@voucher_no)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@voucher_no)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT v.id INTO #ids
    FROM [pay].[voucher] v
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) x ON x.employee_id = v.employee_id
    JOIN [hr].[employee] e ON e.id = v.employee_id
    WHERE v.company_id = @company_id
      AND (@employee_id IS NULL OR v.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@designation_id IS NULL OR e.designation_id = @designation_id)
      AND (@voucher_type IS NULL OR v.voucher_type = @voucher_type)
      AND (@status IS NULL OR v.status = @status)
      AND (@voucher_pattern IS NULL OR v.voucher_no LIKE @voucher_pattern)
      AND (@payroll_id IS NULL OR v.payroll_id = @payroll_id)
      AND (@from_date IS NULL OR v.voucher_date >= @from_date) AND (@to_date IS NULL OR v.voucher_date <= @to_date)
      AND (@amount_from IS NULL OR v.amount >= @amount_from) AND (@amount_to IS NULL OR v.amount <= @amount_to)
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern OR v.voucher_no LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT v.id, v.voucher_no, v.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, ds.name AS designation_name, v.voucher_type, v.voucher_date, v.currency, v.amount,
           v.payment_method, v.purpose, v.notes, v.file_id, f.name AS file_name, v.payroll_id, pr.name AS payroll_name,
           v.requested_by_id, NULLIF(CONCAT(rq.first_name, N' ', rq.last_name), N' ') AS requested_by_name,
           v.approved_by_id, v.decided_by_user_id AS approved_by_user_id,
           COALESCE(NULLIF(CONCAT_WS(N' ', ap.first_name, ap.last_name), N''), apu.display_name, apu.email) AS approved_by_name, v.approved_at,
           v.verified_by_id, v.verified_by_user_id,
           COALESCE(NULLIF(CONCAT_WS(N' ', vf.first_name, vf.last_name), N''), vfu.display_name, vfu.email) AS verified_by_name, v.verified_at,
           v.remarks, v.status, v.created_at, v.updated_at, v.row_version
    FROM #ids i
    JOIN [pay].[voucher] v ON v.id = i.id
    JOIN [hr].[employee] e ON e.id = v.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [core].[stored_file] f ON f.id = v.file_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = v.payroll_id
    LEFT JOIN [hr].[employee] rq ON rq.id = v.requested_by_id
    LEFT JOIN [hr].[employee] ap ON ap.id = v.approved_by_id
    LEFT JOIN [hr].[employee] vf ON vf.id = v.verified_by_id
    LEFT JOIN [auth].[user_account] apu ON apu.id = v.decided_by_user_id
    LEFT JOIN [auth].[user_account] vfu ON vfu.id = v.verified_by_user_id
    ORDER BY v.voucher_date DESC, v.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_voucher_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [pay].[voucher] v
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) x ON x.employee_id = v.employee_id
                   WHERE v.id = @id AND v.company_id = @company_id)
        THROW 50404, N'Voucher not found', 1;

    SELECT v.id, v.voucher_no, v.employee_id, e.code AS employee_code, CONCAT(e.first_name, N' ', e.last_name) AS employee_name,
           dp.name AS department_name, ds.name AS designation_name, v.voucher_type, v.voucher_date, v.currency, v.amount,
           v.payment_method, v.purpose, v.notes, v.file_id, f.name AS file_name, v.payroll_id, pr.name AS payroll_name,
           v.requested_by_id, NULLIF(CONCAT(rq.first_name, N' ', rq.last_name), N' ') AS requested_by_name,
           v.approved_by_id, v.decided_by_user_id AS approved_by_user_id,
           COALESCE(NULLIF(CONCAT_WS(N' ', ap.first_name, ap.last_name), N''), apu.display_name, apu.email) AS approved_by_name, v.approved_at,
           v.verified_by_id, v.verified_by_user_id,
           COALESCE(NULLIF(CONCAT_WS(N' ', vf.first_name, vf.last_name), N''), vfu.display_name, vfu.email) AS verified_by_name, v.verified_at,
           v.remarks, v.status, v.created_at, v.updated_at, v.row_version
    FROM [pay].[voucher] v
    JOIN [hr].[employee] e ON e.id = v.employee_id
    LEFT JOIN [org].[department] dp ON dp.id = e.department_id
    LEFT JOIN [org].[designation] ds ON ds.id = e.designation_id
    LEFT JOIN [core].[stored_file] f ON f.id = v.file_id
    LEFT JOIN [pay].[payroll] pr ON pr.id = v.payroll_id
    LEFT JOIN [hr].[employee] rq ON rq.id = v.requested_by_id
    LEFT JOIN [hr].[employee] ap ON ap.id = v.approved_by_id
    LEFT JOIN [hr].[employee] vf ON vf.id = v.verified_by_id
    LEFT JOIN [auth].[user_account] apu ON apu.id = v.decided_by_user_id
    LEFT JOIN [auth].[user_account] vfu ON vfu.id = v.verified_by_user_id
    WHERE v.id = @id;
END
GO

-- Adds an employee voucher (status pending) or edits one that is still pending. A blank voucher number
-- is given the next VCH- code. The requester defaults to the caller.
CREATE OR ALTER PROCEDURE [pay].[usp_voucher_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT = NULL,
    @employee_id     BIGINT,
    @voucher_no      NVARCHAR(30) = NULL,
    @voucher_type    NVARCHAR(30),
    @voucher_date    DATE,
    @currency        CHAR(3) = NULL,
    @amount          DECIMAL(18,2),
    @payment_method  NVARCHAR(30),
    @purpose         NVARCHAR(500),
    @notes           NVARCHAR(MAX) = NULL,
    @file_id         BIGINT = NULL,
    @requested_by_id BIGINT = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) WHERE employee_id = @employee_id)
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @requested_by_id IS NULL
        SET @requested_by_id = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @requested_by_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @requested_by_id AND company_id = @company_id)
        THROW 50400, N'requestedById|Employee not found.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    SET @voucher_no = NULLIF(LTRIM(RTRIM(@voucher_no)), N'');
    IF @voucher_no IS NOT NULL AND EXISTS (SELECT 1 FROM [pay].[voucher] WHERE company_id = @company_id AND voucher_no = @voucher_no AND (@id IS NULL OR id <> @id))
        THROW 50409, N'voucherNo|VOUCHER_DUPLICATE|A voucher with this number already exists.', 1;
    IF @currency IS NULL
        SET @currency = (SELECT currency FROM [org].[company] WHERE id = @company_id);

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            IF @voucher_no IS NULL
                EXEC [pay].[usp_sequence_next] @company_id, N'VCH-', 5, @voucher_no OUTPUT;
            INSERT [pay].[voucher] (company_id, voucher_no, employee_id, voucher_type, voucher_date, currency, amount, payment_method,
                                    purpose, notes, file_id, requested_by_id, status, created_by)
            VALUES (@company_id, @voucher_no, @employee_id, @voucher_type, @voucher_date, @currency, @amount, @payment_method,
                    @purpose, @notes, @file_id, @requested_by_id, N'pending', @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.voucher', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            DECLARE @rv BINARY(8), @status NVARCHAR(30);
            SELECT @rv = v.row_version, @status = v.status FROM [pay].[voucher] v
            JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) x ON x.employee_id = v.employee_id
            WHERE v.id = @id AND v.company_id = @company_id;
            IF @rv IS NULL
                THROW 50404, N'Voucher not found', 1;
            IF @rv <> @row_version
                THROW 50409, N'Someone else changed this voucher. Reload it and try again', 1;
            IF @status <> N'pending'
                THROW 50409, N'status|VOUCHER_DECIDED|Only a pending voucher can be changed', 1;
            UPDATE [pay].[voucher]
            SET employee_id = @employee_id, voucher_no = ISNULL(@voucher_no, voucher_no), voucher_type = @voucher_type,
                voucher_date = @voucher_date, currency = @currency, amount = @amount, payment_method = @payment_method,
                purpose = @purpose, notes = @notes, file_id = @file_id, requested_by_id = @requested_by_id,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'pay.voucher', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;
    EXEC [pay].[usp_voucher_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = @permission_code, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [pay].[usp_voucher_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30);
    SELECT @rv = v.row_version, @status = v.status FROM [pay].[voucher] v
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) x ON x.employee_id = v.employee_id
    WHERE v.id = @id AND v.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Voucher not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this voucher. Reload it and try again', 1;
    IF @status = N'processed'
        THROW 50409, N'status|VOUCHER_PROCESSED|A processed voucher cannot be deleted', 1;
    BEGIN TRAN;
        DELETE [pay].[voucher] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.voucher', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- approve / reject: pending -> approved / rejected, by the manager (Approval Web Flow).
-- verify: approved -> processed, by Finance (Verification). The decider is the caller's employee record.
-- Publishes payroll.voucher_decided and tells the employee.
CREATE OR ALTER PROCEDURE [pay].[usp_voucher_decide]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @action          NVARCHAR(10),
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT;
    SELECT @rv = v.row_version, @status = v.status, @employee_id = v.employee_id FROM [pay].[voucher] v
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) x ON x.employee_id = v.employee_id
    WHERE v.id = @id AND v.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Voucher not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this voucher. Reload it and try again', 1;
    IF @action IN (N'approve', N'reject') AND @status <> N'pending'
        THROW 50409, N'status|VOUCHER_DECIDED|This voucher was already decided', 1;
    IF @action = N'verify' AND @status <> N'approved'
        THROW 50409, N'status|VOUCHER_NOT_APPROVED|Only an approved voucher can be verified', 1;

    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    IF @me IS NOT NULL AND @me = @employee_id
        THROW 50403, N'You cannot decide your own voucher', 1;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @new NVARCHAR(30) = CASE @action WHEN N'approve' THEN N'approved' WHEN N'reject' THEN N'rejected' ELSE N'processed' END;

    BEGIN TRAN;
        UPDATE [pay].[voucher]
        SET status = @new,
            approved_by_id = CASE WHEN @action IN (N'approve', N'reject') THEN @me ELSE approved_by_id END,
            decided_by_user_id = CASE WHEN @action IN (N'approve', N'reject') THEN @actor_user_id ELSE decided_by_user_id END,
            approved_at = CASE WHEN @action IN (N'approve', N'reject') THEN @now ELSE approved_at END,
            verified_by_id = CASE WHEN @action = N'verify' THEN @me ELSE verified_by_id END,
            verified_by_user_id = CASE WHEN @action = N'verify' THEN @actor_user_id ELSE verified_by_user_id END,
            verified_at = CASE WHEN @action = N'verify' THEN @now ELSE verified_at END,
            remarks = ISNULL(@remarks, remarks), updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'pay.voucher', @id, N'status', @status, @new, @action, @actor_user_id, @now);

        DECLARE @voucher_no NVARCHAR(30), @payload NVARCHAR(MAX);
        SELECT @voucher_no = v.voucher_no,
               @payload = (SELECT CONVERT(NVARCHAR(30), v.id) AS voucherId, v.voucher_no AS voucherNo, v.voucher_type AS voucherType,
                                  CONVERT(NVARCHAR(30), v.employee_id) AS employeeId, v.amount, v.currency,
                                  @action AS [action], @status AS previousStatus, v.status, v.remarks,
                                  CONVERT(NVARCHAR(30), @me) AS decidedById, CONVERT(NVARCHAR(30), @actor_user_id) AS decidedBy
                           FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM [pay].[voucher] v WHERE v.id = @id;
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'payroll.voucher_decided',
             @entity_type = N'pay.voucher', @entity_id = @id, @payload = @payload;

        DECLARE @title NVARCHAR(200) = CONCAT(N'Your voucher ', @voucher_no, N' was ',
                                              CASE @new WHEN N'processed' THEN N'verified for payment' ELSE @new END);
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @employee_id,
             @title = @title, @body = @remarks, @notification_type = N'voucher', @link = N'/payroll/vouchers/employee',
             @entity_type = N'pay.voucher', @entity_id = @id;
    COMMIT;
    EXEC [pay].[usp_voucher_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @permission_code = @permission_code, @id = @id;
END
