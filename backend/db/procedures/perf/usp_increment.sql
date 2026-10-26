-- Performance -> Increments: what finalised appraisals proposed. Applying one is a salary revision written by
-- payroll's own procedure (pay.usp_salary_revision_save, called by the service in the same transaction, so
-- payroll's rules hold: newest salary only, no closed month); this records which revision it became.
-- Sensitive (salary figures): filtered on auth.fn_visible_employees with the endpoint's code.

CREATE OR ALTER PROCEDURE [perf].[usp_increment_list]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @status             NVARCHAR(30) = NULL,
    @appraisal_cycle_id BIGINT = NULL,
    @employee_id        BIGINT = NULL,
    @search             NVARCHAR(200) = NULL,
    @page               INT = 1,
    @page_size          INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT p.id INTO #ids
    FROM [perf].[fn_increment_rows](@company_id) p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE (@status IS NULL OR p.status = @status)
      AND (@appraisal_cycle_id IS NULL OR p.appraisal_cycle_id = @appraisal_cycle_id)
      AND (@employee_id IS NULL OR p.employee_id = @employee_id)
      AND (@pattern IS NULL OR p.employee_name LIKE @pattern OR p.employee_code LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM #ids;

    SELECT p.* FROM #ids i JOIN [perf].[fn_increment_rows](@company_id) p ON p.id = i.id
    ORDER BY CASE WHEN p.status = N'proposed' THEN 0 ELSE 1 END, p.effective_date, p.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE [perf].[usp_increment_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [perf].[increment_proposal] p
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
                   WHERE p.id = @id AND p.company_id = @company_id)
        THROW 50404, N'Increment not found', 1;
    SELECT p.* FROM [perf].[fn_increment_rows](@company_id) p WHERE p.id = @id;
END
GO

-- @decision 'applied' (with the salary revision payroll wrote) or 'rejected'.
CREATE OR ALTER PROCEDURE [perf].[usp_increment_decide]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @id                 BIGINT,
    @decision           NVARCHAR(30),
    @employee_salary_id BIGINT = NULL,
    @remarks            NVARCHAR(MAX) = NULL,
    @row_version        BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @status NVARCHAR(30), @emp BIGINT, @appraisal BIGINT;
    SELECT @rv = p.row_version, @status = p.status, @emp = p.employee_id, @appraisal = p.appraisal_id
    FROM [perf].[increment_proposal] p
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = p.employee_id
    WHERE p.id = @id AND p.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Increment not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this increment. Reload it and try again', 1;
    IF @status <> N'proposed'
        THROW 50409, N'status|INCREMENT_DECIDED|This increment has already been applied or rejected.', 1;
    IF @emp = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id)
        THROW 50403, N'You cannot decide your own increment.', 1;
    IF @decision NOT IN (N'applied', N'rejected')
        THROW 50400, N'decision|Unknown decision.', 1;
    IF @decision = N'applied' AND NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] WHERE id = @employee_salary_id AND employee_id = @emp)
        THROW 50400, N'employeeSalaryId|The salary revision was not found.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [perf].[increment_proposal]
        SET status = @decision, employee_salary_id = @employee_salary_id, remarks = ISNULL(@remarks, remarks),
            proposed_salary = CASE WHEN @decision = N'applied' THEN (SELECT amount FROM [hr].[employee_salary] WHERE id = @employee_salary_id)
                                   ELSE proposed_salary END,
            decided_at = @now, decided_by_user_id = @actor_user_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this increment. Reload it and try again', 1;
        DECLARE @type NVARCHAR(100) = CASE WHEN @decision = N'applied' THEN N'performance.increment_applied' ELSE N'performance.increment_rejected' END;
        DECLARE @payload NVARCHAR(MAX) = (SELECT CONVERT(NVARCHAR(20), @id) AS proposalId, CONVERT(NVARCHAR(20), @appraisal) AS appraisalId,
                                                 CONVERT(NVARCHAR(20), @emp) AS employeeId,
                                                 CONVERT(NVARCHAR(20), @employee_salary_id) AS employeeSalaryId
                                          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @type,
             @entity_type = N'perf.increment_proposal', @entity_id = @id, @payload = @payload;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'perf.increment_proposal', @id, N'status', @status, @decision, @decision, @actor_user_id, @now);
    COMMIT;

    EXEC [perf].[usp_increment_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
