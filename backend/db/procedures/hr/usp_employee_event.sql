-- Employee events and the profile tabs' shared bookkeeping. Callers run these inside their own
-- transaction, so the event is kept only when the change is.

-- Publishes employees.created / updated / deactivated / reactivated with the employee's identity and
-- placement (never the CNIC, salary or bank details). @change says what happened: joining, edit,
-- identity, photo, update_request, promotion, demotion, transfer, <kind>_cancelled.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_event_publish]
    @company_id    BIGINT,
    @employee_id   BIGINT,
    @event_type    NVARCHAR(100),
    @change        NVARCHAR(50) = NULL,
    @actor_user_id BIGINT = NULL,
    @request_id    BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), e.id) AS employeeId, e.code, LTRIM(RTRIM(CONCAT(e.first_name, N' ', e.last_name))) AS name,
               e.status, e.email, CONVERT(NVARCHAR(30), e.branch_id) AS branchId,
               CONVERT(NVARCHAR(30), e.department_id) AS departmentId, CONVERT(NVARCHAR(30), e.designation_id) AS designationId,
               CONVERT(NVARCHAR(30), e.job_title_id) AS jobTitleId, CONVERT(NVARCHAR(30), e.line_manager_id) AS lineManagerId,
               (SELECT TOP 1 ep.joining_date FROM [hr].[employment_period] ep WHERE ep.employee_id = e.id
                ORDER BY ep.joining_date DESC, ep.id DESC) AS joiningDate,
               @change AS change, CONVERT(NVARCHAR(30), @request_id) AS requestId,
               CONVERT(NVARCHAR(30), @actor_user_id) AS actorUserId
        FROM [hr].[employee] e
        WHERE e.id = @employee_id AND e.company_id = @company_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    IF @payload IS NULL
        RETURN;
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event_type, @entity_type = N'hr.employee',
         @entity_id = @employee_id, @payload = @payload;
END
GO

-- A profile tab row was added, changed or removed: one History row on the employee (field = the tab,
-- value = a short summary, never an identity number) and the employees.profile_changed event, which
-- says whether the employee changed their own profile (bySelf).
CREATE OR ALTER PROCEDURE [hr].[usp_employee_profile_changed]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @tab           NVARCHAR(50),
    @action        NVARCHAR(30),
    @row_id        BIGINT,
    @summary       NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
    VALUES (@company_id, N'hr.employee', @employee_id, @tab, CASE WHEN @action = N'delete' THEN @summary END,
            CASE WHEN @action <> N'delete' THEN @summary END, @action, @actor_user_id, @now);

    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), @employee_id) AS employeeId, @tab AS tab, @action AS action,
               CONVERT(NVARCHAR(30), @row_id) AS rowId,
               CAST(CASE WHEN EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @actor_user_id AND employee_id = @employee_id)
                         THEN 1 ELSE 0 END AS BIT) AS bySelf,
               CONVERT(NVARCHAR(30), @actor_user_id) AS actorUserId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'employees.profile_changed',
         @entity_type = N'hr.employee', @entity_id = @employee_id, @payload = @payload;
END
GO

-- Throws "not found" unless the caller reaches the employee through @permission_code.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_reach_check]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @permission_code NVARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] e
                   JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
                   WHERE e.id = @employee_id AND e.company_id = @company_id)
        THROW 50404, N'Employee not found', 1;
END
