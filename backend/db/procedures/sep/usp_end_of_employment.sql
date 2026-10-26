-- End of Employment (All / Pending / Completed), its off-boarding checklist answers, completion
-- and rehire. Records are employee-owned: every read and write goes through auth.fn_visible_employees.
-- A record completes (sep.usp_end_of_employment_try_complete) once sep.fn_end_of_employment_waiting
-- is empty: the employee then leaves (hr.employee.status = left, the open hr.employment_period ends).
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_list]
    @company_id     BIGINT,
    @actor_user_id  BIGINT,
    @search         NVARCHAR(200) = NULL,
    @status         NVARCHAR(30) = NULL,
    @employee_id    BIGINT = NULL,
    @department_id  BIGINT = NULL,
    @branch_id      BIGINT = NULL,
    @location_id    BIGINT = NULL,
    @designation_id BIGINT = NULL,
    @serve_notice   BIT = NULL,
    @from_date      DATE = NULL,
    @to_date        DATE = NULL,
    @page           INT = 1,
    @page_size      INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'offboarding.end_of_employment.view') v ON v.employee_id = x.employee_id
    JOIN [hr].[employee] e ON e.id = x.employee_id
    WHERE x.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@status IS NULL OR x.status = @status)
      AND (@employee_id IS NULL OR x.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@location_id IS NULL OR e.location_id = @location_id)
      AND (@designation_id IS NULL OR e.designation_id = @designation_id)
      AND (@serve_notice IS NULL OR x.serve_notice = @serve_notice)
      AND (@from_date IS NULL OR x.last_working_date >= @from_date)
      AND (@to_date IS NULL OR x.last_working_date <= @to_date)
    OPTION (RECOMPILE);

    SELECT x.id, x.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           b.name AS branch_name, l.name AS location_name, d.name AS department_name, g.name AS designation_name,
           x.reason, x.serve_notice, x.last_working_date, x.status, x.completed_at,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM [hr].[employment_period] p
                                  WHERE p.employee_id = x.employee_id AND p.joining_date > x.last_working_date)
                     AND x.status = N'completed' THEN 1 ELSE 0 END AS BIT) AS is_rehired,
           x.created_at, x.updated_at, x.row_version
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'offboarding.end_of_employment.view') v ON v.employee_id = x.employee_id
    JOIN [hr].[employee] e ON e.id = x.employee_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    LEFT JOIN [org].[location] l ON l.id = e.location_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [org].[designation] g ON g.id = e.designation_id
    WHERE x.company_id = @company_id
      AND (@pattern IS NULL OR CONCAT(e.first_name, N' ', e.last_name) LIKE @pattern OR e.code LIKE @pattern)
      AND (@status IS NULL OR x.status = @status)
      AND (@employee_id IS NULL OR x.employee_id = @employee_id)
      AND (@department_id IS NULL OR e.department_id = @department_id)
      AND (@branch_id IS NULL OR e.branch_id = @branch_id)
      AND (@location_id IS NULL OR e.location_id = @location_id)
      AND (@designation_id IS NULL OR e.designation_id = @designation_id)
      AND (@serve_notice IS NULL OR x.serve_notice = @serve_notice)
      AND (@from_date IS NULL OR x.last_working_date >= @from_date)
      AND (@to_date IS NULL OR x.last_working_date <= @to_date)
    ORDER BY x.created_at DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- One record. Result set 1: the record with the employee card, clearance and settlement status.
