-- Applicants (the talent pool): list, card with their applications, add / edit with the CV file, delete.
-- Scope: rec.fn_visible_applicants with the permission the endpoint required.

-- Result set 1: the applicant. Result set 2: their applications the caller reaches.
CREATE OR ALTER PROCEDURE [rec].[usp_applicant_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [rec].[fn_visible_applicants](@company_id, @actor_user_id, @permission_code) v
                   WHERE v.applicant_id = @id)
        THROW 50404, N'Applicant not found', 1;
    SELECT * FROM [rec].[fn_applicant_rows](@company_id) WHERE id = @id;

    DECLARE @all BIT = CASE WHEN EXISTS (SELECT 1 FROM [auth].[fn_effective_grants](@company_id, @actor_user_id) g
                                         WHERE g.code = @permission_code AND g.scope = N'company') THEN 1 ELSE 0 END;
    SELECT x.*
    FROM [rec].[fn_application_rows](@company_id) x
    WHERE x.applicant_id = @id
      AND (@all = 1 OR x.job_opening_id IN (SELECT job_opening_id FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code)))
    ORDER BY x.applied_on DESC, x.id DESC;
END
GO

-- Result set 1: total. Result set 2: the page, newest first.
CREATE OR ALTER PROCEDURE [rec].[usp_applicant_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @source          NVARCHAR(30) = NULL,
    @city_id         BIGINT = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @v TABLE (id BIGINT PRIMARY KEY);
    INSERT @v SELECT applicant_id FROM [rec].[fn_visible_applicants](@company_id, @actor_user_id, @permission_code);

    SELECT COUNT(*) AS total
    FROM [rec].[applicant] p JOIN @v v ON v.id = p.id
    WHERE (@pattern IS NULL OR CONCAT(p.first_name, N' ', p.last_name) LIKE @pattern OR p.email LIKE @pattern
           OR p.phone LIKE @pattern OR p.current_job_title LIKE @pattern)
      AND (@source IS NULL OR p.source = @source)
      AND (@city_id IS NULL OR p.city_id = @city_id)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [rec].[fn_applicant_rows](@company_id) x JOIN @v v ON v.id = x.id
    WHERE (@pattern IS NULL OR x.full_name LIKE @pattern OR x.email LIKE @pattern OR x.phone LIKE @pattern
           OR x.current_job_title LIKE @pattern)
      AND (@source IS NULL OR x.source = @source)
      AND (@city_id IS NULL OR x.city_id = @city_id)
    ORDER BY x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL) or edits an applicant. The CV is a file already uploaded through /api/files.
