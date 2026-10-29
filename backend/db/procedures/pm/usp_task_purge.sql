-- Internal: removes the tasks listed in the caller's #purge (task_id) table and everything that
-- hangs off them (assignees, tags, dependencies, comments, time, checklist, files, values,
-- extensions, reminders, share links, favourites, doc links, link attachments, recents). The caller checks access and runs the transaction.
CREATE OR ALTER PROCEDURE [pm].[usp_task_purge]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DELETE r FROM [pm].[comment_reaction] r JOIN [pm].[task_comment] c ON c.id = r.comment_id JOIN #purge p ON p.task_id = c.task_id;
    DELETE m FROM [pm].[comment_mention] m JOIN [pm].[task_comment] c ON c.id = m.comment_id JOIN #purge p ON p.task_id = c.task_id;
    DELETE m FROM [pm].[comment_mention] m JOIN #purge p ON p.task_id = m.mentioned_task_id;
    DELETE c FROM [pm].[task_comment] c JOIN #purge p ON p.task_id = c.task_id;
    DELETE a FROM [pm].[task_assignee] a JOIN #purge p ON p.task_id = a.task_id;
    DELETE t FROM [pm].[task_tag] t JOIN #purge p ON p.task_id = t.task_id;
    DELETE d FROM [pm].[task_dependency] d WHERE d.task_id IN (SELECT task_id FROM #purge) OR d.other_task_id IN (SELECT task_id FROM #purge);
    DELETE x FROM [pm].[checklist_item] x JOIN #purge p ON p.task_id = x.task_id;
    DELETE x FROM [pm].[time_entry] x JOIN #purge p ON p.task_id = x.task_id;
    DELETE x FROM [pm].[task_field_value] x JOIN #purge p ON p.task_id = x.task_id;
    DELETE x FROM [pm].[task_extension] x JOIN #purge p ON p.task_id = x.task_id;
    DELETE x FROM [pm].[reminder] x JOIN #purge p ON p.task_id = x.entity_id AND x.entity_type = N'task';
    DELETE x FROM [pm].[favorite] x JOIN #purge p ON p.task_id = x.entity_id AND x.entity_type = N'task';
    DELETE m FROM [pm].[share_member] m JOIN [pm].[share_link] s ON s.id = m.share_link_id JOIN #purge p ON p.task_id = s.entity_id AND s.entity_type = N'task';
    DELETE x FROM [pm].[share_access] x JOIN [pm].[share_link] s ON s.id = x.share_link_id JOIN #purge p ON p.task_id = s.entity_id AND s.entity_type = N'task';
    DELETE s FROM [pm].[share_link] s JOIN #purge p ON p.task_id = s.entity_id AND s.entity_type = N'task';

    DELETE x FROM [pm].[doc_task] x JOIN #purge p ON p.task_id = x.task_id;
    DELETE x FROM [pm].[task_external_file] x JOIN #purge p ON p.task_id = x.task_id;
    DELETE x FROM [pm].[recent_item] x JOIN #purge p ON p.task_id = x.entity_id AND x.entity_type = N'task';

    -- Attachments go; the files themselves stay with the file service (only it removes stored files and bytes).
    DELETE a FROM [core].[attachment] a JOIN #purge p ON p.task_id = a.entity_id AND a.entity_type = N'pm.task';

    -- Subtasks of purged tasks are in #purge too (callers collect the whole tree), so one statement
    -- removes parents and children together.
    DELETE t FROM [pm].[task] t JOIN #purge p ON p.task_id = t.id;
END
