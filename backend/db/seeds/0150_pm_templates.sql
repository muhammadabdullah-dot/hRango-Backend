-- Project management templates (reference data, idempotent).
--   workflow templates: the four Define Workflow cards, each with the views, statuses and organizer
--     features its Customize Template summary starts with (Figma, Create Workspace step 3).
--   status templates: Edit Statuses -> Status Templates, statuses as the BRD lists them
--     (Functional Requirements PDF, "Task Statuses": Not Started, Active (...), Done, Closed).
SET NOCOUNT ON;

DECLARE @t TABLE (template_kind NVARCHAR(30), code NVARCHAR(30), name NVARCHAR(200), description NVARCHAR(400), sort_order INT);
INSERT @t VALUES
 (N'workflow', N'work_starter',        N'Work Starter',          N'Everyday tasks.', 10),
 (N'workflow', N'project_management',  N'Project Management',    N'Plan, manage and execute projects.', 20),
 (N'workflow', N'marketing_team',      N'Marketing Team',        N'Run effective campaigns and strategies.', 30),
 (N'workflow', N'product_engineering', N'Product & Engineering', N'Plan, build and ship products.', 40),
 (N'status',   N'custom',              N'Normal/Custom',         N'Basic statuses for general task management.', 10),
 (N'status',   N'content',             N'Content',               N'Content creation workflows.', 20),
 (N'status',   N'kanban',              N'Kanban',                N'Tasks managed on a Kanban board.', 30),
 (N'status',   N'marketing',           N'Marketing',             N'Marketing projects.', 40),
 (N'status',   N'scrum',               N'Scrum',                 N'Agile sprints.', 50);

MERGE [pm].[template] AS d
USING @t AS s ON d.template_kind = s.template_kind AND d.code = s.code
WHEN MATCHED AND (d.name <> s.name OR ISNULL(d.description, N'') <> s.description OR ISNULL(d.sort_order, 0) <> s.sort_order)
    THEN UPDATE SET name = s.name, description = s.description, sort_order = s.sort_order, updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (template_kind, code, name, description, sort_order)
    VALUES (s.template_kind, s.code, s.name, s.description, s.sort_order);

DECLARE @i TABLE (template_kind NVARCHAR(30), template_code NVARCHAR(30), item_type NVARCHAR(30), item_code NVARCHAR(50),
                  name NVARCHAR(200), status_group NVARCHAR(30), color NVARCHAR(20), sort_order INT, is_default BIT);

-- Organizer features every workflow template switches on (the twelve rows of the Organizer page).
DECLARE @f TABLE (item_code NVARCHAR(50), name NVARCHAR(200), sort_order INT);
INSERT @f VALUES
 (N'priority', N'Priority', 10), (N'custom_fields', N'Add Fields', 20),
 (N'remap_subtask_due_dates', N'Remap Subtask Due Dates', 30), (N'multiple_assignees', N'Multiple Assignees', 40),
 (N'story_points', N'Story Points', 50), (N'tags', N'Tags', 60), (N'time_estimate', N'Time Estimate', 70),
 (N'time_tracking', N'Time Tracking', 80), (N'incomplete_warning', N'Incomplete Warnings', 90),
 (N'dependency_warning', N'Dependencies Warning', 100), (N'reschedule_dependencies', N'Reschedule Dependencies', 110),
 (N'show_status_progress', N'Show Status Progress', 120);

INSERT @i SELECT N'workflow', w.code, N'feature', f.item_code, f.name, NULL, NULL, f.sort_order, 0
FROM @f f CROSS JOIN (VALUES (N'work_starter'), (N'project_management'), (N'marketing_team'), (N'product_engineering')) w (code);

