# 07 Assets and off-boarding: frontend vs documents vs ERD

Status: built (first build). Backend: `app/routers/assets.py` (`/api/assets`, 25 endpoints) and
`app/routers/offboarding.py` (`/api/offboarding`, 14 endpoints); procedures in `db/procedures/sep/`;
tests `tests/test_assets*.py`, `tests/test_offboarding.py`.

Sources: FRD = "Functional Requirements for HRango.pdf" (page numbers of the PDF); FRD-MD =
`requirements/HRango - Functional Requirements Document/02-Payroll/README.md` (and `01-Requests`);
SRS = "HRango - Mini SRS.pdf" (M9 SEP-1..6, WF4); OQ = "HRango - Open Questions.pdf" (E8).
The UI design README `09-Assets-Website-and-Marketing` has no asset or off-boarding screens (only
"Employee Offboarding" illustrations and a brochure listing Offboarding as a module).

## Screens

| Screen / feature | Frontend route | Documents | ERD tables | Decision |
|---|---|---|---|---|
| Asset Types | `/assets/types` | FRD p.148-149 (Code AITP-00002, Name, Description, Active; Edit/View/Delete); FRD-MD row "Asset Type" | sep.asset_type | Build. Code prefix AITP (the FRD example); frontend uses ATP. |
| Company Assets list / create / edit / view / delete | `/assets/company-assets` | FRD p.143-146 (Name, Asset Type, Identification Number, Taxable, Condition Old/New/Fair, Manufacturer, Model, Attachment, Current Value, Acquired Date, Description; Status Active/Damaged/Decommissioned; filters Status, Name, Code, Identification Number, Asset Type); SRS SEP-1 | sep.asset | Build with changes: condition list is old/new/fair (frontend old/new); status adds `lost`; `availability` (available/allocated/unavailable, the frontend's status) is computed from the open allocation. |
| Asset History | History in the row menu | FRD p.145 ("History: complete history of changes ... edits, value adjustments, condition"); SRS NFR-3 | core.audit_log (entity `sep.asset`) | Build: `GET /company-assets/{id}/history`, one row per changed field plus allocate / deallocate / deactivate / activate / clearance actions. |
| Deactivate / Activate | row menu | FRD p.145 (Deactivate when sold, discarded, written off) | sep.asset.status | Build: PATCH deactivate (status decommissioned, refused while allocated) / activate. |
| Asset import (CSV, sample file) | Import File on Company Assets | Not in documents | - | Not in first build: no file format defined. |
| Asset Allocations list / allocate / view | `/assets/allocations` | FRD p.146-148 (Company, Employee, Asset, Identification Number, Allocation Date, Deallocation Date, Status allocated/returned; filters Employees, Asset Type, Is Allocated, Assets, From, To); SRS SEP-2 | sep.asset_allocation | Build. |
| Deallocate | row menu (frontend addition) | SRS SEP-2 "de-allocate ... with dates"; FRD lists Deallocation Date | sep.asset_allocation (deallocated_on, return_condition, deallocation_remarks) | Build: PATCH with date, optional condition good/fair/damaged (damaged marks the asset damaged) and remarks. |
| Asset Clearance Form list / create / edit / view / delete | `/assets/clearance-form` | FRD p.149-152 (Employee ID, Name, Department, Clearance Date, Status Approved / In Progress; per asset Date Allocated, Condition Good/Fair/Damaged, Reason, Return Status Complete/Partial/Not Returned, Comments; Checked By, Clearance Approved By, Approval Date, Attachment); SRS SEP-3, WF4 step 4 | sep.asset_clearance, sep.asset_clearance_item | Build. Status codes `in_progress` / `approved` (FRD wording; frontend "Pending by HR"). Prefill endpoint gives the leaver's open allocations. |
| Clearance bulk Approve / Unapprove | list buttons | FRD p.151 ("Approve All", "Unapproved All" on selected rows) | same | Build: PATCH `/clearance-forms/approve` and `/unapprove` with `{forms: [{id, rowVersion}]}`, all or nothing. |
| End of Employment All / Pending / Completed | `/end-of-employment/all`, `/pending`, `/completed` | FRD p.157-161 (Employee, Branch, Location, Department, Designation, Date, Creation Date, Completion Date, Status Pending/Completed; filters Location, Branch, Department, Employee, Designation, Status, Notice Period, From/To); SRS SEP-4 | sep.end_of_employment | Build: one list with `?status=pending|completed`, filtered by `auth.fn_visible_employees`. |
| End of Employment create / edit / view / delete | dialog | FRD p.158-161 (Employee, Reason, Notice Period tick then Last Working Date, Final Settlement tick, Asset Clearance tick, Attachment, Description, Delegatee / Replacement) | sep.end_of_employment, sep.final_settlement | Build. Reasons resignation / termination / retirement / other (frontend adds transfer: not in documents, left out). |
| End of Employment Import File | list button | FRD p.158 ("batch-processing ... by uploading a file") | - | Not in first build: no file layout defined. |
| "Retire" action | - | FRD p.161 ("Retire: Marks the employee as retired") | - | Covered by reason `retirement`; no separate action. |
| Off-boarding Checklist tab (per employee) | Checklist tab of the dialog | FRD p.162 (employee details, "Asset Clear" date, Save/Cancel) | sep.checklist_answer, sep.end_of_employment.asset_clear_by_date | Build: `PUT /end-of-employment/{id}/checklist` (answers checked by type and range), `GET /end-of-employment/checklist-fields`. The FRD's fixed "Asset Clear" date is a column (`assetClearByDate`); the frontend models it as a checklist field. |
| Completion | automatic in the frontend | Not stated (FRD p.157 "Completion Date"; FRD-MD "which step creates the next ... is not stated") | sep.fn_end_of_employment_waiting | Build: completes automatically when nothing is waiting, plus `PATCH /{id}/complete` that answers 409 with what it waits for. |
| Rehire | row menu on completed | FRD p.162-163 (Employee, Last Working Day read-only, Joining Date; everything else kept); SRS SEP-6 | hr.employment_period (new row) | Build: `PATCH /{id}/rehire`. |
| Settings -> Off Boarding Checklist list / create / edit / view | `/settings/off-boarding/checklist` | FRD p.163-165 (Code ECL-00001, Name, Status, Description; Additional Information fields: Name, Type Number/String/Date/Boolean, Required, Min/Max for numbers) | sep.offboarding_checklist, sep.checklist_field | Build: fields saved with the checklist (JSON). String fields also get min/max length (frontend; FRD silent; ERD already had the columns). Delete added (frontend has only field deletion; refused once answered). |
| Final Settlement list / view payslip / recalculate / close | Payroll screens | FRD p.139 (Payroll section); SRS SEP-5 | sep.final_settlement (+ pay.payslip) | Not built here: payroll owns the screens and the calculation. This module creates the pending `sep.final_settlement` row and completes the leaving chain when payroll closes it. |
| Resignation request -> End of Employment | Requests (frontend: "Approval adds a pending End of Employment record") | FRD p.66 (resignation request); FRD-MD 01-Requests (on approval: Notice Period, Last Working Date, Remarks); SRS WF4 steps 1-3; OQ E8 | req.req_resignation -> sep.end_of_employment | Build: `sep.usp_request_apply_resignation` and `sep.usp_request_revert_resignation`. |

## Gaps both ways

- In the frontend, not in the documents: asset import CSV, the `transfer` reason, the
  available / allocated / unavailable asset status (kept as the computed `availability`), Deallocate
  as a menu action (kept: SRS asks for de-allocation), clearance "Unapproved" undoing approval
  effects (kept), automatic completion (kept), the employee card's age / experience (the API gives
  date of birth and joining date; the screen computes).
