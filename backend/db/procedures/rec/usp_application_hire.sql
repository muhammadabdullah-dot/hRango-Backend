-- Hiring. The service runs these in one transaction (db.transaction()):
--   1. rec.usp_application_hire_prepare   checks the application can be hired and returns the employee's
--                                         details from the applicant, the accepted offer and the opening;
--   2. hr.usp_employee_save               creates the employee and the first employment period (Employees'
--                                         own procedure, so codes, checks, history and audit stay in one place);
--   3. rec.usp_application_hire_complete  links the employee, records the joining salary and documents, fills
--                                         the vacancy (closing the opening and the Manpower seat when the last
--                                         one is filled), publishes recruitment.candidate_hired and tells the
--                                         hiring manager.

CREATE OR ALTER PROCEDURE [rec].[usp_application_hire_prepare]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rv BINARY(8), @stage NVARCHAR(30), @opening BIGINT, @employee BIGINT;
    SELECT @rv = a.row_version, @stage = a.stage, @opening = a.job_opening_id, @employee = a.employee_id
    FROM [rec].[application] a
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE a.id = @id AND a.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Application not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this application. Reload it and try again', 1;
    IF @stage = N'hired' OR @employee IS NOT NULL
        THROW 50409, N'stage|APPLICATION_HIRED|This candidate has already been hired.', 1;
    IF @stage IN (N'rejected', N'withdrawn')
        THROW 50409, N'stage|APPLICATION_CLOSED|A rejected or withdrawn application cannot be hired.', 1;
    IF NOT EXISTS (SELECT 1 FROM [rec].[offer] WHERE application_id = @id AND status = N'accepted')
        THROW 50409, N'offerId|OFFER_NOT_ACCEPTED|The candidate has not accepted an offer yet.', 1;
    IF EXISTS (SELECT 1 FROM [rec].[job_opening] o WHERE o.id = @opening AND o.status = N'closed')
        THROW 50409, N'jobOpeningId|OPENING_CLOSED|The opening is closed. Reopen it to hire.', 1;
    IF EXISTS (SELECT 1 FROM [rec].[job_opening] o WHERE o.id = @opening
               AND o.vacancies <= (SELECT COUNT(*) FROM [rec].[application] x WHERE x.job_opening_id = o.id AND x.stage = N'hired'))
        THROW 50409, N'jobOpeningId|OPENING_FILLED|Every vacancy of this opening is already filled.', 1;

    SELECT TOP 1 x.id AS offer_id, p.first_name, p.last_name, p.email, p.phone, p.gender, p.date_of_birth,
           ISNULL(x.branch_id, o.branch_id) AS branch_id, ISNULL(x.department_id, o.department_id) AS department_id,
           ISNULL(x.designation_id, o.designation_id) AS designation_id, ISNULL(x.job_title_id, o.job_title_id) AS job_title_id,
           ISNULL(x.employment_type_id, o.employment_type_id) AS employment_type_id,
           o.hiring_manager_id AS line_manager_id, x.joining_date, ISNULL(x.probation_months, 0) AS probation_months,
           x.offered_salary, ISNULL(x.salary_frequency, N'monthly') AS salary_frequency
    FROM [rec].[offer] x
    JOIN [rec].[application] a ON a.id = x.application_id
    JOIN [rec].[applicant] p ON p.id = a.applicant_id
    JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
    WHERE x.application_id = @id AND x.status = N'accepted'
    ORDER BY x.id DESC;
END
GO

