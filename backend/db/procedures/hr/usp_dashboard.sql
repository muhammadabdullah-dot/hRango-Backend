-- Dashboard figures built from employee records (CEO and HR dashboards). Every figure covers the
-- employees the dashboard permission's scope reaches (@permission_code). "Employed" means status
-- active, probation or notice.

-- Result sets:
--   1 totals: headcount, women, men, hired and left in @month, headcount at the month's start
--   2 by department      3 by employment type      4 by gender
--   5 by age band and gender (bands 18-25, 26-35, 36-45, 46-55, 56+, unknown)
--   6 hired and left per month for the 12 months ending with @month
--   7 by department and gender      8 women's share per job title
CREATE OR ALTER PROCEDURE [hr].[usp_dashboard_workforce]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @month           DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET @month = DATEFROMPARTS(YEAR(ISNULL(@month, @today)), MONTH(ISNULL(@month, @today)), 1);
    DECLARE @month_end DATE = EOMONTH(@month);
    DECLARE @first DATE = DATEADD(MONTH, -11, @month);

    DECLARE @e TABLE (id BIGINT PRIMARY KEY, gender NVARCHAR(30), department_id BIGINT, employment_type_id BIGINT,
                      job_title_id BIGINT, date_of_birth DATE, employed BIT);
    INSERT @e
    SELECT e.id, e.gender, e.department_id, e.employment_type_id, e.job_title_id, e.date_of_birth,
           CAST(CASE WHEN e.status IN (N'active', N'probation', N'notice') THEN 1 ELSE 0 END AS BIT)
    FROM [hr].[employee] e
    JOIN [auth].[fn_visible_employees](@company_id, @actor_user_id, @permission_code) v ON v.employee_id = e.id
    WHERE e.company_id = @company_id;

    DECLARE @p TABLE (employee_id BIGINT, joining_date DATE, end_date DATE);
    INSERT @p
    SELECT p.employee_id, p.joining_date, p.end_date
    FROM [hr].[employment_period] p JOIN @e e ON e.id = p.employee_id;

    SELECT (SELECT COUNT(*) FROM @e WHERE employed = 1) AS headcount,
           (SELECT COUNT(*) FROM @e WHERE employed = 1 AND gender = N'female') AS women,
           (SELECT COUNT(*) FROM @e WHERE employed = 1 AND gender = N'male') AS men,
           (SELECT COUNT(*) FROM @p WHERE joining_date BETWEEN @month AND @month_end) AS hired,
           (SELECT COUNT(*) FROM @p WHERE end_date BETWEEN @month AND @month_end) AS left_count,
           (SELECT COUNT(DISTINCT employee_id) FROM @p WHERE joining_date < @month AND (end_date IS NULL OR end_date >= @month)) AS opening_headcount;

    SELECT e.department_id AS id, ISNULL(d.name, N'No department') AS name, COUNT(*) AS count
    FROM @e e LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE e.employed = 1
    GROUP BY e.department_id, d.name
    ORDER BY COUNT(*) DESC, d.name;

    SELECT e.employment_type_id AS id, ISNULL(t.name, N'Not set') AS name, COUNT(*) AS count
    FROM @e e LEFT JOIN [org].[employment_type] t ON t.id = e.employment_type_id
    WHERE e.employed = 1
    GROUP BY e.employment_type_id, t.name
    ORDER BY COUNT(*) DESC, t.name;

    SELECT ISNULL(gender, N'not_set') AS gender, COUNT(*) AS count
    FROM @e WHERE employed = 1
    GROUP BY gender
    ORDER BY COUNT(*) DESC;

    SELECT b.band, ISNULL(e.gender, N'not_set') AS gender, COUNT(*) AS count
    FROM @e e
    CROSS APPLY (SELECT CASE
        WHEN e.date_of_birth IS NULL THEN N'unknown'
        WHEN DATEDIFF(YEAR, e.date_of_birth, @today) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.date_of_birth, @today), e.date_of_birth) > @today THEN 1 ELSE 0 END < 26 THEN N'18-25'
        WHEN DATEDIFF(YEAR, e.date_of_birth, @today) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.date_of_birth, @today), e.date_of_birth) > @today THEN 1 ELSE 0 END < 36 THEN N'26-35'
        WHEN DATEDIFF(YEAR, e.date_of_birth, @today) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.date_of_birth, @today), e.date_of_birth) > @today THEN 1 ELSE 0 END < 46 THEN N'36-45'
        WHEN DATEDIFF(YEAR, e.date_of_birth, @today) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.date_of_birth, @today), e.date_of_birth) > @today THEN 1 ELSE 0 END < 56 THEN N'46-55'
        ELSE N'56+' END AS band) b
    WHERE e.employed = 1
    GROUP BY b.band, e.gender
    ORDER BY b.band, e.gender;

    WITH months AS (
        SELECT @first AS m UNION ALL SELECT DATEADD(MONTH, 1, m) FROM months WHERE m < @month
    )
    SELECT m.m AS month,
           (SELECT COUNT(*) FROM @p WHERE joining_date BETWEEN m.m AND EOMONTH(m.m)) AS hired,
           (SELECT COUNT(*) FROM @p WHERE end_date BETWEEN m.m AND EOMONTH(m.m)) AS left_count
    FROM months m
    ORDER BY m.m;

    SELECT e.department_id AS id, ISNULL(d.name, N'No department') AS name,
           SUM(CASE WHEN e.gender = N'male' THEN 1 ELSE 0 END) AS men,
           SUM(CASE WHEN e.gender = N'female' THEN 1 ELSE 0 END) AS women
    FROM @e e LEFT JOIN [org].[department] d ON d.id = e.department_id
    WHERE e.employed = 1
    GROUP BY e.department_id, d.name
    ORDER BY d.name;

    SELECT e.job_title_id AS id, ISNULL(j.name, N'No job title') AS name, COUNT(*) AS total,
           SUM(CASE WHEN e.gender = N'female' THEN 1 ELSE 0 END) AS women
    FROM @e e LEFT JOIN [org].[job_title] j ON j.id = e.job_title_id
    WHERE e.employed = 1
    GROUP BY e.job_title_id, j.name
    ORDER BY j.name;
END
