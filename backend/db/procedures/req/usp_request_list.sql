-- Requests of one type: the My / Subordinates / All tabs, limited to the employees the caller's
-- list permission reaches (auth.fn_visible_employees). Result sets: the total; the page; counts by
-- status for the status tabs (without the status filter).
CREATE OR ALTER PROCEDURE [req].[usp_request_list]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @type_code       NVARCHAR(30),
    @permission_code NVARCHAR(150),
    @view            NVARCHAR(20) = N'all',
    @status          NVARCHAR(30) = NULL,
    @search          NVARCHAR(200) = NULL,
    @employee_id     BIGINT = NULL,
    @department_id   BIGINT = NULL,
    @branch_id       BIGINT = NULL,
    @location_id     BIGINT = NULL,
    @date_from       DATE = NULL,
    @date_to         DATE = NULL,
    @page            INT = 1,
    @page_size       INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @pattern NVARCHAR(500) = CASE WHEN NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@search)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' END;
    DECLARE @me BIGINT = (SELECT employee_id FROM [auth].[user_account] WHERE id = @actor_user_id);

    DECLARE @team TABLE (employee_id BIGINT PRIMARY KEY);
    IF @view = N'subordinates'
    BEGIN
        WITH t AS (
            SELECT e.id FROM [hr].[employee] e WHERE e.line_manager_id = @me AND e.company_id = @company_id
            UNION ALL
            SELECT e.id FROM [hr].[employee] e JOIN t ON e.line_manager_id = t.id
        )
        INSERT @team SELECT DISTINCT id FROM t OPTION (MAXRECURSION 100);
    END

    DECLARE @rows TABLE (id BIGINT PRIMARY KEY, status NVARCHAR(30), submitted_at DATETIME2(0));
    INSERT @rows (id, status, submitted_at)
    SELECT r.id, r.status, r.submitted_at
    FROM [req].[fn_request_rows](@company_id) r
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = r.employee_id
    WHERE r.request_type = @type_code
      AND (@view <> N'my' OR r.employee_id = @me)
      AND (@view <> N'subordinates' OR r.employee_id IN (SELECT employee_id FROM @team))
      AND (@pattern IS NULL OR r.code LIKE @pattern OR r.employee_name LIKE @pattern OR r.employee_code LIKE @pattern)
      AND (@employee_id IS NULL OR r.employee_id = @employee_id)
      AND (@department_id IS NULL OR r.department_id = @department_id)
      AND (@branch_id IS NULL OR r.branch_id = @branch_id)
      AND (@location_id IS NULL OR r.location_id = @location_id)
      AND (@date_from IS NULL OR ISNULL(r.to_date, r.from_date) >= @date_from)
      AND (@date_to IS NULL OR r.from_date <= @date_to)
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS total FROM @rows WHERE @status IS NULL OR status = @status;

    SELECT r.*, [req].[fn_request_details](r.id) AS details_json
    FROM [req].[fn_request_rows](@company_id) r
    WHERE r.id IN (SELECT id FROM @rows x WHERE @status IS NULL OR x.status = @status)
    ORDER BY r.submitted_at DESC, r.id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);

    SELECT s.status, COUNT(x.id) AS total
    FROM (VALUES (N'pending'), (N'approved'), (N'rejected'), (N'cancelling'), (N'cancelled')) s (status)
    LEFT JOIN @rows x ON x.status = s.status
    GROUP BY s.status;
END
