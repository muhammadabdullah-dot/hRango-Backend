-- Notification links that opened "Page not found" in the web app (Test Run 18-19 Nov 2026, rows 3.35,
-- 6.18, 7B.41 and 15.36): the inbox now gets links to pages the web app has, with the record opened
-- by a search parameter (req.fn_request_link and the procedures that notify). This rewrites the links
-- of notifications already sent, so the old ones open too. Data only; runs once. The request types'
-- pages are listed here as req.fn_request_link has them (that function is installed after the
-- migrations, so it cannot be called from here).

DECLARE @pages TABLE (type_code NVARCHAR(30) PRIMARY KEY, page NVARCHAR(100) NOT NULL);
INSERT @pages (type_code, page) VALUES
    (N'punch', N'/requests/punch'), (N'shift_swap', N'/requests/shift'), (N'transfer', N'/requests/transfer'),
    (N'leave', N'/requests/leave'), (N'loan', N'/requests/loan-advances'),
    (N'work_from_home', N'/requests/work-from-home'), (N'official_visit', N'/requests/official-visits'),
    (N'promotion', N'/requests/promotion'), (N'relaxation', N'/requests/relaxation'),
    (N'rest_day', N'/requests/rest-days'), (N'travel', N'/requests/travel'),
    (N'resignation', N'/requests/resignation'), (N'expense', N'/requests/expense'),
    (N'air_ticket', N'/requests/air-tickets'), (N'requisition', N'/requests/requisition');

-- Requests waiting for an approver: /requests/approvals/<id>.
UPDATE n
SET link = CASE WHEN t.code = N'overtime' THEN N'/attendance/overtime?tab=applications&request=' + CONVERT(NVARCHAR(30), r.id)
                ELSE p.page + N'?tab=approvals&request=' + CONVERT(NVARCHAR(30), r.id) END
FROM [core].[notification] n
JOIN [req].[request] r ON r.id = n.entity_id
JOIN [req].[request_type] t ON t.id = r.request_type_id
LEFT JOIN @pages p ON p.type_code = t.code
WHERE n.entity_type = N'req.request' AND n.link = N'/requests/approvals/' + CONVERT(NVARCHAR(30), r.id);

-- A requisition approved, to the people who fulfil it: /requests/requisition/<id>.
UPDATE n
SET link = N'/requests/requisition?scope=all&request=' + CONVERT(NVARCHAR(30), r.id)
FROM [core].[notification] n
JOIN [req].[request] r ON r.id = n.entity_id
WHERE n.entity_type = N'req.request' AND n.notification_type = N'request_fulfil'
  AND n.link = N'/requests/requisition/' + CONVERT(NVARCHAR(30), r.id);

-- A request decided, to the requester: /requests/<type with hyphens>/<id>.
UPDATE n
SET link = CASE WHEN t.code = N'overtime' THEN N'/attendance/overtime?tab=my&request=' + CONVERT(NVARCHAR(30), r.id)
                ELSE p.page + N'?request=' + CONVERT(NVARCHAR(30), r.id) END
FROM [core].[notification] n
JOIN [req].[request] r ON r.id = n.entity_id
JOIN [req].[request_type] t ON t.id = r.request_type_id
LEFT JOIN @pages p ON p.type_code = t.code
WHERE n.entity_type = N'req.request'
  AND n.link = N'/requests/' + REPLACE(t.code, N'_', N'-') + N'/' + CONVERT(NVARCHAR(30), r.id);

-- Update Information: HR's list, the employee's profile, documents expiring.
UPDATE [core].[notification]
SET link = N'/talent-management/update-requests?request=' + CONVERT(NVARCHAR(30), entity_id)
WHERE link = N'/employees/update-requests' AND entity_type = N'hr.employee_change_request' AND entity_id IS NOT NULL;

UPDATE [core].[notification] SET link = N'/my-profile' WHERE link = N'/profile';
UPDATE [core].[notification] SET link = N'/my-profile?tab=documents' WHERE link = N'/profile/documents';

-- Appraisals and recruitment open their record on the list page.
UPDATE [core].[notification]
SET link = N'/performance/reviews?review=' + CONVERT(NVARCHAR(30), entity_id)
WHERE entity_type = N'perf.appraisal' AND link = N'/performance/reviews/' + CONVERT(NVARCHAR(30), entity_id);

UPDATE [core].[notification]
SET link = CASE entity_type WHEN N'rec.application' THEN N'/recruitment/applications?view='
                            WHEN N'rec.interview' THEN N'/recruitment/interviews?view='
                            ELSE N'/recruitment/offers?view=' END + CONVERT(NVARCHAR(30), entity_id)
WHERE (entity_type = N'rec.application' AND link = N'/recruitment/applications/' + CONVERT(NVARCHAR(30), entity_id))
   OR (entity_type = N'rec.interview' AND link = N'/recruitment/interviews/' + CONVERT(NVARCHAR(30), entity_id))
   OR (entity_type = N'rec.offer' AND link = N'/recruitment/offers/' + CONVERT(NVARCHAR(30), entity_id));
