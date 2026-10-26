-- Applications (applicant tracking): one applicant for one opening, moved through the pipeline
-- applied -> screening -> shortlisted -> interview -> offer -> hired, or closed as rejected / withdrawn.
-- Every move writes rec.application_stage_history and publishes recruitment.stage_changed.
-- Scope: the opening's (rec.fn_visible_openings) with the permission the endpoint required.

-- Internal: moves an application to @to_stage inside the caller's transaction. No result set.
CREATE OR ALTER PROCEDURE [rec].[usp_application_stage_write]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @id            BIGINT,
    @to_stage      NVARCHAR(30),
    @remarks       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @from NVARCHAR(30) = (SELECT stage FROM [rec].[application] WHERE id = @id AND company_id = @company_id);
    IF @from IS NULL
        THROW 50404, N'Application not found', 1;
    IF @from = @to_stage
        RETURN;
    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    UPDATE [rec].[application]
    SET stage = @to_stage, stage_changed_at = @now,
        rejected_stage = CASE WHEN @to_stage IN (N'rejected', N'withdrawn') THEN @from ELSE NULL END,
        rejection_reason_id = CASE WHEN @to_stage = N'rejected' THEN rejection_reason_id ELSE NULL END,
        updated_at = @now, updated_by = @actor_user_id
    WHERE id = @id;

    INSERT [rec].[application_stage_history] (application_id, from_stage, to_stage, changed_at, changed_by_user_id, remarks, created_by)
    VALUES (@id, @from, @to_stage, @now, @actor_user_id, NULLIF(LTRIM(RTRIM(@remarks)), N''), @actor_user_id);

    DECLARE @payload NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR(30), a.id) AS applicationId, CONVERT(NVARCHAR(30), a.job_opening_id) AS jobOpeningId,
               o.title AS jobOpeningTitle, CONVERT(NVARCHAR(30), a.applicant_id) AS applicantId,
               CONCAT(p.first_name, N' ', p.last_name) AS applicantName, p.email AS applicantEmail,
               @from AS fromStage, @to_stage AS toStage, NULLIF(LTRIM(RTRIM(@remarks)), N'') AS remarks,
               CONVERT(NVARCHAR(30), @actor_user_id) AS changedByUserId
        FROM [rec].[application] a
        JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
        JOIN [rec].[applicant] p ON p.id = a.applicant_id
        WHERE a.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'recruitment.stage_changed',
         @entity_type = N'rec.application', @entity_id = @id, @payload = @payload;
END
GO

-- Result set 1: the application. 2: its stage history. 3: its interviews. 4: its offers.
CREATE OR ALTER PROCEDURE [rec].[usp_application_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [rec].[application] a
                   JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
                   WHERE a.id = @id AND a.company_id = @company_id)
        THROW 50404, N'Application not found', 1;

    SELECT * FROM [rec].[fn_application_rows](@company_id) WHERE id = @id;

    SELECT h.id, h.from_stage, h.to_stage, h.changed_at, h.changed_by_user_id, n.name AS changed_by_name, h.remarks
    FROM [rec].[application_stage_history] h
    OUTER APPLY [rec].[fn_user_name](h.changed_by_user_id) n
    WHERE h.application_id = @id
    ORDER BY h.changed_at, h.id;

    SELECT * FROM [rec].[fn_interview_rows](@company_id) WHERE application_id = @id ORDER BY round_no, id;

    SELECT * FROM [rec].[fn_offer_rows](@company_id) WHERE application_id = @id ORDER BY id;
END
GO

-- Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [rec].[usp_application_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @job_opening_id  BIGINT = NULL,
    @applicant_id    BIGINT = NULL,
    @stage           NVARCHAR(30) = NULL,
    @active_only     BIT = 0,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
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
    FROM [rec].[fn_application_rows](@company_id) x JOIN @v v ON v.id = x.job_opening_id
    WHERE (@pattern IS NULL OR x.applicant_name LIKE @pattern OR x.applicant_email LIKE @pattern
           OR x.job_opening_title LIKE @pattern OR x.job_opening_code LIKE @pattern)
      AND (@job_opening_id IS NULL OR x.job_opening_id = @job_opening_id)
      AND (@applicant_id IS NULL OR x.applicant_id = @applicant_id)
      AND (@stage IS NULL OR x.stage = @stage)
      AND (ISNULL(@active_only, 0) = 0 OR x.stage NOT IN (N'hired', N'rejected', N'withdrawn'))
      AND (@from_date IS NULL OR x.applied_on >= @from_date)
      AND (@to_date IS NULL OR x.applied_on <= @to_date)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [rec].[fn_application_rows](@company_id) x JOIN @v v ON v.id = x.job_opening_id
    WHERE (@pattern IS NULL OR x.applicant_name LIKE @pattern OR x.applicant_email LIKE @pattern
           OR x.job_opening_title LIKE @pattern OR x.job_opening_code LIKE @pattern)
      AND (@job_opening_id IS NULL OR x.job_opening_id = @job_opening_id)
      AND (@applicant_id IS NULL OR x.applicant_id = @applicant_id)
      AND (@stage IS NULL OR x.stage = @stage)
      AND (ISNULL(@active_only, 0) = 0 OR x.stage NOT IN (N'hired', N'rejected', N'withdrawn'))
      AND (@from_date IS NULL OR x.applied_on >= @from_date)
      AND (@to_date IS NULL OR x.applied_on <= @to_date)
    ORDER BY x.applied_on DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds an application of an existing applicant to an open opening (stage applied).
CREATE OR ALTER PROCEDURE [rec].[usp_application_add]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @job_opening_id  BIGINT,
    @applicant_id    BIGINT,
    @applied_on      DATE = NULL,
    @source          NVARCHAR(30) = NULL,
    @cover_letter    NVARCHAR(MAX) = NULL,
    @remarks         NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @status NVARCHAR(30), @applicant_source NVARCHAR(30), @found BIT = 0;
    SELECT @status = o.status
    FROM [rec].[job_opening] o
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = o.id
    WHERE o.id = @job_opening_id;
    IF @status IS NULL
        THROW 50400, N'jobOpeningId|Job opening not found.', 1;
    SELECT @found = 1, @applicant_source = source FROM [rec].[applicant] WHERE id = @applicant_id AND company_id = @company_id;
    IF @found = 0
        THROW 50400, N'applicantId|Applicant not found.', 1;
    IF @status <> N'open'
        THROW 50409, N'jobOpeningId|OPENING_NOT_OPEN|This opening is not open for applications.', 1;
    SET @source = ISNULL(NULLIF(LTRIM(RTRIM(@source)), N''), @applicant_source);
    IF @source IS NOT NULL AND @source NOT IN (N'career_site', N'referral', N'job_board', N'linkedin', N'walk_in', N'agency', N'other')
        THROW 50400, N'source|Choose career site, referral, job board, LinkedIn, walk-in, agency or other.', 1;
    SET @applied_on = ISNULL(@applied_on, CAST(SYSUTCDATETIME() AS DATE));
    IF @applied_on > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'appliedOn|The applied date cannot be in the future.', 1;
    IF EXISTS (SELECT 1 FROM [rec].[application] WHERE job_opening_id = @job_opening_id AND applicant_id = @applicant_id)
        THROW 50409, N'applicantId|APPLICATION_DUPLICATE|This applicant has already applied to this opening.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @id BIGINT;
    BEGIN TRAN;
        INSERT [rec].[application] (company_id, job_opening_id, applicant_id, applied_on, source, cover_letter, stage,
                                    stage_changed_at, remarks, created_by)
        VALUES (@company_id, @job_opening_id, @applicant_id, @applied_on, @source, NULLIF(LTRIM(RTRIM(@cover_letter)), N''),
                N'applied', @now, NULLIF(LTRIM(RTRIM(@remarks)), N''), @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [rec].[application_stage_history] (application_id, from_stage, to_stage, changed_at, changed_by_user_id, created_by)
        VALUES (@id, NULL, N'applied', @now, @actor_user_id, @actor_user_id);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), a.id) AS applicationId, CONVERT(NVARCHAR(30), a.job_opening_id) AS jobOpeningId,
                   o.code AS jobOpeningCode, o.title AS jobOpeningTitle, CONVERT(NVARCHAR(30), a.applicant_id) AS applicantId,
                   CONCAT(p.first_name, N' ', p.last_name) AS applicantName, p.email AS applicantEmail, p.phone AS applicantPhone,
                   a.applied_on AS appliedOn, a.source
            FROM [rec].[application] a
            JOIN [rec].[job_opening] o ON o.id = a.job_opening_id
            JOIN [rec].[applicant] p ON p.id = a.applicant_id
            WHERE a.id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'recruitment.application_received',
             @entity_type = N'rec.application', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [rec].[usp_application_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Moves an application along the pipeline (applied, screening, shortlisted, interview, offer), or brings
-- a rejected / withdrawn one back. Hired, rejected and withdrawn have their own steps.
CREATE OR ALTER PROCEDURE [rec].[usp_application_stage]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @stage           NVARCHAR(30),
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @old NVARCHAR(30);
    SELECT @rv = a.row_version, @old = a.stage
    FROM [rec].[application] a
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE a.id = @id AND a.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Application not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @stage NOT IN (N'applied', N'screening', N'shortlisted', N'interview', N'offer')
        THROW 50400, N'stage|Choose applied, screening, shortlisted, interview or offer. Reject, withdraw and hire have their own steps.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this application. Reload it and try again', 1;
    IF @old = N'hired'
        THROW 50409, N'stage|APPLICATION_HIRED|This candidate has been hired.', 1;
    IF @old = @stage
        THROW 50409, N'stage|STAGE_UNCHANGED|The application is already at this stage.', 1;

    BEGIN TRAN;
        EXEC [rec].[usp_application_stage_write] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
             @to_stage = @stage, @remarks = @remarks;
    COMMIT;

    EXEC [rec].[usp_application_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Rejects (@stage rejected, with an optional reason) or withdraws (@stage withdrawn: the candidate pulled
-- out) an application. Its scheduled interviews are cancelled and an open offer is withdrawn.
CREATE OR ALTER PROCEDURE [rec].[usp_application_close]
    @company_id          BIGINT,
    @actor_user_id       BIGINT,
    @permission_code     NVARCHAR(150),
    @id                  BIGINT,
    @stage               NVARCHAR(30),
    @rejection_reason_id BIGINT = NULL,
    @remarks             NVARCHAR(MAX) = NULL,
    @row_version         BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @old NVARCHAR(30);
    SELECT @rv = a.row_version, @old = a.stage
    FROM [rec].[application] a
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE a.id = @id AND a.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Application not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @stage NOT IN (N'rejected', N'withdrawn')
        THROW 50400, N'stage|Choose rejected or withdrawn.', 1;
    IF @rejection_reason_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [rec].[rejection_reason]
                                                        WHERE id = @rejection_reason_id AND company_id = @company_id AND is_active = 1)
        THROW 50400, N'rejectionReasonId|Rejection reason not found.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this application. Reload it and try again', 1;
    IF @old IN (N'hired', N'rejected', N'withdrawn')
        THROW 50409, N'stage|APPLICATION_CLOSED|This application is already closed.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
        EXEC [rec].[usp_application_stage_write] @company_id = @company_id, @actor_user_id = @actor_user_id, @id = @id,
             @to_stage = @stage, @remarks = @remarks;
        UPDATE [rec].[application]
        SET rejection_reason_id = CASE WHEN @stage = N'rejected' THEN @rejection_reason_id END,
            remarks = ISNULL(NULLIF(LTRIM(RTRIM(@remarks)), N''), remarks)
        WHERE id = @id;
        UPDATE [rec].[interview]
        SET status = N'cancelled', remarks = CONCAT(remarks, CASE WHEN remarks IS NOT NULL THEN N' ' END, N'(Application ', @stage, N'.)'),
            updated_at = @now, updated_by = @actor_user_id
        WHERE application_id = @id AND status = N'scheduled';
        UPDATE [rec].[offer]
        SET status = N'withdrawn', updated_at = @now, updated_by = @actor_user_id
        WHERE application_id = @id AND status IN (N'draft', N'sent');
    COMMIT;

    EXEC [rec].[usp_application_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Deletes an application entered by mistake: not hired, no interviews and no offers.
CREATE OR ALTER PROCEDURE [rec].[usp_application_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @stage NVARCHAR(30);
    SELECT @rv = a.row_version, @stage = a.stage
    FROM [rec].[application] a
    JOIN [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code) v ON v.job_opening_id = a.job_opening_id
    WHERE a.id = @id AND a.company_id = @company_id;
    IF @rv IS NULL
        THROW 50404, N'Application not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required to delete an application.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this application. Reload it and try again', 1;
    IF @stage = N'hired' OR EXISTS (SELECT 1 FROM [rec].[interview] WHERE application_id = @id)
                         OR EXISTS (SELECT 1 FROM [rec].[offer] WHERE application_id = @id)
        THROW 50409, N'id|APPLICATION_IN_USE|This application has interviews, offers or a hire. Reject or withdraw it instead.', 1;

    BEGIN TRAN;
        DELETE FROM [rec].[application_stage_history] WHERE application_id = @id;
        DELETE FROM [rec].[application] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this application. Reload it and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.application', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO
