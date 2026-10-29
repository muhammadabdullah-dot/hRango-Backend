"""Bank transfer file of a closed run (P3): net pay per person paid by bank transfer through a disbursement
bank, as a generic CSV or a generic fixed-width text file. The rows come from pay.usp_payroll_bank_file.

TODO(payroll): bank-specific layouts (each bank's own upload format, e.g. IBFT / RAAST files) and Excel (xlsx:
no spreadsheet library is installed) are not built; the two generic formats are what the screen offers.
"""
import csv
import io
import re
from datetime import date, datetime, timezone
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from app.core.db import Db
from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.repos import payroll_runs_repo as repo

Row = dict[str, Any]

# code -> (name, extension, media type)
FORMATS: dict[str, tuple[str, str, str]] = {
    "csv": ("Generic CSV", "csv", "text/csv"),
    "txt": ("Generic fixed width (TXT)", "txt", "text/plain"),
}
EXPORT_CODE = {"monthly": "payroll.payrolls.export", "daily_wage": "payroll.daily_wages.export"}


def formats() -> list[Row]:
    return [{"code": code, "name": name, "extension": ext} for code, (name, ext, _) in FORMATS.items()]


def _amount(v) -> Decimal:
    return Decimal(str(v or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _csv(head: Row, rows: list[Row]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\r\n")
    w.writerow(["Employee Code", "Employee Name", "Account Title", "Account Number", "Bank", "Branch Code", "Amount",
                "Currency"])
    for r in rows:
        w.writerow([r["employee_code"], r["employee_name"] or "", r["account_holder"] or "", r["account_number"],
                    r["bank_name"] or "", r["branch_code"] or "", f"{_amount(r['amount']):.2f}", head["currency"] or ""])
    return "﻿" + buf.getvalue()  # BOM so Excel reads names in UTF-8


def _fixed(text, width: int, right: bool = False, fill: str = " ") -> str:
    text = re.sub(r"[\r\n\t]", " ", str(text or ""))[:width]
    return text.rjust(width, fill) if right else text.ljust(width, fill)


def _txt(head: Row, rows: list[Row], when: date) -> str:
    """H: debit account, value date, count, total. D: one transfer each. T: count and total again."""
    total = sum((_amount(r["amount"]) for r in rows), Decimal(0))
    cents = lambda v: str(int(_amount(v) * 100))  # noqa: E731
    lines = ["H" + _fixed(head["bank_account_number"], 24) + _fixed(head["bank_account_holder"], 40)
             + when.strftime("%Y%m%d") + _fixed(head["currency"], 3) + _fixed(len(rows), 6, True, "0")
             + _fixed(cents(total), 15, True, "0")]
    for r in rows:
        lines.append("D" + _fixed(r["account_number"], 24) + _fixed(r["account_holder"], 40) + _fixed(r["bank_name"], 30)
                     + _fixed(r["branch_code"], 10) + _fixed(cents(r["amount"]), 15, True, "0")
                     + _fixed(r["employee_code"], 20))
    lines.append("T" + _fixed(len(rows), 6, True, "0") + _fixed(cents(total), 15, True, "0"))
    return "\r\n".join(lines) + "\r\n"


def _file_name(head: Row, ext: str) -> str:
    stem = f"{head['code']}-{head['bank_name']}-bank-transfer"
    return re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-") + f".{ext}"


def bank_file(db: Db, ctx: RequestContext, id: int, kind: str, disbursement_bank_id: int | None,
              fmt: str | None) -> tuple[bytes, str, str]:
    """Returns (content, media type, file name)."""
    fmt = (fmt or "csv").lower()
    if fmt not in FORMATS:
        message = f"Choose one of: {', '.join(FORMATS)}."
        raise AppError(422, "VALIDATION_FAILED", message, {"format": message})
    head, rows = repo.bank_file(db, ctx.company_id, ctx.user_id, EXPORT_CODE[kind], id, kind, disbursement_bank_id)
    _, ext, media = FORMATS[fmt]
    when = head.get("payroll_month") or head.get("work_date") or datetime.now(timezone.utc).date()
    text = _csv(head, rows) if fmt == "csv" else _txt(head, rows, when)
    return text.encode("utf-8"), media, _file_name(head, ext)
