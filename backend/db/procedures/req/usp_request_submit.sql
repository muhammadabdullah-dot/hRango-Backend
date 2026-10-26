-- Submits a request (WF2 steps 1 and 2): for the caller (My) or, with @employee_id, for someone the
-- caller's create permission reaches (All). Validates the header and the kind's details, refuses a
-- type closed by a request restriction, runs the owning module's validate hook, picks the flow and
-- walks it to the first approver, publishes requests.submitted and tells the first approver.
-- Last result set: the new request's id.
CREATE OR ALTER PROCEDURE [req].[usp_request_submit]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @type_code       NVARCHAR(30),
    @permission_code NVARCHAR(150),
    @employee_id     BIGINT = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @reason          NVARCHAR(MAX) = NULL,
    @description     NVARCHAR(MAX) = NULL,
    @application     NVARCHAR(MAX) = NULL,
    @details         NVARCHAR(MAX) = NULL,
    @attachments     NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @type_id BIGINT, @prefix NVARCHAR(10), @admin_only BIT, @type_name NVARCHAR(200), @msg NVARCHAR(400);
    SELECT @type_id = id, @prefix = ISNULL(NULLIF(prefix, N''), UPPER(LEFT(code, 3))), @admin_only = is_admin_only, @type_name = name
    FROM [req].[request_type] WHERE code = @type_code AND is_active = 1;
    IF @type_id IS NULL
        THROW 50404, N'Request type not found', 1;

    DECLARE @actor_employee_id BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);
    SET @employee_id = COALESCE(@employee_id, @actor_employee_id);
    IF @employee_id IS NULL
        THROW 50400, N'employeeId|Choose the employee this request is for.', 1;
    IF NOT EXISTS (SELECT 1 FROM [hr].[employee] WHERE id = @employee_id AND company_id = @company_id AND status <> N'left')
        THROW 50400, N'employeeId|Employee not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v
                   WHERE v.employee_id = @employee_id)
        THROW 50403, N'You cannot make requests for this employee.', 1;
    IF @admin_only = 1 AND @employee_id = @actor_employee_id
    BEGIN
        SET @msg = @type_name + N' requests are made by HR for an employee, not for yourself.';
        THROW 50403, @msg, 1;
    END
    -- Attachments are uploaded files (POST /api/files): a JSON list of this company's file ids.
    IF @attachments IS NOT NULL AND ISJSON(@attachments) = 0
        THROW 50400, N'attachments|Attachments are not valid.', 1;
    DECLARE @files TABLE (file_id BIGINT PRIMARY KEY);
    INSERT @files (file_id)
    SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM OPENJSON(ISNULL(@attachments, N'[]')) WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;
    IF EXISTS (SELECT 1 FROM OPENJSON(ISNULL(@attachments, N'[]')) WHERE TRY_CAST(value AS BIGINT) IS NULL)
       OR EXISTS (SELECT 1 FROM @files f WHERE NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, f.file_id)))
        THROW 50400, N'attachments|An attached file was not found. Upload it again.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME(), @id BIGINT, @n INT, @code NVARCHAR(30),
            @seq NVARCHAR(10) = N'RQ-' + @prefix;

    BEGIN TRAN;
        UPDATE [core].[number_sequence] WITH (UPDLOCK, HOLDLOCK)
        SET @n = next_number, next_number = next_number + 1, updated_at = @now
        WHERE company_id = @company_id AND prefix = @seq;
        IF @@ROWCOUNT = 0
        BEGIN
            SET @n = 1;
            INSERT [core].[number_sequence] (company_id, prefix, next_number) VALUES (@company_id, @seq, 2);
        END
        SET @code = @seq + N'-' + RIGHT(N'000' + CONVERT(NVARCHAR(10), @n), CASE WHEN @n > 9999 THEN LEN(CONVERT(NVARCHAR(10), @n)) ELSE 4 END);

        INSERT [req].[request] (company_id, code, request_type_id, employee_id, created_by_user_id, from_date, to_date,
                                reason, description, application, status, submitted_at, created_by)
        VALUES (@company_id, @code, @type_id, @employee_id, @actor_user_id, @from_date, @to_date,
                NULLIF(LTRIM(RTRIM(@reason)), N''), NULLIF(LTRIM(RTRIM(@description)), N''), NULLIF(@application, N''),
                N'pending', @now, @actor_user_id);
        SET @id = SCOPE_IDENTITY();

        -- Attachments first: some rules (leave types) need them.
        INSERT [core].[attachment] (company_id, entity_type, entity_id, file_id, created_by)
        SELECT @company_id, N'req.request', @id, file_id, @actor_user_id FROM @files;

        EXEC [req].[usp_request_detail_save] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @id, @details = @details;

        -- Request Restrictions: a type closed for the company over any of the request's dates.
        DECLARE @r_start DATE, @r_end DATE;
        SELECT TOP (1) @r_start = x.start_date, @r_end = x.end_date
        FROM [req].[request_restriction] x
        JOIN [req].[request] r ON r.id = @id
        WHERE x.company_id = @company_id AND x.request_type_id = @type_id
          AND x.start_date <= ISNULL(r.to_date, ISNULL(r.from_date, CAST(@now AS DATE)))
          AND x.end_date >= ISNULL(r.from_date, CAST(@now AS DATE))
        ORDER BY x.start_date;
        IF @r_start IS NOT NULL
        BEGIN
            SET @msg = N'fromDate|REQUEST_RESTRICTED|' + @type_name + N' requests are closed from '
                     + CONVERT(NVARCHAR(10), @r_start, 23) + N' to ' + CONVERT(NVARCHAR(10), @r_end, 23) + N'.';
            THROW 50400, @msg, 1;
        END

        EXEC [req].[usp_request_effect_run] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @id, @verb = N'validate';

        INSERT [req].[request_step] (request_id, purpose, approver_kind, acted_by_id, action_taken, acted_at, created_by)
        VALUES (@id, N'request', N'requester', @actor_employee_id, N'submitted', @now, @actor_user_id);

        -- The colleague of a shift swap gives consent before the flow starts.
        DECLARE @colleague BIGINT = (SELECT with_employee_id FROM [req].[req_shift_swap] WHERE request_id = @id);
        EXEC [req].[usp_request_flow_pick] @company_id = @company_id, @actor_user_id = @actor_user_id,
             @request_id = @id, @purpose = N'request';
        IF @colleague IS NOT NULL
            INSERT [req].[request_step] (request_id, purpose, approver_kind, approver_id, is_consent, action_taken, created_by)
            VALUES (@id, N'request', N'colleague', @colleague, 1, N'pending', @actor_user_id);
        ELSE
        BEGIN
            EXEC [req].[usp_request_advance] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id;
            IF NOT EXISTS (SELECT 1 FROM [req].[request] WHERE id = @id AND status = N'pending')
                THROW 50400, N'employeeId|NO_APPROVER|Nobody in the approval flow can decide this request (for example, no line manager or final authority is set).', 1;
        END

        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'req.request', @id, N'create', @actor_user_id, @now);

        EXEC [req].[usp_request_publish] @company_id = @company_id, @actor_user_id = @actor_user_id, @request_id = @id,
             @event_type = N'requests.submitted', @action = N'submitted';
    COMMIT;

    SELECT @id AS id;
END
