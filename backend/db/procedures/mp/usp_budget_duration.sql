-- E-Budget Settings -> Budget Duration. A duration is the "Plan Year" of plans and budgets; at most one
-- per company is the current period (IsCurrentBudgetDurationPeriod), which drives "Current Planning".
CREATE OR ALTER PROCEDURE [mp].[usp_budget_duration_get]
    @company_id BIGINT,
    @id         BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [mp].[budget_duration] WHERE id = @id AND company_id = @company_id)
        THROW 50404, N'Budget duration not found', 1;

    SELECT d.id, d.name, d.start_date, d.end_date, d.is_current,
           (SELECT COUNT(*) FROM [mp].[manpower_plan] p WHERE p.budget_duration_id = d.id) AS plan_count,
           (SELECT COUNT(*) FROM [mp].[e_budget] b WHERE b.budget_duration_id = d.id) AS budget_count,
           d.created_at, cb.name AS created_by_name, d.updated_at, d.row_version
    FROM [mp].[budget_duration] d
    OUTER APPLY [mp].[fn_actor_name](d.created_by) cb
    WHERE d.id = @id AND d.company_id = @company_id;
END
GO

-- Result set 1: total. Result set 2: the page, newest period first.
CREATE OR ALTER PROCEDURE [mp].[usp_budget_duration_list]
    @company_id BIGINT,
    @search     NVARCHAR(200) = NULL,
    @is_current BIT = NULL,
    @page       INT = 1,
    @page_size  INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [mp].[budget_duration] d
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.name LIKE @pattern)
      AND (@is_current IS NULL OR d.is_current = @is_current)
    OPTION (RECOMPILE);

    SELECT d.id, d.name, d.start_date, d.end_date, d.is_current,
           (SELECT COUNT(*) FROM [mp].[manpower_plan] p WHERE p.budget_duration_id = d.id) AS plan_count,
           (SELECT COUNT(*) FROM [mp].[e_budget] b WHERE b.budget_duration_id = d.id) AS budget_count,
           d.created_at, cb.name AS created_by_name, d.updated_at, d.row_version
    FROM [mp].[budget_duration] d
    OUTER APPLY [mp].[fn_actor_name](d.created_by) cb
    WHERE d.company_id = @company_id
      AND (@pattern IS NULL OR d.name LIKE @pattern)
      AND (@is_current IS NULL OR d.is_current = @is_current)
    ORDER BY d.start_date DESC, d.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END
GO

-- Adds (@id NULL) or edits a duration. Ticking is_current clears it on every other duration, in the same
-- transaction, so a company never has two current periods.
CREATE OR ALTER PROCEDURE [mp].[usp_budget_duration_save]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT = NULL,
    @name          NVARCHAR(200),
    @start_date    DATE,
    @end_date      DATE,
    @is_current    BIT = 0,
    @row_version   BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @name = LTRIM(RTRIM(@name));
    SET @is_current = ISNULL(@is_current, 0);
    IF @name IS NULL OR @name = N''
        THROW 50400, N'name|Budget duration name is required.', 1;
    IF @start_date IS NULL
        THROW 50400, N'startDate|Start date is required.', 1;
    IF @end_date IS NULL
        THROW 50400, N'endDate|End date is required.', 1;
    IF @end_date < @start_date
        THROW 50400, N'endDate|End date cannot be before the start date.', 1;
    IF EXISTS (SELECT 1 FROM [mp].[budget_duration] WHERE company_id = @company_id AND name = @name AND (@id IS NULL OR id <> @id))
        THROW 50409, N'name|BUDGET_DURATION_DUPLICATE|A budget duration with this name already exists.', 1;

    DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

    IF @id IS NOT NULL
    BEGIN
        IF @row_version IS NULL
            THROW 50400, N'rowVersion|rowVersion is required to edit a budget duration.', 1;
        DECLARE @old_rv BINARY(8) = (SELECT row_version FROM [mp].[budget_duration] WHERE id = @id AND company_id = @company_id);
        IF @old_rv IS NULL
            THROW 50404, N'Budget duration not found', 1;
        IF @old_rv <> @row_version
            THROW 50409, N'Someone else changed this budget duration. Reload it and try again', 1;
        IF EXISTS (SELECT 1 FROM [mp].[manpower_plan_line] l JOIN [mp].[manpower_plan] p ON p.id = l.manpower_plan_id
                   WHERE p.budget_duration_id = @id AND (l.start_date < @start_date OR l.end_date > @end_date))
            THROW 50409, N'startDate|DURATION_IN_USE|Plans of this duration have positions outside the new dates.', 1;
    END

    BEGIN TRAN;
        IF @is_current = 1
            UPDATE [mp].[budget_duration]
            SET is_current = 0, updated_at = @now, updated_by = @actor_user_id
            WHERE company_id = @company_id AND is_current = 1 AND (@id IS NULL OR id <> @id);

        IF @id IS NULL
        BEGIN
            INSERT [mp].[budget_duration] (company_id, name, start_date, end_date, is_current, created_by)
            VALUES (@company_id, @name, @start_date, @end_date, @is_current, @actor_user_id);
            SET @id = SCOPE_IDENTITY();
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.budget_duration', @id, N'create', @actor_user_id, @now);
        END
        ELSE
        BEGIN
            UPDATE [mp].[budget_duration]
            SET name = @name, start_date = @start_date, end_date = @end_date, is_current = @is_current,
                updated_at = @now, updated_by = @actor_user_id
            WHERE id = @id AND company_id = @company_id AND row_version = @row_version;
            IF @@ROWCOUNT = 0
                THROW 50409, N'Someone else changed this budget duration. Reload it and try again', 1;
            INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
            VALUES (N'mp.budget_duration', @id, N'update', @actor_user_id, @now);
        END
    COMMIT;

    EXEC [mp].[usp_budget_duration_get] @company_id = @company_id, @id = @id;
END
GO

CREATE OR ALTER PROCEDURE [mp].[usp_budget_duration_delete]
    @company_id    BIGINT,
    @actor_user_id BIGINT = NULL,
    @id            BIGINT,
    @row_version   BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @rv BINARY(8) = (SELECT row_version FROM [mp].[budget_duration] WHERE id = @id AND company_id = @company_id);
    IF @rv IS NULL
        THROW 50404, N'Budget duration not found', 1;
    IF @rv <> @row_version
        THROW 50409, N'Someone else changed this budget duration. Reload it and try again', 1;
    IF EXISTS (SELECT 1 FROM [mp].[manpower_plan] WHERE budget_duration_id = @id)
       OR EXISTS (SELECT 1 FROM [mp].[e_budget] WHERE budget_duration_id = @id)
        THROW 50409, N'id|DURATION_IN_USE|This duration is the plan year of plans or budgets, so it cannot be deleted.', 1;

    BEGIN TRAN;
        DELETE [mp].[budget_duration] WHERE id = @id AND company_id = @company_id;
        INSERT [core].[audit_log] (entity_type, entity_id, action_name, performed_by_user_id, performed_at)
        VALUES (N'mp.budget_duration', @id, N'delete', @actor_user_id, SYSUTCDATETIME());
    COMMIT;
END
