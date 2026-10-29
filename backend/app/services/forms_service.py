"""Custom Form rules. Status, audience, editing limits and answer checks live in the frm procedures; this
layer turns request bodies into the procedures' JSON, shapes rows (JSON columns, answer values by field
type, signed file links) and builds the response summary."""
import json
from collections import defaultdict
from typing import Any

from app.core.db import Db
from app.core.files import file_url
from app.middlewares.auth import RequestContext
from app.repos import auth_repo
from app.repos import forms_repo as repo
from app.schemas.forms import FormIn, ResponseIn

Row = dict[str, Any]
Rows = list[Row]
CHOICE = ("single_choice", "multiple_choice", "dropdown")
RESPONSES_VIEW = "forms.responses.view"


def _loads(text: str | None) -> Any:
    return json.loads(text) if text else None


def _num(value: Any) -> int | float | None:
    """A DECIMAL read back from JSON as a plain number: 5 rather than 5.0."""
    if value is None:
        return None
    f = float(value)
    return int(f) if f.is_integer() else f


def _fields(text: str | None) -> Rows:
    out = []
    for f in _loads(text) or []:
        out.append({**f, "options": f.get("options") or [], "min": _num(f.get("min")), "max": _num(f.get("max"))})
    return out


def shape_form(row: Row) -> Row:
    out = dict(row)
    out["anonymous"] = out.pop("is_anonymous")
    out["one_response_per_person"] = out.pop("is_one_per_person")
    if "audience_kind" in out:
        out["audience"] = {"kind": out.pop("audience_kind"), "targets": _loads(out.pop("audience_json", None)) or []}
    if "sections_json" in out:
        out["sections"] = _loads(out.pop("sections_json")) or []
    if "fields_json" in out:
        out["fields"] = _fields(out.pop("fields_json"))
    created_by, name = out.pop("created_by", None), out.pop("created_by_name", None)
    out["created_by"] = {"id": created_by, "name": name or ""} if created_by is not None else None
    return out


def _answer_value(a: Row, company_id: int) -> Row:
    kind, file = a["field_type"], None
    options = [str(o["id"]) for o in a.get("option_ids") or []]
    if kind in ("short_text", "long_text"):
        value: Any = a.get("answer_text")
    elif kind == "number":
        value = _num(a.get("answer_number"))
    elif kind == "rating":
        value = None if a.get("answer_number") is None else int(float(a["answer_number"]))
    elif kind == "date":
        value = a.get("answer_date")
    elif kind == "checkbox":
        value = None if a.get("answer_bool") is None else bool(a["answer_bool"])
    elif kind in ("single_choice", "dropdown"):
        value = options[0] if options else None
    elif kind == "multiple_choice":
        value = options
    else:  # file
        value = a.get("file_id")
        if value:
            file = {"id": value, "name": a.get("file_name"), "url": file_url(value, company_id)}
    return {"field_id": a["field_id"], "value": value, "file": file}


def shape_response(row: Row, company_id: int) -> Row:
    out = {"id": row["id"], "form_id": row["form_id"], "submitted_at": row["submitted_at"],
           "respondent": None if row.get("employee_id") is None else {
               "id": row["employee_id"], "name": row.get("employee_name") or "", "code": row.get("employee_code"),
               "department_name": row.get("department_name")},
           "answers": [_answer_value(a, company_id) for a in _loads(row.get("answers_json")) or []]}
    if "fields_json" in row:
        out["form"] = {"id": row["form_id"], "title": row["form_title"], "description": row.get("form_description"),
                       "anonymous": row["is_anonymous"], "sections": _loads(row.get("sections_json")) or [],
                       "fields": _fields(row.get("fields_json"))}
    return out


# --------------------------------------------------------------------------- forms (HR)

