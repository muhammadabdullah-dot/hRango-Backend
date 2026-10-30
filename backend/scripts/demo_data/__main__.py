import argparse
import sys
from importlib import import_module
from pathlib import Path

from app.core.config import settings
from scripts.demo import DOMAIN
from scripts.demo_data import PARTS, load
from scripts.seed import db_name


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Create the Top Edge Technologies demo activity.")
    p.add_argument("--admin-email", required=True)
    p.add_argument("--only", help=f"comma-separated parts (default all, in order): {', '.join(PARTS)}")
    p.add_argument("--accounts-out", help="the accounts file scripts.demo wrote: new hires and leavers are added")
    a = p.parse_args()
    name = db_name(settings.db_url)
    if not name.lower().endswith(("_dev", "_demo")):
        sys.exit(f"refused: {name} is not a *_dev or *_demo database")
    parts = [x.strip() for x in a.only.split(",")] if a.only else list(PARTS)
    unknown = [x for x in parts if x not in PARTS]
    if unknown:
        sys.exit(f"unknown parts: {', '.join(unknown)}")
    w = load(a.admin_email)
    for part in parts:
        print(f"== {part}")
        import_module(f"scripts.demo_data.{part}").seed(w)
    if a.accounts_out:
        update_accounts(w, Path(a.accounts_out))
    print("done")


def update_accounts(w, path: Path) -> None:
    """Gives people hired by the parts (recruitment) a sign-in, and notes who has left, in the accounts file."""
    users = w.admin.all("/access/users")
    linked = {u["employeeId"] for u in users if u.get("employeeId")}
    roles = {r["code"]: r for r in w.admin.all("/access/roles")}
    rows = []
    for e in w.admin.all("/employees?includeInactive=true"):
        if e["status"] in ("left", "inactive"):
            rows.append(f"- {e['name']} ({e.get('departmentName')}) has left (status left); their sign-in still "
                        "works, to read their own records.")
        elif e["id"] not in linked:
            email = f"{e['firstName']}.{e['lastName']}@{DOMAIN}".lower()
            w.admin("POST", "/access/users", {"email": email, "employeeId": int(e["id"]), "password": w.demo_password,
                                              "roleIds": [int(roles["employee"]["id"])]})
            rows.append(f"- New hire {e['name']} ({e.get('departmentName')}, {e.get('jobTitleName')}, joins "
                        f"{e.get('joiningDate')}): `{email}`, Employee, same password.")
    if rows and path.exists():
        with path.open("a", encoding="utf-8") as f:
            f.write("\n## Changes from the demo activity\n\n" + "\n".join(rows) + "\n")
        print(f"accounts: {len(rows)} change(s) added to {path}")


if __name__ == "__main__":
    main()