-- One applicant per e-mail address in a company.
CREATE OR ALTER PROCEDURE [rec].[usp_applicant_save]
    @company_id              BIGINT,
    @actor_user_id           BIGINT,
    @permission_code         NVARCHAR(150),
    @id                      BIGINT = NULL,
    @first_name              NVARCHAR(200),
    @last_name               NVARCHAR(200),
    @email                   NVARCHAR(254),
    @phone                   NVARCHAR(30) = NULL,
    @gender                  NVARCHAR(30) = NULL,
    @date_of_birth           DATE = NULL,
    @city_id                 BIGINT = NULL,
    @address                 NVARCHAR(500) = NULL,
    @current_employer        NVARCHAR(200) = NULL,
    @current_job_title       NVARCHAR(200) = NULL,
    @experience_years        DECIMAL(4,1) = NULL,
    @current_salary          DECIMAL(18,2) = NULL,
    @expected_salary         DECIMAL(18,2) = NULL,
    @notice_period_days      INT = NULL,
    @highest_education       NVARCHAR(200) = NULL,
    @linkedin_url            NVARCHAR(500) = NULL,
    @source                  NVARCHAR(30) = NULL,
    @referred_by_employee_id BIGINT = NULL,
    @cv_file_id              BIGINT = NULL,
    @notes                   NVARCHAR(MAX) = NULL,
    @row_version             BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @first_name = LTRIM(RTRIM(@first_name));
    SET @last_name = LTRIM(RTRIM(@last_name));
    SET @email = NULLIF(LOWER(LTRIM(RTRIM(@email))), N'');
    SET @phone = NULLIF(LTRIM(RTRIM(@phone)), N'');
    SET @linkedin_url = NULLIF(LTRIM(RTRIM(@linkedin_url)), N'');
    SET @notes = NULLIF(LTRIM(RTRIM(@notes)), N'');

    DECLARE @old_rv BINARY(8);
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_rv = p.row_version
        FROM [rec].[applicant] p
        JOIN [rec].[fn_visible_applicants](@company_id, @actor_user_id, @permission_code) v ON v.applicant_id = p.id
        WHERE p.id = @id;
        IF @old_rv IS NULL
            THROW 50404, N'Applicant not found', 1;
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit an applicant.', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this applicant. Reload them and try again', 1;
    END

    IF @first_name IS NULL OR @first_name = N''
        THROW 50400, N'firstName|First name is required.', 1;
    IF @last_name IS NULL OR @last_name = N''
        THROW 50400, N'lastName|Last name is required.', 1;
    IF @email IS NULL OR @email NOT LIKE N'_%@_%._%' OR @email LIKE N'% %'
        THROW 50400, N'email|Enter a valid e-mail address.', 1;
    IF @gender IS NOT NULL AND @gender NOT IN (N'male', N'female', N'other')
        THROW 50400, N'gender|Choose male, female or other.', 1;
    IF @source IS NOT NULL AND @source NOT IN (N'career_site', N'referral', N'job_board', N'linkedin', N'walk_in', N'agency', N'other')
        THROW 50400, N'source|Choose career site, referral, job board, LinkedIn, walk-in, agency or other.', 1;
    IF @date_of_birth > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'dateOfBirth|Date of birth is in the future.', 1;
    IF @experience_years < 0 OR @notice_period_days < 0 OR @current_salary < 0 OR @expected_salary < 0
        THROW 50400, N'experienceYears|Experience, notice period and salaries cannot be negative.', 1;
    IF @city_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[city] WHERE id = @city_id)
        THROW 50400, N'cityId|City not found.', 1;
    IF @referred_by_employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @referred_by_employee_id AND company_id = @company_id)
        THROW 50400, N'referredByEmployeeId|Employee not found.', 1;
    IF @cv_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @cv_file_id))
        THROW 50400, N'cvFileId|The CV file was not found. Upload it again.', 1;
    IF EXISTS (SELECT 1 FROM [rec].[applicant] WHERE company_id = @company_id AND email = @email AND (@id IS NULL OR id <> @id))
        THROW 50409, N'email|APPLICANT_DUPLICATE|An applicant with this e-mail address already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [rec].[applicant] (company_id, first_name, last_name, email, phone, gender, date_of_birth, city_id, address,
                                  current_employer, current_job_title, experience_years, current_salary, expected_salary,
                                  notice_period_days, highest_education, linkedin_url, source, referred_by_employee_id,
                                  cv_file_id, notes, created_by)
        VALUES (@company_id, @first_name, @last_name, @email, @phone, @gender, @date_of_birth, @city_id, @address,
                @current_employer, @current_job_title, @experience_years, @current_salary, @expected_salary,
                @notice_period_days, @highest_education, @linkedin_url, @source, @referred_by_employee_id,
                @cv_file_id, @notes, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, new_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.applicant', @id, N'create', @email, @actor_user_id, @now);
    END
    ELSE
    BEGIN
        DECLARE @before NVARCHAR(MAX) = (
            SELECT first_name, last_name, email, phone, gender, date_of_birth, city_id, address, current_employer,
                   current_job_title, experience_years, current_salary, expected_salary, notice_period_days,
                   highest_education, linkedin_url, source, referred_by_employee_id, cv_file_id
            FROM [rec].[applicant] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        UPDATE [rec].[applicant]
        SET first_name = @first_name, last_name = @last_name, email = @email, phone = @phone, gender = @gender,
            date_of_birth = @date_of_birth, city_id = @city_id, address = @address, current_employer = @current_employer,
            current_job_title = @current_job_title, experience_years = @experience_years, current_salary = @current_salary,
            expected_salary = @expected_salary, notice_period_days = @notice_period_days,
            highest_education = @highest_education, linkedin_url = @linkedin_url, source = @source,
            referred_by_employee_id = @referred_by_employee_id, cv_file_id = @cv_file_id, notes = @notes,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this applicant. Reload them and try again', 1;
        DECLARE @after NVARCHAR(MAX) = (
            SELECT first_name, last_name, email, phone, gender, date_of_birth, city_id, address, current_employer,
                   current_job_title, experience_years, current_salary, expected_salary, notice_period_days,
                   highest_education, linkedin_url, source, referred_by_employee_id, cv_file_id
            FROM [rec].[applicant] WHERE id = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT @company_id, N'rec.applicant', @id, b.[key], b.value, a.value, N'update', @actor_user_id, @now
        FROM OPENJSON(@before) b JOIN OPENJSON(@after) a ON a.[key] = b.[key]
        WHERE EXISTS (SELECT b.value EXCEPT SELECT a.value);
    END
    COMMIT;

    SELECT * FROM [rec].[fn_applicant_rows](@company_id) WHERE id = @id;
END
GO

-- Deletes an applicant who has no applications.
CREATE OR ALTER PROCEDURE [rec].[usp_applicant_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rv BINARY(8), @email NVARCHAR(254);
    SELECT @rv = p.row_version, @email = p.email
    FROM [rec].[applicant] p
    JOIN [rec].[fn_visible_applicants](@company_id, @actor_user_id, @permission_code) v ON v.applicant_id = p.id
    WHERE p.id = @id;
    IF @rv IS NULL
        THROW 50404, N'Applicant not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required to delete an applicant.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this applicant. Reload them and try again', 1;
    IF EXISTS (SELECT 1 FROM [rec].[application] WHERE applicant_id = @id)
        THROW 50409, N'id|APPLICANT_IN_USE|This applicant has applications. Delete or keep them instead.', 1;

    BEGIN TRAN;
        DELETE FROM [rec].[applicant] WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this applicant. Reload them and try again', 1;
        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, old_value, performed_by_user_id, performed_at)
        VALUES (@company_id, N'rec.applicant', @id, N'delete', @email, @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
GO
