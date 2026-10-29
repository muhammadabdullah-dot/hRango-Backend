-- Request headers with what every list and the View popup show: the employee card (code, name,
-- job title, branch, department, location, joining date), the next approver ("Next Requestee")
-- and the final authority ("Approving Authority"). Deleted requests are left out.
CREATE OR ALTER FUNCTION [req].[fn_request_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT r.id, r.code, r.request_type_id, t.code AS request_type, t.name AS request_type_name, t.kind,
       r.employee_id, e.code AS employee_code, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS employee_name,
       e.department_id, d.name AS department_name, e.branch_id, b.name AS branch_name, e.location_id,
       lo.name AS location_name, jt.name AS job_title_name, e.status AS employee_status,
       (SELECT MAX(ep.joining_date) FROM [hr].[employment_period] ep WHERE ep.employee_id = e.id) AS joining_date,
       r.from_date, r.to_date, r.days, r.reason, r.description, r.application, r.status,
       r.submitted_at, r.decided_at, r.cancel_reason, r.cancel_requested_at, r.cancel_dates, r.cancel_start_time,
       r.cancel_end_time, r.created_by_user_id,
       ns.approver_id AS next_approver_id,
       COALESCE(NULLIF(CONCAT(na.first_name, N' ', na.last_name), N' '), nr.name) AS next_approver_name,
       ns.approver_kind AS next_approver_kind,
       fa.id AS final_authority_id, NULLIF(CONCAT(fa.first_name, N' ', fa.last_name), N' ') AS final_authority_name,
       r.created_at, r.updated_at, r.row_version
FROM [req].[request] r
JOIN [req].[request_type] t ON t.id = r.request_type_id
JOIN [hr].[employee] e ON e.id = r.employee_id
LEFT JOIN [org].[department] d ON d.id = e.department_id
LEFT JOIN [org].[branch] b ON b.id = e.branch_id
LEFT JOIN [org].[location] lo ON lo.id = e.location_id
LEFT JOIN [org].[job_title] jt ON jt.id = e.job_title_id
OUTER APPLY (SELECT TOP (1) s.approver_id, s.approver_kind, s.approver_role_id
             FROM [req].[request_step] s WHERE s.request_id = r.id AND s.action_taken = N'pending' ORDER BY s.id) ns
LEFT JOIN [hr].[employee] na ON na.id = ns.approver_id
LEFT JOIN [auth].[role] nr ON nr.id = ns.approver_role_id
LEFT JOIN [req].[req_transfer] tr ON tr.request_id = r.id
LEFT JOIN [hr].[employee] fa ON fa.id = COALESCE(tr.final_authority_id, e.final_authority_id)
WHERE r.company_id = @company_id AND r.is_deleted = 0;