-- Result set 2: checklist answers. Result set 3: what it is still waiting for.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @id              BIGINT,
    @permission_code NVARCHAR(150) = N'offboarding.end_of_employment.view'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [sep].[end_of_employment] x
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = x.employee_id
                   WHERE x.id = @id AND x.company_id = @company_id)
        THROW 50404, N'End of employment not found', 1;

    SELECT x.id, x.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
           e.email AS employee_email, e.phone_1 AS employee_phone, e.date_of_birth, e.photo_file_id,
           b.name AS branch_name, l.name AS location_name, d.name AS department_name, g.name AS designation_name,
           p.joining_date,
           x.reason, x.resignation_request_id, x.serve_notice, x.notice_period_days, x.last_working_date,
           x.needs_final_settlement, x.needs_asset_clearance, x.asset_clear_by_date,
           x.replacement_id, NULLIF(CONCAT(rp.first_name, N' ', rp.last_name), N' ') AS replacement_name,
           x.delegatee_id, NULLIF(CONCAT(dl.first_name, N' ', dl.last_name), N' ') AS delegatee_name,
           x.description, x.file_id, (SELECT sf.name FROM [core].[stored_file] sf WHERE sf.id = x.file_id) AS file_name,
           x.status, x.completed_at,
           fs.id AS final_settlement_id, fs.status AS final_settlement_status,
           c.id AS clearance_id, c.status AS clearance_status,
           r.joining_date AS rehire_joining_date,
           CAST(CASE WHEN r.joining_date IS NOT NULL AND x.status = N'completed' THEN 1 ELSE 0 END AS BIT) AS is_rehired,
           x.created_at, x.updated_at, x.row_version
    FROM [sep].[end_of_employment] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    LEFT JOIN [org].[branch] b ON b.id = e.branch_id
    LEFT JOIN [org].[location] l ON l.id = e.location_id
    LEFT JOIN [org].[department] d ON d.id = e.department_id
    LEFT JOIN [org].[designation] g ON g.id = e.designation_id
    LEFT JOIN [hr].[employee] rp ON rp.id = x.replacement_id
    LEFT JOIN [hr].[employee] dl ON dl.id = x.delegatee_id
    LEFT JOIN [sep].[final_settlement] fs ON fs.end_of_employment_id = x.id
    OUTER APPLY (SELECT TOP 1 ac.id, ac.status FROM [sep].[asset_clearance] ac
                 WHERE ac.end_of_employment_id = x.id ORDER BY ac.id DESC) c
    OUTER APPLY (SELECT TOP 1 pp.joining_date FROM [hr].[employment_period] pp
                 WHERE pp.employee_id = x.employee_id AND (pp.joining_date IS NULL OR pp.joining_date <= x.last_working_date)
                 ORDER BY pp.joining_date DESC, pp.id DESC) p
    OUTER APPLY (SELECT TOP 1 rr.joining_date FROM [hr].[employment_period] rr
                 WHERE rr.employee_id = x.employee_id AND rr.joining_date > x.last_working_date
                 ORDER BY rr.joining_date, rr.id) r
    WHERE x.id = @id;

    SELECT a.checklist_field_id, f.name AS field_name, f.field_type, k.id AS checklist_id, k.name AS checklist_name, a.answer
    FROM [sep].[checklist_answer] a
    JOIN [sep].[checklist_field] f ON f.id = a.checklist_field_id
    JOIN [sep].[offboarding_checklist] k ON k.id = f.offboarding_checklist_id
    WHERE a.end_of_employment_id = @id
    ORDER BY k.name, f.sort_order, f.id;

    SELECT item, label FROM [sep].[fn_end_of_employment_waiting](@id) ORDER BY sort_order;
END
GO

-- Completes a pending record when nothing is waiting: the employee leaves on the last working date.
-- @raise = 1 THROWs what it is waiting for; otherwise it does nothing when something is.
-- Payroll calls this after closing a final settlement.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_try_complete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @raise         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @status NVARCHAR(30), @employee_id BIGINT, @lwd DATE;
    SELECT @status = status, @employee_id = employee_id, @lwd = last_working_date
    FROM [sep].[end_of_employment] WHERE id = @id AND company_id = @company_id;
    IF @status IS NULL
        THROW 50404, N'End of employment not found', 1;
    IF @status <> N'pending'
    BEGIN
        IF @raise = 1
            THROW 50409, N'status|END_OF_EMPLOYMENT_COMPLETED|This end of employment is already completed.', 1;
        RETURN;
    END

    DECLARE @waiting NVARCHAR(1000) = (SELECT STRING_AGG(label, N', ') WITHIN GROUP (ORDER BY sort_order)
                                       FROM [sep].[fn_end_of_employment_waiting](@id));
    IF @waiting IS NOT NULL
    BEGIN
        IF @raise = 1
        BEGIN
            DECLARE @msg NVARCHAR(2048) = N'status|END_OF_EMPLOYMENT_WAITING|Waiting for: ' + @waiting + N'.';
            THROW 50409, @msg, 1;
        END
        RETURN;
    END

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [sep].[end_of_employment]
        SET status = N'completed', completed_at = @now, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id;

        UPDATE [hr].[employee] SET status = N'left', updated_at = @now, updated_by = @actor_user_id
        WHERE id = @employee_id;

        UPDATE [hr].[employment_period]
        SET end_date = @lwd, end_of_employment_id = @id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = (SELECT TOP 1 id FROM [hr].[employment_period]
                    WHERE employee_id = @employee_id AND end_date IS NULL
                    ORDER BY joining_date DESC, id DESC);

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.end_of_employment', @id, N'status', N'pending', N'completed', N'complete', @actor_user_id, @now);

        EXEC [sep].[usp_end_of_employment_announce] @company_id = @company_id, @id = @id, @event_type = N'offboarding.completed';
        -- The employees module's event for the status change (the employee has left).
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @employee_id,
             @event_type = N'employees.deactivated', @change = N'left', @actor_user_id = @actor_user_id;
    COMMIT;
