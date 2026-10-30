"""Helpers of the leave_requests demo part: tolerant API calls, filing a request as its employee and walking
it through its approval flow as the people who hold each step, dates by week, receipts."""
import random
from collections import Counter
from datetime import date, timedelta
from typing import Any

from scripts.demo import Api
from scripts.demo_data import World

# Remarks approvers leave, by request type (any type falls back to "default").
APPROVE_REMARKS = {
    "default": ["Approved.", "Approved, thanks for the heads-up.", "OK from my side.", "Approved. Please keep the team posted."],
    "leave": ["Approved. Enjoy your time off.", "Approved, handover noted.", "Approved.", "Approved. Get well soon."],
    "loan": ["Recommended.", "Verified against policy; approved.", "Approved as per loan policy."],
    "travel": ["Approved. Please share the trip report after you return.", "Approved within budget."],
    "expense": ["Receipts checked; approved.", "Approved for reimbursement."],
    "air_ticket": ["Fare checked against the travel policy; approved."],
    "promotion": ["Performance review supports the promotion; approved.", "Approved effective as proposed."],
    "transfer": ["Approved; IT and Admin informed.", "Transfer approved."],
    "relaxation": ["Approved this once; please plan around traffic.", "Approved; genuine reason."],
    "requisition": ["Approved; please raise the purchase order.", "Approved, needed for the team."],
}


def slug(code: str) -> str:
    return code.replace("_", "-")


