## 1. Organisation [org]

```
company                               one legal entity; a customer database holds several (e.g. a Pakistani company and a Dubai FZ-LLC)
  id                PK
  name                                organisation name shown in the app (General Settings)
  legal_name                          registered name
  logo_file_id      FK stored_file
  email, phone, website, address      contact details
  country_id        FK country        optional: where the company is registered
  currency                            ISO 4217; PKR for a Pakistani company, AED for a UAE one
  timezone                            IANA name; Asia/Karachi, Asia/Dubai
  date_format                         dd/MM/yyyy, MM/dd/yyyy, yyyy-MM-dd, dd MMM yyyy
  week_start_day                      monday, saturday, sunday
  fiscal_year_start_month             1 to 12; 7 (July) in Pakistan
  is_active
  UNIQUE (name)

country                               ISO 3166-1
  id PK, name, iso_code {CHAR(2)} {NN}
  UNIQUE (iso_code)

state                                 province, emirate or territory; code is the ISO 3166-2 subdivision code
  id PK, country_id FK country, code, name
  UNIQUE (code)

city
  id PK, state_id FK state, name
  UNIQUE (state_id, name)

location
  id                PK
  company_id        FK company
  name, employee_prefix
  description
  latitude, longitude
  UNIQUE (company_id, name)

area                                  part of a location
  id                PK
  company_id        FK company
  location_id       FK location
  name
  description
  UNIQUE (location_id, name)

branch
  id                PK
  company_id        FK company
  location_id       FK location
  area_id           FK area           optional
  name, employee_prefix, description
  manager_id        FK employee
  country_id        FK country
  state_id          FK state
  city_id           FK city
  latitude, longitude
  UNIQUE (company_id, name)

department
  id                PK
  company_id        FK company
  parent_id         FK department     sub-department
  name
  head_id           FK employee       HOD
  UNIQUE (company_id, name)

division
  id PK, company_id FK company, name
  UNIQUE (company_id, name)

cost_center
  id PK, company_id FK company, code, name
  UNIQUE (company_id, name)

designation
  id PK, company_id FK company, name
  UNIQUE (company_id, name)

job_title
  id PK, company_id FK company, name, limit_head_count, max_head_count, description
  UNIQUE (company_id, name)

grade                                 sort_order ranks grades, so a promotion can be told from a demotion
  id PK, company_id FK company, name, sort_order
  UNIQUE (company_id, name)

job_level
  id PK, company_id FK company, name, sort_order
  UNIQUE (company_id, name)

employee_group
  id PK, company_id FK company, name
  UNIQUE (company_id, name)

employment_type                       a new company starts with Permanent, Contractual, Daily Wager, Management Trainee
  id PK, company_id FK company, name
  UNIQUE (company_id, name)
```

```
company     1──* location 1──* area
company     1──* branch   (branch sits in a location, optionally an area)
company     1──* department 1──* department (sub)
country     1──* state 1──* city
```