def list_forms(db: Db, ctx: RequestContext, search: str | None, status: str | None, page: int,
               page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_forms(db, ctx.company_id, search, status, page, page_size)
    return total, [shape_form(r) for r in rows]


def get_form(db: Db, ctx: RequestContext, form_id: int) -> Row:
    return shape_form(repo.get_form(db, ctx.company_id, form_id))


def save_form(db: Db, ctx: RequestContext, form_id: int | None, body: FormIn, row_version: bytes | None) -> Row:
    sections = json.dumps([{"key": s.key, "id": s.id, "title": s.title, "description": s.description}
                           for s in body.sections])
    fields = json.dumps([{"id": f.id, "section_key": f.section_key, "type": f.type, "label": f.label,
                          "help_text": f.help_text, "required": f.required, "min": f.min, "max": f.max,
                          "options": [{"id": o.id, "label": o.label} for o in f.options]} for f in body.fields])
    row = repo.save_form(db, ctx.company_id, ctx.user_id, form_id, body.title, body.description, body.category,
                         body.closes_on, body.audience.kind, json.dumps(body.audience.ids), body.one_response_per_person,
                         body.anonymous, sections, fields, row_version)
    return shape_form(row)


def delete_form(db: Db, ctx: RequestContext, form_id: int, row_version: bytes) -> None:
    repo.delete_form(db, ctx.company_id, ctx.user_id, form_id, row_version)


def publish_form(db: Db, ctx: RequestContext, form_id: int, row_version: bytes) -> Row:
    return shape_form(repo.form_action(db, "publish", ctx.company_id, ctx.user_id, form_id, row_version))


def close_form(db: Db, ctx: RequestContext, form_id: int, row_version: bytes) -> Row:
    return shape_form(repo.form_action(db, "close", ctx.company_id, ctx.user_id, form_id, row_version))


def duplicate_form(db: Db, ctx: RequestContext, form_id: int) -> Row:
    return shape_form(repo.duplicate_form(db, ctx.company_id, ctx.user_id, form_id))


# --------------------------------------------------------------------------- filling

def _shape_assigned(row: Row) -> Row:
    out = shape_form(row)
    out.pop("created_by", None)
    return out


def list_assigned(db: Db, ctx: RequestContext, search: str | None, page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_assigned(db, ctx.company_id, ctx.user_id, search, page, page_size)
    return total, [_shape_assigned(r) for r in rows]


def get_assigned(db: Db, ctx: RequestContext, form_id: int) -> Row:
    return _shape_assigned(repo.get_assigned(db, ctx.company_id, ctx.user_id, form_id))


def submit_response(db: Db, ctx: RequestContext, form_id: int, body: ResponseIn) -> Row:
    answers = json.dumps([{"field_id": a.field_id, "value": a.value} for a in body.answers])
    return shape_response(repo.submit_response(db, ctx.company_id, ctx.user_id, form_id, answers), ctx.company_id)


def list_my_responses(db: Db, ctx: RequestContext, search: str | None, page: int, page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_my_responses(db, ctx.company_id, ctx.user_id, search, page, page_size)
    return total, [{**r, "anonymous": r["is_anonymous"]} for r in rows]


# --------------------------------------------------------------------------- responses (HR)

def list_responses(db: Db, ctx: RequestContext, form_id: int, search: str | None, page: int,
                   page_size: int) -> tuple[int, Rows]:
    total, rows = repo.list_responses(db, ctx.company_id, ctx.user_id, form_id, search, page, page_size)
    return total, [shape_response(r, ctx.company_id) for r in rows]


def response_summary(db: Db, ctx: RequestContext, form_id: int) -> Row:
    total, fields, options, checks, ratings = repo.response_summary(db, ctx.company_id, form_id)
    by_option: dict[Any, Rows] = defaultdict(list)
    for o in options:
        by_option[o["field_id"]].append({"value": str(o["option_id"]), "count": o["answer_count"]})
    ticked = {(c["field_id"], bool(c["value"])): c["answer_count"] for c in checks}
    rated = {(r["field_id"], r["value"]): r["answer_count"] for r in ratings}
    out = []
    for f in fields:
        fid, kind = f["field_id"], f["field_type"]
        if kind in CHOICE:
            counts = by_option[fid]
        elif kind == "checkbox":
            counts = [{"value": "true", "count": ticked.get((fid, True), 0)},
                      {"value": "false", "count": ticked.get((fid, False), 0)}]
        elif kind == "rating":
            scale = int(f["max_value"] or 5)
            counts = [{"value": str(v), "count": rated.get((fid, v), 0)} for v in range(1, scale + 1)]
        else:
            counts = []
        out.append({"field_id": fid, "answered": f["answered"], "counts": counts})
    return {"total": total[0]["total"], "fields": out}


def get_response(db: Db, ctx: RequestContext, response_id: int) -> Row:
    """HR (forms.responses.view) reads the responses it reaches; anyone reads their own."""
    as_hr = bool(auth_repo.permission_check(db, ctx.company_id, ctx.user_id, RESPONSES_VIEW)["allowed"])
    return shape_response(repo.get_response(db, ctx.company_id, ctx.user_id, response_id, as_hr), ctx.company_id)
