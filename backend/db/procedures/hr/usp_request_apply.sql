-- Approval effects of promotion and transfer requests. The requests engine calls
-- usp_request_apply_<kind> inside the final approval's transaction, and usp_request_revert_<kind>
-- when an approved request is cancelled. A THROW blocks the approval and its message goes to the
-- approver. The change takes effect on approval; hr.employee_history keeps the request's
-- effective date. Applying twice does nothing the second time.

CREATE OR ALTER PROCEDURE [hr].[usp_request_apply_promotion]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @is_demotion BIT, @grade_id BIGINT, @job_level_id BIGINT, @designation_id BIGINT,
            @job_title_id BIGINT, @previous_salary DECIMAL(18,2), @new_salary DECIMAL(18,2), @effective_date DATE;
    SELECT @employee_id = r.employee_id, @is_demotion = p.is_demotion, @grade_id = p.grade_id, @job_level_id = p.job_level_id,
           @designation_id = p.designation_id, @job_title_id = p.job_title_id, @previous_salary = p.previous_salary,
           @new_salary = p.new_salary, @effective_date = p.effective_date
    FROM [req].[request] r
    JOIN [req].[req_promotion] p ON p.request_id = r.id
    JOIN [hr].[employee] e ON e.id = r.employee_id AND e.company_id = @company_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF @employee_id IS NULL
        THROW 50404, N'Promotion request not found', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_history] WHERE source_request_id = @request_id AND is_reverted = 0)
        RETURN;

    IF @grade_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[grade] WHERE id = @grade_id AND company_id = @company_id)
        THROW 50409, N'The grade on this promotion no longer exists.', 1;
    IF @job_level_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_level] WHERE id = @job_level_id AND company_id = @company_id)
        THROW 50409, N'The job level on this promotion no longer exists.', 1;
    IF @designation_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[designation] WHERE id = @designation_id AND company_id = @company_id)
        THROW 50409, N'The designation on this promotion no longer exists.', 1;
    IF @job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50409, N'The job title on this promotion no longer exists.', 1;
    IF @job_title_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND job_title_id = @job_title_id)
       AND EXISTS (SELECT 1 FROM [org].[job_title] j
                   WHERE j.id = @job_title_id AND j.limit_head_count = 1
                     AND j.max_head_count <= (SELECT COUNT(*) FROM [hr].[employee] x
                                              WHERE x.job_title_id = j.id AND x.status NOT IN (N'left', N'inactive')))
        THROW 50409, N'The new job title has reached its head-count limit.', 1;
    IF @new_salary < 0
        THROW 50409, N'The new salary on this promotion is negative.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    SET @effective_date = ISNULL(@effective_date, CAST(@now AS DATE));
    DECLARE @before NVARCHAR(MAX) = (
        SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
               line_manager_id, final_authority_id
        FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    BEGIN TRAN;
        UPDATE [hr].[employee]
        SET grade_id = ISNULL(@grade_id, grade_id), job_level_id = ISNULL(@job_level_id, job_level_id),
            designation_id = ISNULL(@designation_id, designation_id), job_title_id = ISNULL(@job_title_id, job_title_id),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @employee_id;

        INSERT [hr].[employee_history] (employee_id, change_type, effective_date, location_id, branch_id, department_id,
                                        designation_id, job_title_id, grade_id, job_level_id, line_manager_id,
                                        final_authority_id, source_request_id, previous_values, created_by)
        SELECT id, CASE WHEN @is_demotion = 1 THEN N'demotion' ELSE N'promotion' END, @effective_date, location_id,
               branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id, line_manager_id,
               final_authority_id, @request_id, @before, @actor_user_id
        FROM [hr].[employee] WHERE id = @employee_id;

        IF @new_salary IS NOT NULL
            INSERT [hr].[employee_salary] (employee_id, effective_date, amount, previous_amount, source, source_request_id, created_by)
            VALUES (@employee_id, @effective_date, @new_salary,
                    COALESCE((SELECT TOP 1 amount FROM [hr].[employee_salary]
                              WHERE employee_id = @employee_id AND effective_date <= @effective_date
                              ORDER BY effective_date DESC, id DESC), @previous_salary),
                    N'promotion', @request_id, @actor_user_id);

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'hr.employee', @employee_id, b.[key], b.value, a.value,
               CASE WHEN @is_demotion = 1 THEN N'demotion' ELSE N'promotion' END, @actor_user_id, @now
        FROM OPENJSON(@before) b
        JOIN OPENJSON((SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
                              line_manager_id, final_authority_id
                       FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) a
             ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);

        DECLARE @event_change NVARCHAR(50) = CASE WHEN @is_demotion = 1 THEN N'demotion' ELSE N'promotion' END;
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @employee_id,
             @event_type = N'employees.updated', @change = @event_change, @actor_user_id = @actor_user_id,
             @request_id = @request_id;
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_request_apply_transfer]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @employee_id BIGINT, @location_id BIGINT, @branch_id BIGINT, @department_id BIGINT,
            @line_manager_id BIGINT, @final_authority_id BIGINT, @effective_date DATE;
    SELECT @employee_id = r.employee_id, @location_id = t.location_id, @branch_id = t.branch_id,
           @department_id = t.department_id, @line_manager_id = t.line_manager_id,
           @final_authority_id = t.final_authority_id, @effective_date = t.effective_date
    FROM [req].[request] r
    JOIN [req].[req_transfer] t ON t.request_id = r.id
    JOIN [hr].[employee] e ON e.id = r.employee_id AND e.company_id = @company_id
    WHERE r.id = @request_id AND r.company_id = @company_id;

    IF @employee_id IS NULL
        THROW 50404, N'Transfer request not found', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_history] WHERE source_request_id = @request_id AND is_reverted = 0)
        RETURN;

    DECLARE @branch_location BIGINT, @branch_area BIGINT;
    IF @branch_id IS NOT NULL
    BEGIN
        SELECT @branch_location = location_id, @branch_area = area_id FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id;
        IF @branch_location IS NULL
            THROW 50409, N'The branch on this transfer no longer exists.', 1;
        IF @location_id IS NOT NULL AND @location_id <> @branch_location
            THROW 50409, N'The branch on this transfer is not in its location.', 1;
        SET @location_id = @branch_location;
    END
    ELSE IF @location_id IS NOT NULL
        THROW 50409, N'A transfer to another location needs a branch in that location.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50409, N'The department on this transfer no longer exists.', 1;
    IF @line_manager_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @line_manager_id AND company_id = @company_id)
        THROW 50409, N'The line manager on this transfer is not an employee of this company.', 1;
    IF @line_manager_id IS NOT NULL AND (@line_manager_id = @employee_id
        OR EXISTS (SELECT 1 FROM [hr].[fn_manager_chain](@line_manager_id) c WHERE c.id = @employee_id))
        THROW 50409, N'The new line manager reports to this employee, so they cannot manage them.', 1;
    IF @final_authority_id IS NOT NULL AND (@final_authority_id = @employee_id
        OR NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @final_authority_id AND company_id = @company_id))
        THROW 50409, N'The final authority on this transfer is not valid.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    SET @effective_date = ISNULL(@effective_date, CAST(@now AS DATE));
    DECLARE @before NVARCHAR(MAX) = (
        SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
               line_manager_id, final_authority_id, area_id
        FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    BEGIN TRAN;
        UPDATE [hr].[employee]
        SET location_id = ISNULL(@location_id, location_id),
            area_id = CASE WHEN @branch_id IS NOT NULL AND @branch_id <> branch_id THEN @branch_area ELSE area_id END,
            branch_id = ISNULL(@branch_id, branch_id), department_id = ISNULL(@department_id, department_id),
            line_manager_id = ISNULL(@line_manager_id, line_manager_id),
            final_authority_id = ISNULL(@final_authority_id, final_authority_id),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @employee_id;

        INSERT [hr].[employee_history] (employee_id, change_type, effective_date, location_id, branch_id, department_id,
                                        designation_id, job_title_id, grade_id, job_level_id, line_manager_id,
                                        final_authority_id, source_request_id, previous_values, created_by)
        SELECT id, N'transfer', @effective_date, location_id, branch_id, department_id, designation_id, job_title_id,
               grade_id, job_level_id, line_manager_id, final_authority_id, @request_id, @before, @actor_user_id
        FROM [hr].[employee] WHERE id = @employee_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'hr.employee', @employee_id, b.[key], b.value, a.value, N'transfer', @actor_user_id, @now
        FROM OPENJSON(@before) b
        JOIN OPENJSON((SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
                              line_manager_id, final_authority_id, area_id
                       FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) a
             ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);

        DECLARE @event_change NVARCHAR(50) = N'transfer';
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @employee_id,
             @event_type = N'employees.updated', @change = @event_change, @actor_user_id = @actor_user_id,
             @request_id = @request_id;
    COMMIT;
END
GO

-- Puts back what an approved promotion or transfer changed, when the request is cancelled. Refused
-- when the employee has been changed again since (undo the later change first).
CREATE OR ALTER PROCEDURE [hr].[usp_request_revert_placement]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT,
    @kinds         NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @history_id BIGINT, @employee_id BIGINT, @previous NVARCHAR(MAX), @change NVARCHAR(30);
    SELECT TOP 1 @history_id = h.id, @employee_id = h.employee_id, @previous = h.previous_values, @change = h.change_type
    FROM [hr].[employee_history] h
    JOIN [hr].[employee] e ON e.id = h.employee_id AND e.company_id = @company_id
    WHERE h.source_request_id = @request_id AND h.is_reverted = 0
      AND h.change_type IN (SELECT value FROM STRING_SPLIT(@kinds, N','))
    ORDER BY h.id DESC;

    IF @history_id IS NULL
        RETURN;  -- never applied, or already put back
    IF EXISTS (SELECT 1 FROM [hr].[employee_history] WHERE employee_id = @employee_id AND id > @history_id AND is_reverted = 0)
        THROW 50409, N'This employee''s placement has changed since this request was approved. Undo the later change first.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @before NVARCHAR(MAX) = (
        SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
               line_manager_id, final_authority_id, area_id
        FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    BEGIN TRAN;
        UPDATE [hr].[employee]
        SET location_id = TRY_CAST(JSON_VALUE(@previous, '$.location_id') AS BIGINT),
            branch_id = ISNULL(TRY_CAST(JSON_VALUE(@previous, '$.branch_id') AS BIGINT), branch_id),
            department_id = TRY_CAST(JSON_VALUE(@previous, '$.department_id') AS BIGINT),
            designation_id = TRY_CAST(JSON_VALUE(@previous, '$.designation_id') AS BIGINT),
            job_title_id = TRY_CAST(JSON_VALUE(@previous, '$.job_title_id') AS BIGINT),
            grade_id = TRY_CAST(JSON_VALUE(@previous, '$.grade_id') AS BIGINT),
            job_level_id = TRY_CAST(JSON_VALUE(@previous, '$.job_level_id') AS BIGINT),
            line_manager_id = TRY_CAST(JSON_VALUE(@previous, '$.line_manager_id') AS BIGINT),
            final_authority_id = TRY_CAST(JSON_VALUE(@previous, '$.final_authority_id') AS BIGINT),
            area_id = CASE WHEN @change = N'transfer' THEN TRY_CAST(JSON_VALUE(@previous, '$.area_id') AS BIGINT) ELSE area_id END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @employee_id;

        UPDATE [hr].[employee_history] SET is_reverted = 1, updated_at = @now, updated_by = @actor_user_id WHERE id = @history_id;
        DELETE [hr].[employee_salary] WHERE source_request_id = @request_id AND employee_id = @employee_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'hr.employee', @employee_id, b.[key], b.value, a.value, CONCAT(@change, N'_cancelled'), @actor_user_id, @now
        FROM OPENJSON(@before) b
        JOIN OPENJSON((SELECT location_id, branch_id, department_id, designation_id, job_title_id, grade_id, job_level_id,
                              line_manager_id, final_authority_id, area_id
                       FROM [hr].[employee] WHERE id = @employee_id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) a
             ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);

        DECLARE @event_change NVARCHAR(50) = CONCAT(@change, N'_cancelled');
        EXEC [hr].[usp_employee_event_publish] @company_id = @company_id, @employee_id = @employee_id,
             @event_type = N'employees.updated', @change = @event_change, @actor_user_id = @actor_user_id,
             @request_id = @request_id;
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_request_revert_promotion]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_request_revert_placement] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @request_id = @request_id, @kinds = N'promotion,demotion';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_request_revert_transfer]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @request_id    BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_request_revert_placement] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @request_id = @request_id, @kinds = N'transfer';
END
