-- The fixed list of request types (Functional Requirements pp. 1-97, Figma Requests menu, Mini SRS M7).
-- kind = the detail table req.req_<kind> and the owning module's effect <schema>.usp_request_apply_<kind>.
-- Idempotent: re-applied on every seed. Names and order may change here; codes never change meaning.
MERGE [req].[request_type] AS t
USING (VALUES
    (N'leave',           N'Leave',            N'leave',           N'LV',  0, 1,  10),
    (N'punch',           N'Punch',            N'punch',           N'PCH', 0, 1,  20),
    (N'relaxation',      N'Relaxation',       N'time_window',     N'RLX', 0, 1,  30),
    (N'official_visit',  N'Official Visit',   N'time_window',     N'OV',  0, 1,  40),
    (N'work_from_home',  N'Work From Home',   N'work_from_home',  N'WFH', 0, 1,  50),
    (N'overtime',        N'Overtime',         N'overtime',        N'OT',  0, 1,  60),
    (N'rest_day',        N'Rest Days',        N'rest_day',        N'RD',  0, 1,  70),
    (N'shift_swap',      N'Shift Request',    N'shift_swap',      N'SFT', 0, 1,  80),
    (N'promotion',       N'Promotion',        N'promotion',       N'PRM', 1, 1,  90),
    (N'transfer',        N'Transfer',         N'transfer',        N'TRF', 1, 1, 100),
    (N'resignation',     N'Resignation',      N'resignation',     N'RSG', 0, 1, 110),
    (N'loan',            N'Loan & Advances',  N'loan',            N'LA',  0, 1, 120),
    (N'travel',          N'Travel',           N'travel',          N'TRV', 0, 1, 130),
    (N'expense',         N'Expense',          N'expense',         N'EXP', 0, 1, 135),
    (N'air_ticket',      N'Air Tickets',      N'air_ticket',      N'AIR', 0, 1, 137),
    (N'requisition',     N'Requisition',      N'requisition',     N'RQN', 0, 1, 140),
    (N'task_extension',  N'Task Extension',   N'task_extension',  N'TEX', 0, 1, 150)
) AS s (code, name, kind, prefix, is_admin_only, is_active, sort_order)
ON t.code = s.code
WHEN MATCHED AND (t.name <> s.name OR t.kind <> s.kind OR ISNULL(t.prefix, N'') <> s.prefix
                  OR t.is_admin_only <> s.is_admin_only OR ISNULL(t.sort_order, 0) <> s.sort_order) THEN
    UPDATE SET name = s.name, kind = s.kind, prefix = s.prefix, is_admin_only = s.is_admin_only,
               sort_order = s.sort_order, updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (code, name, kind, prefix, is_admin_only, is_active, sort_order)
    VALUES (s.code, s.name, s.kind, s.prefix, s.is_admin_only, s.is_active, s.sort_order);
