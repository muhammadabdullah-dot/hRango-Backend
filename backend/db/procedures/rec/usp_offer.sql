-- Offers: draft, send (the application moves to the offer stage), record the candidate's answer
-- (accepted / declined), withdraw. One live offer (draft, sent or accepted) per application; a revised
-- offer is a new one after the last was declined or withdrawn. The offer letter is a file uploaded
-- through /api/files. Scope: the opening's (rec.fn_visible_openings).

-- Internal: publishes an offer event. No result set.
CREATE OR ALTER PROCEDURE [rec].[usp_offer_event]
    @company_id BIGINT,
    @id         BIGINT,
    @event_type NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), x.id) AS offerId, CONVERT(NVARCHAR(30), x.application_id) AS applicationId,
               CONVERT(NVARCHAR(30), a.job_opening_id) AS jobOpeningId, o.title AS jobOpeningTitle,
               CONVERT(NVARCHAR(30), a.applicant_id) AS applicantId, CONCAT(p.first_name, N' ', p.last_name) AS applicantName,
               p.email AS applicantEmail, x.status, x.offered_salary AS offeredSalary, x.salary_frequency AS salaryFrequency,
               x.joining_date AS joiningDate, x.expires_on AS expiresOn,
               CONVERT(NVARCHAR(30), x.offer_letter_file_id) AS offerLetterFileId, x.response_remarks AS responseRemarks
        FROM [rec].[offer] x
        JOIN [rec].[application] a ON a.id = x.application_id
        JOIN [rec].[applicant] p ON p.id = a.applicant_id
        JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
        WHERE x.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event_type,
         @entity_type = N'rec.offer', @entity_id = @id, @payload = @payload;
END
GO

