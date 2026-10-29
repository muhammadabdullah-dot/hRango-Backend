# 08 Project management: frontend vs documents vs ERD

Status: first build done (backend `/api/projects`, schema `pm`). Second build (29 Oct 2026): gray structure for
the frontend's Backend Dependencies T1-T11 (docs, AI routes, notepad, reminder delivery, overdue settings, public
share page, recents and dashboards, location fields, external storage links, personal list); see "Second build".

Sources: Functional Requirements PDF pp. 181-257 (Project and Task Management BRD, "BRD" below) and its
digest `requirements/HRango - Project Management BRD/README.md`; `requirements/HRango - Project Management
Module/**` (Create Workspace wizard: 01 popup, 02 Define Workflow, 03 Customize Template, User Persona);
`requirements/HRango - Project Workspace UX UI Design/README.md` ("Workspace design" below);
`requirements/HRango - PMS Backlog Columns/README.md`; `erd/source/15-pm.md`. Frontend:
`frontend/src/features/project-management`, routes `frontend/src/routes/_app/project-management/**`,
README "Project Management" and "departures".

## Screens and features

| Screen / feature | Frontend (route) | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Create Workspace page + Workspaces panel (search, favourites, tree) | `/project-management/workspaces` | Wizard README 01; Workspace design 01; BRD "Post creation actions" (favourites, hide) | workspace, favorite, folder, task_list | Build: list (search, favourites filter, hidden last), favourites/hide marks |
| Wizard step 1: name, owner, description, visibility, members | `?create=true` | Wizard 01; BRD "Workspace Requirements" (3-50 chars, unique, 300 chars, private/public/workspace) | workspace, workspace_member | Build in one call (`POST /workspaces`) |
| Wizard step 2: department, workflow template | same | Wizard 02 (department required, 4 templates); BRD "Use Templates" (Starter default) | workspace.department_id, template | Build; templates seeded |
| Wizard step 3: default views, statuses (default / custom, status templates), organizer | same | Wizard 03; BRD "Default View List Options", "Task Statuses", "Organizational Features" | list_view, workspace_status, workspace_feature, template_item | Build with changes: status templates read-only (no template editing API, as the frontend already does) |
| Workspace page: banner, members, Invite Members, view bar | `/project-management/workspaces/$workspaceId` | Workspace design 01 | workspace, workspace_member, list_view | Build: details, members, views (+ View, pin, private, protect, default). Cover image: not built (file storage) |
| List view (grouped by status, columns, filters, customize, sort) | same | Workspace design 01; BRD "Task Filtering and Viewing Options", "Grouping & Sorting", "Show Task Alignment" | task + children, list_view.config | Build: `GET /workspaces/{id}/tasks` with filters, group by, sort, subtask display, paging, group counts |
| Column header menu: sort, move, hide, delete, Add Role Permission | same | Workspace design 01, 04 | list_view.config, column_permission | Build: column layout lives in the view's config; Set Role Permission stored and enforced |
| Set Role Permission (default, roles, custom per member; Can Edit / Can View / Private) | same (role-permission-dialog) | Workspace design 04; BRD custom fields "Role-Based Permissions" | column_permission | Build: enforced on edits, private columns blanked in reads |
| Task row menu: rename, favourite, move, convert, task type, remind me, share, delete | same | Workspace design 01 | task, favorite, reminder, share_link | Build: all; Duplicate and Merge (BRD only, not in the row menu) not built |
| Task fields: assignees (+ story points), dates + time, recurrence, priority, tags, dependencies, status, task type, time estimate, time tracked, files | List view cells | Workspace design 02, 03; BRD "Task Detail Screen" | task, task_assignee, task_tag, task_dependency, time_entry, core.attachment | Build |
| Labels | List view cells | BRD: Labels = multi-select custom field type | custom_field (labels) | Build with changes: a custom field of type `labels`, not a second tag kind |
| Custom fields ("Add Fields") | not drawn (column "+") | BRD "Task Custom Fields" (25 types); Backlog Columns marks 37 columns Skipped | custom_field, task_field_value | Build 15 plain types (location added in the second build: `{address, lat, lng}`, `?hasLocation=true`); formula, rollup, relationship, tasks, AI, signature, voting, files, progress auto: not built (computed / AI / need storage) |
| Comments: threads, @mentions (people, tasks), assign, resolve, like/emoji, edit, delete | comments-panel | Workspace design 03; BRD "Employee Side" (comment, edit own) | task_comment, comment_mention, comment_reaction | Build. Docs / Locations mentions: not built (no docs, no locations in PM) |
| Time tracking: timer, manual entries, notes, per person | time-tracked-field | Workspace design 03; BRD "Time Tracking" | time_entry | Build |
| Reminders ("Remind Me", reminder on task / list / workspace) | reminder-popover | BRD "Reminders"; Workspace design 02 | reminder | Build. Delivery: `pm.usp_reminder_deliver_due` / `deliver_due_reminders(db)` sends due reminders to the inbox (`projects.reminder`); a scheduler must call it (not wired yet) |
| Sharing & Permissions | share-dialog | BRD "Sharing and Permission"; Workspace design (full read) | share_link, share_member, share_access | Build. Public page `GET /api/public/shares/{token}` (+ `/tasks/{id}`), validity and access limit enforced; invitation emails not sent |
| Checklist (20 max) | not in frontend | BRD "Subtasks and Checklist" | checklist_item | Build |
| Overdue, Request Extension, story point impact | not in frontend | BRD "Overdue Task Handling", "Request Task Extension" | task.original_due_date, is_closed_late, task_extension | Build: request by assignee, decision by workspace manager+ inside PM |
| History | not in frontend | BRD "Maintain History" | core.audit_log | Build: task and workspace history with action/date filter and search; export not built |
| Home / Workspace / Project / Task Dashboards | `/project-management/home`, `workspace-dashboard`, `project-dashboard`, `task-dashboard` (placeholders) | BRD "Dashboards" (no design) | recent_item, personal_item (rest computed) | Second build: `/dashboard/home`, `/workspaces/{id}/dashboard`, `/folders/{id}/dashboard`, `/recents`, `/personal-list` |
| Docs, Notepad | doc rows in the panel (not links) | BRD "Documents", "Notepad" (no design) | doc, doc_task, doc_comment, doc_contributor, note, note_version | Second build (gray): docs CRUD, archive, duplicate, task links, comments; export answers 501. Notes with versions and convert to task / doc |
| Sprints, Board / Calendar / Timeline / Gantt / Team / Table / Activity / Map / Workload / Mind Map views | view tabs open "not designed" | BRD; Backlog Columns marks Sprints Skipped | sprint, list_view | Views are stored (type only); only List has data behind it. Sprints not built |
| Invite from email (assignee / workspace) | assignee popup | Workspace design 02 | none | Not built: brings non-employees into an HR system (design README issue 8). Share invites by email are stored |
| AI features (16) | none | BRD "AI Automation" (no acceptance criteria) | none | Routes and shapes only (`/projects/ai/*`): 503 `AI_UNAVAILABLE` until a model is connected |

