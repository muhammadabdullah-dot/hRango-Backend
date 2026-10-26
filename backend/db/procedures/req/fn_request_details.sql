-- The kind-specific part of a request as one JSON object (snake_case keys), with the names the
-- lists and the View popup show. Lists call it per row of a page; the detail popup once.
CREATE OR ALTER FUNCTION [req].[fn_request_details] (@request_id BIGINT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @kind NVARCHAR(30) = (
        SELECT t.kind FROM [req].[request] r JOIN [req].[request_type] t ON t.id = r.request_type_id WHERE r.id = @request_id);

    IF @kind = N'leave'
        RETURN (SELECT l.leave_type_id, lt.title AS leave_type_name, l.is_short, l.short_leave_type,
                       l.start_time, l.end_time, l.days
                FROM [req].[req_leave] l
                LEFT JOIN [lv].[leave_type] lt ON lt.id = l.leave_type_id
                WHERE l.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'punch'
        RETURN (SELECT p.punch_date, p.punch_type, p.punch_time
                FROM [req].[req_punch] p WHERE p.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'time_window'
        RETURN (SELECT w.kind AS window_kind, w.window_date, w.start_time, w.end_time, w.duration_minutes,
                       w.time_slot_id, ts.name AS time_slot_name, ts.start_time AS slot_start_time,
                       ts.end_time AS slot_end_time
                FROM [req].[req_time_window] w
                LEFT JOIN [sch].[time_slot] ts ON ts.id = w.time_slot_id
                WHERE w.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'work_from_home'
        RETURN (SELECT JSON_QUERY(ISNULL((SELECT d.request_date, d.schedule_id
                                          FROM [req].[request_day] d WHERE d.request_id = @request_id
                                          ORDER BY d.request_date FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS days
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'overtime'
        RETURN (SELECT o.department_id, d.name AS department_name, o.location_id, lo.name AS location_name,
                       o.branch_id, b.name AS branch_name, o.overtime_date, o.start_time, o.end_time,
                       o.applied_minutes, o.approved_minutes
                FROM [req].[req_overtime] o
                LEFT JOIN [org].[department] d ON d.id = o.department_id
                LEFT JOIN [org].[location] lo ON lo.id = o.location_id
                LEFT JOIN [org].[branch] b ON b.id = o.branch_id
                WHERE o.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'rest_day'
        RETURN (SELECT x.department_id, d.name AS department_name, x.roster_group_id, g.title AS roster_group_name,
                       x.is_payable,
                       JSON_QUERY(ISNULL((SELECT rd.request_date, rd.schedule_id
                                          FROM [req].[request_day] rd WHERE rd.request_id = @request_id
                                          ORDER BY rd.request_date FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS days
                FROM [req].[req_rest_day] x
                LEFT JOIN [org].[department] d ON d.id = x.department_id
                LEFT JOIN [sch].[roster_group] g ON g.id = x.roster_group_id
                WHERE x.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'shift_swap'
        RETURN (SELECT s.shift_date, s.from_schedule_id, fts.name AS from_time_slot_name,
                       s.time_slot_id, ts.name AS time_slot_name,
                       s.with_employee_id, NULLIF(CONCAT(we.first_name, N' ', we.last_name), N' ') AS with_employee_name,
                       s.to_schedule_id, tts.name AS to_time_slot_name
                FROM [req].[req_shift_swap] s
                LEFT JOIN [sch].[schedule] fs ON fs.id = s.from_schedule_id
                LEFT JOIN [sch].[time_slot] fts ON fts.id = fs.time_slot_id
                LEFT JOIN [sch].[time_slot] ts ON ts.id = s.time_slot_id
                LEFT JOIN [hr].[employee] we ON we.id = s.with_employee_id
                LEFT JOIN [sch].[schedule] tsch ON tsch.id = s.to_schedule_id
                LEFT JOIN [sch].[time_slot] tts ON tts.id = tsch.time_slot_id
                WHERE s.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'promotion'
        RETURN (SELECT p.is_demotion, p.grade_id, g.name AS grade_name, p.job_level_id, jl.name AS job_level_name,
                       p.designation_id, ds.name AS designation_name, p.job_title_id, jt.name AS job_title_name,
                       p.previous_salary, p.new_salary, p.effective_date,
                       JSON_QUERY(ISNULL((SELECT b.pay_item_id, pi.name AS pay_item_name
                                          FROM [req].[req_promotion_benefit] b
                                          LEFT JOIN [pay].[pay_item] pi ON pi.id = b.pay_item_id
                                          WHERE b.request_id = @request_id FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS benefits
                FROM [req].[req_promotion] p
                LEFT JOIN [org].[grade] g ON g.id = p.grade_id
                LEFT JOIN [org].[job_level] jl ON jl.id = p.job_level_id
                LEFT JOIN [org].[designation] ds ON ds.id = p.designation_id
                LEFT JOIN [org].[job_title] jt ON jt.id = p.job_title_id
                WHERE p.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'transfer'
        RETURN (SELECT t.location_id, lo.name AS location_name, t.branch_id, b.name AS branch_name,
                       t.department_id, d.name AS department_name,
                       t.line_manager_id, NULLIF(CONCAT(lm.first_name, N' ', lm.last_name), N' ') AS line_manager_name,
                       t.final_authority_id, NULLIF(CONCAT(fa.first_name, N' ', fa.last_name), N' ') AS final_authority_name,
                       t.effective_date
                FROM [req].[req_transfer] t
                LEFT JOIN [org].[location] lo ON lo.id = t.location_id
                LEFT JOIN [org].[branch] b ON b.id = t.branch_id
                LEFT JOIN [org].[department] d ON d.id = t.department_id
                LEFT JOIN [hr].[employee] lm ON lm.id = t.line_manager_id
                LEFT JOIN [hr].[employee] fa ON fa.id = t.final_authority_id
                WHERE t.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'resignation'
        RETURN (SELECT x.resignation_type, x.resignation_date, x.last_working_date, x.notice_period_days, x.serve_notice
                FROM [req].[req_resignation] x WHERE x.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'loan'
        RETURN (SELECT l.loan_type_id, lt.name AS loan_type_name, l.loan_category_id, lc.name AS loan_category_name,
                       l.amount_requested, l.required_date, l.extension_no, l.approved_amount, l.currency,
                       l.payment_method, l.repayment_date,
                       JSON_QUERY(ISNULL((SELECT g.id, g.name, g.cnic, g.known_since, g.relationship, g.extension_no,
                                                 g.description, g.file_id, gf.name AS file_name
                                          FROM [req].[loan_guarantor] g
                                          LEFT JOIN [core].[stored_file] gf ON gf.id = g.file_id
                                          WHERE g.request_id = @request_id
                                          ORDER BY g.id FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS guarantors
                FROM [req].[req_loan] l
                LEFT JOIN [loan].[loan_type] lt ON lt.id = l.loan_type_id
                LEFT JOIN [loan].[loan_category] lc ON lc.id = l.loan_category_id
                WHERE l.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'travel'
        RETURN (SELECT t.purpose, t.extension_no, t.alt_phone, t.advance_required,
                       JSON_QUERY(ISNULL((SELECT a.id, a.amount, a.currency FROM [req].[travel_advance] a
                                          WHERE a.request_id = @request_id ORDER BY a.id FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS advances,
                       JSON_QUERY(ISNULL((SELECT l.id, l.travel_type, l.from_place, l.to_place, l.travel_mode, l.distance_km,
                                                 l.depart_at, l.arrive_at, l.stay_required
                                          FROM [req].[travel_leg] l WHERE l.request_id = @request_id
                                          ORDER BY l.depart_at, l.id FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS legs,
                       JSON_QUERY(ISNULL((SELECT s.id, s.stay_type, s.address, s.city, s.from_date, s.to_date, s.nights,
                                                 s.phone, s.email
                                          FROM [req].[travel_stay] s WHERE s.request_id = @request_id
                                          ORDER BY s.from_date, s.id FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS stays,
                       JSON_QUERY(ISNULL((SELECT k.id, k.ticket_no, k.travel_class, k.from_place, k.to_place, k.travel_at,
                                                 k.description, k.file_id, kf.name AS file_name
                                          FROM [req].[travel_ticket] k
                                          LEFT JOIN [core].[stored_file] kf ON kf.id = k.file_id
                                          WHERE k.request_id = @request_id
                                          ORDER BY k.travel_at, k.id FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS tickets
                FROM [req].[req_travel] t
                WHERE t.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'expense'
        RETURN (SELECT x.currency, x.total_amount, x.approved_amount,
                       JSON_QUERY(ISNULL((SELECT l.id, l.line_no, l.title, l.claim_date, l.expense_category_id,
                                                 c.name AS expense_category_name, l.amount, l.approved_amount, l.description,
                                                 l.file_id, f.name AS file_name, l.opening_balance_id,
                                                 ob.balance_month AS paid_in_month
                                          FROM [req].[expense_line] l
                                          LEFT JOIN [req].[expense_category] c ON c.id = l.expense_category_id
                                          LEFT JOIN [core].[stored_file] f ON f.id = l.file_id
                                          LEFT JOIN [pay].[opening_balance] ob ON ob.id = l.opening_balance_id
                                          WHERE l.request_id = @request_id
                                          ORDER BY l.line_no FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS lines
                FROM [req].[req_expense] x
                WHERE x.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'air_ticket'
        RETURN (SELECT a.title, a.claim_date, a.travel_date, a.from_place, a.to_place, a.amount, a.approved_amount,
                       a.currency, a.description, a.file_id, f.name AS file_name, a.opening_balance_id,
                       ob.balance_month AS paid_in_month
                FROM [req].[req_air_ticket] a
                LEFT JOIN [core].[stored_file] f ON f.id = a.file_id
                LEFT JOIN [pay].[opening_balance] ob ON ob.id = a.opening_balance_id
                WHERE a.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    IF @kind = N'requisition'
        RETURN (SELECT q.title, q.requisition_type, q.needed_by_date, q.delivery_location, q.estimated_amount, q.currency,
                       JSON_QUERY(ISNULL((SELECT l.id, l.line_no, l.item_name, l.quantity, l.unit, l.estimated_unit_cost,
                                                 l.description
                                          FROM [req].[requisition_line] l WHERE l.request_id = @request_id
                                          ORDER BY l.line_no FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS lines
                FROM [req].[req_requisition] q
                WHERE q.request_id = @request_id
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

    RETURN N'{}';
END
