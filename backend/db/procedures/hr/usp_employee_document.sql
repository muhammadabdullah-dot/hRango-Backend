-- Employee documents (SRS EMP-3, APP Documents) and employment contracts, each with an uploaded file.
-- Documents need employees.documents.view / .edit; identity documents (CNIC, passport, driving licence)
-- also need employees.identity.view for the same employee, and pay letters (offer, promotion, appraisal,
-- salary certificate) employees.salary.view. A document the caller may not see is "not found".
-- Contracts are sensitive as a whole (employees.contracts): a contract states pay.

-- The guard a document type falls under: identity, pay or general.
CREATE OR ALTER FUNCTION [hr].[fn_document_category] (@document_type NVARCHAR(30))
RETURNS TABLE
AS RETURN
SELECT CASE WHEN @document_type IN (N'cnic', N'passport', N'driving_licence') THEN N'identity'
            WHEN @document_type IN (N'offer_letter', N'promotion_letter', N'appraisal_letter', N'salary_certificate') THEN N'pay'
            ELSE N'general' END AS category;
GO

-- The categories the caller may handle for one employee (general always; identity and pay with the codes).
CREATE OR ALTER FUNCTION [hr].[fn_document_categories_allowed] (@company_id BIGINT, @actor_user_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT N'general' AS category
UNION ALL
SELECT N'identity' FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.identity.view') v
WHERE v.employee_id = @employee_id
UNION ALL
SELECT N'pay' FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, N'employees.salary.view') v
WHERE v.employee_id = @employee_id;
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_document_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @id              BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.documents.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    SELECT d.id, d.employee_id, d.document_type, k.category, d.title, d.document_number, d.issue_date, d.expiry_date,
           CAST(CASE WHEN d.expiry_date < CAST(SYSUTCDATETIME() AS DATE) THEN 1 ELSE 0 END AS BIT) AS is_expired,
           d.file_id, f.name AS file_name, f.mime_type AS file_mime_type, f.size_bytes AS file_size_bytes, d.remarks,
           d.created_at, d.updated_at, d.row_version
    FROM [hr].[employee_document] d
    CROSS APPLY [hr].[fn_document_category](d.document_type) k
    JOIN [core].[stored_file] f ON f.id = d.file_id
    WHERE d.employee_id = @employee_id AND (@id IS NULL OR d.id = @id)
      AND k.category IN (SELECT category FROM [hr].[fn_document_categories_allowed](@company_id, @actor_user_id, @employee_id))
    ORDER BY d.document_type, d.created_at DESC, d.id DESC;
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_document_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @id              BIGINT = NULL,
    @document_type   NVARCHAR(30),
    @title           NVARCHAR(200) = NULL,
    @document_number NVARCHAR(100) = NULL,
    @issue_date      DATE = NULL,
    @expiry_date     DATE = NULL,
    @file_id         BIGINT,
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    SET @document_number = NULLIF(LTRIM(RTRIM(@document_number)), N'');
    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.documents.edit';

    DECLARE @allowed TABLE (category NVARCHAR(30) PRIMARY KEY);
    INSERT @allowed SELECT DISTINCT category FROM [hr].[fn_document_categories_allowed](@company_id, @actor_user_id, @employee_id);

    DECLARE @old_type NVARCHAR(30), @old_expiry DATE;
    IF @id IS NOT NULL
    BEGIN
        SELECT @old_type = d.document_type, @old_expiry = d.expiry_date
        FROM [hr].[employee_document] d
        CROSS APPLY [hr].[fn_document_category](d.document_type) k
        WHERE d.id = @id AND d.employee_id = @employee_id AND k.category IN (SELECT category FROM @allowed);
        IF @old_type IS NULL
            THROW 50404, N'Document not found', 1;
    END

    IF @document_type NOT IN (N'cnic', N'passport', N'driving_licence', N'offer_letter', N'promotion_letter',
                              N'appraisal_letter', N'salary_certificate', N'experience_letter', N'degree',
                              N'certificate', N'medical', N'other')
        THROW 50400, N'documentType|Choose a document type from the list.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[fn_document_category](@document_type) k JOIN @allowed a ON a.category = k.category)
        THROW 50403, N'You may not handle this kind of document (identity documents need the CNIC permission, pay letters the salary permission).', 1;
    IF @file_id IS NULL
        THROW 50400, N'fileId|Attach the document.', 1;
    IF NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF @expiry_date < @issue_date
        THROW 50400, N'expiryDate|The expiry date is before the issue date.', 1;
    IF @issue_date > CAST(SYSUTCDATETIME() AS DATE)
        THROW 50400, N'issueDate|The issue date is in the future.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_document] (employee_id, document_type, title, document_number, issue_date, expiry_date,
                                         file_id, remarks, created_by)
        VALUES (@employee_id, @document_type, @title, @document_number, @issue_date, @expiry_date, @file_id, @remarks,
                @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_document]
        SET document_type = @document_type, title = @title, document_number = @document_number, issue_date = @issue_date,
            expiry_date = @expiry_date, file_id = @file_id, remarks = @remarks,
            -- a new expiry date is warned about again
            expiry_notified_at = CASE WHEN EXISTS (SELECT @old_expiry EXCEPT SELECT @expiry_date) THEN NULL ELSE expiry_notified_at END,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this document. Reload it and try again', 1;
    END
    -- The document number is not copied into the log.
    DECLARE @summary NVARCHAR(400) = CONCAT(@document_type, CASE WHEN @title IS NOT NULL THEN CONCAT(N': ', @title) END);
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'document', @action, @id, @summary;
    COMMIT;

    EXEC [hr].[usp_employee_document_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.documents.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_document_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.documents.edit';
    DECLARE @rv BINARY(8), @summary NVARCHAR(400);
    SELECT @rv = d.row_version, @summary = CONCAT(d.document_type, CASE WHEN d.title IS NOT NULL THEN CONCAT(N': ', d.title) END)
    FROM [hr].[employee_document] d
    CROSS APPLY [hr].[fn_document_category](d.document_type) k
    WHERE d.id = @id AND d.employee_id = @employee_id
      AND k.category IN (SELECT category FROM [hr].[fn_document_categories_allowed](@company_id, @actor_user_id, @employee_id));
    IF @rv IS NULL
        THROW 50404, N'Document not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this document. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_document] WHERE id = @id;
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'document', N'delete', @id, @summary;
    COMMIT;
END
GO

-- Tells employees whose documents expire within @days_ahead days (or have expired unnoticed), once
-- per expiry date: an inbox notification and the employees.document_expiring event. Run it daily
-- (for every company) from the nightly job. Returns how many documents were reported.
CREATE OR ALTER PROCEDURE [hr].[usp_employee_document_expiry_notify]
    @company_id BIGINT,
    @days_ahead INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE), @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @due TABLE (id BIGINT PRIMARY KEY, employee_id BIGINT, document_type NVARCHAR(30), title NVARCHAR(200), expiry_date DATE);
    INSERT @due
    SELECT d.id, d.employee_id, d.document_type, d.title, d.expiry_date
    FROM [hr].[employee_document] d
    JOIN [hr].[employee] e ON e.id = d.employee_id AND e.company_id = @company_id
    WHERE d.expiry_date IS NOT NULL AND d.expiry_date <= DATEADD(DAY, @days_ahead, @today)
      AND d.expiry_notified_at IS NULL AND e.status NOT IN (N'left', N'inactive');

    DECLARE @id BIGINT = (SELECT MIN(id) FROM @due), @emp BIGINT, @type NVARCHAR(30), @expiry DATE,
            @title NVARCHAR(200), @body NVARCHAR(MAX), @payload NVARCHAR(MAX);
    BEGIN TRAN;
    WHILE @id IS NOT NULL
    BEGIN
        SELECT @emp = employee_id, @type = document_type, @expiry = expiry_date FROM @due WHERE id = @id;
        SET @title = CASE WHEN @expiry < @today THEN N'A document of yours has expired' ELSE N'A document of yours expires soon' END;
        SET @body = CONCAT(REPLACE(@type, N'_', N' '), N' expiry date: ', CONVERT(NVARCHAR(10), @expiry, 23), N'. Please give HR a renewed copy.');
        EXEC [core].[usp_notification_add_employee] @quiet = 1, @company_id = @company_id, @employee_id = @emp,
             @title = @title, @body = @body, @notification_type = N'employee_document',
             @link = N'/profile/documents', @entity_type = N'hr.employee_document', @entity_id = @id;
        SET @payload = (SELECT CONVERT(NVARCHAR(30), @id) AS documentId, CONVERT(NVARCHAR(30), @emp) AS employeeId,
                               @type AS documentType, @expiry AS expiryDate,
                               CAST(CASE WHEN @expiry < @today THEN 1 ELSE 0 END AS BIT) AS isExpired
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'employees.document_expiring',
             @entity_type = N'hr.employee_document', @entity_id = @id, @payload = @payload;
        UPDATE [hr].[employee_document] SET expiry_notified_at = @now WHERE id = @id;
        SET @id = (SELECT MIN(id) FROM @due WHERE id > @id);
    END
    COMMIT;

    SELECT COUNT(*) AS reported FROM @due;
END
GO

-- ---------------------------------------------------------------- contracts (sensitive)

CREATE OR ALTER PROCEDURE [hr].[usp_employee_contract_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @id              BIGINT = NULL,
    @permission_code NVARCHAR(150) = N'employees.contracts.view'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, @permission_code;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SELECT c.id, c.employee_id, c.contract_type, c.duration_months, c.from_date, c.to_date,
           CASE WHEN c.from_date > @today THEN N'upcoming' WHEN c.to_date < @today THEN N'expired' ELSE N'active' END AS status,
           c.file_id, f.name AS file_name, c.remarks, c.created_at, c.updated_at, c.row_version
    FROM [hr].[employee_contract] c
    LEFT JOIN [core].[stored_file] f ON f.id = c.file_id
    WHERE c.employee_id = @employee_id AND (@id IS NULL OR c.id = @id)
    ORDER BY c.from_date DESC, c.id DESC;
END
GO

-- Duration in months fills an empty To date (From + months - 1 day); give To yourself for "Custom".
-- Contracts of one employee may not overlap (an open-ended one runs for ever).
CREATE OR ALTER PROCEDURE [hr].[usp_employee_contract_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @employee_id     BIGINT,
    @id              BIGINT = NULL,
    @contract_type   NVARCHAR(30),
    @duration_months INT = NULL,
    @from_date       DATE,
    @to_date         DATE = NULL,
    @file_id         BIGINT = NULL,
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), N'');
    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.contracts.edit';
    IF @from_date IS NULL
        THROW 50400, N'fromDate|From date is required.', 1;
    IF @duration_months IS NOT NULL AND (@duration_months < 1 OR @duration_months > 600)
        THROW 50400, N'durationMonths|Duration is between 1 and 600 months.', 1;
    IF @to_date IS NULL AND @duration_months IS NOT NULL
        SET @to_date = DATEADD(DAY, -1, DATEADD(MONTH, @duration_months, @from_date));
    IF @to_date < @from_date
        THROW 50400, N'toDate|The end date is before the start date.', 1;
    IF @file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @file_id))
        THROW 50400, N'fileId|The file was not found. Upload it again.', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee_contract]
               WHERE employee_id = @employee_id AND (@id IS NULL OR id <> @id)
                 AND from_date <= ISNULL(@to_date, '9999-12-31') AND ISNULL(to_date, '9999-12-31') >= @from_date)
        THROW 50409, N'fromDate|CONTRACT_OVERLAP|This contract overlaps another contract of this employee.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @action NVARCHAR(30) = CASE WHEN @id IS NULL THEN N'create' ELSE N'update' END;
    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        INSERT [hr].[employee_contract] (employee_id, contract_type, duration_months, from_date, to_date, file_id, remarks, created_by)
        VALUES (@employee_id, @contract_type, @duration_months, @from_date, @to_date, @file_id, @remarks, @actor_user_id);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE [hr].[employee_contract]
        SET contract_type = @contract_type, duration_months = @duration_months, from_date = @from_date, to_date = @to_date,
            file_id = @file_id, remarks = @remarks, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND employee_id = @employee_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [hr].[employee_contract] WHERE id = @id AND employee_id = @employee_id)
                THROW 50404, N'Contract not found', 1;
            THROW 50409, N'Someone else changed this contract. Reload it and try again', 1;
        END
    END
    DECLARE @summary NVARCHAR(400) = CONCAT(@contract_type, N' ', CONVERT(NVARCHAR(10), @from_date, 23), N' - ',
                                            ISNULL(CONVERT(NVARCHAR(10), @to_date, 23), N'open'));
    EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'contract', @action, @id, @summary;
    COMMIT;

    EXEC [hr].[usp_employee_contract_list] @company_id, @actor_user_id, @employee_id, @id, N'employees.contracts.edit';
END
GO

CREATE OR ALTER PROCEDURE [hr].[usp_employee_contract_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT,
    @employee_id   BIGINT,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC [hr].[usp_employee_reach_check] @company_id, @actor_user_id, @employee_id, N'employees.contracts.edit';
    DECLARE @rv BINARY(8), @summary NVARCHAR(400);
    SELECT @rv = row_version, @summary = CONCAT(contract_type, N' ', CONVERT(NVARCHAR(10), from_date, 23))
    FROM [hr].[employee_contract] WHERE id = @id AND employee_id = @employee_id;
    IF @rv IS NULL
        THROW 50404, N'Contract not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this contract. Reload it and try again', 1;

    BEGIN TRAN;
        DELETE [hr].[employee_contract] WHERE id = @id;
        EXEC [hr].[usp_employee_profile_changed] @company_id, @actor_user_id, @employee_id, N'contract', N'delete', @id, @summary;
    COMMIT;
END