## Gaps both ways

- Documents without frontend: checklist, extension requests and the overdue rule, history, Request Extension,
  reminders list, dashboards, docs, notepad, file manager ("Resources"), custom field definition screen.
- Frontend without documents: tasks at a workspace's top level (no list) - kept, contradicts nothing; per-task
  `rating` 1-3 (design "Fair / Good / Excellent") - kept as `task.rating`; Average Story Points footer
  (computed by the client from `storyPointsTotal`); third-party file sources (Drive, Dropbox ...) - routes only
  (`/api/integrations/storage`, 503 `STORAGE_NOT_CONFIGURED`), link attachments stored.
- Frontend payloads differ from the API (ids vs names for departments, `labels` as tags, comments `likedByIds`,
  share `full-edit/edit/view`): the frontend will be adjusted to the API.

## ERD changes (erd/source/15-pm.md) and why

- New `template`, `template_item`: workflow templates (4) and status templates (5) with their views, statuses
  and organizer features, seeded in `db/seeds/0150_pm_templates.sql`. Replaces `workspace.template` text.
- `workspace`: `department_id` (Define Workflow, required), `workflow_template_id`, `status_mode`,
  `status_template_id`; owner NN; UNIQUE (company_id, name) (BRD unique title).
- `workspace_setting` renamed `workspace_feature` (feature_code UNIQUE per workspace; presence = on).
- `workspace_status.wip_limit` (WIP limits per phase); UNIQUE (workspace_id, name).
- `folder.sort_order`; `task_list.sort_order`, `start_at`/`end_at` (BRD "date and time"); UNIQUE names per workspace.
- New `task_list_member` (BRD "Add Members to Project"; who sees a private list).
- `task`: `company_id` (per-company code `HR000000001`), `workspace_id` (tasks may sit outside a list),
  dates split into `start_date/start_time/due_date/due_time` (time optional in the design),
  `original_due_date`, `rating`, `url` (URL Connection), `sort_order`, `is_closed_late`.