class Ctx:
    """State shared by the set-up and history steps."""

    def __init__(self, w: World):
        self.w = w
        self.rng = random.Random(20261029)
        self.name_of = {int(e["id"]): n for n, e in w.employees.items()}
        self.monday = w.today - timedelta(days=w.today.weekday())
        self.stats: Counter = Counter()        # (type code, status) -> count
        self.problems: list[str] = []
        self.skipped: list[str] = []
        self.ids: dict[str, Any] = {}          # set-up ids by name (leave types, loan types, categories ...)
        self.shifts: dict[int, dict[date, dict]] = {}  # employee id -> work date -> shift (when scheduled)

    # ------------------------------------------------------------------ dates

    fy_start = 1  # the company's fiscal (= leave) year start month, read by the set-up

    def leave_year(self, d: date) -> int:
        return d.year if d.month >= self.fy_start else d.year - 1

    def day(self, weeks_ago: int, dow: int = 0) -> date:
        """Monday (dow 0) .. Sunday (6) of the week `weeks_ago` weeks before this one (negative: ahead)."""
        return self.monday - timedelta(weeks=weeks_ago) + timedelta(days=dow)

    # ------------------------------------------------------------------ calls

    def call(self, api: Api, method: str, path: str, body: dict | None = None, quiet: bool = False) -> dict | None:
        """Like api(...) but records a refusal instead of stopping the whole run."""
        r = api.client.request(method, f"/api{path}", json=body, headers=api.headers)
        if r.status_code >= 300:
            if not quiet:
                self.problems.append(f"{method} {path} -> {r.status_code}: {r.text[:400]}")
            return None
        return r.json() if r.content else {}

    def emp(self, name: str) -> dict:
        return self.w.employees[name]

    def eid(self, name: str) -> int:
        return int(self.w.employees[name]["id"])

    def upload_pdf(self, who: str, filename: str, lines: list[str]) -> int | None:
        api = self.w.as_(who)
        r = api.client.post("/api/files", files={"file": (filename, _pdf(lines), "application/pdf")},
                            data={"module": "requests"}, headers=api.headers)
        if r.status_code >= 300:
            self.problems.append(f"POST /files ({filename}) -> {r.status_code}: {r.text[:300]}")
            return None
        return int(r.json()["data"]["id"])

    # ------------------------------------------------------------------ requests

    def file(self, who: str, code: str, body: dict, outcome: str = "approved", *, by: str | None = None,
             **walk) -> dict | None:
        """Files a request as `by` (default: the employee `who` themselves) and walks it to `outcome`:
        approved | pending | pending+N (N decisions made, waiting on the next) | rejected | rejected+N (N
        approvals, then rejected) | cancelled (approved, then its cancellation approved) | cancelling
        (approved, cancellation waiting) | withdrawn (pending request cancelled by the requester)."""
        api = self.w.as_(by or who)
        res = self.call(api, "POST", f"/requests/{slug(code)}", body)
        if not res:
            return None
        return self.walk(res["data"], code, outcome, requester=by or who, **walk)

    def walk(self, r: dict, code: str, outcome: str, requester: str, remarks: str | None = None,
             reject_remarks: str = "Not possible at this time.", details: Any = None,
             delegates: dict[str, str] | None = None, cancel_reason: str = "Plans changed.") -> dict | None:
        kind, _, n = outcome.partition("+")
        limit = int(n) if n else None
        if kind in ("approved", "cancelled", "cancelling"):
            r = self._decide_until(r, code, None, remarks, details, delegates)
        elif kind == "pending":
            r = self._decide_until(r, code, limit or 0, remarks, details, delegates)
        elif kind == "rejected":
            r = self._decide_until(r, code, limit or 0, remarks, details, delegates)
            if r and r["status"] == "pending":
                r = self._decide(r, code, "reject", reject_remarks, None, delegates)
        elif kind == "withdrawn":
            r = self._cancel(r, code, requester, cancel_reason)
        if r and kind in ("cancelled", "cancelling") and r["status"] == "approved":
            r = self._cancel(r, code, requester, cancel_reason)
            if r and kind == "cancelled":
                r = self._decide_until(r, code, None, "Cancellation approved.", None, delegates, status="cancelling")
        if r:
            self.stats[(code, r["status"])] += 1
            if not outcome.startswith(r["status"]) and not (kind == "withdrawn" and r["status"] == "cancelled"):
                self.problems.append(f"{code} {r.get('code')} of {requester}: wanted {outcome}, got {r['status']}")
        return r

    def _decide_until(self, r: dict | None, code: str, limit: int | None, remarks, details, delegates,
                      status: str = "pending") -> dict | None:
        made = 0
        while r and r["status"] == status and (limit is None or made < limit):
            nxt = self._decide(r, code, "approve", remarks, details, delegates)
            if nxt is None:
                return r
            r, made = nxt, made + 1
        return r

    def _decide(self, r: dict, code: str, action: str, remarks, details, delegates) -> dict | None:
        step = next((s for s in r.get("steps") or [] if s.get("actionTaken") == "pending"), None)
        approver = r.get("nextApproverId") or (step or {}).get("approverId")
        if not approver:
            self.problems.append(f"{code} {r.get('code')}: nobody to decide the pending step")
            return None
        name = self.name_of.get(int(approver))
        name = (delegates or {}).get(name, name)
        api = self.w.as_(name)
        if step and step.get("isConsent"):
            body = {"agree": action == "approve", "remarks": remarks or "Fine with me.", "rowVersion": r["rowVersion"]}
            res = self.call(api, "POST", f"/requests/approvals/{r['id']}/consent", body)
        else:
            text = remarks or self.rng.choice(APPROVE_REMARKS.get(code, APPROVE_REMARKS["default"]))
            det = details(r) if callable(details) else details
            body = {"remarks": text, "rowVersion": r["rowVersion"], "details": det if action == "approve" else None}
            res = self.call(api, "POST", f"/requests/approvals/{r['id']}/{action}", body)
        return res["data"] if res else None

    def _cancel(self, r: dict, code: str, requester: str, reason: str) -> dict | None:
        res = self.call(self.w.as_(requester), "POST", f"/requests/{slug(code)}/{r['id']}/cancel",
                        {"reason": reason, "rowVersion": r["rowVersion"]})
        return res["data"] if res else None

    def reject(self, r: dict, code: str, remarks: str) -> dict | None:
        return self._decide(r, code, "reject", remarks, None, None)


def _pdf(lines: list[str]) -> bytes:
    """A one-page PDF with a few lines of text (receipts, tickets, certificates)."""
    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    text = "BT /F1 13 Tf 36 300 Td 16 TL " + " ".join(f"({esc(t)}) Tj T*" for t in lines) + " ET"
    stream = text.encode("latin-1", "replace")
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 340] /Contents 4 0 R "
            b"/Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offsets = bytearray(b"%PDF-1.4\n"), []
    for i, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def first_of_next_month(d: date) -> date:
    return (d.replace(day=1) + timedelta(days=32)).replace(day=1)
