# Files and events: attendance, assets, offboarding, payroll, manpower, benefits, projects, leaves, warning

State on 26 Oct 2026. These modules now take real uploaded files and publish events and notifications
through the shared services (backend README, "Files" and "Events, notifications and webhooks").
Scheduling and roster hold no files and gained no events (nothing in them needs to reach people beyond
the screens; the requests engine already announces rest-day and shift-swap decisions).

## The rules every module here follows

- **Upload first, then send the id.** `POST /api/files` (multipart `file`, `module` = the module key,
  e.g. `payroll`) returns `{id, name, url, ...}`. Forms send that id (`fileId`, `photoFileId`, `jdFileId`,
  `documentFileId`, `fileIds`). Procedures accept only this company's uploads (`core.fn_file_usable`);
  anything else is `422` with the field named (`fieldErrors.fileId: "The file was not found. Upload it
  again."`). No module procedure inserts or deletes `core.stored_file` rows any more.
- **Outputs give a FileRef.** Where a record has a file, the response keeps the id column and adds an
  object `{id, name, url}`; `url` is a signed download link that expires (open it with a plain `<a href>`
  or `<img src>`, no Authorization header). Fetch the record again for a fresh link. Old `fileName` /
  `jdFileName` columns are replaced by the object's `name`.
- **Attachments** (`core.attachment`) now carry `company_id`. Removing an attachment does not delete the
  file: the uploader can delete it through `DELETE /api/files/{id}` once nothing uses it.
- **Events** are published in the same transaction as the change (`core.usp_event_publish`), so a
  webhook only ever hears about committed work. Each notification to a person is also the
  `notification.created` event. Listed per module in `backend/app/catalogue/<module>.py` (`EVENTS`).

## Per module: inputs and outputs (old shape -> new shape)

### Attendance

