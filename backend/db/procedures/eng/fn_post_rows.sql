-- How a post is shown, as seen by one employee (@employee_id: their reaction, whether it is theirs).
-- Callers decide which posts the reader may see (eng.fn_visible_posts) before joining this.
-- reactions_json: [{kind, count}]; media_json: [{file_id, media_type, name, mime_type}];
-- mentions_json: [{employee_id, name}] (mentions in the post itself, not in its comments).
CREATE OR ALTER FUNCTION [eng].[fn_post_rows] (@company_id BIGINT, @employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT p.id, p.author_id, NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS author_name,
       a.photo_file_id AS author_photo_file_id, p.body, p.visibility, p.department_id, d.name AS department_name,
       p.branch_id, b.name AS branch_name, p.posted_at, p.edited_at, p.is_pinned, p.pinned_at, p.is_hidden,
       p.hidden_at, p.hidden_reason,
       CAST(CASE WHEN p.author_id = @employee_id THEN 1 ELSE 0 END AS BIT) AS is_mine,
       (SELECT COUNT(*) FROM [eng].[post_reaction] r WHERE r.post_id = p.id) AS reaction_count,
       (SELECT r.kind, COUNT(*) AS [count] FROM [eng].[post_reaction] r WHERE r.post_id = p.id
        GROUP BY r.kind ORDER BY COUNT(*) DESC, r.kind FOR JSON PATH) AS reactions_json,
       (SELECT r.kind FROM [eng].[post_reaction] r WHERE r.post_id = p.id AND r.employee_id = @employee_id) AS my_reaction,
       (SELECT COUNT(*) FROM [eng].[post_comment] c WHERE c.post_id = p.id) AS comment_count,
       (SELECT COUNT(*) FROM [eng].[post_view] v WHERE v.post_id = p.id) AS view_count,
       (SELECT CONVERT(NVARCHAR(30), m.file_id) AS file_id, m.media_type, f.name, f.mime_type
        FROM [eng].[post_media] m JOIN [core].[stored_file] f ON f.id = m.file_id
        WHERE m.post_id = p.id ORDER BY m.sort_order, m.id FOR JSON PATH) AS media_json,
       (SELECT CONVERT(NVARCHAR(30), x.employee_id) AS employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name
        FROM [eng].[post_mention] x JOIN [hr].[employee] e ON e.id = x.employee_id
        WHERE x.post_id = p.id AND x.post_comment_id IS NULL ORDER BY x.id FOR JSON PATH) AS mentions_json,
       p.row_version
FROM [eng].[post] p
JOIN [hr].[employee] a ON a.id = p.author_id
LEFT JOIN [org].[department] d ON d.id = p.department_id
LEFT JOIN [org].[branch] b ON b.id = p.branch_id
WHERE p.company_id = @company_id;
