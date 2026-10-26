## 5. Attendance [att]

All date-times in this module (punched_at, expected_in, first_in, out_at ...) are local wall-clock time in the
company's time zone, like sch.schedule.start_at: devices report local time and the time sheet is read in local time.

```
device                                biometric machine (ATT-1 to ATT-3); fingerprints stay on the device (NFR-10)
  id                PK
  company_id        FK company
  code                                MCH-00001, from core.number_sequence prefix MCH-
  name
  UNIQUE (company_id, name)
  model, serial_no, ip_address
  port              {INT}
  branch_id         FK branch         optional: where the machine stands
  address                             where the machine stands, as text
  status            {NN}              active, inactive
  last_synced_at                      last time punches arrived from it

device_enrolment                      an employee's user number on a machine
  device_id FK device, employee_id FK employee, device_user_no {NN}
  UNIQUE (device_id, device_user_no)

geo_fence                             where web and mobile punches are allowed (ATT-6); Scheduling offers the ones marked for shifts
  id                PK
  company_id        FK company
  code                                GF-00001, from core.number_sequence prefix GF-
  name
  UNIQUE (company_id, name)
  shape             {NN}              circle, polygon
  center_lat, center_lng, radius_m    circle
  polygon_points                      polygon: JSON list of lat and lng points, at least 3
  applies_to_all                      on: everyone; off: the employees the targets select
  joining_from_date, joining_to_date  optional target: employees who joined in this range
  is_for_shift                        "For Shift": offered when scheduling shifts
  is_active

geo_fence_target                      who the fence applies to: one value per row; rows of one type are OR, types are AND
  id                PK
  geo_fence_id      FK geo_fence
  target_type       {NN}              employee, country, location, branch, area, department, designation, grade, job_title, religion, nationality
  target_id                           the id, for every type except religion and nationality
  target_value                        religion, nationality

ip_restriction                        addresses web and mobile punches must come from (ATT-6)
  id                PK
  company_id        FK company
  code                                IPR-00001, from core.number_sequence prefix IPR-
  ipv4, ipv6                          an address, or a network such as 192.168.2.38/31
  netmask                             subnet mask for ipv4, e.g. 255.255.255.0
  range_start, range_end              or a range of addresses
  applies_to_all                      on: everyone; off: the employees the targets select
  is_active

ip_restriction_target                 who the restriction applies to; same rules as geo_fence_target
  id                PK
  ip_restriction_id FK ip_restriction
  target_type       {NN}              employee, country, location, branch, area, department, designation, grade, job_title, religion, nationality
  target_id
  target_value

punch                                 every raw clock event
  id                PK
  company_id        FK company
  employee_id       FK employee
  punched_at                          local wall-clock time
  punch_type                          check_in, check_out, break_out, break_in
  UNIQUE (employee_id, punched_at, punch_type)
  break_type_id     FK break_type
  source                              biometric, mobile, web, manual, import_file, punch_request
  device_id         FK device
  latitude, longitude, ip_address
  photo_file_id     FK stored_file    "Take Picture For Attendance For Dashboard"
  request_id        FK request        when it came from an approved punch request
  remarks
  is_manually_updated                 a manual or imported punch changed after it was entered
  is_ignored                          left out of the time sheet (a device punch cannot be edited, only ignored)

timesheet_day                         computed result for one employee, one day
  id                PK
  company_id        FK company
  employee_id       FK employee
  work_date
  schedule_id       FK schedule       the first shift of the day; several shifts are one day from first start to last end
  expected_in, expected_out
  expected_minutes                    planned minutes of the day's shifts
  first_in, last_out
  worked_minutes, break_minutes, shift_worked_minutes
  late_minutes, early_left_minutes
  overtime_before_minutes, overtime_after_minutes
  approved_overtime_minutes           from approved overtime requests, or the computed overtime when approval is not required
  grace_consumed_minutes
  day_status        {NN}              present, absent, holiday, weekend, rest_day, leave, half_day, short_day, wfh, official_visit, sandwich, yet_to_start
  marked_status                       what HR marked on the day: absent, half_day, short_day
  leave_request_id  FK request        the approved leave covering the day
  is_manually_updated                 HR edited the day; processing keeps the edited times unless told to overwrite
  comments
  processed_at
  is_frozen                           locked once payroll has used it; processing and edits leave it alone

timesheet_flag                        several per day: late, early, grace, overtime, missing_punch, relaxation, official_visit, half_leave, short_leave
  id PK, timesheet_day_id FK timesheet_day, flag {NN}, minutes

timesheet_break                       breaks taken on the day, from punches or entered by HR
  id PK, timesheet_day_id FK timesheet_day, break_type_id FK break_type, out_at {NN}, in_at, minutes

overtime_policy                       how overtime minutes convert to leave or a day (design: Overtime Policy)
  id                PK
  company_id        FK company
  name
  UNIQUE (company_id, name)
  period            {NN}              daily, monthly
  description
  is_active

overtime_policy_slab
  id                PK
  overtime_policy_id FK overtime_policy
  min_minutes       {NN}
  max_minutes       {NN}
  encashment_type   {NN}              full_day, leave
  leave_type_id     FK leave_type     when encashment_type is leave

```

```
device 1──* punch *──1 employee
device 1──* device_enrolment *──1 employee
employee 1──* timesheet_day 1──* timesheet_flag / timesheet_break
timesheet_day *──1 schedule
geo_fence 1──* geo_fence_target
ip_restriction 1──* ip_restriction_target
overtime_policy 1──* overtime_policy_slab
```