- In the documents, not in the frontend: condition `fair` on assets; status `damaged` /
  `decommissioned` on assets; asset type code AITP; the fixed "Asset Clear" date; Replacement as well
  as Delegatee (both kept as columns); filter on asset Company (one company per session, so not a
  filter); EOE "Import File" and "Retire" (see table).
- Neither defines the "Reason for Clearance" options; it is free text.

## ERD changes (erd/source/10-sep.md)

- `company_id` added to `asset_allocation`, `end_of_employment`, `asset_clearance`, `final_settlement`
  (every query filters on company; these were reachable only through joins).
- `asset`: `description` (FRD field), status values documented (active, damaged, lost,
  decommissioned); `UNIQUE (company_id, identification_no)`.
- `asset_allocation`: `employee_id`, `allocated_on` NOT NULL; `return_condition`,
  `deallocation_remarks` (condition at hand-back); `asset_clearance_id` (the clearance that closed it,
  so Unapprove can reopen exactly those).
- `end_of_employment`: `reason` NOT NULL, `last_working_date` NOT NULL, `asset_clear_by_date`
  (FRD "Asset Clear"), `file_id` (Attachment); `UNIQUE (resignation_request_id)`.
- `asset_clearance`: `approved_at` replaced by `approval_date` (a date in the FRD), `file_id`;
  `end_of_employment_id` optional (the FRD creates forms from the Assets menu too); `clearance_date`
  NOT NULL. `asset_clearance_item`: `UNIQUE (asset_clearance_id, asset_allocation_id)`.