END
GO

-- Adds a record (@id NULL) or edits a pending one. Final Settlement ticked starts a pending
-- sep.final_settlement for payroll; unticking drops it while payroll has not started on it.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_save]
    @company_id             BIGINT,
    @actor_user_id          BIGINT,
    @id                     BIGINT = NULL,
    @employee_id            BIGINT,
    @reason                 NVARCHAR(30),
    @serve_notice           BIT = 0,
    @notice_period_days     INT = NULL,
    @last_working_date      DATE = NULL,
    @needs_final_settlement BIT = 0,
    @needs_asset_clearance  BIT = 0,
    @asset_clear_by_date    DATE = NULL,
    @replacement_id         BIGINT = NULL,
    @delegatee_id           BIGINT = NULL,
    @description            NVARCHAR(MAX) = NULL,
    @file_id                BIGINT = NULL,
    @row_version            BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @code NVARCHAR(150) = CASE WHEN @id IS NULL THEN N'offboarding.end_of_employment.create'
                                       ELSE N'offboarding.end_of_employment.edit' END;
    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @today DATE = CAST(SYSDATETIME() AS DATE);
    SET @serve_notice = ISNULL(@serve_notice, 0);
    SET @needs_final_settlement = ISNULL(@needs_final_settlement, 0);
    SET @needs_asset_clearance = ISNULL(@needs_asset_clearance, 0);

    DECLARE @emp_status NVARCHAR(30) = (
        SELECT e.status FROM [hr].[employee] e
        JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @code) v ON v.employee_id = e.id
        WHERE e.id = @employee_id AND e.company_id = @company_id);
    IF @emp_status IS NULL
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF @employee_id = @actor_employee_id
        THROW 50403, N'You cannot start or change your own end of employment.', 1;
    IF @reason IS NULL OR @reason NOT IN (N'resignation', N'termination', N'retirement', N'other')
        THROW 50400, N'reason|Reason must be resignation, termination, retirement or other.', 1;
    IF @serve_notice = 1 AND @last_working_date IS NULL
        THROW 50400, N'lastWorkingDate|Last working date is required with a notice period.', 1;
    IF @notice_period_days < 0
        THROW 50400, N'noticePeriodDays|Notice period cannot be negative.', 1;
    IF @replacement_id IS NOT NULL AND (@replacement_id = @employee_id
            OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @replacement_id AND company_id = @company_id AND status <> N'left'))
        THROW 50400, N'replacementId|Choose another employee who is still working here.', 1;
    IF @delegatee_id IS NOT NULL AND (@delegatee_id = @employee_id
            OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @delegatee_id AND company_id = @company_id AND status <> N'left'))
        THROW 50400, N'delegateeId|Choose another employee who is still working here.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    IF @id IS NULL
    BEGIN
        -- Without a notice period the employee leaves on the day the record is made.
        IF @serve_notice = 0 AND @last_working_date IS NULL
            SET @last_working_date = @today;
        IF @emp_status = N'left'
            THROW 50409, N'employeeId|EMPLOYEE_LEFT|This employee has already left.', 1;
        IF EXISTS (SELECT 1 FROM [sep].[end_of_employment] WHERE company_id = @company_id AND employee_id = @employee_id AND status = N'pending')
            THROW 50409, N'employeeId|END_OF_EMPLOYMENT_OPEN|This employee already has a pending end of employment.', 1;

        BEGIN TRAN;
            INSERT [sep].[end_of_employment] (company_id, employee_id, reason, serve_notice, notice_period_days,
                last_working_date, needs_final_settlement, needs_asset_clearance, asset_clear_by_date, replacement_id,
                delegatee_id, description, file_id, status, created_by)
            VALUES (@company_id, @employee_id, @reason, @serve_notice, @notice_period_days, @last_working_date,
                @needs_final_settlement, @needs_asset_clearance, @asset_clear_by_date, @replacement_id, @delegatee_id,
                @description, @file_id, N'pending', @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            IF @needs_final_settlement = 1
                INSERT [sep].[final_settlement] (company_id, end_of_employment_id, status, created_by)
                VALUES (@company_id, @id, N'pending', @actor_user_id);

            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'sep.end_of_employment', @id, N'create', @actor_user_id, @now);

            EXEC [sep].[usp_end_of_employment_announce] @company_id = @company_id, @id = @id, @event_type = N'offboarding.started';

            EXEC [sep].[usp_end_of_employment_try_complete] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30), @old_employee BIGINT, @old_lwd DATE;
        SELECT @old_rv = row_version, @old_status = status, @old_employee = employee_id, @old_lwd = last_working_date
        FROM [sep].[end_of_employment] WHERE id = @id AND company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'End of employment not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an end of employment.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;
        IF @old_status <> N'pending'
            THROW 50409, N'status|END_OF_EMPLOYMENT_COMPLETED|A completed end of employment cannot be changed.', 1;
        IF @old_employee <> @employee_id
            THROW 50400, N'employeeId|The employee of an end of employment cannot be changed.', 1;
        IF @serve_notice = 0 AND @last_working_date IS NULL
            SET @last_working_date = @old_lwd;

        DECLARE @fs_id BIGINT, @fs_status NVARCHAR(30), @fs_payslip BIGINT;
        SELECT @fs_id = id, @fs_status = status, @fs_payslip = payslip_id
        FROM [sep].[final_settlement] WHERE end_of_employment_id = @id;
        IF @needs_final_settlement = 0 AND @fs_id IS NOT NULL AND (@fs_status <> N'pending' OR @fs_payslip IS NOT NULL)
            THROW 50409, N'needsFinalSettlement|Payroll has started the final settlement; it cannot be dropped.', 1;

        BEGIN TRAN;
            UPDATE [sep].[end_of_employment]
            SET reason = @reason, serve_notice = @serve_notice, notice_period_days = @notice_period_days,
                last_working_date = @last_working_date, needs_final_settlement = @needs_final_settlement,
                needs_asset_clearance = @needs_asset_clearance, asset_clear_by_date = @asset_clear_by_date,
                replacement_id = @replacement_id, delegatee_id = @delegatee_id, description = @description,
                file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;

            IF @needs_final_settlement = 1 AND @fs_id IS NULL
                INSERT [sep].[final_settlement] (company_id, end_of_employment_id, status, created_by)
                VALUES (@company_id, @id, N'pending', @actor_user_id);
            IF @needs_final_settlement = 0 AND @fs_id IS NOT NULL
                DELETE [sep].[final_settlement] WHERE id = @fs_id;

            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'sep.end_of_employment', @id, N'update', @actor_user_id, @now);

            EXEC [sep].[usp_end_of_employment_try_complete] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
        COMMIT;
    END

    EXEC [sep].[usp_end_of_employment_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = @code;
END
GO

-- Saves Checklist tab answers. @answers is a JSON array of {"checklist_field_id", "answer"} (answer as
-- text: numbers as digits, dates as yyyy-mm-dd, booleans as true / false; empty clears it).
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_checklist_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @answers       NVARCHAR(MAX),
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT, @msg NVARCHAR(2048), @bad BIGINT;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    SELECT @rv = x.row_version, @status = x.status, @employee_id = x.employee_id
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'offboarding.end_of_employment.edit') v ON v.employee_id = x.employee_id
    WHERE x.id = @id AND x.company_id = @company_id;

    IF @rv IS NULL
        THROW 50404, N'End of employment not found', 1;
    IF @employee_id = @actor_employee_id
        THROW 50403, N'You cannot start or change your own end of employment.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;
    IF @status <> N'pending'
        THROW 50409, N'status|END_OF_EMPLOYMENT_COMPLETED|A completed end of employment cannot be changed.', 1;
    IF ISJSON(ISNULL(@answers, N'')) = 0
        THROW 50400, N'answers|Answers are not valid.', 1;

    DECLARE @a TABLE (checklist_field_id BIGINT PRIMARY KEY, answer NVARCHAR(MAX), field_type NVARCHAR(30) NULL,
                      min_value DECIMAL(18,4) NULL, max_value DECIMAL(18,4) NULL, min_length INT NULL, max_length INT NULL);
    INSERT @a (checklist_field_id, answer)
    SELECT x.checklist_field_id, MAX(NULLIF(LTRIM(RTRIM(x.answer)), N''))
    FROM OPENJSON(@answers) WITH (checklist_field_id BIGINT '$.checklist_field_id', answer NVARCHAR(MAX) '$.answer') x
    WHERE x.checklist_field_id IS NOT NULL
    GROUP BY x.checklist_field_id;

    UPDATE a SET field_type = f.field_type, min_value = f.min_value, max_value = f.max_value,
                 min_length = f.min_length, max_length = f.max_length
    FROM @a a
    JOIN [sep].[checklist_field] f ON f.id = a.checklist_field_id
    JOIN [sep].[offboarding_checklist] k ON k.id = f.offboarding_checklist_id
    WHERE k.company_id = @company_id AND k.is_active = 1;

    SELECT TOP 1 @bad = checklist_field_id FROM @a WHERE field_type IS NULL;
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers.', @bad, N'|This field is not on an active off-boarding checklist.');
        THROW 50400, @msg, 1;
    END

    UPDATE @a SET answer = LOWER(answer) WHERE field_type = N'boolean';

    SELECT TOP 1 @bad = checklist_field_id FROM @a WHERE answer IS NOT NULL AND (
           (field_type = N'number' AND TRY_CONVERT(DECIMAL(18,4), answer) IS NULL)
        OR (field_type = N'date' AND TRY_CONVERT(DATE, answer, 23) IS NULL)
        OR (field_type = N'boolean' AND answer NOT IN (N'true', N'false')));
    IF @bad IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'answers.', @bad, N'|This answer is not a valid ',
                          (SELECT field_type FROM @a WHERE checklist_field_id = @bad), N'.');
        THROW 50400, @msg, 1;
    END

    SELECT TOP 1 @bad = checklist_field_id FROM @a WHERE answer IS NOT NULL AND field_type = N'number' AND (
           (min_value IS NOT NULL AND TRY_CONVERT(DECIMAL(18,4), answer) < min_value)
        OR (max_value IS NOT NULL AND TRY_CONVERT(DECIMAL(18,4), answer) > max_value));
    IF @bad IS NOT NULL
    BEGIN
        SELECT @msg = CONCAT(N'answers.', @bad, N'|The value must be between ',
                             ISNULL(FORMAT(min_value, N'0.####'), N'any'), N' and ', ISNULL(FORMAT(max_value, N'0.####'), N'any'), N'.')
        FROM @a WHERE checklist_field_id = @bad;
        THROW 50400, @msg, 1;
    END

    SELECT TOP 1 @bad = checklist_field_id FROM @a WHERE answer IS NOT NULL AND field_type = N'string' AND (
           (min_length IS NOT NULL AND LEN(answer) < min_length)
        OR (max_length IS NOT NULL AND LEN(answer) > max_length));
    IF @bad IS NOT NULL
    BEGIN
        SELECT @msg = CONCAT(N'answers.', @bad, N'|The text must be ', ISNULL(CAST(min_length AS NVARCHAR(10)), N'0'),
                             N' to ', ISNULL(CAST(max_length AS NVARCHAR(10)), N'any'), N' characters long.')
        FROM @a WHERE checklist_field_id = @bad;
        THROW 50400, @msg, 1;
    END

    BEGIN TRAN;
        UPDATE [sep].[end_of_employment] SET updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;

        DELETE ans FROM [sep].[checklist_answer] ans
        JOIN @a a ON a.checklist_field_id = ans.checklist_field_id
        WHERE ans.end_of_employment_id = @id AND a.answer IS NULL;

        UPDATE ans SET answer = a.answer, updated_at = @now, updated_by = @actor_user_id
        FROM [sep].[checklist_answer] ans
        JOIN @a a ON a.checklist_field_id = ans.checklist_field_id
        WHERE ans.end_of_employment_id = @id AND a.answer IS NOT NULL;

        INSERT [sep].[checklist_answer] (end_of_employment_id, checklist_field_id, answer, created_by)
        SELECT @id, a.checklist_field_id, a.answer, @actor_user_id
        FROM @a a
        WHERE a.answer IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM [sep].[checklist_answer] ans
                          WHERE ans.end_of_employment_id = @id AND ans.checklist_field_id = a.checklist_field_id);

        EXEC [sep].[usp_end_of_employment_try_complete] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id;
    COMMIT;

    EXEC [sep].[usp_end_of_employment_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'offboarding.end_of_employment.edit';
END
GO

-- Complete button: completes now, or answers 409 with what it is waiting for.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_complete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @rv BINARY(8), @employee_id BIGINT;
    SELECT @rv = x.row_version, @employee_id = x.employee_id
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'offboarding.end_of_employment.edit') v ON v.employee_id = x.employee_id
    WHERE x.id = @id AND x.company_id = @company_id;

    IF @rv IS NULL
        THROW 50404, N'End of employment not found', 1;
    IF @employee_id = @actor_employee_id
        THROW 50403, N'You cannot start or change your own end of employment.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;

    EXEC [sep].[usp_end_of_employment_try_complete] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id, @raise = 1;

    EXEC [sep].[usp_end_of_employment_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'offboarding.end_of_employment.edit';
END
GO

-- Deletes a pending record. In-progress clearance forms stay, unlinked; an approved one, or a
-- settlement payroll has started, stops the delete.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT;
    SELECT @rv = x.row_version, @status = x.status, @employee_id = x.employee_id
    FROM [sep].[end_of_employment] x
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'offboarding.end_of_employment.delete') v ON v.employee_id = x.employee_id
    WHERE x.id = @id AND x.company_id = @company_id;

    IF @rv IS NULL
        THROW 50404, N'End of employment not found', 1;
    IF @employee_id = @actor_employee_id
        THROW 50403, N'You cannot start or change your own end of employment.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;
    IF @status <> N'pending'
        THROW 50409, N'status|END_OF_EMPLOYMENT_COMPLETED|A completed end of employment cannot be deleted.', 1;
    IF EXISTS (SELECT 1 FROM [sep].[asset_clearance] WHERE end_of_employment_id = @id AND status = N'approved')
        THROW 50409, N'Its asset clearance is approved. Unapprove the clearance first.', 1;
    IF EXISTS (SELECT 1 FROM [sep].[final_settlement] WHERE end_of_employment_id = @id AND (status <> N'pending' OR payslip_id IS NOT NULL))
        THROW 50409, N'Payroll has started the final settlement.', 1;

    BEGIN TRAN;
        UPDATE [sep].[asset_clearance] SET end_of_employment_id = NULL WHERE end_of_employment_id = @id;
        DELETE [sep].[checklist_answer] WHERE end_of_employment_id = @id;
        DELETE [sep].[final_settlement] WHERE end_of_employment_id = @id;
        DELETE [sep].[end_of_employment] WHERE id = @id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.end_of_employment', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Rehire a past employee on the same record: a new hr.employment_period from @joining_date,
