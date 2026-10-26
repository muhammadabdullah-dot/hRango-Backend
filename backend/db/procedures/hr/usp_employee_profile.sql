-- Employee profile tabs (comparison/12-employee-profile.md): emergency contacts, dependents, skills,
-- education (with a document) and professional experience. Each tab has _list, _save (add when @id
-- is NULL, else edit with the @row_version last read) and _delete, guarded by employees.<tab>.view /
-- .edit through auth.fn_visible_employees, so staff granted the edit code with own scope keep their own
-- profile. Every change leaves a History row and the employees.profile_changed event.

-- ---------------------------------------------------------------- emergency contacts

CREATE OR ALTER PROCEDURE [hr].[usp_employee_emergency_contact_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.emergency_contacts.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    SELECT c.id, c.employee_id, c.name, c.relation, c.phone, c.alt_phone, c.address, c.is_primary, c.created_at,
           c.updated_at, c.row_version
    FROM [hr].[employee_emergency_contact] c
    WHERE c.employee_id = @employee_id AND (@id IS NULL OR c.id = @id)
    ORDER BY c.is_primary DESC, c.name, c.id;
END
GO

-- The first contact is the primary one; making another primary moves the mark.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_emergency_contact_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @relation      NVARCHAR(30),
    @phone         NVARCHAR(30),
    @alt_phone     NVARCHAR(30) = NULL,
    @address       NVARCHAR(500) = NULL,
    @is_primary    BIT = 0,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    SET @phone = NULLIF(LTRIM(RTRIM(@phone)), N'');
    SET @alt_phone = NULLIF(LTRIM(RTRIM(@alt_phone)), N'');
    SET @address = NULLIF(LTRIM(RTRIM(@address)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.emergency_contacts.edit';
    IF @name IS NULL
        THROW 50400, N'name|Name is required.', 1;
    IF @phone IS NULL
        THROW 50400, N'phone|Phone is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee_emergency_contact] WHERE employee_id = @employee_id AND (@id IS NULL OR id <> @id))
        SET @is_primary = 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @is_primary = 1
        UPDATE [hr].[employee_emergency_contact] SET is_primary = 0, updated_at = @now, updated_by = @actor_user_id
        WHERE employee_id = @employee_id AND is_primary = 1 AND (@id IS NULL OR id <> @id);

    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_emergency_contact] (employee_id, name, relation, phone, alt_phone, address, is_primary, created_by)
        VALUES (@employee_id, @name, @relation, @phone, @alt_phone, @address, @is_primary, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_emergency_contact]
        SET name = @name, relation = @relation, phone = @phone, alt_phone = @alt_phone, address = @address,
            is_primary = @is_primary, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_emergency_contact] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Emergency contact not found', 1;
            THROW 50409, N'Someone else changed this contact. Reload it and try again', 1;
        END
    END
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'emergency_contact', @action, @id, @name;
    COMMIT;

    EXEC [hr].[usp_employee_emergency_contact_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.emergency_contacts.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_emergency_contact_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.emergency_contacts.edit';
    DECLARE @rv BINARY(8), @primary BIT, @name NVARCHAR(200);
    SELECT @rv = row_version, @primary = is_primary, @name = name
    FROM [hr].[employee_emergency_contact] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Emergency contact not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this contact. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_emergency_contact] WHERE id = @id;
        IF @primary = 1
            UPDATE [hr].[employee_emergency_contact] SET is_primary = 1
            WHERE id = (SELECT TOP 1 id FROM [hr].[employee_emergency_contact] WHERE employee_id = @employee_id ORDER BY id);
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'emergency_contact', N'delete', @id, @name;
    COMMIT;
END
GO

-- ---------------------------------------------------------------- dependents

CREATE OR ALTER PROCEDURE [hr].[usp_employee_dependent_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.dependents.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    SELECT d.id, d.employee_id, d.first_name, d.last_name, LTRIM(RTRIM(CONCAT(d.first_name, N' ', d.last_name))) AS name,
           d.relation, d.occupation, d.date_of_birth, d.created_at, d.updated_at, d.row_version
    FROM [hr].[employee_dependent] d
    WHERE d.employee_id = @employee_id AND (@id IS NULL OR d.id = @id)
    ORDER BY d.date_of_birth, d.first_name, d.id;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_dependent_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @first_name    NVARCHAR(200),
    @last_name     NVARCHAR(200) = NULL,
    @relation      NVARCHAR(30),
    @occupation    NVARCHAR(200) = NULL,
    @date_of_birth DATE = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @first_name = NULLIF(LTRIM(RTRIM(@first_name)), N'');
    SET @last_name = NULLIF(LTRIM(RTRIM(@last_name)), N'');
    SET @occupation = NULLIF(LTRIM(RTRIM(@occupation)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.dependents.edit';
    IF @first_name IS NULL
        THROW 50400, N'firstName|First name is required.', 1;
    IF @date_of_birth > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'dateOfBirth|Date of birth is in the future.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_dependent] (employee_id, first_name, last_name, relation, occupation, date_of_birth, created_by)
        VALUES (@employee_id, @first_name, @last_name, @relation, @occupation, @date_of_birth, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_dependent]
        SET first_name = @first_name, last_name = @last_name, relation = @relation, occupation = @occupation,
            date_of_birth = @date_of_birth, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_dependent] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Dependent not found', 1;
            THROW 50409, N'Someone else changed this dependent. Reload it and try again', 1;
        END
    END
    DECLARE @summary NVARCHAR(400) = CONCAT(@first_name, N' (', @relation, N')');
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'dependent', @action, @id, @summary;
    COMMIT;

    EXEC [hr].[usp_employee_dependent_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.dependents.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_dependent_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.dependents.edit';
    DECLARE @rv BINARY(8), @summary NVARCHAR(400);
    SELECT @rv = row_version, @summary = CONCAT(first_name, N' (', relation, N')')
    FROM [hr].[employee_dependent] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Dependent not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this dependent. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_dependent] WHERE id = @id;
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'dependent', N'delete', @id, @summary;
    COMMIT;
END
GO

-- ---------------------------------------------------------------- skills

CREATE OR ALTER PROCEDURE [hr].[usp_employee_skill_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.skills.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    SELECT s.id, s.employee_id, s.skill_title, s.skill_level, s.created_at, s.updated_at, s.row_version
    FROM [hr].[employee_skill] s
    WHERE s.employee_id = @employee_id AND (@id IS NULL OR s.id = @id)
    ORDER BY s.skill_title, s.id;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_skill_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @skill_title   NVARCHAR(200),
    @skill_level   NVARCHAR(30),
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @skill_title = NULLIF(LTRIM(RTRIM(@skill_title)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.skills.edit';
    IF @skill_title IS NULL
        THROW 50400, N'skillTitle|Skill title is required.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_skill] WHERE employee_id = @employee_id AND skill_title = @skill_title
               AND (@id IS NULL OR id <> @id))
        THROW 50409, N'skillTitle|SKILL_DUPLICATE|This skill is already listed.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_skill] (employee_id, skill_title, skill_level, created_by)
        VALUES (@employee_id, @skill_title, @skill_level, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_skill]
        SET skill_title = @skill_title, skill_level = @skill_level, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_skill] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Skill not found', 1;
            THROW 50409, N'Someone else changed this skill. Reload it and try again', 1;
        END
    END
    DECLARE @summary NVARCHAR(400) = CONCAT(@skill_title, N' (', @skill_level, N')');
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'skill', @action, @id, @summary;
    COMMIT;

    EXEC [hr].[usp_employee_skill_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.skills.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_skill_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.skills.edit';
    DECLARE @rv BINARY(8), @summary NVARCHAR(400);
    SELECT @rv = row_version, @summary = skill_title FROM [hr].[employee_skill] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Skill not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this skill. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_skill] WHERE id = @id;
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'skill', N'delete', @id, @summary;
    COMMIT;
END
GO

-- ---------------------------------------------------------------- education (academic records)

CREATE OR ALTER PROCEDURE [hr].[usp_employee_education_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.education.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    SELECT x.id, x.employee_id, x.title, x.institute, x.from_date, x.to_date, x.is_in_process, x.file_id,
           f.name AS file_name, x.created_at, x.updated_at, x.row_version
    FROM [hr].[employee_education] x
    LEFT JOIN [core].[stored_file] f ON f.id = x.file_id
    WHERE x.employee_id = @employee_id AND (@id IS NULL OR x.id = @id)
    ORDER BY x.is_in_process DESC, x.to_date DESC, x.from_date DESC, x.id DESC;
END
GO

-- "In Process" means not finished yet, so it has no end date.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_education_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @title         NVARCHAR(200),
    @institute     NVARCHAR(200),
    @from_date     DATE = NULL,
    @to_date       DATE = NULL,
    @is_in_process BIT = 0,
    @file_id       BIGINT = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    SET @institute = NULLIF(LTRIM(RTRIM(@institute)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.education.edit';
    IF @title IS NULL
        THROW 50400, N'title|Academic title is required.', 1;
    IF @institute IS NULL
        THROW 50400, N'institute|Institute is required.', 1;
    IF @is_in_process = 1 AND @to_date IS NOT NULL
        THROW 50400, N'toDate|A course still in process has no end date.', 1;
    IF @to_date < @from_date
        THROW 50400, N'toDate|The end date is before the start date.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_education] (employee_id, title, institute, from_date, to_date, is_in_process, file_id, created_by)
        VALUES (@employee_id, @title, @institute, @from_date, @to_date, @is_in_process, @file_id, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_education]
        SET title = @title, institute = @institute, from_date = @from_date, to_date = @to_date,
            is_in_process = @is_in_process, file_id = @file_id, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_education] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Academic record not found', 1;
            THROW 50409, N'Someone else changed this academic record. Reload it and try again', 1;
        END
    END
    DECLARE @summary NVARCHAR(400) = CONCAT(@title, N', ', @institute);
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'education', @action, @id, @summary;
    COMMIT;

    EXEC [hr].[usp_employee_education_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.education.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_education_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.education.edit';
    DECLARE @rv BINARY(8), @summary NVARCHAR(400);
    SELECT @rv = row_version, @summary = CONCAT(title, N', ', institute)
    FROM [hr].[employee_education] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Academic record not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this academic record. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_education] WHERE id = @id;
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'education', N'delete', @id, @summary;
    COMMIT;
END
GO

-- ---------------------------------------------------------------- professional experience

CREATE OR ALTER PROCEDURE [hr].[usp_employee_experience_list]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.experience.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    SELECT x.id, x.employee_id, x.company_name, x.role_title AS job_title, x.from_date, x.to_date,
           CAST(CASE WHEN x.to_date IS NULL THEN 1 ELSE 0 END AS BIT) AS is_current,
           DATEDIFF(MONTH, x.from_date, ISNULL(x.to_date, CAST(SYSUTCDATETIME() AS DATE))) AS months,
           x.created_at, x.updated_at, x.row_version
    FROM [hr].[employee_experience] x
    WHERE x.employee_id = @employee_id AND (@id IS NULL OR x.id = @id)
    ORDER BY CASE WHEN x.to_date IS NULL THEN 0 ELSE 1 END, x.to_date DESC, x.from_date DESC, x.id DESC;
END
GO

-- An empty To date means the job is current ("2020 - Present").
CREATE OR ALTER PROCEDURE [hr].[usp_employee_experience_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT = NULL,
    @company_name  NVARCHAR(200),
    @job_title     NVARCHAR(100),
    @from_date     DATE,
    @to_date       DATE = NULL,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @company_name = NULLIF(LTRIM(RTRIM(@company_name)), N'');
    SET @job_title = NULLIF(LTRIM(RTRIM(@job_title)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.experience.edit';
    IF @company_name IS NULL
        THROW 50400, N'companyName|Company name is required.', 1;
    IF @job_title IS NULL
        THROW 50400, N'jobTitle|Job title is required.', 1;
    IF @from_date IS NULL
        THROW 50400, N'fromDate|From date is required.', 1;
    IF @from_date > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'fromDate|From date is in the future.', 1;
    IF @to_date < @from_date
        THROW 50400, N'toDate|The end date is before the start date.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_experience] (employee_id, company_name, role_title, from_date, to_date, created_by)
        VALUES (@employee_id, @company_name, @job_title, @from_date, @to_date, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_experience]
        SET company_name = @company_name, role_title = @job_title, from_date = @from_date, to_date = @to_date,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_experience] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Experience not found', 1;
            THROW 50409, N'Someone else changed this experience. Reload it and try again', 1;
        END
    END
    DECLARE @summary NVARCHAR(400) = CONCAT(@job_title, N', ', @company_name);
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'experience', @action, @id, @summary;
    COMMIT;

    EXEC [hr].[usp_employee_experience_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.experience.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_experience_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.experience.edit';
    DECLARE @rv BINARY(8), @summary NVARCHAR(400);
    SELECT @rv = row_version, @summary = CONCAT(role_title, N', ', company_name)
    FROM [hr].[employee_experience] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Experience not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this experience. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_experience] WHERE id = @id;
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'experience', N'delete', @id, @summary;
    COMMIT;
END