| Where | Old | New |
|---|---|---|
| `POST /api/attendance/clock` body | `photoFileId` checked only for existence (any company's id passed) | `photoFileId`: an upload of this company (module `attendance`); else 422 `photoFileId` |
| Punch (`/logs`, `/logs/{id}`, clock response, time-sheet day `punches[]`) | `photoFileId` | `photoFileId` + `photo: {id, name, url}` (null when no photo) |

Events: `attendance.timesheet_processed` - one summary per run: the Process button (`trigger: manual`) or
the nightly job (`trigger: scheduled`, only when days were processed). Payload: `fromDate`, `toDate`,
`processedDays`, `employees`, `overwriteManual`, `processedBy`. Re-processing after a punch, a day edit
or a request approval is not announced (no per-day noise).

### Warning

No files. Event `warning.issued`: when raising warnings (Process on the warnings list, or attendance
processing) creates warnings that did not exist before (same rule, same day), one event per employee per
run lists them (`employeeId`, `warnings`, `items[{id, workDate, warningPolicyRuleId, deduction,
penaltyPercentage}]`), and the employee gets one notification ("You received 2 attendance warnings",
link `/attendance/time-sheet`). Re-running the same days issues nothing again.
Internal change: `att.usp_warning_raise` takes `@quiet = 1` and is called with a plain `EXEC` from
`att.usp_timesheet_process` (it used `INSERT ... EXEC`, which cannot wrap a procedure that notifies).

### Leaves

No file columns (leave attachments live on the request, owned by the requests module). Event
`leaves.balance_adjusted` on `POST /api/leaves/ledger` (opening balance or adjustment): `ledgerEntryId`,
`employeeId`, `leaveTypeId`, `leaveTypeTitle`, `fiscalYear`, `entryDate`, `days`, `reason`, `remarks`,
`adjustedBy`. The employee is notified ("Your Annual Leave balance was increased by 1.5 days", body =
remarks, link `/leaves/my-leaves`).

### Assets

| Where | Old | New |
|---|---|---|
| Company asset `POST/PUT /company-assets` | `fileId` (any id) | `fileId` of this company's upload |
| Company asset out (list, get) | `fileId` | `fileId` + `file: {id, name, url}` |
| Allocation `POST /allocations` | `fileId` (any id) | `fileId` of this company's upload |
| Allocation out (list, get, allocate, deallocate) | `fileId` | `fileId` + `file` |
| Clearance form `POST/PUT /clearance-forms` | `fileId` (any id) | `fileId` of this company's upload |
| Clearance form out (get, save) | `fileId` | `fileId` + `file` (the list rows carry no file) |

Events: `assets.allocated` and `assets.returned` (Deallocate) with the allocation, asset and employee;
the employee is notified ("An asset was handed to you: Laptop (AST-00012)" / "Asset return recorded:
...", link `/assets/allocations`). `assets.clearance_approved` per approved form with its items (asset,
condition, return status); no notification (the person is leaving).

### Offboarding

| Where | Old | New |
|---|---|---|
| End of employment `POST/PUT` | `fileId` (any id) | `fileId` of this company's upload |
| End of employment out (get, save, checklist, complete, rehire) | `fileId`, `photoFileId` | `fileId` + `file`, `photoFileId` + `photoUrl` |

Events: `offboarding.started` (HR saves a new record, or an approved resignation starts one; the
delegatee is notified "You will take over the work of ..."), `offboarding.completed` (with
`employees.deactivated`, change `left`, from `hr.usp_employee_event_publish`), `offboarding.rehired`
(with `employees.reactivated`, change `rehire`).

### Payroll

| Where | Old | New |
|---|---|---|
| Tax rebate `POST/PUT /tax-rebates` | `fileId` (any id) | `fileId` of this company's upload |
| Tax rebate out | `fileId`, `fileName` | `fileId`, `file: {id, name, url}` (`fileName` removed) |
| Voucher `POST/PUT /vouchers` | `fileId` (any id) | `fileId` of this company's upload |
| Voucher out | `fileId`, `fileName` | `fileId`, `file` (`fileName` removed) |
| Final settlement close `POST /final-settlements/{id}/close` | `{rowVersion}` | `{rowVersion, fileId?}`: the signed settlement letter (new column `sep.final_settlement.file_id`) |
| Final settlement out | no file | `fileId`, `file` |
| Imports `POST /opening-balances/import`, `/employee-accounts/import`, `/salary-revisions/import` | `{rows: [...]}` (at least one) | `{rows: [...]}` **or** `{fileId}`: an uploaded `.csv` whose first line names the columns, as `Employee Code, Pay Item, Month, Amount, Taxable, Description` or `employeeCode, payItem, ...`. Row numbers in `errors` count data lines from 1; rows that do not parse are reported (`Row 3: effective_date: Input should be a valid date ...`) and the rest are imported. Other file types: 422 `fileId` ("Save the sheet as CSV"). Neither or both: 422. |

Events: `payroll.closed` (run id, code, name, kind, month or work date, payslips, `payslipsReleased`,
`payslipsOnHold`, totals, `closedBy`); each employee whose payslip is released is notified ("Your payslip
for July 2026 is ready", or "Your daily wage slip for ... is ready", link `/payroll/pay-slips/my`). A slip
released later (paid before the close, or taken off hold after it) notifies its employee then; nobody is
told twice. `payroll.voucher_decided` (approve, reject, verify; the employee is notified "Your voucher
VCH-... was approved / rejected / verified for payment", link `/payroll/vouchers/employee`).
`payroll.final_settlement_closed` (settlement, payslip, totals; the employee is notified "Your final
settlement payslip is ready").

### Manpower

| Where | Old | New |
|---|---|---|
| Open position `PUT /open-positions/{id}` | `jdFileId` (any id) | `jdFileId` of this company's upload |
| Open position out | `jdFileId`, `jdFileName` | `jdFileId`, `jdFile: {id, name, url}` (`jdFileName` removed) |
| `GET /open-positions/{id}/jd` | `{id, name, mimeType, sizeBytes, createdAt}` | the same + `url` |
| Plan `POST/PUT /plans` | no files | `fileIds: [id, ...]` (up to 20; the list replaces the plan's files; omit to keep them) |
| Plan detail out | no files | `files: [{attachmentId, id, name, mimeType, sizeBytes, createdAt, url}]` |

Events: `manpower.budget_decided` (status, amount, positions, remarks, `openPositions` released; whoever
submitted the budget is notified "Budget approved: ..." / "Budget rejected: ...", link
`/manpower-planning/e-budgeting`, unless they decided it themselves). `manpower.position_opened` per
open position released by an approval, and again on Reopen (`reopened: true`); `manpower.position_closed`
on Close. Recruitment can subscribe to both.

### Benefits

| Where | Old | New |
|---|---|---|
| Plan files `POST /plans/{id}/files` | `fileId` (any id) | `fileId` of this company's upload |
| Plan file out (`/files`, add) | `fileId`, `fileName`, ... | the same + `file: {id, name, url}` |
| Health benefit `POST/PUT /health-benefits` | no document | `documentFileId` (policy or insurance card; new column `ben.health_benefit.document_file_id`) |
| Health benefit out | no document | `documentFileId`, `documentFile: {id, name, url}` |

Event: `benefits.election_decided` (status, plan year, plans chosen, remarks); the employee is notified
("Your benefit choices for 2027 were approved", link `/benefits/employees`).

### Projects

| Where | Old | New |
|---|---|---|
| `POST /tasks/{id}/attachments` | `{name, mimeType, sizeBytes}` (a file name only; the procedure made a `stored_file` row) | `{fileId}`: an upload (PDF, DOCX, XLSX, PNG, JPG; up to 10 MB, checked on the stored file); 409 `FILE_DUPLICATE` if already attached |
| Attachment out | `id, taskId, fileId, name, mimeType, sizeBytes, uploadedBy...` | the same + `url`; `uploadedBy*` is who attached it |
| `DELETE /attachments/{id}` | also deleted the file row | removes the attachment only |
| New `PUT /workspaces/{id}/cover` | - | `{fileId \| null, rowVersion}`: banner image (PNG, JPG, GIF, WEBP); workspace admins and HR |
| New `PUT /tasks/{id}/cover` | - | `{fileId \| null, rowVersion}`: cover image; team leaders and above, or the creator |
| Workspace out (list and get) | no cover | `coverFileId`, `cover: {id, name, url}` |
| Task out (List view rows and task) | no cover | `coverFileId`, `cover` |
| People picker (`/people`) | `photoFileId` | `photoFileId` + `photoUrl` |

Events: `projects.task_assigned` (on create with assignees, and on Assignees for people newly added;
each is notified "Task assigned to you: HR000000012 Write the brief", link
`/project-management/workspaces/<id>?task=<id>`; whoever assigns themselves is not notified).
`projects.comment_mention` (a new comment's mentions, or people an edit newly mentions; each is notified
"<author> mentioned you on <task code>" with an excerpt).

## ERD changes (file columns only)

- `10-sep.md`: `final_settlement.file_id FK stored_file` (the signed settlement letter, given on Close FS).
- `17-ben.md`: `health_benefit.document_file_id FK stored_file` (policy document or insurance card).
- Plan files use `core.attachment` (entity_type `mp.manpower_plan`); task attachments stay on
  `core.attachment` (entity_type `pm.task`); covers use the existing `cover_file_id` columns.

## Left for later

- A clean-up job for files nothing uses any more (detached task attachments, replaced JDs and covers).
  Today the uploader deletes them through `/api/files`; a core job could sweep old unreferenced uploads.
- Asset and end-of-employment "Import File" stay out (no file layout defined, as before).
- The position import (Manpower, "Upload Excel") still takes rows read by the client; it can take a CSV
  `fileId` the same way as the payroll imports when the layout is agreed.
