## 10. Assets and separation [sep]

Sources: Functional Requirements PDF pp. 143-151 (assets, allocation, asset types, clearance form), pp. 157-165
(end of employment, off-boarding checklist, rehire, checklist set-up), p. 139 (final settlement, payroll),
p. 66 (resignation request); Mini SRS M9 SEP-1..6 and WF4. Allowed codes for enum-like columns are in the
notes; the backend checks them. Decisions: comparison/07-assets-offboarding.md.

```
asset_type                            Assets -> Asset Types
  id PK, company_id FK company, code, name, description, is_active
  UNIQUE (company_id, name)

asset                                 Assets -> Company Assets
  id                PK
  company_id        FK company
  code                                AST-00001
  asset_type_id     FK asset_type
  name
  identification_no                   serial / identification number
  is_taxable
  asset_condition                     old, new, fair (condition when recorded)
  manufacturer, model
  current_value
  acquired_date
  description
  status                              active, damaged, lost, decommissioned; who holds it comes from the open asset_allocation
  file_id           FK stored_file    attachment
  UNIQUE (company_id, identification_no)

asset_allocation                      one row per hand-over; deallocated_on NULL while the employee holds it
  id                PK
  company_id        FK company
  asset_id          FK asset
  employee_id       FK employee {NN}
  allocated_on {NN}
  deallocated_on
  status                              allocated, deallocated
  description
  return_condition                    good, fair, damaged (at deallocation)
  deallocation_remarks {NVARCHAR(500)}
  file_id           FK stored_file
  asset_clearance_id FK asset_clearance   the clearance that closed it, if any

end_of_employment                     End of Employment (All / Pending / Completed)
  id                PK
  company_id        FK company
  employee_id       FK employee
  reason {NN}                         resignation, termination, retirement, other
  resignation_request_id FK request   set when an approved resignation started it
  serve_notice                        the Notice Period tick
  notice_period_days
  last_working_date {NN}              the day it is made when there is no notice period
  needs_final_settlement, needs_asset_clearance
  asset_clear_by_date                 off-boarding checklist "Asset Clear" date
  replacement_id    FK employee
  delegatee_id      FK employee
  description
  file_id           FK stored_file    attachment
  status                              pending, completed
  completed_at
  UNIQUE (resignation_request_id)

asset_clearance                       Asset Clearance Form, one per leaver at a time
  id                PK
  company_id        FK company
  employee_id       FK employee
  end_of_employment_id FK end_of_employment  optional: a form can be made without one
  clearance_date {NN}
  checked_by_id     FK employee
  approved_by_id    FK employee
  approval_date
  file_id           FK stored_file
  status                              in_progress, approved

asset_clearance_item                  one Asset Details block: an allocation being cleared
  id PK, asset_clearance_id FK asset_clearance, asset_allocation_id FK asset_allocation {NN}, condition_at_clearance, reason, return_status, comments
  UNIQUE (asset_clearance_id, asset_allocation_id)

final_settlement                      started by end of employment; payroll fills the payslip and closes it
  id PK, company_id FK company, end_of_employment_id FK end_of_employment, payslip_id FK payslip, status, closed_at
  file_id           FK stored_file    the signed settlement letter, given on Close FS
  UNIQUE (end_of_employment_id)

offboarding_checklist                 Settings -> Off Boarding Checklist (ECL-00001)
  id PK, company_id FK company, code, name, description, is_active
  UNIQUE (company_id, name)

checklist_field                       "Additional Information": number, string, date, boolean
  id PK, offboarding_checklist_id FK offboarding_checklist, name, field_type, is_required, min_value, max_value, min_length, max_length, sort_order
  UNIQUE (offboarding_checklist_id, name)

checklist_answer
  id PK, end_of_employment_id FK end_of_employment, checklist_field_id FK checklist_field {NN}, answer
  UNIQUE (end_of_employment_id, checklist_field_id)
```

Notes:
- condition_at_clearance: good, fair, damaged. return_status: complete, partial, not_returned.
  final_settlement.status: pending, closed.
- Approving a clearance ends each listed allocation on the clearance date; damaged sets the asset to damaged,
  not_returned sets it to lost.
- Completing an end of employment closes the employee's open hr.employment_period (end_date,
  end_of_employment_id) and sets hr.employee.status to left. Rehire adds a new hr.employment_period.

```
asset_type 1──* asset 1──* asset_allocation *──1 employee
employee 1──* end_of_employment
end_of_employment 1──* asset_clearance 1──* asset_clearance_item *──1 asset_allocation
end_of_employment 1──1 final_settlement
end_of_employment 1──* checklist_answer *──1 checklist_field *──1 offboarding_checklist
```
