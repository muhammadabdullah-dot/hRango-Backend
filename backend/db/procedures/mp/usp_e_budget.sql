-- E-Budgeting and Budget Approvals. Budgets come from submitted plans (one per position title and
-- department) or are added by hand. Approving one releases its open positions; the plan's status follows
-- its budgets. Approval is status based here (not req.request): see comparison/09-manpower-benefits.md.
-- Scope: a budget is reached through its department, or its plan's station (mp.fn_unit_reach).

CREATE OR ALTER PROCEDURE [mp].[usp_e_budget_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @found BIT = 0;
    SELECT @found = 1 FROM [mp].[fn_budget_rows](@company_id) x
    WHERE x.id = @id
      AND EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = x.department_id)
                     OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id));
    IF @found = 0
        THROW 50404, N'Budget not found', 1;

    SELECT * FROM [mp].[fn_budget_rows](@company_id) WHERE id = @id;
END
GO

-- Result set 1: total. Result set 2: the page: pending first, then newest.
CREATE OR ALTER PROCEDURE [mp].[usp_e_budget_list]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @search             NVARCHAR(200) = NULL,
    @budget_duration_id BIGINT = NULL,
    @manpower_plan_id   BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @status             NVARCHAR(30) = NULL,
    @page               INT = 1,
    @page_size          INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @reach TABLE (unit_type NVARCHAR(30), unit_id BIGINT);
    INSERT @reach SELECT unit_type, unit_id FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code);
    DECLARE @all BIT = CASE WHEN EXISTS (SELECT 1 FROM @reach WHERE unit_type = N'company') THEN 1 ELSE 0 END;

    SELECT COUNT(*) AS total
    FROM [mp].[fn_budget_rows](@company_id) x
    WHERE (@all = 1 OR EXISTS (SELECT 1 FROM @reach r WHERE (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                                        OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
      AND (@pattern IS NULL OR x.title LIKE @pattern OR x.plan_title LIKE @pattern)
      AND (@budget_duration_id IS NULL OR x.budget_duration_id = @budget_duration_id)
      AND (@manpower_plan_id IS NULL OR x.manpower_plan_id = @manpower_plan_id)
      AND (@department_id IS NULL OR x.department_id = @department_id)
      AND (@status IS NULL OR x.status = @status)
    OPTION (RECOMPILE);

    SELECT x.*
    FROM [mp].[fn_budget_rows](@company_id) x
    WHERE (@all = 1 OR EXISTS (SELECT 1 FROM @reach r WHERE (r.unit_type = N'department' AND r.unit_id = x.department_id)
                                                        OR (r.unit_type = N'branch' AND r.unit_id = x.branch_id)))
      AND (@pattern IS NULL OR x.title LIKE @pattern OR x.plan_title LIKE @pattern)
      AND (@budget_duration_id IS NULL OR x.budget_duration_id = @budget_duration_id)
      AND (@manpower_plan_id IS NULL OR x.manpower_plan_id = @manpower_plan_id)
      AND (@department_id IS NULL OR x.department_id = @department_id)
      AND (@status IS NULL OR x.status = @status)
    ORDER BY CASE x.status WHEN N'pending' THEN 0 WHEN N'approved' THEN 1 ELSE 2 END, x.created_at DESC, x.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds a budget by hand (@id NULL) or edits one. An approved budget cannot change; editing a pending or
-- rejected one sends it (back) for approval. A plan's budget keeps its plan year.
CREATE OR ALTER PROCEDURE [mp].[usp_e_budget_save]
    @company_id         BIGINT,
    @actor_user_id      BIGINT,
    @permission_code    NVARCHAR(150),
    @id                 BIGINT = NULL,
    @title              NVARCHAR(200) = NULL,
    @budget_duration_id BIGINT,
    @job_title_id       BIGINT = NULL,
    @department_id      BIGINT = NULL,
    @amount             DECIMAL(18,2),
    @total_positions    INT = 0,
    @start_date         DATE,
    @end_date           DATE,
    @row_version        BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @d_start DATE, @d_end DATE, @now DATETIME2(0) = SYSUTCDATETIME(), @plan_id BIGINT, @plan_branch BIGINT;
    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    SET @total_positions = ISNULL(@total_positions, 0);

    SELECT @d_start = start_date, @d_end = end_date FROM [mp].[budget_duration]
    WHERE id = @budget_duration_id AND company_id = @company_id;
    IF @d_start IS NULL
        THROW 50400, N'budgetDurationId|Choose the budget duration.', 1;
    IF @job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[job_title] WHERE id = @job_title_id AND company_id = @company_id)
        THROW 50400, N'jobTitleId|Position title not found.', 1;
    IF @department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [org].[department] WHERE id = @department_id AND company_id = @company_id)
        THROW 50400, N'departmentId|Department not found.', 1;
    IF @title IS NULL
        SET @title = (SELECT name FROM [org].[job_title] WHERE id = @job_title_id);
    IF @title IS NULL
        THROW 50400, N'title|Enter the title or choose the position title.', 1;
    IF @amount IS NULL OR @amount <= 0
        THROW 50400, N'amount|Enter the budget amount.', 1;
    IF @total_positions < 0
        THROW 50400, N'totalPositions|Positions cannot be negative.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Enter the start date.', 1;
    IF @end_date IS NULL
        THROW 50400, N'endDate|Enter the end date.', 1;
    IF @end_date < @start_date
        THROW 50400, N'endDate|The end cannot be before the start.', 1;
    IF @start_date < @d_start OR @end_date > @d_end
        THROW 50400, N'startDate|The dates must fall in the budget duration.', 1;

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a budget.', 1;
        DECLARE @old_rv BINARY(8), @old_status NVARCHAR(30), @old_dept BIGINT, @old_duration BIGINT;
        SELECT @old_rv = b.row_version, @old_status = b.status, @old_dept = b.department_id, @plan_id = b.manpower_plan_id,
               @plan_branch = p.branch_id, @old_duration = b.budget_duration_id
        FROM [mp].[e_budget] b LEFT JOIN [mp].[manpower_plan] p ON p.id = b.manpower_plan_id
        WHERE b.id = @id AND b.company_id = @company_id;
        IF @old_rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                          WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @old_dept)
                                             OR (r.unit_type = N'branch' AND r.unit_id = @plan_branch))
            THROW 50404, N'Budget not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this budget. Reload it and try again', 1;
        IF @old_status = N'approved'
            THROW 50409, N'status|BUDGET_LOCKED|An approved budget cannot be changed.', 1;
        IF @plan_id IS NOT NULL AND @budget_duration_id <> @old_duration
            THROW 50400, N'budgetDurationId|A plan''s budget keeps the plan year.', 1;
    END

    IF NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                   WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @department_id)
                      OR (r.unit_type = N'branch' AND r.unit_id = @plan_branch))
        THROW 50403, N'You cannot budget for this department.', 1;

    BEGIN TRAN;
        IF @id IS NULL
        BEGIN
            INSERT [mp].[e_budget] (company_id, budget_duration_id, job_title_id, department_id, title, amount, total_positions,
                                    start_date, end_date, status, created_by)
            VALUES (@company_id, @budget_duration_id, @job_title_id, @department_id, @title, @amount, @total_positions,
                    @start_date, @end_date, N'pending', @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.e_budget', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [mp].[e_budget]
            SET title = @title, budget_duration_id = @budget_duration_id, job_title_id = @job_title_id,
                department_id = @department_id, amount = @amount, total_positions = @total_positions,
                start_date = @start_date, end_date = @end_date, status = N'pending',
                decided_by_user_id = NULL, decided_at = NULL, remarks = NULL, updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this budget. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.e_budget', @id, N'update', @actor_user_id, @now);
            EXEC [mp].[usp_manpower_plan_status_sync] @plan_id = @plan_id, @actor_user_id = @actor_user_id;
        END
    COMMIT;

    EXEC [mp].[usp_e_budget_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
GO

-- Deletes a pending or rejected budget. Its plan lines stay, no longer counted in a budget.
CREATE OR ALTER PROCEDURE [mp].[usp_e_budget_delete]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @dept BIGINT, @plan_id BIGINT, @branch BIGINT;
    SELECT @rv = b.row_version, @status = b.status, @dept = b.department_id, @plan_id = b.manpower_plan_id, @branch = p.branch_id
    FROM [mp].[e_budget] b LEFT JOIN [mp].[manpower_plan] p ON p.id = b.manpower_plan_id
    WHERE b.id = @id AND b.company_id = @company_id;
    IF @rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @dept)
                                     OR (r.unit_type = N'branch' AND r.unit_id = @branch))
        THROW 50404, N'Budget not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this budget. Reload it and try again', 1;
    IF @status = N'approved'
        THROW 50409, N'status|BUDGET_LOCKED|An approved budget cannot be deleted.', 1;

    BEGIN TRAN;
        UPDATE [mp].[manpower_plan_line] SET e_budget_id = NULL WHERE e_budget_id = @id;
        DELETE [mp].[e_budget] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.e_budget', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
        EXEC [mp].[usp_manpower_plan_status_sync] @plan_id = @plan_id, @actor_user_id = @actor_user_id;
    COMMIT;
