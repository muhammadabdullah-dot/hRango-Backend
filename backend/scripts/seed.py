r"""The seeder: installs or updates a complete HRango database on any SQL Server.

Steps, in order:
  1. db/migrations/*.sql   the DDL (schemas, tables, keys, indexes). Applied once each, in name
                           order, each in one transaction; recorded in dbo.schema_migration with a
                           checksum, so an applied file must never change.
  2. db/procedures/**.sql  functions (fn_*) then procedures (usp_*). CREATE OR ALTER, re-applied
                           on every run.
  3. db/seeds/*.sql        reference data. Idempotent, re-applied on every run.
  4. auth.permission       synced from the catalogue (app/catalogue, app/core/permissions.py).
  5. default roles         offered to every company (app/core/default_roles.py); a permission a
                           customer removed from a role is not offered again.

Run from the backend folder (connection comes from DB_URL in .env):
  .venv\\Scripts\\python.exe -m scripts.seed              bring the database up to date
  .venv\\Scripts\\python.exe -m scripts.seed --create     also create the database if missing
  .venv\\Scripts\\python.exe -m scripts.seed --reset      drop and recreate (only *_dev databases)
  .venv\\Scripts\\python.exe -m scripts.seed --export hrango_install.sql
        write everything as one script for SSMS or sqlcmd, for a server without Python.
        The script is for an empty database.
  .venv\Scripts\python.exe -m scripts.seed --bootstrap --company "Top Edge Technologies" --admin-email admin@example.com
        first install: also create the company and its administrator. The password is read from
        HRANGO_ADMIN_PASSWORD, or asked for.
"""
import argparse
import getpass
import hashlib
import os
import json
import re
import sys
from pathlib import Path

import pyodbc

from app.core.config import settings
from app.core.default_roles import expanded as default_roles
from app.core.permissions import catalogue_rows
from app.core.security import hash_password

ROOT = Path(__file__).resolve().parent.parent / "db"
# Overridable for parallel work: --migrations-dir points at your own generated baseline.
MIGRATIONS_DIR = ROOT / "migrations"
# --keep-going: report a failing procedure or seed file and carry on (development only).
KEEP_GOING = False
GO = re.compile(r"^\s*GO\s*$", re.M | re.I)
TRACKING_DDL = """IF OBJECT_ID(N'dbo.schema_migration') IS NULL
    CREATE TABLE dbo.schema_migration (
        file_name NVARCHAR(200) NOT NULL CONSTRAINT PK_schema_migration PRIMARY KEY,
        checksum CHAR(64) NOT NULL,
        applied_at DATETIME2(0) NOT NULL CONSTRAINT DF_schema_migration_applied_at DEFAULT SYSUTCDATETIME())"""


def batches(sql: str) -> list[str]:
    return [b.strip() for b in GO.split(sql) if b.strip()]


def migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


def procedure_files() -> list[Path]:
    return sorted((ROOT / "procedures").rglob("*.sql"), key=lambda p: (not p.name.startswith("fn_"), str(p)))


def seed_files() -> list[Path]:
    return sorted((ROOT / "seeds").glob("*.sql"))


def checksum(sql: str) -> str:
    return hashlib.sha256(sql.encode("utf-8")).hexdigest()


def catalogue_json() -> str:
    return json.dumps(catalogue_rows(), ensure_ascii=False)


def roles_json() -> str:
    return json.dumps(default_roles(), ensure_ascii=False)


# ---------------------------------------------------------------- live database

def db_name(conn_str: str) -> str:
    m = re.search(r"(?:Database|Initial Catalog)=([^;]+)", conn_str, re.I)
    if not m:
        sys.exit("DB_URL has no Database=...")
    return m.group(1).strip()


def ensure_database(name: str, reset: bool) -> None:
    master = re.sub(r"((?:Database|Initial Catalog)=)[^;]+", r"\1master", settings.db_url, flags=re.I)
    conn = pyodbc.connect(master, autocommit=True)
    cur = conn.cursor()
    exists = cur.execute("SELECT DB_ID(?)", name).fetchval() is not None
    if reset and exists:
        if not name.lower().endswith("_dev"):
            sys.exit(f"--reset refused: {name} is not a *_dev database")
        cur.execute(f"ALTER DATABASE [{name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{name}]")
        print(f"dropped {name}")
        exists = False
    if not exists:
        cur.execute(f"CREATE DATABASE [{name}]")
        print(f"created {name}")
    conn.close()


def run_file(cur: pyodbc.Cursor, f: Path, tolerant: bool = False) -> bool:
    for b in batches(f.read_text(encoding="utf-8")):
        try:
            cur.execute(b)
            while cur.nextset():
                pass
        except pyodbc.Error as exc:
            print(f"FAILED in {f}")
            if tolerant and KEEP_GOING:
                print(f"  {exc.args[-1] if exc.args else exc}")
                return False
            raise
    return True


def apply_migrations(conn: pyodbc.Connection) -> int:
    cur = conn.cursor()
    cur.execute(TRACKING_DDL)
    applied = {r.file_name: r.checksum for r in cur.execute("SELECT file_name, checksum FROM dbo.schema_migration")}
    count = 0
    for f in migration_files():
        digest = checksum(f.read_text(encoding="utf-8"))
        if f.name in applied:
            if applied[f.name] != digest:
                sys.exit(f"{f.name} changed after it was applied. Add a new migration instead "
                         f"(or --reset a development database).")
            continue
        conn.autocommit = False
        try:
            run_file(cur, f)
            cur.execute("INSERT dbo.schema_migration (file_name, checksum) VALUES (?, ?)", f.name, digest)
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.autocommit = True
        print(f"  applied {f.name}")
        count += 1
    return count


