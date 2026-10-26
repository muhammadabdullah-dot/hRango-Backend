-- Job titles (Settings -> Control Panel -> Organization -> Job Title), with an optional head-count
-- limit. hr.usp_employee_save refuses an employee that would take a limited title over its limit.

CREATE OR ALTER PROCEDURE [org].[usp_job_title_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Job title not found', 1;

    SELECT j.id, j.name, j.limit_head_count, j.max_head_count, j.description,
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.job_title_id = j.id AND e.status NOT IN (N'left', N'inactive')) AS head_count,
           j.created_at, j.updated_at, j.row_version
    FROM [org].[job_title] j
    WHERE j.id = @id AND j.company_id = @company_id;
END
GO

-- Result set 1: total matching rows. Result set 2: the requested page.
CREATE OR ALTER PROCEDURE [org].[usp_job_title_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [org].[job_title] j
    WHERE j.company_id = @company_id AND (@pattern IS NULL OR j.name LIKE @pattern)
    OPTION (RECOMPILE);

    SELECT j.id, j.name, j.limit_head_count, j.max_head_count, j.description,
           (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.job_title_id = j.id AND e.status NOT IN (N'left', N'inactive')) AS head_count,
           j.created_at, j.updated_at, j.row_version
    FROM [org].[job_title] j
    WHERE j.company_id = @company_id AND (@pattern IS NULL OR j.name LIKE @pattern)
    ORDER BY j.name, j.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_job_title_save]
    @company_id       BIGINT,
    @actor_user_id    BIGINT = NULL,
    @id               BIGINT = NULL,
    @name             NVARCHAR(200),
    @limit_head_count BIT = 0,
    @max_head_count   INT = NULL,
    @description      NVARCHAR(MAX) = NULL,
    @row_version      BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), N'');
    SET @limit_head_count = ISNULL(@limit_head_count, 0);
    IF @limit_head_count = 0
        SET @max_head_count = NULL;

    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Job title name is required.', 1;
    IF @limit_head_count = 1 AND (@max_head_count IS NULL OR @max_head_count < 1)
        THROW 50400, N'maxHeadCount|Enter the maximum head count (1 or more).', 1;
    IF EXISTS (SELECT 1 FROM [org].[job_title] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|JOB_TITLE_DUPLICATE|A job title with this name already exists.', 1;
    IF @id IS NOT NULL AND @limit_head_count = 1
       AND (SELECT COUNT(*) FROM [hr].[employee] e WHERE e.job_title_id = @id AND e.status NOT IN (N'left', N'inactive')) > @max_head_count
        THROW 50409, N'maxHeadCount|More employees already hold this job title than the new limit allows.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NULL
    BEGIN
        BEGIN TRAN;
            INSERT [org].[job_title] (company_id, name, limit_head_count, max_head_count, description, created_by)
            VALUES (@company_id, @name, @limit_head_count, @max_head_count, @description, @actor_user_id);
            SET @id = SCOPE_IDENTITY();

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (@company_id, N'org.job_title', @id, N'create', @actor_user_id, @now);
        COMMIT;
    END
    ELSE
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a job title.', 1;

        DECLARE @o_name NVARCHAR(200), @o_limit BIT, @o_max INT, @o_desc NVARCHAR(MAX), @o_rv BINARY(8);
        SELECT @o_name = name, @o_limit = limit_head_count, @o_max = max_head_count, @o_desc = description,
               @o_rv = row_version
        FROM [org].[job_title] WHERE id = @id AND company_id = @company_id;

        IF @o_rv IS NULL
            THROW 50404, N'Job title not found', 1;
        IF @o_rv <> @row_version
            THROW 50409, N'Someone else changed this job title. Reload it and try again', 1;

        BEGIN TRAN;
            UPDATE [org].[job_title]
            SET name = @name, limit_head_count = @limit_head_count, max_head_count = @max_head_count,
                description = @description, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;

            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this job title. Reload it and try again', 1;

            INSERT [core].[audit_log] (company_id, entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
            SELECT @company_id, N'org.job_title', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
            FROM (VALUES
                (N'name', @o_name, @name), (N'description', @o_desc, @description),
                (N'limit_head_count', CONVERT(NVARCHAR(10), @o_limit), CONVERT(NVARCHAR(10), @limit_head_count)),
                (N'max_head_count', CONVERT(NVARCHAR(10), @o_max), CONVERT(NVARCHAR(10), @max_head_count))
            ) f (field_name, old_value, new_value)
            WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
        COMMIT;
    END

    EXEC [org].[usp_job_title_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [org].[usp_job_title_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [org].[job_title] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Job title not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this job title. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [hr].[employee] WHERE job_title_id = @id)
        THROW 50409, N'Employees hold this job title. Change their job title first', 1;

    BEGIN TRAN;
        DELETE [org].[job_title] WHERE id = @id AND company_id = @company_id;

        INSERT [core].[audit_log] (company_id, entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (@company_id, N'org.job_title', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
