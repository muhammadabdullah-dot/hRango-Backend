"""Permission codes for Project Management. These open the module and its screens; what a person may
do inside a workspace is decided by their workspace role (workspace_admin, hr, manager, team_leader,
contributor), which the pm procedures enforce. Scopes are not used: membership decides whose
workspaces and tasks a person reaches.

A person's own Personal List, Recents and Notepad need only projects.workspaces.view (they are the
caller's own records). The public share page (/api/public/shares/{token}) needs no sign-in."""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("projects.workspaces", "Workspaces (create wizard, settings, members, statuses, fields, views)",
     ("view", "create", "edit", "delete"), False),
    ("projects.lists", "Folders and lists", ("view", "create", "edit", "delete"), False),
    ("projects.tasks", "Tasks and subtasks", ("view", "create", "edit", "delete", "assign"), False),
    ("projects.comments", "Task comments", ("view", "create", "edit", "delete"), False),
    ("projects.time_tracking", "Time tracking", ("view", "create", "edit", "delete"), False),
    ("projects.reminders", "Reminders", ("view", "create", "edit", "delete"), False),
    ("projects.sharing", "Sharing and permissions", ("view", "edit"), False),
    ("projects.extensions", "Task extension requests", ("create", "approve", "reject"), False),
    ("projects.history", "Project history", ("view",), False),
    ("projects.docs", "Docs", ("view", "create", "edit", "delete", "archive", "export"), False),
    ("projects.ai", "Writing and suggestions with AI", ("generate",), False),
    ("projects.storage", "External file sources (Google Drive, Dropbox, Box, OneDrive)", ("view", "create", "delete"),
     False),
]

# Events this module publishes (core.usp_event_publish); webhooks subscribe to them.
EVENTS: list[tuple[str, str]] = [
    ("projects.task_assigned", "People were newly assigned to a task (on create or on Assignees); each is notified."),
    ("projects.comment_mention", "A task comment mentions people (new, or newly added on edit); each is notified."),
]