INSERT @i VALUES
 -- Work Starter: List, Board; To Do > In-Progress > Completed
 (N'workflow', N'work_starter', N'view', N'list', N'List', NULL, NULL, 10, 1),
 (N'workflow', N'work_starter', N'view', N'board', N'Board', NULL, NULL, 20, 0),
 (N'workflow', N'work_starter', N'status', NULL, N'To Do', N'not_started', N'#979797', 10, 0),
 (N'workflow', N'work_starter', N'status', NULL, N'In-Progress', N'active', N'#2F639A', 20, 0),
 (N'workflow', N'work_starter', N'status', NULL, N'Completed', N'closed', N'#318845', 30, 0),
 -- Project Management
 (N'workflow', N'project_management', N'view', N'list', N'List', NULL, NULL, 10, 1),
 (N'workflow', N'project_management', N'view', N'board', N'Board', NULL, NULL, 20, 0),
 (N'workflow', N'project_management', N'view', N'calendar', N'Calendar', NULL, NULL, 30, 0),
 (N'workflow', N'project_management', N'view', N'gantt', N'Gantt', NULL, NULL, 40, 0),
 (N'workflow', N'project_management', N'view', N'team', N'Team', NULL, NULL, 50, 0),
 (N'workflow', N'project_management', N'status', NULL, N'To Do', N'not_started', N'#979797', 10, 0),
 (N'workflow', N'project_management', N'status', NULL, N'Planning', N'active', N'#762AFD', 20, 0),
 (N'workflow', N'project_management', N'status', NULL, N'In-Progress', N'active', N'#2F639A', 30, 0),
 (N'workflow', N'project_management', N'status', NULL, N'At Risk', N'active', N'#DC3545', 40, 0),
 (N'workflow', N'project_management', N'status', NULL, N'Update Required', N'active', N'#E9540D', 50, 0),
 (N'workflow', N'project_management', N'status', NULL, N'Completed', N'closed', N'#318845', 60, 0),
 -- Marketing Team
 (N'workflow', N'marketing_team', N'view', N'list', N'List', NULL, NULL, 10, 1),
 (N'workflow', N'marketing_team', N'view', N'board', N'Board', NULL, NULL, 20, 0),
 (N'workflow', N'marketing_team', N'view', N'team', N'Team', NULL, NULL, 30, 0),
 (N'workflow', N'marketing_team', N'view', N'calendar', N'Calendar', NULL, NULL, 40, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'Backlog', N'not_started', N'#979797', 10, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'Planning', N'active', N'#762AFD', 20, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'In-Progress', N'active', N'#2F639A', 30, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'Ready for Review', N'active', N'#2E64E2', 40, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'Update Required', N'active', N'#B2B22F', 50, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'On Hold', N'active', N'#9A782F', 60, 0),
 (N'workflow', N'marketing_team', N'status', NULL, N'Completed', N'closed', N'#318845', 70, 0),
 -- Product & Engineering: List, Board, Team, Calendar; Backlog > Planning > In-Progress > Ready for Review ...
 (N'workflow', N'product_engineering', N'view', N'list', N'List', NULL, NULL, 10, 1),
 (N'workflow', N'product_engineering', N'view', N'board', N'Board', NULL, NULL, 20, 0),
 (N'workflow', N'product_engineering', N'view', N'team', N'Team', NULL, NULL, 30, 0),
 (N'workflow', N'product_engineering', N'view', N'calendar', N'Calendar', NULL, NULL, 40, 0),
 (N'workflow', N'product_engineering', N'status', NULL, N'Backlog', N'not_started', N'#979797', 10, 0),
 (N'workflow', N'product_engineering', N'status', NULL, N'Planning', N'active', N'#762AFD', 20, 0),
 (N'workflow', N'product_engineering', N'status', NULL, N'In-Progress', N'active', N'#2F639A', 30, 0),
 (N'workflow', N'product_engineering', N'status', NULL, N'Ready for Review', N'active', N'#2E64E2', 40, 0),
 (N'workflow', N'product_engineering', N'status', NULL, N'Completed', N'closed', N'#318845', 50, 0),
 -- Status templates (BRD)
 (N'status', N'custom', N'status', NULL, N'Not Started', N'not_started', N'#979797', 10, 0),
 (N'status', N'custom', N'status', NULL, N'In Progress', N'active', N'#2F639A', 20, 0),
 (N'status', N'custom', N'status', NULL, N'Done', N'done', N'#4DDC00', 30, 0),
 (N'status', N'custom', N'status', NULL, N'Closed', N'closed', N'#318845', 40, 0),
 (N'status', N'content', N'status', NULL, N'Not Started', N'not_started', N'#979797', 10, 0),
 (N'status', N'content', N'status', NULL, N'Ready', N'active', N'#2F669A', 20, 0),
 (N'status', N'content', N'status', NULL, N'Writing', N'active', N'#562F9A', 30, 0),
 (N'status', N'content', N'status', NULL, N'Approval', N'active', N'#389A2F', 40, 0),
 (N'status', N'content', N'status', NULL, N'Rejected', N'active', N'#9A2F2F', 50, 0),
 (N'status', N'content', N'status', NULL, N'Publish', N'active', N'#619A2F', 60, 0),
 (N'status', N'content', N'status', NULL, N'Done', N'done', N'#4DDC00', 70, 0),
 (N'status', N'content', N'status', NULL, N'Closed', N'closed', N'#318845', 80, 0),
 (N'status', N'kanban', N'status', NULL, N'Not Started', N'not_started', N'#979797', 10, 0),
 (N'status', N'kanban', N'status', NULL, N'In Progress', N'active', N'#2F639A', 20, 0),
 (N'status', N'kanban', N'status', NULL, N'Review', N'active', N'#562F9A', 30, 0),
 (N'status', N'kanban', N'status', NULL, N'Done', N'done', N'#4DDC00', 40, 0),
 (N'status', N'kanban', N'status', NULL, N'Closed', N'closed', N'#318845', 50, 0),
 (N'status', N'marketing', N'status', NULL, N'Not Started', N'not_started', N'#979797', 10, 0),
 (N'status', N'marketing', N'status', NULL, N'Concept', N'active', N'#2F639A', 20, 0),
 (N'status', N'marketing', N'status', NULL, N'In Progress', N'active', N'#562F9A', 30, 0),
 (N'status', N'marketing', N'status', NULL, N'Running', N'active', N'#4DDC00', 40, 0),
 (N'status', N'marketing', N'status', NULL, N'Review', N'active', N'#DC1200', 50, 0),
 (N'status', N'marketing', N'status', NULL, N'Done', N'done', N'#619A2F', 60, 0),
 (N'status', N'marketing', N'status', NULL, N'Closed', N'closed', N'#318845', 70, 0),
 (N'status', N'scrum', N'status', NULL, N'Not Started', N'not_started', N'#979797', 10, 0),
 (N'status', N'scrum', N'status', NULL, N'Pending', N'active', N'#2F639A', 20, 0),
 (N'status', N'scrum', N'status', NULL, N'In Progress', N'active', N'#562F9A', 30, 0),
 (N'status', N'scrum', N'status', NULL, N'Completed', N'active', N'#4DDC00', 40, 0),
 (N'status', N'scrum', N'status', NULL, N'In Review', N'active', N'#DC9600', 50, 0),
 (N'status', N'scrum', N'status', NULL, N'Accepted', N'active', N'#0072DC', 60, 0),
 (N'status', N'scrum', N'status', NULL, N'Rejected', N'active', N'#DC1200', 70, 0),
 (N'status', N'scrum', N'status', NULL, N'Blocked', N'active', N'#DC5C00', 80, 0),
 (N'status', N'scrum', N'status', NULL, N'Done', N'done', N'#619A2F', 90, 0),
 (N'status', N'scrum', N'status', NULL, N'Closed', N'closed', N'#318845', 100, 0);

-- Items are matched on template, type and sort order; anything else in a seeded template is removed.
MERGE [pm].[template_item] AS d
USING (SELECT t.id AS template_id, i.* FROM @i i
       JOIN [pm].[template] t ON t.template_kind = i.template_kind AND t.code = i.template_code) AS s
   ON d.template_id = s.template_id AND d.item_type = s.item_type AND d.sort_order = s.sort_order
WHEN MATCHED AND (d.name <> s.name OR ISNULL(d.item_code, N'') <> ISNULL(s.item_code, N'')
                  OR ISNULL(d.status_group, N'') <> ISNULL(s.status_group, N'') OR ISNULL(d.color, N'') <> ISNULL(s.color, N'')
                  OR d.is_default <> s.is_default)
    THEN UPDATE SET name = s.name, item_code = s.item_code, status_group = s.status_group, color = s.color,
                    is_default = s.is_default, updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN INSERT (template_id, item_type, item_code, name, status_group, color, sort_order, is_default)
    VALUES (s.template_id, s.item_type, s.item_code, s.name, s.status_group, s.color, s.sort_order, s.is_default)
WHEN NOT MATCHED BY SOURCE AND d.template_id IN (SELECT id FROM [pm].[template]) THEN DELETE;