- `final_settlement`: `UNIQUE (end_of_employment_id)`; status pending / closed.
- `offboarding_checklist`: `UNIQUE (company_id, name)`; `checklist_field`: `sort_order`,
  `UNIQUE (offboarding_checklist_id, name)`; `checklist_answer`: `UNIQUE (end_of_employment_id,
  checklist_field_id)`.

## Decisions on unclear points

1. E8 (does an approved resignation start the leaving chain?): yes. The effect creates a pending end
   of employment (reason resignation, Final Settlement and Asset Clearance ticked, notice and last
   working date from the request; last working date falls back to resignation date + notice days,
   then the resignation date) and a pending final settlement. If HR already made a pending record for
   the person, the request is linked to it instead; a second resignation while one is linked blocks
   the approval (409). Applying twice is a no-op.
2. Cancelling an approved resignation (`usp_request_revert_resignation`): removes the record while
   nobody has worked on it (no clearance form, no answers, settlement untouched); otherwise unlinks it
   and leaves it with HR. A completed record blocks the cancellation.
3. Completion waits for: Final Settlement closed (if ticked), an approved clearance and no assets
   still allocated (if Asset Clearance ticked), required answers of active checklists, and the last
   working date reached. On completion the employee's status becomes `left` and the open
   `hr.employment_period` gets `end_date` and `end_of_employment_id`. A completed record cannot be
   edited, deleted, or have its clearance unapproved.
4. Without a notice period the last working date is the day the record is made (frontend; FRD shows
   the date only with Notice Period).
5. Rehire: only from the employee's latest completed record, joining date after the last working
   date; adds an `hr.employment_period` and sets the employee `active`. Nothing else changes (FRD).
6. Clearance approval ends each listed allocation on the clearance date with the condition at
   clearance; `damaged` marks the asset damaged, `not_returned` marks it lost. One in-progress form
   per employee; an approved form is read-only until unapproved. A form made without an end of
   employment links itself to the employee's pending one.
7. Self rule: nobody creates, edits, deletes or completes their own end of employment, or creates or
   approves their own clearance form (403), whatever their role.
8. Company-level records (asset types, company assets, checklist settings) are refused to a caller
   who holds the code with own scope only: the Employee role gets `*.view` / `*.create` with own
   scope by pattern, which must not let staff add company assets. Allocating is the `assign` action,
   so the Employee role sees the assets it holds but cannot allocate. Rehire is
   `offboarding.rehire.process`, so only HR roles get it by default.
9. Attachments are `fileId` references to `core.stored_file`; uploading is the shared file
   service's job (not built here).
10. Codes AITP-, AST-, ECL- come from `core.number_sequence` through `sep.usp_number_next`.
11. **Unapprove after reallocation** is refused only when the asset was allocated again *after* the allocation the
    form closed (`o.id > al.id`), not for an earlier allocation on the same date.
12. Bulk approve / unapprove name the body field `forms` in their errors (`fieldErrors.forms`).
13. Deleting an asset type that assets use: 409 `ASSET_TYPE_IN_USE` (field `id`), "deactivate the type instead".

## Permission codes

assets.types.{view,create,edit,delete,export}; assets.company_assets.{view,create,edit,delete,export};
assets.allocations.{view,assign,export}; assets.clearance.{view,create,edit,delete,approve,export};
offboarding.end_of_employment.{view,create,edit,delete,export}; offboarding.rehire.process;
offboarding.settings.checklist.{view,create,edit,delete,export}. Export has no endpoint yet.

## Cross-module needs

- Payroll: Close FS sets `sep.final_settlement.status = 'closed'`, `closed_at`, and `payslip_id` when
  it makes the payslip, then calls `EXEC sep.usp_end_of_employment_try_complete @company_id,
  @actor_user_id, @id = <end_of_employment_id>` in the same transaction. Its Final Settlement list
  can read `sep.final_settlement` joined to `sep.end_of_employment` (reason, last working date,
  resignation request).
- Requests: call `sep.usp_request_apply_resignation` on final approval and
  `sep.usp_request_revert_resignation` on an approved cancellation (both return no result set).
  They read `req.request.employee_id`, `reason` and `req.req_resignation.resignation_date`,
  `last_working_date`, `notice_period_days`, `serve_notice`; please keep those names. The approver's
  Notice Period / Last Working Date (FRD-MD 01-Requests) should be written to `req_resignation`
  before the effect runs.
- Organisation / employees: `hr.employee.status` values `active` and `left` and
  `hr.employment_period` (joining_date, end_date, end_of_employment_id) are written here.
  Employees joining should create the first `hr.employment_period`, so the card shows a joining date.
- Shared: a core `usp_number_next` for every module would replace `sep.usp_number_next`; the
  default Employee role pattern (`*.create` own) reaches company-level screens in every module
  (handled here in the service).
