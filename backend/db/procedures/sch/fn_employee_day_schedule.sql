-- Holidays per employee and date between @from and @to. A holiday without rules is for everyone;
-- with rules, for anyone at least one rule takes in: the named employee (employee), the employee's
-- branch (org_structure), the country / state / city of the employee's branch (geo_location), or the
-- employee's religion (religion). One row per employee, date and holiday (holidays can overlap).
CREATE OR ALTER FUNCTION [sch].[fn_employee_holidays] (@company_id BIGINT, @from DATE, @to DATE)
RETURNS TABLE
AS RETURN
SELECT e.id AS employee_id, d.d AS holiday_date, h.id AS holiday_id, h.name AS holiday_name,
       h.holiday_type, h.attendance_exempt
FROM [sch].[holiday] h
CROSS APPLY [sch].[fn_dates](CASE WHEN h.start_date > @from THEN h.start_date ELSE @from END,
                             CASE WHEN h.end_date < @to THEN h.end_date ELSE @to END) d
JOIN [hr].[employee] e ON e.company_id = h.company_id
LEFT JOIN [org].[branch] b ON b.id = e.branch_id
WHERE h.company_id = @company_id
  AND h.start_date <= @to AND h.end_date >= @from
  AND (NOT EXISTS (SELECT 1 FROM [sch].[holiday_rule] r WHERE r.holiday_id = h.id)
       OR EXISTS (
            SELECT 1 FROM [sch].[holiday_rule] r
            WHERE r.holiday_id = h.id
              AND (   (r.rule_type = N'employee' AND r.employee_id = e.id)
                   OR (r.rule_type = N'org_structure' AND r.branch_id = e.branch_id)
                   OR (r.rule_type = N'geo_location' AND r.country_id = b.country_id
                       AND (r.state_id IS NULL OR r.state_id = b.state_id)
                       AND (r.city_id IS NULL OR r.city_id = b.city_id))
                   OR (r.rule_type = N'religion' AND r.religion = e.religion))));
GO

-- The planned day for each employee and date: what attendance compares punches with.
-- @employee_id NULL = every employee of the company. One row per employee and date, or one per
-- shift on a day with several shifts. Columns:
--   schedule_id ... planned_minutes   the shift (NULL when nothing is scheduled). start_at / end_at
--                                     are local wall-clock date-times; end_at is the next day for
--                                     an overnight shift. Breaks are in sch.schedule_break.
--   is_rest_day, rest_day_payable     a rest day (rule or approved request)
--   holiday_id, holiday_name,
--   holiday_exempt                    a holiday that applies to the employee (an attendance-exempt one first)
--   day_kind                          holiday (exempt holiday), rest_day, shift, unscheduled.
--                                     A holiday wins over a rest day, a rest day wins over a shift.
CREATE OR ALTER FUNCTION [sch].[fn_employee_day_schedule] (@company_id BIGINT, @employee_id BIGINT, @from DATE, @to DATE)
RETURNS TABLE
AS RETURN
WITH days AS (
    SELECT e.id AS employee_id, d.d AS work_date
    FROM [hr].[employee] e
    CROSS JOIN [sch].[fn_dates](@from, @to) d
    WHERE e.company_id = @company_id AND (@employee_id IS NULL OR e.id = @employee_id)
),
hol AS (
    SELECT h.employee_id, h.holiday_date, h.holiday_id, h.holiday_name, h.attendance_exempt,
           ROW_NUMBER() OVER (PARTITION BY h.employee_id, h.holiday_date
                              ORDER BY h.attendance_exempt DESC, h.holiday_id) AS rn
    FROM [sch].[fn_employee_holidays](@company_id, @from, @to) h
    WHERE @employee_id IS NULL OR h.employee_id = @employee_id
)
SELECT days.employee_id, days.work_date,
       s.id AS schedule_id, s.time_slot_id, ts.code AS time_slot_code, ts.name AS time_slot_name,
       s.start_at, s.end_at, s.planned_minutes, ts.workable_minutes, ts.is_flexible, ts.is_overnight,
       ts.full_overtime, ts.short_overtime, s.is_wfh, s.geo_fence_id,
       CAST(CASE WHEN rd.id IS NULL THEN 0 ELSE 1 END AS BIT) AS is_rest_day,
       rd.is_payable AS rest_day_payable,
       hol.holiday_id, hol.holiday_name, hol.attendance_exempt AS holiday_exempt,
       CASE WHEN hol.attendance_exempt = 1 THEN N'holiday'
            WHEN rd.id IS NOT NULL THEN N'rest_day'
            WHEN s.id IS NOT NULL THEN N'shift'
            ELSE N'unscheduled' END AS day_kind
FROM days
LEFT JOIN [sch].[schedule] s ON s.employee_id = days.employee_id AND s.work_date = days.work_date
LEFT JOIN [sch].[time_slot] ts ON ts.id = s.time_slot_id
LEFT JOIN [sch].[rest_day] rd ON rd.employee_id = days.employee_id AND rd.rest_date = days.work_date
LEFT JOIN hol ON hol.employee_id = days.employee_id AND hol.holiday_date = days.work_date AND hol.rn = 1;
