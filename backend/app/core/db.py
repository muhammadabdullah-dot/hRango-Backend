"""SQL Server connection. All data access goes through stored procedures, called from app/repos.

Connections run in autocommit mode: every procedure is its own unit of work and manages its own
transaction (SET XACT_ABORT ON). When a service must call several procedures as one unit, it wraps
them in `db.transaction()`.
"""
import re
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any

import pyodbc

from app.core.config import settings
from app.core.errors import AppError

_NAME = re.compile(r"^\[?\w+\]?\.\[?\w+\]?$")
_PARAM = re.compile(r"^\w+$")
_NATIVE_ERROR = re.compile(r"\((\d+)\) \(SQL")

# Error numbers our procedures THROW on purpose. The message text is written for the user.
_THROWN = {50400: (422, "VALIDATION_FAILED"), 50403: (403, "FORBIDDEN"), 50404: (404, "NOT_FOUND"),
           50409: (409, "CONFLICT")}
# SQL Server's own errors that mean the request, not the server, is wrong.
_ENGINE = {2627: (409, "DUPLICATE", "A record with the same value already exists."),
           2601: (409, "DUPLICATE", "A record with the same value already exists."),
           547: (409, "IN_USE", "This record is linked to other records.")}
# A thrown message may name the form field it belongs to: N'name|A department with this name already exists'.
# An optional code may follow the field: N'title|POLICY_DUPLICATE|A policy with this title already exists'.
_FIELD = re.compile(r"^([A-Za-z][\w.\[\]]*)\|(?:([A-Z][A-Z0-9_]+)\|)?(.*)$", re.S)


# One driver error can carry several server messages (a warning such as 8153 "Null value is eliminated"
# before the THROW): every "[SQL Server]<text> (<number>)" in it.
_MESSAGES = re.compile(r"\[SQL Server\](.*?) \((\d+)\)(?= \[| \(SQL|$)", re.S)


def _translate(exc: pyodbc.Error) -> Exception:
    text = str(exc.args[1]) if len(exc.args) > 1 else str(exc)
    found = [(int(n), m.strip()) for m, n in _MESSAGES.findall(text)]
    if not found:
        m = _NATIVE_ERROR.search(text)
        found = [(int(m.group(1)), "")] if m else []
    for number, message in found:
        if number in _THROWN:
            status, code = _THROWN[number]
            message = message or "Request rejected."
            f = _FIELD.match(message)
            if f:
                field, own_code, message = f.group(1), f.group(2), f.group(3).strip()
                return AppError(status, own_code or code, message, {field: message})
            return AppError(status, code, message)
    for number, _ in found:
        if number in _ENGINE:
            return AppError(*_ENGINE[number])
    return exc


class Db:
    def __init__(self, conn: pyodbc.Connection):
        self.conn = conn

    def _exec(self, proc: str, params: dict[str, Any]) -> pyodbc.Cursor:
        if not _NAME.match(proc):
            raise ValueError(f"bad procedure name {proc!r}")
        names = list(params)
        for n in names:
            if not _PARAM.match(n):
                raise ValueError(f"bad parameter name {n!r}")
        sql = f"SET NOCOUNT ON; EXEC {proc} " + ", ".join(f"@{n} = ?" for n in names)
        try:
            return self.conn.cursor().execute(sql, *[params[n] for n in names])
        except pyodbc.Error as exc:
            raise _translate(exc) from exc

    @staticmethod
    def _rows(cur: pyodbc.Cursor) -> list[dict[str, Any]]:
        if cur.description is None:
            return []
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]

    def call(self, proc: str, **params: Any) -> list[dict[str, Any]]:
        """Run a procedure and return its first result set."""
        cur = self._exec(proc, params)
        try:
            return self._rows(cur)
        except pyodbc.Error as exc:
            raise _translate(exc) from exc
        finally:
            cur.close()

    def call_one(self, proc: str, **params: Any) -> dict[str, Any] | None:
        rows = self.call(proc, **params)
        return rows[0] if rows else None

    def call_sets(self, proc: str, **params: Any) -> list[list[dict[str, Any]]]:
        """Run a procedure that returns several result sets (e.g. a header and its lines)."""
        cur = self._exec(proc, params)
        sets = []
        try:
            while True:
                if cur.description is not None:
                    sets.append(self._rows(cur))
                if not cur.nextset():
                    break
        except pyodbc.Error as exc:
            raise _translate(exc) from exc
        finally:
            cur.close()
        return sets

    @contextmanager
    def transaction(self) -> Iterator["Db"]:
        self.conn.autocommit = False
        try:
            yield self
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise
        finally:
            self.conn.autocommit = True


def connect() -> pyodbc.Connection:
    if not settings.db_url:
        raise RuntimeError("DB_URL is not set in .env")
    return pyodbc.connect(settings.db_url, autocommit=True)


def get_db() -> Iterator[Db]:
    """FastAPI dependency: one connection per request, returned to the ODBC pool afterwards."""
    conn = connect()
    try:
        yield Db(conn)
    finally:
        conn.close()