-- everything else kept. Only from the employee's latest, completed end of employment.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_rehire]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @joining_date  DATE,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @employee_id BIGINT, @lwd DATE, @emp_status NVARCHAR(30);
    SELECT @rv = x.row_version, @status = x.status, @employee_id = x.employee_id, @lwd = x.last_working_date,
           @emp_status = e.status
    FROM [sep].[end_of_employment] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, N'offboarding.rehire.process') v ON v.employee_id = x.employee_id
    WHERE x.id = @id AND x.company_id = @company_id;

    IF @rv IS NULL
        THROW 50404, N'End of employment not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;
    IF @status <> N'completed'
        THROW 50409, N'status|END_OF_EMPLOYMENT_PENDING|Only a completed end of employment can be rehired.', 1;
    IF @emp_status <> N'left' OR EXISTS (SELECT 1 FROM [sep].[end_of_employment] WHERE employee_id = @employee_id AND id > @id)
        THROW 50409, N'employeeId|ALREADY_REHIRED|This employee has been rehired since.', 1;
    IF @joining_date IS NULL
        THROW 50400, N'joiningDate|Joining date is required.', 1;
    IF @joining_date <= @lwd
        THROW 50400, N'joiningDate|The joining date must be after the last working date.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        INSERT [hr].[employment_period] (employee_id, joining_date, created_by)
        VALUES (@employee_id, @joining_date, @actor_user_id);

        UPDATE [hr].[employee] SET status = N'active', updated_at = @now, updated_by = @actor_user_id
        WHERE id = @employee_id;

        UPDATE [sep].[end_of_employment] SET updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this end of employment. Reload it and try again', 1;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'sep.end_of_employment', @id, N'joining_date', NULL, CONVERT(NVARCHAR(10), @joining_date, 23), N'rehire',
                @actor_user_id, @now);

        EXEC [sep].[usp_end_of_employment_announce] @company_id = @company_id, @id = @id, @event_type = N'offboarding.rehired';
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @employee_id,
             @event_type = N'employees.reactivated', @change = N'rehire', @actor_user_id = @actor_user_id;
    COMMIT;

    EXEC [sep].[usp_end_of_employment_get] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
         @permission_code = N'offboarding.rehire.process';