CREATE OR ALTER PROCEDURE [rec].[usp_application_hire_complete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8),
    @employee_id     BIGINT,
    @salary          DECIMAL(18,2) = NULL,
    @joining_date    DATE,
    @remarks         NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @stage NVARCHAR(30), @opening BIGINT, @applicant BIGINT;
    SELECT @rv = a.row_version, @stage = a.stage, @opening = a.job_opening_id, @applicant = a.applicant_id
    FROM [rec].[application] a
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE a.id = @id AND a.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Application not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this application. Reload it and try again', 1;
    IF @stage IN (N'hired', N'rejected', N'withdrawn')
        THROW 50409, N'stage|APPLICATION_CLOSED|This application can no longer be hired.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id)
        THROW 50404, N'Employee not found', 1;

    DECLARE @offer BIGINT, @offer_letter BIGINT, @cv BIGINT, @op BIGINT, @vacancies INT, @hiring_manager BIGINT,
            @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT TOP 1 @offer = id, @offer_letter = offer_letter_file_id
    FROM [rec].[offer] WHERE application_id = @id AND status = N'accepted' ORDER BY id DESC;
    IF @offer IS NULL
        THROW 50409, N'offerId|OFFER_NOT_ACCEPTED|The candidate has not accepted an offer yet.', 1;
    SELECT @cv = cv_file_id FROM [rec].[applicant] WHERE id = @applicant;
    SELECT @op = open_position_id, @vacancies = vacancies, @hiring_manager = hiring_manager_id
    FROM [rec].[job_opening] WHERE id = @opening;

    BEGIN TRAN;
        UPDATE [rec].[application]
        SET employee_id = @employee_id, hired_at = @now, remarks = ISNULL(NULLIF(LTRIM(RTRIM(@remarks)), N''), remarks)
        WHERE id = @id;
        EXEC [rec].[usp_application_stage_write] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
             @to_stage = N'hired', @remarks = @remarks;

        -- The salary agreed in the offer, from the joining date (Employees' salary history).
        IF @salary IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee_salary] WHERE employee_id = @employee_id AND effective_date = @joining_date)
            INSERT [hr].[employee_salary] (employee_id, effective_date, amount, source, remarks, created_by)
            VALUES (@employee_id, @joining_date, @salary, N'joining', CONCAT(N'Offer ', @offer), @actor_user_id);

        -- The CV and the offer letter become the employee's documents (SRS EMP-3).
        INSERT [hr].[employee_document] (employee_id, document_type, file_id, created_by)
        SELECT @employee_id, d.document_type, d.file_id, @actor_user_id
        FROM (VALUES (N'cv', @cv), (N'offer_letter', @offer_letter)) d (document_type, file_id)
        WHERE d.file_id IS NOT NULL;

        -- The vacancy is filled: close the opening with its last vacancy, and take the seat off Manpower's open position.
        IF @vacancies <= (SELECT COUNT(*) FROM [rec].[application] WHERE job_opening_id = @opening AND stage = N'hired')
        BEGIN
            DECLARE @old_status NVARCHAR(30) = (SELECT status FROM [rec].[job_opening] WHERE id = @opening);
            UPDATE [rec].[job_opening] SET status = N'closed', closed_at = @now, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @opening;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'rec.job_opening', @opening, N'status', @old_status, N'closed', N'close', @actor_user_id, @now);
            DECLARE @closed NVARCHAR(MAX) = (
                SELECT CONVERT(NVARCHAR(30), o.id) AS jobOpeningId, o.code, o.title, o.status, o.vacancies,
                       CONVERT(NVARCHAR(30), o.department_id) AS departmentId, CONVERT(NVARCHAR(30), o.branch_id) AS branchId,
                       o.posted_on AS postedOn, o.apply_by AS applyBy, N'filled' AS reason
                FROM [rec].[job_opening] o WHERE o.id = @opening FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'recruitment.opening_closed',
                 @entity_type = N'rec.job_opening', @entity_id = @opening, @payload = @closed;
        END
        IF @op IS NOT NULL
        BEGIN
            DECLARE @seats INT, @op_status NVARCHAR(30);
            SELECT @seats = total_positions, @op_status = status FROM [mp].[open_position] WHERE id = @op;
            UPDATE [mp].[open_position]
            SET total_positions = CASE WHEN total_positions > 0 THEN total_positions - 1 ELSE 0 END,
                status = CASE WHEN total_positions <= 1 THEN N'closed' ELSE status END,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @op;
            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'mp.open_position', @op, N'total_positions', CONVERT(NVARCHAR(30), @seats),
                    CONVERT(NVARCHAR(30), CASE WHEN @seats > 0 THEN @seats - 1 ELSE 0 END), N'hire', @actor_user_id, @now);
        END

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), a.id) AS applicationId, CONVERT(NVARCHAR(30), a.applicant_id) AS applicantId,
                   CONCAT(p.first_name, N' ', p.last_name) AS applicantName, p.email,
                   CONVERT(NVARCHAR(30), e.id) AS employeeId, e.code AS employeeCode,
                   CONVERT(NVARCHAR(30), a.job_opening_id) AS jobOpeningId, o.title AS jobOpeningTitle,
                   CONVERT(NVARCHAR(30), @offer) AS offerId, @joining_date AS joiningDate,
                   CONVERT(NVARCHAR(30), e.department_id) AS departmentId, CONVERT(NVARCHAR(30), e.branch_id) AS branchId,
                   CONVERT(NVARCHAR(30), e.job_title_id) AS jobTitleId
            FROM [rec].[application] a
            JOIN [rec].[applicant] p ON p.id = a.applicant_id
            JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
            JOIN [hr].[employee] e ON e.id = @employee_id
            WHERE a.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'recruitment.candidate_hired',
             @entity_type = N'rec.application', @entity_id = @id, @payload = @payload;

        IF @hiring_manager IS NOT NULL
        BEGIN
            DECLARE @title NVARCHAR(200), @body NVARCHAR(MAX), @link NVARCHAR(500) = CONCAT(N'/recruitment/applications/', @id);
            SELECT @title = LEFT(CONCAT(N'Hired: ', p.first_name, N' ', p.last_name), 200),
                   @body = CONCAT(p.first_name, N' ', p.last_name, N' joins as ', o.title, N' on ',
                                  CONVERT(NVARCHAR(10), @joining_date, 23), N' (', e.code, N').')
            FROM [rec].[application] a
            JOIN [rec].[applicant] p ON p.id = a.applicant_id
            JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
            JOIN [hr].[employee] e ON e.id = @employee_id
            WHERE a.id = @id;
            EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @hiring_manager,
                 @title = @title, @body = @body, @notification_type = N'recruitment', @link = @link,
                 @entity_type = N'rec.application', @entity_id = @id;
        END
    COMMIT;

    EXEC [rec].[usp_application_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO
