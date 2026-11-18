-- What a company's organisation may use under its plan (roadmap 1.3): the employee limit of its live
-- subscription (trial, active or past due; the newest when there are several) and how many employees count
-- against it now, across every company of the organisation. Employees who left or were switched off do
-- not count. No row when the company belongs to no organisation; employee_limit NULL = no limit.
CREATE OR ALTER FUNCTION [plat].[fn_plan_allowance] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT cc.customer_id,
       p.id AS plan_id, p.name AS plan_name, p.employee_limit, s.status AS subscription_status,
       (SELECT COUNT(*) FROM [hr].[employee] e
        JOIN [plat].[customer_company] x ON x.company_id = e.company_id AND x.customer_id = cc.customer_id
        WHERE e.status NOT IN (N'left', N'inactive')) AS employees_used
FROM [plat].[customer_company] cc
OUTER APPLY (SELECT TOP 1 s.plan_id, s.status FROM [plat].[subscription] s
             WHERE s.customer_id = cc.customer_id AND s.status IN (N'trial', N'active', N'past_due')
             ORDER BY s.start_date DESC, s.id DESC) s
LEFT JOIN [plat].[plan] p ON p.id = s.plan_id
WHERE cc.company_id = @company_id;
GO
