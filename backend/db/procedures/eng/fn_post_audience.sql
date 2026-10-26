-- The posts an employee is in the audience of: public posts, posts to their department or any department
-- above it (a department post reaches its sub-departments), posts to their branch, and their own posts.
-- Deleted posts are left out; hidden posts are not (eng.fn_visible_posts decides who sees those).
-- @employee_id NULL (a user with no employee record) reaches public posts only.
CREATE OR ALTER FUNCTION [eng].[fn_post_audience] (@company_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
WITH me AS (
    SELECT e.id, e.department_id, e.branch_id
    FROM [hr].[employee] e
    WHERE e.id = @employee_id AND e.company_id = @company_id
),
up AS (
    SELECT d.id, d.parent_id FROM [org].[department] d JOIN me ON d.id = me.department_id
    UNION ALL
    SELECT d.id, d.parent_id FROM [org].[department] d JOIN up ON d.id = up.parent_id
)
SELECT p.id AS post_id
FROM [eng].[post] p
WHERE p.company_id = @company_id AND p.is_deleted = 0
  AND (   p.visibility = N'public'
       OR p.author_id IN (SELECT id FROM me)
       OR (p.visibility = N'department' AND p.department_id IN (SELECT id FROM up))
       OR (p.visibility = N'branch' AND p.branch_id IN (SELECT branch_id FROM me)));