- `task_dependency` stored once as "waits on" (`kind` waiting_on / linked); UNIQUE pair.
- `task_comment.assigned_by_id`, `edited_at`; new `comment_mention`, `comment_reaction`.
- `reminder`: `workspace_id`, `name`, `notify_before_minutes`, `reminder_kind`, `notified_at`.
- `task_extension`: `requested_by_id`, `old_due_date`, `status`, `decided_by_id`, `decided_at`, `remarks`
  (`request_id` kept for a later move into the Requests module).
- `custom_field`: `description`, `sort_order`; `custom_field_permission` replaced by `column_permission`
  (any List view column, built-in or `cf_<id>`; default / role / member rows).
- `list_view`: `workspace_id`, `owner_id`, `is_required`, `sort_order` (workspace-level views from the wizard).
- `share_link`: `workspace_id`, `share_scope`, `allow_open_tasks`; new `share_member` (people / emails with
  Full Edit, Limited, Commenter).
- New `favorite` (Add to Favorites, Hide Space; per employee).
- `sprint` kept, marked not in the first build.
- Second build: `doc` rebuilt (company, folder / list, content JSON + HTML, visibility, owner, cover, settings,
  counts, archived_at) with `doc_task`, `doc_comment`, `doc_contributor`; `note` per sign-in (`user_account_id`,
  `content_html`, `version_no`, `archived_at`) with `note_version`; new `personal_item`, `recent_item`,
  `workspace_overdue_setting`, `task_external_file` (link attachments), `share_access` (one row per public
  opening; `share_link.access_count` is no longer written, so visits do not change the link's row version).

## Workspace roles (enforced in the pm procedures)

Rank: workspace_admin 5, hr 4, manager 3, team_leader 2, contributor 1; a non-member reading a non-private workspace 0.

| Action | Who |
|---|---|
| See a private workspace | members only (company roles do not override privacy) |
| See tasks | everyone who sees the workspace; in a private workspace a contributor sees tasks assigned to or created by them and subtasks of their tasks; a private list: its members and admins / HR |
| Edit workspace, statuses, features, column permissions, shared views; add / remove members | admin, hr (granting or removing workspace_admin: admin only; the owner stays admin) |
| Delete workspace | admin |
| Folders, lists, custom fields, convert task to list, decide extensions, share links | manager and above |
| Add tasks, edit any task, assign people and story points, move, tags, comments assignment | team leader and above |
| Contributor | add subtasks under tasks assigned to them; edit tasks they created; change status, log time, checklist, attach files on tasks assigned to them; comment; request an extension (assignees) |
| Delete a task | manager and above, or its creator |
| Edit / delete a comment | its author (delete also manager and above) |

Column permissions on top: Can View or Private refuse the edit; Private blanks the column in reads
(`hiddenColumns`). Admins always edit every column.

## Decisions on unclear points

- Visibility: `private` = members only; `workspace` and `public` = everyone in the company reads, members
  edit. "Anyone on the internet" (design) is not offered; real outside links are public share links (`/api/public/shares/{token}`).
- Company RBAC (`projects.*`) only opens screens; scopes are not used. The workspace role decides.
- Task name uniqueness within a list, "every field required when adding", "due date not in the past unless
  Backlog", "time entries within start / due": not enforced (BRD digest shows they block normal use or are
  undefined). Only the name is required.