END
GO

-- Publishes offboarding.started / offboarding.completed for one end of employment. On start, the
-- delegatee (who takes over the work) is told. Called inside the caller's transaction; no result set.
CREATE OR ALTER PROCEDURE [sep].[usp_end_of_employment_announce]
    @company_id BIGINT,
    @id         BIGINT,
    @event_type NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @delegatee BIGINT, @name NVARCHAR(400), @lwd DATE, @payload NVARCHAR(MAX);
    SELECT @delegatee = x.delegatee_id, @name = NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' '),
           @lwd = x.last_working_date,
           @payload = (SELECT CONVERT(NVARCHAR(30), x.id) AS endOfEmploymentId, CONVERT(NVARCHAR(30), x.employee_id) AS employeeId,
                              e.code AS employeeCode, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employeeName,
                              x.reason, CONVERT(NVARCHAR(30), x.resignation_request_id) AS resignationRequestId,
                              CONVERT(NVARCHAR(10), x.last_working_date, 23) AS lastWorkingDate,
                              x.needs_final_settlement AS needsFinalSettlement, x.needs_asset_clearance AS needsAssetClearance,
                              CONVERT(NVARCHAR(30), x.replacement_id) AS replacementId,
                              CONVERT(NVARCHAR(30), x.delegatee_id) AS delegateeId, x.status, x.completed_at AS completedAt
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM [sep].[end_of_employment] x
    JOIN [hr].[employee] e ON e.id = x.employee_id
    WHERE x.id = @id AND x.company_id = @company_id;
    IF @payload IS NULL
        RETURN;

    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event_type,
         @entity_type = N'sep.end_of_employment', @entity_id = @id, @payload = @payload;

    IF @event_type = N'offboarding.started' AND @delegatee IS NOT NULL
    BEGIN
        DECLARE @title NVARCHAR(200) = LEFT(CONCAT(N'You will take over the work of ', @name), 200);
        DECLARE @body NVARCHAR(MAX) = CONCAT(N'Last working date: ', CONVERT(NVARCHAR(10), @lwd, 23), N'.');
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @delegatee,
             @title = @title, @body = @body, @notification_type = N'offboarding',
             @entity_type = N'sep.end_of_employment', @entity_id = @id;
    END
END
