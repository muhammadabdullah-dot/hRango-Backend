-- Helpers for the attendance procedures.

-- The company's local wall-clock time now. org.company.timezone holds an IANA name (Asia/Karachi);
-- SQL Server knows Windows names, so the common ones are mapped. A Windows name is used as is.
-- Unknown or empty: Pakistan time (NFR-8).
CREATE OR ALTER FUNCTION [att].[fn_company_now] (@company_id BIGINT)
RETURNS DATETIME2(0)
AS
BEGIN
    DECLARE @tz NVARCHAR(64) = (SELECT timezone FROM [org].[company] WHERE id = @company_id);
    DECLARE @win NVARCHAR(64) = CASE @tz
        WHEN N'Asia/Karachi' THEN N'Pakistan Standard Time'
        WHEN N'Asia/Dubai' THEN N'Arabian Standard Time'
        WHEN N'Asia/Riyadh' THEN N'Arab Standard Time'
        WHEN N'Asia/Qatar' THEN N'Arab Standard Time'
        WHEN N'Asia/Kolkata' THEN N'India Standard Time'
        WHEN N'Asia/Dhaka' THEN N'Bangladesh Standard Time'
        WHEN N'Asia/Singapore' THEN N'Singapore Standard Time'
        WHEN N'Europe/London' THEN N'GMT Standard Time'
        WHEN N'Europe/Berlin' THEN N'W. Europe Standard Time'
        WHEN N'America/New_York' THEN N'Eastern Standard Time'
        WHEN N'America/Chicago' THEN N'Central Standard Time'
        WHEN N'America/Denver' THEN N'Mountain Standard Time'
        WHEN N'America/Los_Angeles' THEN N'Pacific Standard Time'
        WHEN N'UTC' THEN N'UTC'
        WHEN N'Etc/UTC' THEN N'UTC'
    END;
    IF @win IS NULL AND EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @tz)
        SET @win = @tz;
    RETURN CAST(SYSUTCDATETIME() AT TIME ZONE N'UTC' AT TIME ZONE ISNULL(@win, N'Pakistan Standard Time') AS DATETIME2(0));
END
GO

-- One attendance or overtime setting as text (core.company_setting); NULL when never saved.
CREATE OR ALTER FUNCTION [att].[fn_setting] (@company_id BIGINT, @module NVARCHAR(30), @setting_key NVARCHAR(100))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN (SELECT TOP 1 setting_value FROM [core].[company_setting]
            WHERE company_id = @company_id AND module = @module AND setting_key = @setting_key);
END
GO

-- Direct and indirect reports of the user's employee record (the "Subordinates" tab).
CREATE OR ALTER FUNCTION [att].[fn_team] (@company_id BIGINT, @user_id BIGINT)
RETURNS TABLE
AS RETURN
WITH team AS (
    SELECT e.id
    FROM [hr].[employee] e
    JOIN [auth].[user_account] u ON u.employee_id = e.line_manager_id
    WHERE u.id = @user_id AND e.company_id = @company_id
    UNION ALL
    SELECT e.id FROM [hr].[employee] e JOIN team t ON e.line_manager_id = t.id
)
SELECT id AS employee_id FROM team;
GO

-- The attributes geo-fence and IP-restriction targets are matched against.
CREATE OR ALTER FUNCTION [att].[fn_employee_profile] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT e.id AS employee_id, e.location_id, e.branch_id, e.area_id, e.department_id, e.designation_id,
       e.grade_id, e.job_title_id, e.religion, e.nationality, b.country_id,
       (SELECT MAX(p.joining_date) FROM [hr].[employment_period] p WHERE p.employee_id = e.id) AS joining_date
FROM [hr].[employee] e
LEFT JOIN [org].[branch] b ON b.id = e.branch_id
WHERE e.company_id = @company_id;
GO