- Statuses: four groups (not_started, active, done, closed); done and closed both count as completed. A
  workspace keeps at least one Not Started and one Done or Closed status. Status names unique per workspace.
- Status templates follow the BRD literally (Not Started, the listed Active statuses, Done, Closed). Workflow
  templates follow the wizard summaries; Project Management and Marketing Team status lists, absent from the
  documents, follow the frontend's design-derived constants (contradicts nothing). Card descriptions were
  cleaned (Product & Engineering's design copy repeats another card's).
- Priority: Urgent, High, Normal, Low (design and BRD task detail).
- Blocking: a task waiting on unfinished tasks stays in Not Started and cannot be completed.
- Remap Subtask Due Dates / Reschedule Dependencies: shift direct subtasks / waiting tasks by the same days.
- Story points: numeric per assignee (0-100). Late completion sets `is_closed_late`. Second build: the
  workspace's overdue setting `penaltyPercent` (default 0) gives `storyPointsPenalty = round(total x percent / 100, 2)`
  for a task closed late (0 when on time, null without story points) and `storyPointsEffective = total - penalty`;
  nothing is stored, so changing the percent changes past tasks too (TODO: freeze at closing if wanted).
- Extension: up to the workspace's `maxExtensions` requests per task (default 1, so one in total unless
  changed), one pending at a time; approval inside PM by a workspace manager or above; approval keeps the
  first due date in `original_due_date`. `TaskRowOut.latestExtension` carries the newest request.
- Dates are compared with today in UTC (company time zone handling is shared work).
- Comments up to 2000 characters; time entry notes 165 (design); attachments PDF, DOCX, XLSX, PNG, JPG up to 10 MB.
- A **private** workspace created by an account without an employee record is refused up front (422
  `WORKSPACE_CREATOR_NOT_EMPLOYEE` on `privacy`, nothing written): only members (employees) see a private
  workspace, so the creator could not open it. Workspace / public privacy is unchanged. Visibility rules unchanged.

## Cross-module needs

- `app/core/default_roles.py`: the Employee role should hold `projects.*` with own scope (at least
  view / create / edit / delete / assign on tasks, comments, time_tracking, reminders; extensions.create),
  because inside a workspace the workspace role decides. Today Employee gets only view / create, so a
  contributor cannot change a status. Tests grant the codes per user (`tests/factories_projects.py`).
- Notifications (core.notification): task assignment and mentions notify; reminders notify once a scheduler
  calls `projects_collab_service.deliver_due_reminders(db)` (every few minutes; worker or `scripts/nightly.py`,
  not wired: shared files). Comment assignment and extension decisions do not notify yet.
- File storage: attachments and covers keep file details only (`storage_path` empty).
- Requests module: an optional `task_extension` request kind if extensions should follow approval flows.
- Employees module: photo URL for the people picker (only `photoFileId` is returned).

## Second build (gray structure, 29 Oct 2026)

Endpoints for the frontend's `docs/backend-dependencies.md` "Project and Task Management" T1-T11. Shapes follow
that file and `frontend/src/features/project-management/api/dashboards.api.ts`. Tests: `tests/test_projects_extras.py`.

