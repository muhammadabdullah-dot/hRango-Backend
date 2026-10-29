"""The permission catalogue: every view and button the server checks, as module.screen.action.

Each module lists its screens in app/catalogue/<module>.py. The seeder syncs the whole list into
auth.permission; customers tick these on the role screen but cannot add to them. A code never
changes meaning once released; retire it and add a new one instead.

Scopes say whose records a permission reaches. They are held per tick on a role (and per grant on
a user), not here.
"""
from importlib import import_module

from app.catalogue._actions import ACTION_LABELS

SCOPES = ("own", "team", "department", "branch", "selected_units", "company")

# Order here is the order on the role screen.
MODULES = ("organisation", "employees", "access", "integrations", "dashboard", "inbox", "attendance", "roster",
           "scheduling", "warning", "requests", "leaves", "loans", "payroll", "assets", "offboarding", "manpower",
           "recruitment", "performance", "training", "benefits", "engagement", "projects", "forms")


def catalogue_rows() -> list[dict]:
    rows, order = [], 0
    for module in MODULES:
        for screen, label, actions, sensitive in import_module(f"app.catalogue.{module}").SCREENS:
            if not screen.startswith(module + "."):
                raise ValueError(f"{screen} is listed under {module}")
            for action in actions:
                order += 10
                rows.append({"code": f"{screen}.{action}", "module": module, "screen": screen,
                             "action_code": action, "label": f"{label}: {ACTION_LABELS[action]}",
                             "is_sensitive": sensitive, "sort_order": order})
    return rows


CODES = frozenset(r["code"] for r in catalogue_rows())
