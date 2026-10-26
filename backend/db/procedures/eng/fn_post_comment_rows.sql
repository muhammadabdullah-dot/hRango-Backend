-- How a comment is shown, as seen by one employee (liked by them, written by them).
-- mentions_json: [{employee_id, name}].
CREATE OR ALTER FUNCTION [eng].[fn_post_comment_rows] (@employee_id BIGINT)
RETURNS TABLE
AS RETURN
SELECT c.id, c.post_id, c.parent_id, c.employee_id AS author_id,
       NULLIF(CONCAT(a.first_name, N' ', a.last_name), N' ') AS author_name, a.photo_file_id AS author_photo_file_id,
       c.body, c.commented_at, c.edited_at,
       CAST(CASE WHEN c.employee_id = @employee_id THEN 1 ELSE 0 END AS BIT) AS is_mine,
       (SELECT COUNT(*) FROM [eng].[post_comment_like] l WHERE l.post_comment_id = c.id) AS like_count,
       CAST(CASE WHEN EXISTS (SELECT 1 FROM [eng].[post_comment_like] l
                              WHERE l.post_comment_id = c.id AND l.employee_id = @employee_id) THEN 1 ELSE 0 END AS BIT) AS liked_by_me,
       (SELECT COUNT(*) FROM [eng].[post_comment] r WHERE r.parent_id = c.id) AS reply_count,
       (SELECT CONVERT(NVARCHAR(30), x.employee_id) AS employee_id, NULLIF(CONCAT(e.first_name, N' ', e.last_name), N' ') AS name
        FROM [eng].[post_mention] x JOIN [hr].[employee] e ON e.id = x.employee_id
        WHERE x.post_comment_id = c.id ORDER BY x.id FOR JSON PATH) AS mentions_json,
       c.row_version
FROM [eng].[post_comment] c
JOIN [hr].[employee] a ON a.id = c.employee_id;
