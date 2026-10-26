-- Recruitment Dashboard (requirements/HRango - UI design/All Dashboards/04-Recruitment-Dashboard).
-- Everything is limited to the openings the caller reaches with the permission. The period is
-- @year, or one month of it when @month is given; the monthly chart always covers the year.
-- Result sets:
--   1. tiles and overview: open openings, open vacancies, interviews, hired, rejected (tiles);
--      applications, interviews, offers accepted, rejected (the Overview pie)
--   2. Job Statistics: per month of the year, applications, shortlisted, rejected, hired
--   3. Job Applications table: the next scheduled interviews (candidate, opening, city, panel, slot, contact)
--   4. Recent Activity: the latest stage changes
CREATE OR ALTER PROCEDURE [rec].[usp_dashboard]
    @company_id      BIGINT,
    @actor_user_id   BIGINT,
    @permission_code NVARCHAR(150),
    @year            INT,
    @month           INT = NULL,
    @limit           INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    IF @month IS NOT NULL AND (@month < 1 OR @month > 12)
        THROW 50400, N'month|Choose a month from 1 to 12.', 1;
    IF @year IS NULL OR @year < 2000 OR @year > 2100
        THROW 50400, N'year|Choose a year.', 1;

    DECLARE @from DATE = DATEFROMPARTS(@year, ISNULL(@month, 1), 1);
    DECLARE @to DATE = CASE WHEN @month IS NULL THEN DATEFROMPARTS(@year + 1, 1, 1) ELSE DATEADD(MONTH, 1, @from) END;
    DECLARE @year_from DATE = DATEFROMPARTS(@year, 1, 1), @year_to DATE = DATEFROMPARTS(@year + 1, 1, 1);
    DECLARE @now DATETIME2(0) = SYSDATETIME();   -- interview times are local wall-clock time

    DECLARE @v TABLE (id BIGINT PRIMARY KEY);
    INSERT @v SELECT job_opening_id FROM [rec].[fn_visible_openings](@company_id, @actor_user_id, @permission_code);
    DECLARE @apps TABLE (id BIGINT PRIMARY KEY, applied_on DATE, stage NVARCHAR(30));
    INSERT @apps SELECT a.id, a.applied_on, a.stage FROM [rec].[application] a JOIN @v v ON v.id = a.job_opening_id;
    DECLARE @moves TABLE (application_id BIGINT, to_stage NVARCHAR(30), changed_at DATETIME2(0));
    INSERT @moves SELECT h.application_id, h.to_stage, h.changed_at
    FROM [rec].[application_stage_history] h JOIN @apps a ON a.id = h.application_id
    WHERE h.changed_at >= @year_from AND h.changed_at < @year_to;

    -- 1. Tiles and overview.
    SELECT
        (SELECT COUNT(*) FROM [rec].[job_opening] o JOIN @v v ON v.id = o.id WHERE o.status = N'open') AS open_openings,
        (SELECT COUNT(*) FROM [rec].[job_opening] o JOIN @v v ON v.id = o.id WHERE o.status <> N'draft'
            AND ISNULL(o.published_at, o.created_at) < @to AND (o.closed_at IS NULL OR o.closed_at >= @from)) AS total_openings,
        ISNULL((SELECT SUM(o.vacancies - h.n)
                FROM [rec].[job_opening] o JOIN @v v ON v.id = o.id
                OUTER APPLY (SELECT COUNT(*) AS n FROM [rec].[application] x WHERE x.job_opening_id = o.id AND x.stage = N'hired') h
                WHERE o.status = N'open'), 0) AS open_vacancies,
        (SELECT COUNT(*) FROM @apps WHERE applied_on >= @from AND applied_on < @to) AS applications,
        (SELECT COUNT(*) FROM [rec].[interview] i JOIN @apps a ON a.id = i.application_id
         WHERE i.status <> N'cancelled' AND i.scheduled_at >= @from AND i.scheduled_at < @to) AS interviews,
        (SELECT COUNT(*) FROM [rec].[interview] i JOIN @apps a ON a.id = i.application_id
         WHERE i.status = N'scheduled' AND i.scheduled_at >= @now) AS upcoming_interviews,
        (SELECT COUNT(*) FROM [rec].[offer] x JOIN @apps a ON a.id = x.application_id
         WHERE x.status IN (N'accepted') AND x.responded_at >= @from AND x.responded_at < @to) AS offers_accepted,
        (SELECT COUNT(DISTINCT m.application_id) FROM @moves m WHERE m.to_stage = N'hired' AND m.changed_at >= @from AND m.changed_at < @to) AS hired,
        (SELECT COUNT(DISTINCT m.application_id) FROM @moves m WHERE m.to_stage = N'rejected' AND m.changed_at >= @from AND m.changed_at < @to) AS rejected;

    -- 2. Job Statistics by month.
    WITH months AS (SELECT n AS month_no FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) m (n))
    SELECT m.month_no,
           (SELECT COUNT(*) FROM @apps a WHERE YEAR(a.applied_on) = @year AND MONTH(a.applied_on) = m.month_no) AS applications,
           (SELECT COUNT(DISTINCT x.application_id) FROM @moves x WHERE x.to_stage = N'shortlisted' AND MONTH(x.changed_at) = m.month_no) AS shortlisted,
           (SELECT COUNT(DISTINCT x.application_id) FROM @moves x WHERE x.to_stage = N'rejected' AND MONTH(x.changed_at) = m.month_no) AS rejected,
           (SELECT COUNT(DISTINCT x.application_id) FROM @moves x WHERE x.to_stage = N'hired' AND MONTH(x.changed_at) = m.month_no) AS hired
    FROM months m
    ORDER BY m.month_no;

    -- 3. Next scheduled interviews.
    SELECT TOP (@limit) r.id AS interview_id, r.application_id, r.applicant_id, r.applicant_name, r.applicant_email,
           r.applicant_phone, r.applicant_city_name, r.job_opening_id, r.job_opening_title, r.title, r.round_no, r.mode,
           r.scheduled_at, r.duration_minutes, r.venue, r.interviewer_names,
           (SELECT TOP 1 CONCAT(e.first_name, N' ', e.last_name) FROM [rec].[interview_interviewer] ii
            JOIN [hr].[employee] e ON e.id = ii.employee_id WHERE ii.interview_id = r.id ORDER BY e.first_name) AS first_interviewer_name,
           (SELECT TOP 1 jt.name FROM [rec].[interview_interviewer] ii JOIN [hr].[employee] e ON e.id = ii.employee_id
            LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id WHERE ii.interview_id = r.id ORDER BY e.first_name) AS first_interviewer_title
    FROM [rec].[fn_interview_rows](@company_id) r
    JOIN @apps a ON a.id = r.application_id
    WHERE r.status = N'scheduled' AND r.scheduled_at >= @now
    ORDER BY r.scheduled_at, r.id;

    -- 4. Recent activity.
    SELECT TOP (@limit) h.id, h.application_id, x.applicant_name, x.job_opening_title, h.from_stage, h.to_stage,
           h.changed_at, n.name AS changed_by_name
    FROM [rec].[application_stage_history] h
    JOIN @apps a ON a.id = h.application_id
    JOIN [rec].[fn_application_rows](@company_id) x ON x.id = h.application_id
    OUTER APPLY [rec].[fn_user_name](h.changed_by_user_id) n
    ORDER BY h.changed_at DESC, h.id DESC;
END
GO