END
GO

-- Budget Approvals: approve or reject a pending budget. Approving releases its open positions: one per
-- new-position line of the budget (its headcount), or, for a budget without such lines, one for its
-- total positions. Then the plan's status follows. Publishes manpower.budget_decided (the person who
-- submitted the budget is told) and manpower.position_opened for each open position released.
CREATE OR ALTER PROCEDURE [mp].[usp_e_budget_decide]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT,
    @decision        NVARCHAR(30),
    @remarks         NVARCHAR(MAX) = NULL,
    @row_version     BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @decision NOT IN (N'approve', N'reject')
        THROW 50400, N'decision|Decision is approve or reject.', 1;

    DECLARE @rv BINARY(8), @status NVARCHAR(30), @dept BIGINT, @plan_id BIGINT, @branch BIGINT, @now DATETIME2(0) = SYSUTCDATETIME();
    SELECT @rv = b.row_version, @status = b.status, @dept = b.department_id, @plan_id = b.manpower_plan_id, @branch = p.branch_id
    FROM [mp].[e_budget] b LEFT JOIN [mp].[manpower_plan] p ON p.id = b.manpower_plan_id
    WHERE b.id = @id AND b.company_id = @company_id;
    IF @rv IS NULL OR NOT EXISTS (SELECT 1 FROM [mp].[fn_unit_reach](@company_id, @actor_user_id, @permission_code) r
                                  WHERE r.unit_type = N'company' OR (r.unit_type = N'department' AND r.unit_id = @dept)
                                     OR (r.unit_type = N'branch' AND r.unit_id = @branch))
        THROW 50404, N'Budget not found', 1;
    IF @row_version IS NULL
        THROW 50400, N'rowVersion|rowVersion is required.', 1;
    -- Decided first: a second decision with the old rowVersion is "already decided", not "someone else changed it".
    IF @status <> N'pending'
        THROW 50409, N'status|BUDGET_ALREADY_DECIDED|This budget was already decided.', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this budget. Reload it and try again', 1;

    DECLARE @opened TABLE (id BIGINT PRIMARY KEY);

    BEGIN TRAN;
        UPDATE [mp].[e_budget]
        SET status = CASE @decision WHEN N'approve' THEN N'approved' ELSE N'rejected' END,
            decided_by_user_id = @actor_user_id, decided_at = @now, remarks = NULLIF(LTRIM(RTRIM(@remarks)), N''),
            updated_at = @now, updated_by = @actor_user_id
        WHERE id = @id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Someone else changed this budget. Reload it and try again', 1;

        IF @decision = N'approve'
        BEGIN
            INSERT [mp].[open_position] (company_id, e_budget_id, manpower_plan_line_id, position_id, job_title_id,
                                         department_id, branch_id, title, approved_positions, total_positions, end_date,
                                         status, created_by)
            OUTPUT inserted.id INTO @opened
            SELECT @company_id, @id, l.id, ps.id, ps.job_title_id, ps.department_id, ps.branch_id, jt.name,
                   l.headcount, l.headcount, l.end_date, N'active', @actor_user_id
            FROM [mp].[manpower_plan_line] l
            JOIN [mp].[position] ps ON ps.id = l.position_id
            JOIN [org].[job_title] jt ON jt.id = ps.job_title_id
            WHERE l.e_budget_id = @id AND l.kind = N'new_position';

            IF @@ROWCOUNT = 0
                INSERT [mp].[open_position] (company_id, e_budget_id, job_title_id, department_id, branch_id, title,
                                             approved_positions, total_positions, end_date, status, created_by)
                OUTPUT inserted.id INTO @opened
                SELECT @company_id, b.id, b.job_title_id, b.department_id, @branch, b.title, b.total_positions,
                       b.total_positions, b.end_date, N'active', @actor_user_id
                FROM [mp].[e_budget] b
                WHERE b.id = @id AND b.total_positions > 0;
        END

        INSERT [core].[audit_log] (entity_type, entity_id, field_name, old_value, new_value, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.e_budget', @id, N'status', N'pending', CASE @decision WHEN N'approve' THEN N'approved' ELSE N'rejected' END,
                @decision, @actor_user_id, @now);
        EXEC [mp].[usp_manpower_plan_status_sync] @plan_id = @plan_id, @actor_user_id = @actor_user_id;

        DECLARE @payload NVARCHAR(MAX), @submitter BIGINT, @title NVARCHAR(200);
        SELECT @submitter = b.created_by,
               @title = LEFT(CONCAT(N'Budget ', CASE @decision WHEN N'approve' THEN N'approved: ' ELSE N'rejected: ' END, b.title), 200),
               @payload = (SELECT CONVERT(NVARCHAR(30), b.id) AS budgetId, b.title, b.status, b.amount,
                                  b.total_positions AS totalPositions, CONVERT(NVARCHAR(30), b.manpower_plan_id) AS manpowerPlanId,
                                  CONVERT(NVARCHAR(30), b.department_id) AS departmentId,
                                  CONVERT(NVARCHAR(30), b.job_title_id) AS jobTitleId, b.remarks,
                                  CONVERT(NVARCHAR(30), @actor_user_id) AS decidedBy,
                                  (SELECT COUNT(*) FROM @opened) AS openPositions
                           FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM [mp].[e_budget] b WHERE b.id = @id;
        EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'manpower.budget_decided',
             @entity_type = N'mp.e_budget', @entity_id = @id, @payload = @payload;
        IF @submitter IS NOT NULL AND @submitter <> @actor_user_id
           AND EXISTS (SELECT 1 FROM [auth].[user_account] WHERE id = @submitter AND is_active = 1)
        BEGIN
            EXEC [core].[usp_notification_add] @quiet = 1, @company_id = @company_id, @user_account_id = @submitter,
                 @title = @title, @body = @remarks, @notification_type = N'manpower',
                 @link = N'/manpower-planning/e-budgeting', @entity_type = N'mp.e_budget', @entity_id = @id;
        END

        DECLARE @op BIGINT = (SELECT MIN(id) FROM @opened);
        WHILE @op IS NOT NULL
        BEGIN
            SET @payload = (
                SELECT CONVERT(NVARCHAR(30), o.id) AS openPositionId, o.title, CONVERT(NVARCHAR(30), o.e_budget_id) AS budgetId,
                       CONVERT(NVARCHAR(30), o.position_id) AS positionId, CONVERT(NVARCHAR(30), o.job_title_id) AS jobTitleId,
                       CONVERT(NVARCHAR(30), o.department_id) AS departmentId, CONVERT(NVARCHAR(30), o.branch_id) AS branchId,
                       o.approved_positions AS approvedPositions, o.total_positions AS totalPositions,
                       CONVERT(NVARCHAR(10), o.end_date, 23) AS endDate
                FROM [mp].[open_position] o WHERE o.id = @op
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC [core].[usp_event_publish] @company_id = @company_id, @event_type = N'manpower.position_opened',
                 @entity_type = N'mp.open_position', @entity_id = @op, @payload = @payload;
            SET @op = (SELECT MIN(id) FROM @opened WHERE id > @op);
        END
    COMMIT;

    EXEC [mp].[usp_e_budget_get] @company_id = @company_id, @actor_user_id = @actor_user_id,
         @permission_code = @permission_code, @id = @id;
END
