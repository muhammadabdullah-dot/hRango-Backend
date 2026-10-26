-- Leaves -> My Leaves / Leave Applications: the leave requests (req.request + req.req_leave, owned by
-- the requests module) as the Leaves screens list them. Read only: applying, approving and
-- cancelling go through the requests API.
-- @tab: 'my' (the actor's own), 'subordinates' (their direct and indirect reports), 'all'
-- (everyone @permission_code reaches).
CREATE OR ALTER FUNCTION [lv].[fn_leave_application_rows] (@company_id BIGINT, @actor_user_id BIGINT,
                                                          @permission_code NVARCHAR(150), @tab NVARCHAR(20))
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT u.employee_id AS id FROM [auth].[user_account] u WHERE u.id = @actor_user_id AND u.employee_id IS NOT NULL
),
team AS (
    SELECT e.id FROM [hr].[employee] e JOIN me ON e.line_manager_id = me.id
    UNION ALL
    SELECT e.id FROM [hr].[employee] e JOIN team t ON e.line_manager_id = t.id
)
SELECT r.id, r.code, r.status, r.employee_id, e.code AS employee_code,
       CONCAT(e.first_name, N' ', e.last_name) AS employee_name, e.department_id, d.name AS department_name,
       rl.leave_type_id, t.title AS leave_type_title, t.short_code AS leave_type_code,
       r.from_date, r.to_date, CAST(ISNULL(rl.days, r.days) AS DECIMAL(6,2)) AS days, rl.is_short, rl.short_leave_type,
       rl.start_time, rl.end_time, r.reason, r.submitted_at, r.decided_at, r.cancel_reason, r.created_at
FROM [req].[request] r
JOIN [req].[request_type] rt ON rt.id = r.request_type_id AND rt.code = N'leave'
JOIN [req].[req_leave] rl ON rl.request_id = r.id
JOIN [hr].[employee] e ON e.id = r.employee_id
JOIN [lv].[leave_type] t ON t.id = rl.leave_type_id
JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
WHERE r.company_id = @company_id
  AND r.is_deleted = 0
  AND (   @tab = N'all'
       OR (@tab = N'my' AND r.employee_id IN (SELECT id FROM me))
       OR (@tab = N'subordinates' AND r.employee_id IN (SELECT id FROM team)));
GO

CREATE OR ALTER PROCEDURE [lv].[usp_leave_application_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @tab             NVARCHAR(20) = N'all',
    @status          NVARCHAR(30) = NULL,
    @leave_type_id   BIGINT = NULL,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL,
    @search          NVARCHAR(200) = NULL,
    @page            INT = 1,
    @page_size       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;

    SELECT COUNT(*) AS total
    FROM [lv].[fn_leave_application_rows](@company_id, @actor_user_id, @permission_code, @tab) a
    WHERE (@status IS NULL OR a.status = @status)
      AND (@leave_type_id IS NULL OR a.leave_type_id = @leave_type_id)
      AND (@employee_id IS NULL OR a.employee_id = @employee_id)
      AND (@department_id IS NULL OR a.department_id = @department_id)
      AND (@from_date IS NULL OR a.to_date >= @from_date)
      AND (@to_date IS NULL OR a.from_date <= @to_date)
      AND (@pattern IS NULL OR a.code LIKE @pattern OR a.employee_code LIKE @pattern OR a.employee_name LIKE @pattern)
    OPTION (RECOMPILE, MAXRECURSION 100);

    SELECT a.*
    FROM [lv].[fn_leave_application_rows](@company_id, @actor_user_id, @permission_code, @tab) a
    WHERE (@status IS NULL OR a.status = @status)
      AND (@leave_type_id IS NULL OR a.leave_type_id = @leave_type_id)
      AND (@employee_id IS NULL OR a.employee_id = @employee_id)
      AND (@department_id IS NULL OR a.department_id = @department_id)
      AND (@from_date IS NULL OR a.to_date >= @from_date)
      AND (@to_date IS NULL OR a.from_date <= @to_date)
      AND (@pattern IS NULL OR a.code LIKE @pattern OR a.employee_code LIKE @pattern OR a.employee_name LIKE @pattern)
    ORDER BY a.from_date DESC, a.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE, MAXRECURSION 100);
END
GO

-- The status counts for the "All Requests (n)" picker: same filters as the list, without status.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_application_counts]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @tab             NVARCHAR(20) = N'all',
    @leave_type_id   BIGINT = NULL,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @from_date       DATE = NULL,
    @to_date         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS [all],
           SUM(CASE WHEN a.status = N'pending' THEN 1 ELSE 0 END) AS pending,
           SUM(CASE WHEN a.status = N'approved' THEN 1 ELSE 0 END) AS approved,
           SUM(CASE WHEN a.status = N'rejected' THEN 1 ELSE 0 END) AS rejected,
           SUM(CASE WHEN a.status = N'cancelling' THEN 1 ELSE 0 END) AS cancelling,
           SUM(CASE WHEN a.status = N'cancelled' THEN 1 ELSE 0 END) AS cancelled
    FROM [lv].[fn_leave_application_rows](@company_id, @actor_user_id, @permission_code, @tab) a
    WHERE (@leave_type_id IS NULL OR a.leave_type_id = @leave_type_id)
      AND (@employee_id IS NULL OR a.employee_id = @employee_id)
      AND (@department_id IS NULL OR a.department_id = @department_id)
      AND (@from_date IS NULL OR a.to_date >= @from_date)
      AND (@to_date IS NULL OR a.from_date <= @to_date)
    OPTION (RECOMPILE, MAXRECURSION 100);
END
GO

-- One application with the person's balance of its leave type in the leave year it starts in.
CREATE OR ALTER PROCEDURE [lv].[usp_leave_application_get]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @id              BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [lv].[fn_leave_application_rows](@company_id, @actor_user_id, @permission_code, N'all') a WHERE a.id = @id)
        THROW 50404, N'Leave application not found', 1;

    SELECT a.*, b.entitled AS balance_entitled, b.used AS balance_used, b.pending AS balance_pending,
           b.available AS balance_available
    FROM [lv].[fn_leave_application_rows](@company_id, @actor_user_id, @permission_code, N'all') a
    OUTER APPLY [lv].[fn_leave_balance](@company_id, a.employee_id, a.leave_type_id, a.from_date) b
    WHERE a.id = @id
    OPTION (MAXRECURSION 100);
END