def install(create: bool, reset: bool, bootstrap: tuple[str, str] | None) -> None:
    if not settings.db_url:
        sys.exit("DB_URL is not set in .env")
    if create or reset:
        ensure_database(db_name(settings.db_url), reset)
    conn = pyodbc.connect(settings.db_url, autocommit=True)
    cur = conn.cursor()
    print(f"migrations: {apply_migrations(conn)} applied")
    procs = procedure_files()
    ok = sum(run_file(cur, f, tolerant=True) for f in procs)
    print(f"procedures: {ok} of {len(procs)} applied")
    seeds = seed_files()
    ok = sum(run_file(cur, f, tolerant=True) for f in seeds)
    print(f"seeds: {ok} of {len(seeds)} applied")
    r = cur.execute("EXEC auth.usp_permission_sync @catalogue = ?", catalogue_json()).fetchone()
    print(f"permissions: {r.total} in catalogue, {r.added} added, {r.retired} no longer in code")
    if bootstrap:
        bootstrap_company(cur, *bootstrap)
    roles = roles_json()
    for (company_id,) in cur.execute("SELECT id FROM org.company ORDER BY id").fetchall():
        r = cur.execute("EXEC auth.usp_role_defaults_apply @company_id = ?, @roles = ?", company_id, roles).fetchone()
        print(f"company {company_id}: {r.roles_added} roles added, {r.permissions_offered} permissions offered")
    conn.close()


def bootstrap_company(cur: pyodbc.Cursor, company: str, admin_email: str) -> None:
    """First install: the company, its default roles and a system administrator."""
    password = os.environ.get("HRANGO_ADMIN_PASSWORD") or getpass.getpass(f"Password for {admin_email}: ")
    if len(password) < 8:
        sys.exit("The administrator password must be at least 8 characters.")
    company_id = cur.execute("EXEC org.usp_company_provision @name = ?", company).fetchval()
    cur.execute("EXEC auth.usp_role_defaults_apply @company_id = ?, @roles = ?", company_id, roles_json()).fetchall()
    cur.execute("EXEC auth.usp_user_provision @company_id = ?, @email = ?, @password_hash = ?, @display_name = ?, "
                "@is_system_admin = 1, @role_codes = ?", company_id, admin_email, hash_password(password),
                "Administrator", "company_admin").fetchall()
    print(f"bootstrap: company {company!r} (id {company_id}), administrator {admin_email}")


# ---------------------------------------------------------------- one-file export

def export(path: Path) -> None:
    out = ["-- HRango full install script. Generated by scripts/seed.py --export; do not edit by hand.",
           "-- Run it connected to an EMPTY database (SSMS, or: sqlcmd -S <server> -d <database> -i <this file>).",
           # Procedures keep the settings they were created under; filtered indexes need these ON.
           "SET NOCOUNT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;", "GO", TRACKING_DDL, "GO", ""]
    for f in migration_files():
        sql = f.read_text(encoding="utf-8")
        out += [f"-- ===== migration {f.name}", sql.strip(), "GO",
                f"INSERT dbo.schema_migration (file_name, checksum) VALUES (N'{f.name}', '{checksum(sql)}');", "GO", ""]
    for f in procedure_files() + seed_files():
        out += [f"-- ===== {f.relative_to(ROOT).as_posix()}", f.read_text(encoding="utf-8").strip(), "GO", ""]
    literal = catalogue_json().replace("'", "''")
    out += ["-- ===== permission catalogue", f"EXEC auth.usp_permission_sync @catalogue = N'{literal}';", "GO", ""]
    roles = roles_json().replace("'", "''")
    out += ["-- ===== default roles, for every company already in the database",
            "DECLARE @company_id BIGINT = (SELECT MIN(id) FROM org.company);",
            "WHILE @company_id IS NOT NULL",
            "BEGIN",
            f"    EXEC auth.usp_role_defaults_apply @company_id = @company_id, @roles = N'{roles}';",
            "    SET @company_id = (SELECT MIN(id) FROM org.company WHERE id > @company_id);",
            "END", "GO", ""]
    path.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {path} ({path.stat().st_size // 1024} KB)")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Install or update the HRango database.")
    p.add_argument("--create", action="store_true", help="create the database if it does not exist")
    p.add_argument("--reset", action="store_true", help="drop and recreate a *_dev database")
    p.add_argument("--export", metavar="FILE", help="write one install script instead of touching a database")
    p.add_argument("--bootstrap", action="store_true", help="create the first company and its administrator")
    p.add_argument("--company", help="company name for --bootstrap")
    p.add_argument("--admin-email", help="administrator email for --bootstrap")
    p.add_argument("--migrations-dir", help="read migrations from this folder (parallel development)")
    p.add_argument("--keep-going", action="store_true", help="report failing procedure/seed files and continue")
    a = p.parse_args()
    global MIGRATIONS_DIR, KEEP_GOING
    if a.migrations_dir:
        MIGRATIONS_DIR = Path(a.migrations_dir).resolve()
    KEEP_GOING = a.keep_going
    if a.bootstrap and not (a.company and a.admin_email):
        p.error("--bootstrap needs --company and --admin-email")
    if a.export:
        export(Path(a.export))
    else:
        install(a.create, a.reset, (a.company, a.admin_email) if a.bootstrap else None)


if __name__ == "__main__":
    main()
