"""Uploading, reading and deleting files. Who may download a file is decided by the module whose
record holds it: that module hands out signed links (app/core/files.file_url)."""
from pathlib import Path
from typing import Any, BinaryIO

from app.core import files
from app.core.db import Db
from app.core.errors import AppError, not_found
from app.core.permissions import MODULES
from app.middlewares.auth import RequestContext
from app.repos import files_repo

UPLOAD_MODULES = frozenset(MODULES) | {"core"}


def upload(db: Db, ctx: RequestContext, stream: BinaryIO, name: str | None, module: str) -> dict[str, Any]:
    if module not in UPLOAD_MODULES:
        raise AppError(422, "VALIDATION_FAILED", "module is not valid.", {"module": "Not a module name."})
    stored = files.save(stream, name, ctx.company_id, module)
    try:
        return files_repo.create(db, ctx.company_id, ctx.user_id, module, stored)
    except Exception:
        files.remove(stored.storage_path)
        raise


def get_own(db: Db, ctx: RequestContext, file_id: int) -> dict[str, Any]:
    """A file's details for the person who uploaded it (or a system administrator)."""
    row = files_repo.get(db, ctx.company_id, file_id)
    if row is None or (row["uploaded_by_user_id"] != ctx.user_id and not ctx.is_system_admin):
        raise not_found("File")
    return row


def for_download(db: Db, file_id: int, token: str) -> tuple[dict[str, Any], Path]:
    company_id = files.read_file_token(token, file_id)
    if company_id is None:
        raise AppError(403, "LINK_EXPIRED", "This download link has expired. Open the record again for a new one.")
    row = files_repo.get(db, company_id, file_id)
    if row is None:
        raise not_found("File")
    path = files.path_of(row["storage_path"])
    if not path.is_file():
        raise not_found("File")
    return row, path


def delete(db: Db, ctx: RequestContext, file_id: int) -> None:
    storage_path = files_repo.delete(db, ctx.company_id, ctx.user_id, file_id)
    files.remove(storage_path)
