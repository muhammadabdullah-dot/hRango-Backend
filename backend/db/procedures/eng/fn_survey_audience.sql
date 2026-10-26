-- The employees a survey asks: everyone in the company when it has no audience rows, otherwise the
-- employees of the chosen departments (and their sub-departments), branches and people. Employees who
-- have left or were switched off are not asked.
CREATE OR ALTER FUNCTION [eng].[fn_survey_audience] (@company_id BIGINT, @survey_id BIGINT)
RETURNS TABLE
AS RETURN
WITH s AS (
    SELECT id FROM [eng].[survey] WHERE id = @survey_id AND company_id = @company_id
),
down AS (
    SELECT d.id FROM [eng].[survey_audience] a JOIN s ON s.id = a.survey_id JOIN [org].[department] d ON d.id = a.unit_id
    WHERE a.unit_type = N'department'
    UNION ALL
    SELECT d.id FROM [org].[department] d JOIN down ON d.parent_id = down.id
)
SELECT e.id AS employee_id
FROM [hr].[employee] e
WHERE e.company_id = @company_id
  AND EXISTS (SELECT 1 FROM s)
  AND ISNULL(e.status, N'active') NOT IN (N'left', N'inactive')
  AND (   NOT EXISTS (SELECT 1 FROM [eng].[survey_audience] a WHERE a.survey_id = @survey_id)
       OR e.department_id IN (SELECT id FROM down)
       OR EXISTS (SELECT 1 FROM [eng].[survey_audience] a
                  WHERE a.survey_id = @survey_id
                    AND ((a.unit_type = N'branch' AND a.unit_id = e.branch_id)
                      OR (a.unit_type = N'employee' AND a.unit_id = e.id))));
