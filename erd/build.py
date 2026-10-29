"""Build the SQL Server ERD from erd/source/*.md.

Writes:
  ../HRango - ERD.md       typed, per module, ready for review
  ../HRango - ERD.drawio   one draw.io page per module
  ../backend/db/migrations/0001_baseline.sql   the tables as SQL Server DDL

Run:  python erd/build.py
      python erd/build.py --sql-out <file>   only the SQL, to your own file
"""
import re
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

HERE = Path(__file__).resolve().parent
SRC_DIR = HERE / "source"   # one file per module, read in name order
OUT_MD = HERE.parent / "HRango - ERD.md"
OUT_DRAWIO = HERE.parent / "HRango - ERD.drawio"
OUT_SQL = HERE.parent / "backend" / "db" / "migrations" / "0001_baseline.sql"

BACKEND_MODULE = {
    "org": "organisation", "hr": "employees", "auth": "access", "sch": "scheduling", "att": "attendance",
    "lv": "leave", "req": "requests", "loan": "loans", "pay": "payroll", "sep": "separation",
    "rec": "recruitment", "mp": "manpower", "core": "core", "eng": "engagement", "pm": "projects",
    "ben": "benefits", "perf": "performance", "trn": "training", "frm": "forms",
}

# ---------------------------------------------------------------- parsing