CREATE OR ALTER PROCEDURE [rec].[usp_offer_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [rec].[offer] x
                   JOIN [rec].[application] a ON a.id = x.application_id
                   JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
                   WHERE x.id = @id AND x.company_id = @company_id)
        THROW 50404, N'Offer not found', 1;
    SELECT * FROM [rec].[fn_offer_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [rec].[usp_offer_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @job_opening_id  BIGINT = NULL,
    @application_id  BIGINT = NULL,
    @status          NVARCHAR(30) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @v TABLE (id BIGINT PRIMARY KEY);
    INSERT @v SELECT job_opening_id FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [rec].[fn_offer_rows](@company_id) x JOIN @v v ON v.id = x.job_opening_id
    WHERE (@pattern IS NULL OR x.applicant_name LIKE @pattern OR x.job_opening_title LIKE @pattern)
      AND (@job_opening_id IS NULL OR x.job_opening_id = @job_opening_id)
      AND (@application_id IS NULL OR x.application_id = @application_id)
      AND (@status IS NULL OR x.status = @status)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [rec].[fn_offer_rows](@company_id) x JOIN @v v ON v.id = x.job_opening_id
    WHERE (@pattern IS NULL OR x.applicant_name LIKE @pattern OR x.job_opening_title LIKE @pattern)
      AND (@job_opening_id IS NULL OR x.job_opening_id = @job_opening_id)
      AND (@application_id IS NULL OR x.application_id = @application_id)
      AND (@status IS NULL OR x.status = @status)
    ORDER BY x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL, as a draft) or edits a draft offer. Blank placement fields take the opening's.
CREATE OR ALTER PROCEDURE [rec].[usp_offer_save]
    @company_id           BIGINT,
    @actor_user_id        BIGINT,
    @permission_code      NVARCHAR(150),
    @id                   BIGINT = NULL,
    @application_id       BIGINT = NULL,
    @job_title_id         BIGINT = NULL,
    @designation_id       BIGINT = NULL,
    @department_id        BIGINT = NULL,
    @branch_id            BIGINT = NULL,
    @employment_type_id   BIGINT = NULL,
    @offered_salary       DECIMAL(18,2),
    @salary_frequency     NVARCHAR(30) = N'monthly',
    @joining_date         DATE,
    @probation_months     INT = NULL,
    @expires_on           DATE = NULL,
    @offer_letter_file_id BIGINT = NULL,
    @remarks              NVARCHAR(MAX) = NULL,
    @row_version          BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @stage NVARCHAR(30), @opening BIGINT, @old_rv BINARY(8), @old_status NVARCHAR(30);
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_rv = x.row_version, @old_status = x.status, @application_id = x.application_id
        FROM [rec].[offer] x
        JOIN [rec].[application] a ON a.id = x.application_id
        JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
        WHERE x.id = @id AND x.company_id = @company_id;
        IF @old_rv IS NULL
            THROW 50404, N'Offer not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an offer.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this offer. Reload it and try again', 1;
        IF @old_status <> N'draft'
            THROW 50409, N'status|OFFER_NOT_DRAFT|Only a draft offer can be edited. Withdraw it and make a new one.', 1;
    END
    SELECT @stage = a.stage, @opening = a.job_opening_id
    FROM [rec].[application] a
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE a.id = @application_id AND a.company_id = @company_id;
    IF @stage IS NULL
        THROW 50400, N'applicationId|Application not found.', 1;
    IF @stage IN (N'hired', N'rejected', N'withdrawn')
        THROW 50409, N'applicationId|APPLICATION_CLOSED|This application is closed; no offer can be made.', 1;
    IF @id IS NULL AND EXISTS (SELECT 1 FROM [rec].[offer] WHERE application_id = @application_id
                               AND status IN (N'draft', N'sent', N'accepted'))
        THROW 50409, N'applicationId|OFFER_EXISTS|This application already has an open offer.', 1;

    SELECT @job_title_id = ISNULL(@job_title_id, job_title_id), @designation_id = ISNULL(@designation_id, designation_id),
           @department_id = ISNULL(@department_id, department_id), @branch_id = ISNULL(@branch_id, branch_id),
           @employment_type_id = ISNULL(@employment_type_id, employment_type_id)
    FROM [rec].[job_opening] WHERE id = @opening;

    IF @offered_salary IS NULL OR @offered_salary <= 0
        THROW 50400, N'offeredSalary|Enter the salary offered.', 1;
    IF @salary_frequency IS NULL OR @salary_frequency NOT IN (N'monthly', N'daily', N'hourly')
        THROW 50400, N'salaryFrequency|Choose monthly, daily or hourly.', 1;
    IF @joining_date IS NULL
        THROW 50400, N'joiningDate|Joining date is required.', 1;
    IF @probation_months < 0 OR @probation_months > 24
        THROW 50400, N'probationMonths|Probation is 0 to 24 months.', 1;
    IF @expires_on > @joining_date
        THROW 50400, N'expiresOn|The offer should expire on or before the joining date.', 1;
    IF @job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50400, N'jobTitleId|Job title not found.', 1;
    IF @designation_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[designation] WHERE id = @designation_id AND company_id = @company_id)
        THROW 50400, N'designationId|Designation not found.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[branch] WHERE id = @branch_id AND company_id = @company_id)
        THROW 50400, N'branchId|Station not found.', 1;
    IF @employment_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[employment_type] WHERE id = @employment_type_id AND company_id = @company_id)
        THROW 50400, N'employmentTypeId|Employment type not found.', 1;
    IF @offer_letter_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @offer_letter_file_id))
        THROW 50400, N'offerLetterFileId|The offer letter file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [rec].[offer] (company_id, application_id, job_title_id, designation_id, department_id, branch_id,
                              employment_type_id, offered_salary, salary_frequency, joining_date, probation_months,
                              expires_on, offer_letter_file_id, status, remarks, created_by)
        VALUES (@company_id, @application_id, @job_title_id, @designation_id, @department_id, @branch_id,
                @employment_type_id, @offered_salary, @salary_frequency, @joining_date, ISNULL(@probation_months, 0),
                @expires_on, @offer_letter_file_id, N'draft', NULLIF(LTRIM(RTRIM(@remarks)), N''), @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.offer', @id, N'create', @actor_user_id, @now);
    END
    ELSE
    BEGIN
        DECLARE @before NVARCHAR(MAX) = (
            SELECT job_title_id, designation_id, department_id, branch_id, employment_type_id, offered_salary,
                   salary_frequency, joining_date, probation_months, expires_on, offer_letter_file_id
            FROM [rec].[offer] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        UPDATE [rec].[offer]
        SET job_title_id = @job_title_id, designation_id = @designation_id, department_id = @department_id,
            branch_id = @branch_id, employment_type_id = @employment_type_id, offered_salary = @offered_salary,
            salary_frequency = @salary_frequency, joining_date = @joining_date,
            probation_months = ISNULL(@probation_months, 0), expires_on = @expires_on,
            offer_letter_file_id = @offer_letter_file_id, remarks = NULLIF(LTRIM(RTRIM(@remarks)), N''),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this offer. Reload it and try again', 1;
        DECLARE @after NVARCHAR(MAX) = (
            SELECT job_title_id, designation_id, department_id, branch_id, employment_type_id, offered_salary,
                   salary_frequency, joining_date, probation_months, expires_on, offer_letter_file_id
            FROM [rec].[offer] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'rec.offer', @id, b.[key], b.value, a.value, N'update', @actor_user_id, @now
        FROM OPENJSON(@before) b JOIN OPENJSON(@after) a ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);
    END
    COMMIT;

    EXEC [rec].[usp_offer_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Deletes a draft offer.
CREATE OR ALTER PROCEDURE [rec].[usp_offer_delete]
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
    SELECT @rv = x.row_version, @status = x.status
    FROM [rec].[offer] x
    JOIN [rec].[application] a ON a.id = x.application_id
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE x.id = @id AND x.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Offer not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required to delete an offer.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this offer. Reload it and try again', 1;
    IF @status <> N'draft'
        THROW 50409, N'status|OFFER_NOT_DRAFT|Only a draft offer can be deleted. Withdraw it instead.', 1;
    BEGIN TRAN;
        DELETE FROM [rec].[offer] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this offer. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.offer', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO

-- Moves an offer on: @action send (draft -> sent; the application moves to the offer stage),
-- accept / decline (sent -> accepted / declined: the candidate's answer; the hiring manager is told of an
-- acceptance), withdraw (draft / sent / accepted -> withdrawn, before the hire).
CREATE OR ALTER PROCEDURE [rec].[usp_offer_status]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @action          NVARCHAR(30),
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @old NVARCHAR(30), @application BIGINT, @stage NVARCHAR(30), @expires DATE, @hm BIGINT;
    SELECT @rv = x.row_version, @old = x.status, @application = x.application_id, @stage = a.stage,
           @expires = x.expires_on, @hm = o.hiring_manager_id
    FROM [rec].[offer] x
    JOIN [rec].[application] a ON a.id = x.application_id
    JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE x.id = @id AND x.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Offer not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this offer. Reload it and try again', 1;

    DECLARE @new NVARCHAR(30) = CASE @action WHEN N'send' THEN N'sent' WHEN N'accept' THEN N'accepted'
                                             WHEN N'decline' THEN N'declined' WHEN N'withdraw' THEN N'withdrawn' END;
    IF @new IS NULL
        THROW 50400, N'action|Choose send, accept, decline or withdraw.', 1;
    IF NOT (   (@action = N'send' AND @old = N'draft')
            OR (@action IN (N'accept', N'decline') AND @old = N'sent')
            OR (@action = N'withdraw' AND @old IN (N'draft', N'sent', N'accepted')))
        THROW 50409, N'status|OFFER_STATUS|The offer cannot do that in its current state.', 1;
    IF @action <> N'withdraw' AND @stage IN (N'hired', N'rejected', N'withdrawn')
        THROW 50409, N'applicationId|APPLICATION_CLOSED|The application is closed.', 1;
    IF @action = N'withdraw' AND @stage = N'hired'
        THROW 50409, N'applicationId|APPLICATION_HIRED|The candidate has been hired on this offer.', 1;
    IF @action = N'accept' AND @expires < CAST(SYSUTCDATETIME() AS DATE)
        THROW 50409, N'expiresOn|OFFER_EXPIRED|The offer expired before it was accepted.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        UPDATE [rec].[offer]
        SET status = @new,
            sent_at = CASE WHEN @action = N'send' THEN @now ELSE sent_at END,
            responded_at = CASE WHEN @action IN (N'accept', N'decline') THEN @now ELSE responded_at END,
            response_remarks = CASE WHEN @action IN (N'accept', N'decline') THEN NULLIF(LTRIM(RTRIM(@remarks)), N'') ELSE response_remarks END,
            remarks = CASE WHEN @action IN (N'send', N'withdraw') THEN ISNULL(NULLIF(LTRIM(RTRIM(@remarks)), N''), remarks) ELSE remarks END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this offer. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.offer', @id, N'status', @old, @new, @action, @actor_user_id, @now);

        IF @action = N'send' AND @stage <> N'offer'
            EXEC [rec].[usp_application_stage_write] @company_id = @company_id, @actor_user_id = @actor_user_id,
                 @id = @application, @to_stage = N'offer', @remarks = N'Offer sent.';

        DECLARE @event NVARCHAR(100) = CASE @action WHEN N'send' THEN N'recruitment.offer_made'
                                                    WHEN N'accept' THEN N'recruitment.offer_accepted'
                                                    WHEN N'decline' THEN N'recruitment.offer_declined'
                                                    ELSE N'recruitment.offer_withdrawn' END;
        EXEC [rec].[usp_offer_event] @company_id = @company_id, @id = @id, @event_type = @event;

        IF @action = N'accept' AND @hm IS NOT NULL
        BEGIN
            DECLARE @title NVARCHAR(200), @body NVARCHAR(MAX), @link NVARCHAR(500) = CONCAT(N'/recruitment/offers/', @id);
            SELECT @title = LEFT(CONCAT(N'Offer accepted: ', p.first_name, N' ', p.last_name), 200),
                   @body = CONCAT(p.first_name, N' ', p.last_name, N' accepted the offer for ', o.title,
                                  N' and can join on ', CONVERT(NVARCHAR(10), x.joining_date, 23), N'.')
            FROM [rec].[offer] x
            JOIN [rec].[application] a ON a.id = x.application_id
            JOIN [rec].[applicant] p ON p.id = a.applicant_id
            JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
            WHERE x.id = @id;
            EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @hm,
                 @title = @title, @body = @body, @notification_type = N'recruitment', @link = @link,
                 @entity_type = N'rec.offer', @entity_id = @id;
        END
    COMMIT;

    EXEC [rec].[usp_offer_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO
