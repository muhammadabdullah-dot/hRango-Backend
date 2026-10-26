-- Workflow or status templates with what each starts with.
-- Result set 1: templates. Result set 2: their items (views, statuses, organizer features).
CREATE OR ALTER PROCEDURE [pm].[usp_template_list]
    @template_kind NVARCHAR(30) = N'workflow'
AS
BEGIN
    SET NOCOUNT ON;

    SELECT t.id, t.code, t.name, t.description
    FROM [pm].[template] t
    WHERE t.template_kind = @template_kind
    ORDER BY t.sort_order, t.id;

    SELECT i.template_id, i.item_type, i.item_code, i.name, i.status_group, i.color, i.sort_order, i.is_default
    FROM [pm].[template_item] i
    JOIN [pm].[template] t ON t.id = i.template_id
    WHERE t.template_kind = @template_kind
    ORDER BY i.template_id, i.item_type, i.sort_order;
END
