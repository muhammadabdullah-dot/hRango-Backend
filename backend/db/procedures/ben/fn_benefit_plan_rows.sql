-- Benefit plans of a company as the Plans list shows them: enrolled (approved elections), pending
-- elections, attached files and the plan years offering it.
CREATE OR ALTER FUNCTION [ben].[fn_benefit_plan_rows] (@company_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT b.id, b.category, b.name, b.plan_type, b.plan_type_ref, b.carrier, b.start_date, b.end_date, b.description,
       b.status,
       (SELECT COUNT(*) FROM [ben].[election_plan] ep JOIN [ben].[election] e ON e.id = ep.election_id
        WHERE ep.benefit_plan_id = b.id AND e.status = N'approved') AS enrolled,
       (SELECT COUNT(*) FROM [ben].[election_plan] ep JOIN [ben].[election] e ON e.id = ep.election_id
        WHERE ep.benefit_plan_id = b.id AND e.status = N'pending') AS pending,
       (SELECT COUNT(*) FROM [core].[attachment] a WHERE a.entity_type = N'ben.benefit_plan' AND a.entity_id = b.id) AS file_count,
       (SELECT STRING_AGG(CAST(pp.plan_year_id AS NVARCHAR(20)), N',') FROM [ben].[plan_year_plan] pp
        WHERE pp.benefit_plan_id = b.id) AS plan_year_ids,
       b.created_at, cb.name AS created_by_name, b.updated_at, b.row_version
FROM [ben].[benefit_plan] b
OUTER APPLY [ben].[fn_actor_name](b.created_by) cb
WHERE b.company_id = @company_id;