-- Active geo fences that apply to an employee. Targets of one type are alternatives (OR); different
-- types must all match (AND); the joining range, when set, must match too.
CREATE OR ALTER FUNCTION [att].[fn_employee_geo_fences] (@company_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT f.id AS geo_fence_id
FROM [att].[geo_fence] f
JOIN [att].[fn_employee_profile](@company_id) e ON e.employee_id = @employee_id
WHERE f.company_id = @company_id AND f.is_active = 1
  AND (f.applies_to_all = 1 OR (
        (EXISTS (SELECT 1 FROM [att].[geo_fence_target] t WHERE t.geo_fence_id = f.id)
            OR f.joining_from_date IS NOT NULL OR f.joining_to_date IS NOT NULL)
    AND (f.joining_from_date IS NULL OR e.joining_date >= f.joining_from_date)
    AND (f.joining_to_date IS NULL OR e.joining_date <= f.joining_to_date)
    AND NOT EXISTS (
        SELECT 1 FROM [att].[geo_fence_target] t
        WHERE t.geo_fence_id = f.id
          AND NOT EXISTS (
            SELECT 1 FROM [att].[geo_fence_target] x
            WHERE x.geo_fence_id = f.id AND x.target_type = t.target_type
              AND (   (x.target_type = N'employee' AND x.target_id = e.employee_id)
                   OR (x.target_type = N'country' AND x.target_id = e.country_id)
                   OR (x.target_type = N'location' AND x.target_id = e.location_id)
                   OR (x.target_type = N'branch' AND x.target_id = e.branch_id)
                   OR (x.target_type = N'area' AND x.target_id = e.area_id)
                   OR (x.target_type = N'department' AND x.target_id = e.department_id)
                   OR (x.target_type = N'designation' AND x.target_id = e.designation_id)
                   OR (x.target_type = N'grade' AND x.target_id = e.grade_id)
                   OR (x.target_type = N'job_title' AND x.target_id = e.job_title_id)
                   OR (x.target_type = N'religion' AND x.target_value = e.religion)
                   OR (x.target_type = N'nationality' AND x.target_value = e.nationality))))));
GO

-- Active IP restrictions that apply to an employee; same matching as geo fences.
CREATE OR ALTER FUNCTION [att].[fn_employee_ip_restrictions] (@company_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT r.id AS ip_restriction_id
FROM [att].[ip_restriction] r
JOIN [att].[fn_employee_profile](@company_id) e ON e.employee_id = @employee_id
WHERE r.company_id = @company_id AND r.is_active = 1
  AND (r.applies_to_all = 1 OR (
        EXISTS (SELECT 1 FROM [att].[ip_restriction_target] t WHERE t.ip_restriction_id = r.id)
    AND NOT EXISTS (
        SELECT 1 FROM [att].[ip_restriction_target] t
        WHERE t.ip_restriction_id = r.id
          AND NOT EXISTS (
            SELECT 1 FROM [att].[ip_restriction_target] x
            WHERE x.ip_restriction_id = r.id AND x.target_type = t.target_type
              AND (   (x.target_type = N'employee' AND x.target_id = e.employee_id)
                   OR (x.target_type = N'country' AND x.target_id = e.country_id)
                   OR (x.target_type = N'location' AND x.target_id = e.location_id)
                   OR (x.target_type = N'branch' AND x.target_id = e.branch_id)
                   OR (x.target_type = N'area' AND x.target_id = e.area_id)
                   OR (x.target_type = N'department' AND x.target_id = e.department_id)
                   OR (x.target_type = N'designation' AND x.target_id = e.designation_id)
                   OR (x.target_type = N'grade' AND x.target_id = e.grade_id)
                   OR (x.target_type = N'job_title' AND x.target_id = e.job_title_id)
                   OR (x.target_type = N'religion' AND x.target_value = e.religion)
                   OR (x.target_type = N'nationality' AND x.target_value = e.nationality))))));
GO

-- Converts what a device, file or form sends into a punch type: check_in, check_out, break_out, break_in
-- (also with spaces or hyphens), or a break type's start identifier (break_out) or end identifier (break_in).
CREATE OR ALTER FUNCTION [att].[fn_punch_type_parse] (@company_id BIGINT, @text NVARCHAR(100))
RETURNS TABLE
AS RETURN
SELECT TOP 1 x.punch_type, x.break_type_id
FROM (
    SELECT v.punch_type, CAST(NULL AS BIGINT) AS break_type_id, 1 AS pri
    FROM (VALUES (N'check_in'), (N'check_out'), (N'break_out'), (N'break_in')) v (punch_type)
    WHERE v.punch_type = REPLACE(REPLACE(LOWER(LTRIM(RTRIM(@text))), N'-', N'_'), N' ', N'_')
    UNION ALL
    SELECT N'break_out', b.id, 2 FROM [sch].[break_type] b
    WHERE b.company_id = @company_id AND b.start_identifier = LTRIM(RTRIM(@text))
    UNION ALL
    SELECT N'break_in', b.id, 3 FROM [sch].[break_type] b
    WHERE b.company_id = @company_id AND b.end_identifier = LTRIM(RTRIM(@text))
) x
ORDER BY x.pri;