def split_top(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        depth += ch == "("
        depth -= ch == ")"
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return [p.strip() for p in out if p.strip()]


# Only upper-case SQL types and NN / NULL count as markers, so a note like {"lat","lng"} stays a note.
_TOKEN = r"(?:NN|NULL|[A-Z][A-Z0-9]*(?:\((?:\d+(?:,\d+)?|MAX)\))?)"
DIRECTIVE = re.compile(r"\{(" + _TOKEN + r"(?:\s+" + _TOKEN + r")*)\}")


def directives(text):
    """Pull {TYPE}, {NN} and {NULL} markers out of a column's text: (text, type, not_null)."""
    typ, nn = None, None
    for d in DIRECTIVE.findall(text):
        for tok in d.split():
            if tok == "NN":
                nn = True
            elif tok == "NULL":
                nn = False
            else:
                typ = tok
    return DIRECTIVE.sub("", text), typ, nn


def parse_item(item):
    item = re.sub(r"\s*\(.*?\)", "", item).strip()
    m = re.match(r"^(\w+)\s+(PK/FK|PK|FK)\s*(\w+)?$", item)
    if m:
        return {"name": m.group(1), "key": m.group(2), "ref": m.group(3), "note": ""}
    return {"name": item.split()[0], "key": None, "ref": None, "note": ""}


def add_cols(tbl, text):
    m = re.match(r"^(UNIQUE|INDEX)\s*\((.+)\)\s*$", text)
    if m:
        cols = tuple(x.strip() for x in m.group(2).split(","))
        tbl["extra_uniques" if m.group(1) == "UNIQUE" else "extra_indexes"].append(cols)
        return
    first = re.split(r"\s{2,}", text, maxsplit=1)
    head, tail = first[0], (first[1] if len(first) > 1 else "")
    if "," in head or re.search(r"\b(PK|FK)\b", head):
        for item in split_top(head):
            item, typ, nn = directives(item)
            col = parse_item(item)
            col["type_override"], col["nn_override"] = typ, nn
            tbl["cols"].append(col)
        return
    text, typ, nn = directives(text)
    first = re.split(r"\s{2,}", text.strip(), maxsplit=1)
    head, tail = first[0].strip(), (first[1] if len(first) > 1 else "")
    m = re.match(r"^(PK/FK|PK|FK)\s*(\w+)?\s*(.*)$", tail)
    if m:
        col = {"name": head, "key": m.group(1), "ref": m.group(2), "note": m.group(3).strip()}
    else:
        col = {"name": head, "key": None, "ref": None, "note": tail.strip()}
    col["type_override"], col["nn_override"] = typ, nn
    tbl["cols"].append(col)


REL_LINE = re.compile(r"^\S+(?:\s+/\s+\S+)*\s+[1*]?──")


def parse():
    modules, tables = [], {}
    mod = tbl = None
    in_code = False
    text = "\n".join(f.read_text(encoding="utf-8") for f in sorted(SRC_DIR.glob("*.md")))
    for raw in text.splitlines():
        h = re.match(r"^## (\d+)\. (.+?) \[(\w+)\]$", raw)
        if h:
            mod = {"no": h.group(1), "title": h.group(2), "schema": h.group(3), "tables": [], "rels": []}
            modules.append(mod)
            continue
        if raw.startswith("```"):
            in_code, tbl = not in_code, None
            continue
        if not in_code or mod is None or not raw.strip():
            continue
        # A relationship line starts with a table name and then its cardinality: "a 1──* b", "a ──> b".
        # A "──" later in a table's note does not make it one.
        if not raw.startswith(" ") and REL_LINE.match(raw):
            mod["rels"].append(raw.strip())
            tbl = None
            continue
        if not raw.startswith(" "):
            parts = re.split(r"\s{2,}", raw.strip(), maxsplit=1)
            name, rest = parts[0], (parts[1] if len(parts) > 1 else "")
            if name in tables:
                raise SystemExit(f"table {name} is defined twice")
            tbl = {"name": name, "schema": mod["schema"], "cols": [], "note": "", "extra_uniques": [], "extra_indexes": []}
            mod["tables"].append(tbl)
            tables[name] = tbl
            if re.search(r"\b(PK|FK)\b", rest):
                body, _, note = rest.partition("     ")
                add_cols(tbl, body.strip())
                tbl["note"] = note.strip()
            else:
                tbl["note"] = rest.strip()
            continue
        if tbl is not None and len(raw) - len(raw.lstrip()) < 30:
            add_cols(tbl, raw.strip())
    return modules, tables

# ---------------------------------------------------------------- types

BOOL = {"limit_head_count", "full_overtime", "short_overtime", "attendance_exempt", "applies_to_all",
        "sandwich_across_types", "attachment_required", "carry_forward", "pro_rated", "allowed_in_probation",
        "guarantor_required", "non_payable", "tax_applicable", "arrear_applicable", "final_settlement",
        "calculate_only", "serve_notice", "stay_required", "advance_required", "skipped", "auto_allotment",
        "auto_balance_on_joining", "show_in_payslip", "for_integration", "needs_final_settlement",
        "needs_asset_clearance"}
DATE = {"date_of_birth", "from_date", "to_date", "posted_on", "apply_by", "close_on", "allocated_on",
        "deallocated_on", "applied_on", "closes_on", "publish_from", "publish_to", "known_since"}
MONTH = {"payroll_month", "payslip_month", "start_month", "due_month", "balance_month", "entry_month",
         "applicable_month"}
DAYS_FRACTION = {("leave_ledger", "days"), ("req_leave", "days"), ("leave_encashment_employee", "days"),
                 ("payslip", "worked_days"), ("payslip", "leave_days"), ("payslip", "absent_days"),
                 ("leave_type", "encashment_min"), ("leave_type", "encashment_max")}
INT = {"minutes", "step_no", "sort_order", "installments", "headcount", "vacancies", "nights", "max_access",
       "access_count", "after_count", "occurrence_count", "max_applications", "next_number", "total_positions",
       "approved_positions", "max_head_count", "radius_m", "story_points", "step", "fixed_days", "min_months",
       "max_months", "tenure", "min_length", "max_length", "fiscal_year_start_month", "repeat_every_weeks"}
MONEY_WORDS = ("amount", "salary", "cost", "gross", "net_payable", "total_earnings", "total_deductions",
               "total_reimbursements", "principal", "employer_contribution", "current_value", "total_allowance",
               "annual_gross", "amount_per_leave")
MONEY = {"credit", "debit", "change_value", "surcharge_value", "reward_value", "slab_value"}
TEXT_MAX = {"description", "body", "expression", "eligibility_expression", "comments", "notes", "remarks",
            "message", "config", "filters", "properties", "polygon_points", "recurrence", "setting_value",
            "old_value", "new_value", "answer", "field_value", "answer_text", "reason", "cancel_reason"}
SHORT = {"code": 30, "short_code": 10, "employee_prefix": 10, "prefix": 10, "iso_code": 3, "cnic": 15,
         "phone": 30, "phone_1": 30, "phone_2": 30, "alt_phone": 30, "extension_no": 20, "ip_address": 45,
         "ipv4": 45, "ipv6": 45, "netmask": 45, "range_start": 45, "range_end": 45, "color": 20,
         "serial_no": 50, "voucher_no": 30, "ticket_no": 50, "identification_no": 100, "account_number": 50,
         "branch_code": 30, "device_user_no": 30, "tax_payer_id": 30, "token": 100, "timezone": 64,
         "weekdays": 30, "password_hash": 255, "refresh_token_hash": 255, "storage_path": 500,
         "mime_type": 100, "link": 500, "resource": 100, "setting_key": 100, "field_name": 100, "screen": 100,
         "template": 100, "device": 200, "email": 254, "address": 500, "purpose": 500, "question_text": 1000,
         "option_text": 500, "item_text": 500, "start_identifier": 50, "end_identifier": 50,
         "model": 100, "manufacturer": 100, "religion": 50, "nationality": 50, "role_title": 100,
         "unit_type": 30, "target_type": 30, "rule_type": 30, "entity_type": 50, "scope_type": 30}
OVERRIDES = {
    ("approval_flow", "purpose"): "NVARCHAR(30)", ("request_step", "purpose"): "NVARCHAR(30)",
    ("leave_ledger", "reason"): "NVARCHAR(30)", ("end_of_employment", "reason"): "NVARCHAR(30)",
    ("company", "currency"): "CHAR(3)", ("checklist_field", "min_value"): "DECIMAL(18,4)",
    ("checklist_field", "max_value"): "DECIMAL(18,4)", ("leave_type", "allowance"): "DECIMAL(6,2)",
    ("leave_policy_type", "allowance"): "DECIMAL(6,2)", ("leave_type_experience_slab", "balance"): "DECIMAL(6,2)",
    ("leave_type_short_slab", "balance"): "DECIMAL(6,2)", ("share_link", "valid_from"): "DATETIME2(0)",
    ("share_link", "valid_to"): "DATETIME2(0)", ("job_position", "description"): "NVARCHAR(MAX)",
    ("task", "time_estimate_minutes"): "INT", ("time_entry", "minutes"): "INT",
    ("payroll", "work_date"): "DATE", ("rest_day_rule", "step"): "INT",
    ("employee", "salary_frequency"): "NVARCHAR(30)", ("payroll", "applicable_days"): "NVARCHAR(30)",
    ("asset_clearance_item", "condition_at_clearance"): "NVARCHAR(30)",
    ("permission", "code"): "NVARCHAR(150)", ("permission", "action_code"): "NVARCHAR(50)",
    ("permission", "hint"): "NVARCHAR(500)",
}
ENUM_SUFFIX = ("_type", "_kind", "_mode", "_status", "_level", "_role", "_basis", "_rule", "_group",
               "_condition", "_method", "_frequency", "_event", "_distribution", "_day", "_class")
ENUMS = {"status", "kind", "category", "scope", "mode", "gender", "marital_status", "stage", "source",
         "shape", "period", "flag", "effect", "action_name", "action_taken", "privacy", "visibility",
         "priority", "relation", "result", "work_mode", "basis", "applies_to", "clock_event", "approver_kind",
         "applicable_days", "module", "sync_status", "day_status", "currency", "attachment_rule"}


def sql_type(t, c):
    n, key = c["name"], c["key"]
    if (t, n) in OVERRIDES:
        return OVERRIDES[(t, n)]
    if key == "PK" and n == "id":
        return "BIGINT IDENTITY"
    if key in ("PK/FK", "FK") or (n.endswith("_id") and n != "tax_payer_id"):
        return "BIGINT"
    if n in SHORT:
        return f"NVARCHAR({SHORT[n]})" if SHORT[n] != 3 else "CHAR(3)"
    if n in BOOL or re.match(r"^(is|has|can|allow|needs)_", n):
        return "BIT"
    if n.endswith("_at"):
        return "DATETIME2(0)"
    if n in ("expected_in", "expected_out", "first_in", "last_out"):
        return "DATETIME2(0)"
    if n in MONTH:
        return "DATE"
    if n.endswith("_date") or n in DATE:
        return "DATE"
    if n.endswith("_time"):
        return "TIME(0)"
    if n in ("fiscal_year",):
        return "SMALLINT"
    if (t, n) in DAYS_FRACTION:
        return "DECIMAL(6,2)"
    if n.endswith(("_minutes", "_months", "_days", "_weeks", "_years")) or n in INT:
        return "INT"
    if n in ("percentage", "penalty_percentage"):
        return "DECIMAL(5,2)"
    if n in ("latitude", "longitude", "center_lat", "center_lng"):
        return "DECIMAL(9,6)"
    if n == "distance_km":
        return "DECIMAL(9,2)"
    if n == "size_bytes":
        return "BIGINT"
    if n in MONEY or any(w in n for w in MONEY_WORDS):
        return "DECIMAL(18,2)"
    if n in TEXT_MAX:
        return "NVARCHAR(MAX)"
    if n in ENUMS or n.endswith(ENUM_SUFFIX):
        return "NVARCHAR(30)"
    return "NVARCHAR(200)"


NOT_NULL_NAMES = {"company_id", "code", "name", "title", "status", "first_name", "last_name", "kind"}
EXTRA_NN = {("request", "employee_id"), ("punch", "punched_at"), ("punch", "punch_type"), ("punch", "source"),
            ("timesheet_day", "work_date"), ("schedule", "work_date"), ("schedule", "start_at"),
            ("schedule", "end_at"), ("leave_ledger", "days"), ("leave_ledger", "fiscal_year"),
            ("payslip_line", "amount"), ("employee_salary", "amount"), ("employee_salary", "effective_date"),
            ("user_account", "email"), ("user_account", "password_hash"), ("payslip", "employee_id"),
            ("position", "employee_group_id"), ("manpower_plan", "planning_mode"), ("post", "visibility"),
            ("post", "posted_at"), ("post_media", "file_id"), ("post_reaction", "kind"), ("post_reaction", "employee_id"),
            ("post_comment", "employee_id"), ("post_comment", "body"), ("permission", "module"),
            ("permission", "screen"), ("permission", "action_code"), ("permission", "label"),
            ("role_permission", "scope"), ("user_permission_override", "permission_id"),
            ("user_permission_override", "effect"), ("role_permission_unit", "permission_id"),
            ("role_permission_unit", "unit_type"), ("role_permission_unit", "unit_id")}


def enrich(modules, tables):
    for m in modules:
        for t in m["tables"]:
            has_id = any(c["name"] == "id" for c in t["cols"])
            first_fk_done = False
            for c in t["cols"]:
                c["type"] = c.get("type_override") or sql_type(t["name"], c)
                ref = c["ref"]
                if c["key"] in ("FK", "PK/FK") and not ref:
                    base = re.sub(r"_id$", "", c["name"])
                    ref = base if base in tables else None
                c["ref"] = ref if ref in tables else None
                c["ref_full"] = f"{tables[c['ref']]['schema']}.{c['ref']}" if c["ref"] else ""
                if c["key"] == "FK" and c["ref"] is None:
                    c["key"] = None
                nn = (c["key"] in ("PK", "PK/FK") or c["name"] in NOT_NULL_NAMES or c["type"] == "BIT"
                      or (not has_id and c["key"] == "FK") or (t["name"], c["name"]) in EXTRA_NN)
                if c["key"] == "FK" and c["ref"] == t["name"]:
                    first_fk_done = True  # a self-reference (parent row) is optional and ends the search
                if (c["key"] == "FK" and not first_fk_done and c["name"] != "company_id"
                        and (c["ref"] not in ("stored_file", "user_account") or c["name"] == "user_account_id")
                        and "optional" not in c["note"]):
                    nn, first_fk_done = True, True
                c["nn"] = nn if c.get("nn_override") is None else c["nn_override"]
            t["link"] = not has_id
            uniques = []
            names = [c["name"] for c in t["cols"]]
            if "company_id" in names and "code" in names:
                uniques.append(("company_id", "code"))
            uniques += UNIQUE.get(t["name"], []) + t["extra_uniques"]
            t["uniques"] = uniques


UNIQUE = {
    "permission": [("code",)], "user_permission_override": [("company_id", "user_account_id", "permission_id")],
    "role_permission_unit": [("role_id", "permission_id", "unit_type", "unit_id")],
    "post_reaction": [("post_id", "employee_id")],
    "user_account": [("email",)], "timesheet_day": [("employee_id", "work_date")],
    "leave_type": [("company_id", "short_code")], "payslip": [("payroll_id", "employee_id")],
    "company_setting": [("company_id", "module", "setting_key")], "number_sequence": [("company_id", "prefix")],
    "employee": [("company_id", "cnic")], "schedule": [("employee_id", "start_at")],
    "rest_day": [("employee_id", "rest_date")], "employee_bank_account": [("employee_id", "account_number")],
}

# ---------------------------------------------------------------- markdown

def write_md(modules):
    total = sum(len(m["tables"]) for m in modules)
    L = ["# HRango — ERD (SQL Server, first build)", "",
         "Generated from `erd/source/*.md` by `erd/build.py`. Edit the source, not this file.", "",
         "## Conventions", "",
         "- **Database:** SQL Server from day one. One database for now; every business table carries `company_id`.",
         "- **Schemas:** one SQL Server schema per module (table below). The same name is the backend module.",
         "- **Keys:** `id BIGINT IDENTITY(1,1)` primary key. Link tables (no `id`) use the pair of foreign keys as the primary key.",
         "- **Foreign keys:** `ON DELETE NO ACTION` everywhere (SQL Server rejects multiple cascade paths). Deleting is done by the service layer.",
         "- **Every table also has:** `created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()`, `created_by BIGINT NULL`, `updated_at DATETIME2(0) NULL`, `updated_by BIGINT NULL`, `row_version ROWVERSION` (stops two people overwriting each other).",
         "- **Text:** `NVARCHAR` (Urdu names work). Enum-like values are `NVARCHAR(30)` holding a code; the allowed codes live in the backend.",
         "- **Money:** `DECIMAL(18,2)`. Leave days: `DECIMAL(6,2)` (half days).",
         "- **Time:** audit columns and system stamps are UTC. Attendance and scheduling times (punches, shifts, time-sheet days) are the company's local wall-clock time, as biometric devices report them. `DATE` and `TIME` columns are local business dates.",
         "- **NN** = NOT NULL. Everything else is nullable. `BIT` columns are `NOT NULL DEFAULT 0`.",
         "- Reserved words avoided: `user` → `user_account`, `file` → `stored_file`, `order` → `sort_order`, `key`/`value` → `setting_key`/`setting_value`, `group` → `status_group`, `view` → `list_view`, `list` → `task_list`.",
         "",
         "## Modules, schemas and backend layers", "",
         "Each module gets one file per layer: `app/routers/<module>.py`, `app/controllers/<module>_controller.py`, `app/services/<module>_service.py`, `app/repos/<module>_repo.py`, `app/schemas/<module>.py`. Data access goes through stored procedures in `db/procedures/<schema>/`. The tables come from `db/migrations/0001_baseline.sql`, generated from this ERD.", "",
         "| # | Module | SQL schema | Backend module | Tables |", "|---|---|---|---|---|"]
    for m in modules:
        L.append(f"| {m['no']} | {m['title']} | `{m['schema']}` | `{BACKEND_MODULE[m['schema']]}` | {len(m['tables'])} |")
    L += [f"| | **Total** | | | **{total}** |", ""]
    for m in modules:
        L += ["---", "", f"## {m['no']}. {m['title']}  (`{m['schema']}`)", ""]
        for t in m["tables"]:
            L.append("```")
            head = f"{t['schema']}.{t['name']}"
            L.append(head + (f"    -- {t['note']}" if t["note"] else ""))
            w = max(len(c["name"]) for c in t["cols"]) + 2
            for c in t["cols"]:
                key = "PK" if c["key"] == "PK" or (t["link"] and c["key"] == "FK") else ""
                if c["key"] == "PK/FK":
                    key = "PK"
                fk = f"FK → {c['ref_full']}" if c["ref_full"] else ""
                parts = [c["name"].ljust(w), c["type"].ljust(17), ("NN" if c["nn"] else "").ljust(3),
                         key.ljust(3), fk]
                line = "  " + " ".join(parts).rstrip()
                if c["note"]:
                    line += "    -- " + c["note"]
                L.append(line)
            for u in t["uniques"]:
                L.append(f"  UNIQUE ({', '.join(u)})")
            L += ["```", ""]
        if m["rels"]:
            L += ["Relationships:", "```"] + m["rels"] + ["```", ""]
    L += ["---", "", "## Not in the first build", "",
          "Left out until someone defines them. Nothing above depends on them. Each module's own gaps are in "
          "`comparison/`.", "",
          "| Item | Why |", "|---|---|",
          "| Recruitment (`rec` tables) | Placeholder in the designs; no screens built; tables kept for later |",
          "| Requisition and Expense requests | Only menu items; no fields defined |",
          "| Performance (KPIs, appraisals), Training, Custom Forms, Configuration | Menu items only |",
          "| Employee contract, education, dependents, skills, documents | Profile tabs; need file storage, most have no design |",
          "| Engagement newsfeed and surveys (`eng` tables except announcements) | No screens in the frontend yet |",
          "| Project sprints, docs, notes | Marked skipped in the design |",
          "| Customer control database, subscriptions, invoices | Comes when a second customer database is added |",
          "| Finance dashboard (FDO) | Display only, one client |", ""]
    OUT_MD.write_text("\n".join(L), encoding="utf-8")

# ---------------------------------------------------------------- SQL Server DDL

AUDIT_COLS = [("created_at", "DATETIME2(0) NOT NULL CONSTRAINT [DF_{t}_created_at] DEFAULT SYSUTCDATETIME()"),
              ("created_by", "BIGINT NULL"), ("updated_at", "DATETIME2(0) NULL"), ("updated_by", "BIGINT NULL"),
              ("row_version", "ROWVERSION")]


def sql_str(s):
    return "N'" + s.replace("'", "''") + "'"


def pk_cols(t):
    pk = [c["name"] for c in t["cols"] if c["key"] in ("PK", "PK/FK")]
    return pk or [c["name"] for c in t["cols"] if c["key"] == "FK"]


def write_sql(modules, tables):
    """Baseline migration: schemas, tables, foreign keys, indexes, descriptions."""
    L = ["-- HRango baseline schema. Generated from erd/source/*.md by erd/build.py. Do not edit by hand:",
         "-- change erd/source/*.md and rebuild. Once a database outside development has this applied,",
         "-- freeze this file and put further changes in new numbered migrations.",
         "SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;", "GO", ""]
    for schema in dict.fromkeys(m["schema"] for m in modules):
        L += [f"IF SCHEMA_ID(N'{schema}') IS NULL EXEC(N'CREATE SCHEMA [{schema}]');", "GO"]
    L.append("")
    fks, idx, desc = [], [], []
    for m in modules:
        for t in m["tables"]:
            s, n = t["schema"], t["name"]
            rows = []
            for c in t["cols"]:
                typ = c["type"].replace("BIGINT IDENTITY", "BIGINT IDENTITY(1,1)")
                line = f"    [{c['name']}] {typ} {'NOT NULL' if c['nn'] else 'NULL'}"
                if c["type"] == "BIT":
                    line += f" CONSTRAINT [DF_{n}_{c['name']}] DEFAULT 0"
                rows.append(line)
                if c["ref"]:
                    tgt = tables[c["ref"]]
                    tpk = pk_cols(tgt)
                    fks.append(f"ALTER TABLE [{s}].[{n}] ADD CONSTRAINT [FK_{n}_{c['name']}] FOREIGN KEY ([{c['name']}]) "
                               f"REFERENCES [{tgt['schema']}].[{tgt['name']}] ([{tpk[0]}]);")
                if c["note"]:
                    desc.append((s, n, c["name"], c["note"]))
            names = {c["name"] for c in t["cols"]}
            rows += [f"    [{a}] {d.format(t=n)}" for a, d in AUDIT_COLS if a not in names]
            pk = pk_cols(t)
            rows.append(f"    CONSTRAINT [PK_{n}] PRIMARY KEY CLUSTERED ({', '.join(f'[{p}]' for p in pk)})")
            nullable = {c["name"] for c in t["cols"] if not c["nn"]}
            covered = {pk[0]}
            for u in t["uniques"]:
                cols = ", ".join(f"[{x}]" for x in u)
                uname = f"UQ_{n}_{'_'.join(u)}"
                if nullable & set(u):
                    where = " AND ".join(f"[{x}] IS NOT NULL" for x in u if x in nullable)
                    idx.append(f"CREATE UNIQUE NONCLUSTERED INDEX [{uname}] ON [{s}].[{n}] ({cols}) WHERE {where};")
                else:
                    rows.append(f"    CONSTRAINT [{uname}] UNIQUE ({cols})")
                covered.add(u[0])
            for c in t["cols"]:
                if c["ref"] and c["name"] not in covered:
                    idx.append(f"CREATE NONCLUSTERED INDEX [IX_{n}_{c['name']}] ON [{s}].[{n}] ([{c['name']}]);")
            for cols in t["extra_indexes"]:
                idx.append(f"CREATE NONCLUSTERED INDEX [IX_{n}_{'_'.join(cols)}] ON [{s}].[{n}] "
                           f"({', '.join(f'[{x}]' for x in cols)});")
            L += [f"CREATE TABLE [{s}].[{n}] (", ",\n".join(rows), ");", "GO"]
            if t["note"]:
                desc.append((s, n, None, t["note"]))
    L += ["", "-- Foreign keys (all ON DELETE NO ACTION)"] + fks + ["GO", "", "-- Indexes"] + idx + ["GO", "",
          "-- Descriptions (visible in SSMS and to anyone reading the database)"]
    for s, n, col, note in desc:
        args = f"N'SCHEMA', N'{s}', N'TABLE', N'{n}'" + (f", N'COLUMN', N'{col}'" if col else "")
        L.append(f"EXEC sys.sp_addextendedproperty N'MS_Description', {sql_str(note)}, {args};")
    L += ["GO", ""]
    OUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUT_SQL.write_text("\n".join(L), encoding="utf-8")
    return len(fks), len(idx)

# ---------------------------------------------------------------- draw.io

W, ROW_H, HEAD_H, GAP_X, GAP_Y, COLS = 330, 20, 28, 110, 50, 5
TABLE_STYLE = ("swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;startSize=28;horizontalStack=0;"
               "resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=1;marginBottom=0;html=1;"
               "fillColor={fill};strokeColor={stroke};fontColor={font};rounded=1;arcSize=4;")
ROW_STYLE = ("text;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;spacingLeft=6;spacingRight=4;"
             "overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];portConstraint=eastwest;html=1;fontSize=11;{extra}")
EDGE_STYLE = ("edgeStyle=entityRelationEdgeStyle;html=1;endArrow=ERmandOne;startArrow=ERmany;endFill=0;"
              "startFill=0;strokeColor=#64748B;rounded=0;")
SKIP_EDGE = {"company", "stored_file", "user_account"}


def page_xml(m, tables, pno):
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    own = [t["name"] for t in m["tables"]]
    refs = []
    for t in m["tables"]:
        for c in t["cols"]:
            r = c["ref"]
            if r and r not in own and r not in SKIP_EDGE and r not in refs:
                refs.append(r)
    heights, pos = [0] * COLS, {}
    for t in m["tables"]:
        h = HEAD_H + ROW_H * len(t["cols"])
        k = heights.index(min(heights))
        pos[t["name"]] = (40 + k * (W + GAP_X), 80 + heights[k], h)
        heights[k] += h + GAP_Y
    for i, r in enumerate(refs):
        pos["ref:" + r] = (40 + COLS * (W + GAP_X) + 40, 80 + i * (HEAD_H + 30), HEAD_H)
    title = escape(f"HRango ERD — {m['no']}. {m['title']}  (schema {m['schema']})")
    cells.append(f'<mxCell id="p{pno}title" value="{title}" style="text;html=1;fontSize=22;fontStyle=1;align=left;'
                 f'verticalAlign=middle;" vertex="1" parent="1"><mxGeometry x="40" y="20" width="1200" height="40" '
                 f'as="geometry"/></mxCell>')
    ids = {}
    for ti, t in enumerate(m["tables"]):
        tid = f"p{pno}t{ti}"
        ids[t["name"]] = tid
        x, y, h = pos[t["name"]]
        style = TABLE_STYLE.format(fill="#1A273A", stroke="#1A273A", font="#FFFFFF")
        cells.append(f'<mxCell id="{tid}" value="{escape(t["schema"] + "." + t["name"])}" style="{style}" vertex="1" '
                     f'parent="1"><mxGeometry x="{x}" y="{y}" width="{W}" height="{h}" as="geometry"/></mxCell>')
        for ci, c in enumerate(t["cols"]):
            is_pk = c["key"] in ("PK", "PK/FK") or (t["link"] and c["key"] == "FK")
            nm = f"<b>{escape(c['name'])}</b>" if is_pk else escape(c["name"])
            typ = f"<font color='#64748B'>{escape(c['type'])}{' NN' if c['nn'] and not is_pk else ''}</font>"
            tag = []
            if is_pk:
                tag.append("PK")
            if c["ref_full"]:
                tag.append(f"<font color='#7325EE'>FK→{escape(c['ref_full'])}</font>")
            text = f"{nm}  {typ}  {' '.join(tag)}".rstrip()
            extra = "fillColor=#EEF0FA;" if is_pk else ""
            cells.append(f'<mxCell id="{tid}r{ci}" value="{escape(text)}" style="{ROW_STYLE.format(extra=extra)}" '
                         f'vertex="1" parent="{tid}"><mxGeometry y="{HEAD_H + ci * ROW_H}" width="{W}" height="{ROW_H}" '
                         f'as="geometry"/></mxCell>')
    for r in refs:
        rid = f"p{pno}ref_{r}"
        ids["ref:" + r] = rid
        x, y, h = pos["ref:" + r]
        style = TABLE_STYLE.format(fill="#E2E8F0", stroke="#94A3B8", font="#334155")
        label = f"{tables[r]['schema']}.{r} (other page)"
        cells.append(f'<mxCell id="{rid}" value="{escape(label)}" style="{style}dashed=1;" vertex="1" parent="1">'
                     f'<mxGeometry x="{x}" y="{y}" width="{W - 40}" height="{h}" as="geometry"/></mxCell>')
    ei = 0
    for ti, t in enumerate(m["tables"]):
        for ci, c in enumerate(t["cols"]):
            r = c["ref"]
            if not r or r in SKIP_EDGE:
                continue
            dst = ids.get(r) or ids.get("ref:" + r)
            if dst:
                cells.append(f'<mxCell id="p{pno}e{ei}" style="{EDGE_STYLE}" edge="1" parent="1" source="p{pno}t{ti}r{ci}" '
                             f'target="{dst}"><mxGeometry relative="1" as="geometry"/></mxCell>')
                ei += 1
    return "<mxGraphModel><root>" + "".join(cells) + "</root></mxGraphModel>", ei


def write_drawio(modules, tables):
    parts, stats = ['<mxfile host="app.diagrams.net" type="device">'], []
    for i, m in enumerate(modules):
        xml, edges = page_xml(m, tables, i)
        parts.append(f'<diagram id="hrango-erd-{m["schema"]}" name={quoteattr(m["no"] + ". " + m["title"])}>{xml}</diagram>')
        stats.append((m["title"], len(m["tables"]), edges))
    parts.append("</mxfile>")
    OUT_DRAWIO.write_text("".join(parts), encoding="utf-8")
    return stats


if __name__ == "__main__":
    import sys
    import xml.dom.minidom
    sys.stdout.reconfigure(encoding="utf-8")
    modules, tables = parse()
    enrich(modules, tables)
    if len(sys.argv) == 3 and sys.argv[1] == "--sql-out":
        # Only the SQL, to a file of your own (parallel work; nothing shared is touched).
        OUT_SQL = Path(sys.argv[2]).resolve()
        n_fk, n_ix = write_sql(modules, tables)
        print(f"SQL: {OUT_SQL}  tables {len(tables)}  foreign keys {n_fk}  indexes {n_ix}")
        sys.exit(0)
    write_md(modules)
    stats = write_drawio(modules, tables)
    xml.dom.minidom.parse(str(OUT_DRAWIO))
    n_fk, n_ix = write_sql(modules, tables)
    print(f"SQL: {OUT_SQL.name}  foreign keys {n_fk}  indexes {n_ix}")
    for title, n, e in stats:
        print(f"{title:<32} tables {n:>3}  lines {e:>3}")
    print("total tables", sum(s[1] for s in stats))
    unresolved = [(t["name"], c["name"]) for t in tables.values() for c in t["cols"]
                  if c["name"].endswith("_id") and c["name"] not in ("id",) and not c["ref"]
                  and c["name"] not in ("entity_id", "ref_id", "target_id", "scope_id", "unit_id", "tax_payer_id")]
    print("ids without a FK target:", unresolved)
