-- Open Positions: seats released by approved budgets, with the JD file, Edit and Close / Reopen.
-- Scope: reached through the department or station (mp.fn_unit_reach).

CREATE OR ALTER PROCEDURE [mp].[usp_open_position_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [mp].[open_position] x WHERE x.id = @id AND x.company_id = @company_id
                   AND EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                               WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                  OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
        THROW 50404, N'Open position not found', 1;

    SELECT * FROM [mp].[fn_open_position_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page: active first, then by end date.
CREATE OR ALTER PROCEDURE [mp].[usp_open_position_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @search          NVARCHAR(200) = NULL,
    @job_title_id    BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @status          NVARCHAR(30) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @reach TABLE (unit_type NVARCHAR(30), unit_id BIGINT);
    INSERT @reach SELECT unit_type, unit_id FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code);
    DECLARE @all BIT = CASE WHEN EXISTS (SELECT 1 FROM @reach WHERE unit_type = N'company') THEN 1 ELSE 0 END;

    SELECT COUNT(*) AS total
    FROM [mp].[fn_open_position_rows](@company_id) x
    WHERE (@all = 1 OR EXISTS (SELECT 1 FROM @reach r WHERE (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                                        OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
      AND (@pattern IS NULL OR x.title LIKE @pattern OR x.position_code LIKE @pattern)
      AND (@job_title_id IS NULL OR x.job_title_id = @job_title_id)
      AND (@department_id IS NULL OR x.department_id = @department_id)
      AND (@status IS NULL OR x.status = @status)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [mp].[fn_open_position_rows](@company_id) x
    WHERE (@all = 1 OR EXISTS (SELECT 1 FROM @reach r WHERE (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                                        OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
      AND (@pattern IS NULL OR x.title LIKE @pattern OR x.position_code LIKE @pattern)
      AND (@job_title_id IS NULL OR x.job_title_id = @job_title_id)
      AND (@department_id IS NULL OR x.department_id = @department_id)
      AND (@status IS NULL OR x.status = @status)
    ORDER BY CASE x.status WHEN N'active' THEN 0 ELSE 1 END, x.end_date, x.id
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Edit: the seats still open, until when, and the JD file (a core.stored_file already uploaded).
CREATE OR ALTER PROCEDURE [mp].[usp_open_position_save]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @total_positions INT,
    @end_date        DATE = NULL,
    @jd_file_id      BIGINT = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @dept BIGINT, @branch BIGINT, @old_total INT, @old_end DATE, @old_jd BIGINT,
            @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @rv = row_version, @dept = department_id, @branch = branch_id, @old_total = total_positions,
           @old_end = end_date, @old_jd = jd_file_id
    FROM [mp].[open_position] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @dept)
                                     OR (r.unit_type = N'branch' AND r.unit_id = @branch))
        THROW 50404, N'Open position not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required to edit an open position.', 1;
    IF @total_positions IS NULL OR @total_positions < 1
        THROW 50400, N'totalPositions|Enter the number of positions (1 or more).', 1;
    IF @jd_file_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [core].[fn_file_usable](@company_id, @jd_file_id))
        THROW 50400, N'jdFileId|The file was not found. Upload it again.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this open position. Reload it and try again', 1;

    BEGIN TRAN;
        UPDATE [mp].[open_position]
        SET total_positions = @total_positions, end_date = @end_date, jd_file_id = @jd_file_id,
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this open position. Reload it and try again', 1;

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        SELECT N'mp.open_position', @id, f.field_name, f.old_value, f.new_value, N'update', @actor_user_id, @now
        FROM (VALUES
            (N'total_positions', CONVERT(NVARCHAR(30), @old_total), CONVERT(NVARCHAR(30), @total_positions)),
            (N'end_date', CONVERT(NVARCHAR(30), @old_end, 23), CONVERT(NVARCHAR(30), @end_date, 23)),
            (N'jd_file_id', CONVERT(NVARCHAR(30), @old_jd), CONVERT(NVARCHAR(30), @jd_file_id))
        ) f (field_name, old_value, new_value)
        WHERE EXISTS (SELECT f.old_value EXCEPT SELECT f.new_value);
    COMMIT;

    EXEC [mp].[usp_open_position_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Close or reopen an open position (@status closed / active). Publishes manpower.position_closed or
-- manpower.position_opened (reopened: true).
CREATE OR ALTER PROCEDURE [mp].[usp_open_position_status]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @status          NVARCHAR(30),
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @dept BIGINT, @branch BIGINT, @old NVARCHAR(30), @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @rv = row_version, @dept = department_id, @branch = branch_id, @old = status
    FROM [mp].[open_position] WHERE id = @id AND company_id = @company_id;
    IF @rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @dept)
                                     OR (r.unit_type = N'branch' AND r.unit_id = @branch))
        THROW 50404, N'Open position not found', 1;
    IF @status NOT IN (N'active', N'closed')
        THROW 50400, N'status|Status is active or closed.', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this open position. Reload it and try again', 1;
    IF @old = @status
        THROW 50409, N'status|OPEN_POSITION_STATUS|The open position is already in that state.', 1;

    BEGIN TRAN;
        UPDATE [mp].[open_position] SET status = @status, updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this open position. Reload it and try again', 1;
        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.open_position', @id, N'status', @old, @status,
                CASE @status WHEN N'closed' THEN N'close' ELSE N'reopen' END, @actor_user_id, @now);

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(30), o.id) AS openPositionId, o.title, CONVERT(NVARCHAR(30), o.e_budget_id) AS budgetId,
                   CONVERT(NVARCHAR(30), o.position_id) AS positionId, CONVERT(NVARCHAR(30), o.job_title_id) AS jobTitleId,
                   CONVERT(NVARCHAR(30), o.department_id) AS departmentId, CONVERT(NVARCHAR(30), o.branch_id) AS branchId,
                   o.approved_positions AS approvedPositions, o.total_positions AS totalPositions,
                   CONVERT(NVARCHAR(10), o.end_date, 23) AS endDate, CAST(CASE WHEN @status = N'active' THEN 1 ELSE 0 END AS BIT) AS reopened
            FROM [mp].[open_position] o WHERE o.id = @id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        DECLARE @event NVARCHAR(100) = CASE @status WHEN N'closed' THEN N'manpower.position_closed' ELSE N'manpower.position_opened' END;
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = @event,
             @entity_type = N'mp.open_position', @entity_id = @id, @payload = @payload;
    COMMIT;

    EXEC [mp].[usp_open_position_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- The JD file of an open position: the stored file's details; the API adds a signed download link.
CREATE OR ALTER PROCEDURE [mp].[usp_open_position_jd]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @jd BIGINT, @found BIT = 0;
    SELECT @found = 1, @jd = x.jd_file_id
    FROM [mp].[open_position] x
    WHERE x.id = @id AND x.company_id = @company_id
      AND EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = x.department_id)
                     OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id));
    IF @found = 0
        THROW 50404, N'Open position not found', 1;
    IF @jd IS NULL
        THROW 50404, N'No job description is attached to this open position', 1;

    SELECT f.id, f.name, f.mime_type, f.size_bytes, f.created_at
    FROM [core].[stored_file] f WHERE f.id = @jd AND f.company_id = @company_id;
END