| Item | Endpoints | Permission | Built | Left (TODO) |
|---|---|---|---|---|
| T1 Docs | `GET/POST /projects/workspaces/{id}/docs`, `GET/PUT/DELETE /projects/docs/{id}`, `PATCH .../archive`, `POST .../duplicate`, `PUT .../tasks`, `GET .../export?format=pdf\|docx`, `GET/POST .../comments` | `projects.docs.view/create/edit/delete/archive/export`; comments post `projects.comments.create` | private docs owner-only; members add; owner or manager+ edit (editors become contributors); owner or HR+ delete; word / character counts and reading minutes from the HTML | export (501 `EXPORT_NOT_AVAILABLE`); comment edit / delete / mentions; `public` visibility behaves as `workspace` (no public doc page); version history |
| T2, T10 AI | `POST /projects/ai/write`, `GET ai/line-up`, `ai/standup`, `POST ai/reminders/suggest`, `GET ai/at-risk`, `POST ai/assign/suggest`, `GET ai/dependency-risk`, `POST ai/doc-suggest`, `GET ai/related`, `POST ai/comment-suggest`, `GET ai/extension-suggestions`, `ai/search`, `ai/workload`, `ai/summary` | `projects.ai.generate` | request / response schemas; 503 `AI_UNAVAILABLE` (`app.core.ai`) | every model call (a configured provider answers 501 `AI_NOT_IMPLEMENTED`); server jobs #7, #10, #13 |
| T3 Notepad | `GET/POST /projects/notes`, `PUT/DELETE /notes/{id}`, `PATCH .../archive`, `GET .../history`, `POST .../convert` | `projects.workspaces.view` (own notes); convert also `projects.tasks.create` / `projects.docs.create` | per sign-in; a version per save; convert to task (title, text) or doc (HTML), original delete / archive / keep, one transaction | rich content beyond HTML; restoring an old version |
| T4 Reminder delivery | procedure `pm.usp_reminder_deliver_due`, `projects_collab_service.deliver_due_reminders(db, company_id=None, now=None) -> int` | none (job) | due = `remind_at - notify_before_minutes` passed in the company's local time; inbox notification `projects.reminder` (entity `task` / `list` / `workspace`, app link) to the assignee (else owner), then `notified_at`; claimed with the row version so overlapping runs do not send twice | wiring into a scheduler; recurring and "adaptive" reminders; doc reminders |
| T5 Overdue | `GET/PUT /projects/workspaces/{id}/settings/overdue`; `TaskOut/TaskRowOut.storyPointsPenalty`, `storyPointsEffective`, `latestExtension` | view `projects.workspaces.view`; save `projects.workspaces.edit` + workspace HR / admin | penalty rule above; `maxExtensions` enforced on extension requests | freezing the penalty at closing; penalty in reports |
| T6 Public share page | `GET /api/public/shares/{token}`, `GET /api/public/shares/{token}/tasks/{taskId}` | none (token) | only `isPublic` links; 404 `SHARE_NOT_FOUND`, 410 `SHARE_EXPIRED` (also before `validFrom`), 410 `SHARE_EXHAUSTED`; each page or task opened counts one access (`share_access`); properties filter the fields; entity `task_list` shows as `list`, `workspace` as `view` | rate limiting; invitation emails; a page per share scope (`page` vs `list`) |
| T7 Recents, dashboards | `GET/POST /projects/recents`, `GET /projects/dashboard/home`, `GET /projects/workspaces/{id}/dashboard`, `GET /projects/folders/{id}/dashboard` | recents `projects.workspaces.view`; dashboards `projects.tasks.view` | newest 50 recents per person, items no longer reachable drop out; dashboards per the spec (weeks start Sunday, UTC dates), private columns hidden in My Work | the screens still compute most figures themselves; dates in company time |
| T8 Location fields | custom field type `location`, value `{address, lat, lng}`; `GET .../tasks?hasLocation=true` | as custom fields / tasks | validated in Python and in the procedure | Map view itself; geocoding |
| T9 External storage | `GET /api/integrations/storage`, `POST .../{provider}/connect`, `GET .../{provider}/callback`, `DELETE .../{provider}`, `GET .../{provider}/files`; `POST /projects/tasks/{taskId}/attachments/link` | `projects.storage.view/create/delete`; link `projects.tasks.edit` | four providers listed as not connected; connect / callback / files 503 `STORAGE_NOT_CONFIGURED`; disconnect a no-op 204; link attachments stored (`task_external_file`, id `link-<n>`, `fileId` null, `url` = provider address) and listed / counted / deleted with the task's files | OAuth apps, a per-user connection table (tokens encrypted), file browsing, checking a link against the connection; the router `app/routers/integrations_storage.py` is not registered in `app/main.py` yet |
| T11 Personal List | `GET/POST /projects/personal-list`, `PATCH/DELETE /projects/personal-list/{id}` | `projects.workspaces.view` (own items) | per sign-in, open items first, 120 characters, 409 on a stale row version, 500 items at most | none |

