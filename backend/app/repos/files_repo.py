"""Uploaded files."""
from typing import Any

from app.core.db import Db
from app.core.files import Stored


def create(db: Db, company_id: int, actor_user_id: int, module: str, f: Stored) -> dict[str, Any]:
    return db.call_one("core.usp_file_create", company_id=company_id, actor_user_id=actor_user_id, module=module,
                       name=f.name, extension=f.extension, mime_type=f.mime_type, size_bytes=f.size_bytes,
                       sha256=f.sha256, storage_path=f.storage_path)


def get(db: Db, company_id: int, file_id: int) -> dict[str, Any] | None:
    return db.call_one("core.usp_file_get", company_id=company_id, id=file_id)


def delete(db: Db, company_id: int, actor_user_id: int, file_id: int) -> str:
    return db.call_one("core.usp_file_delete", company_id=company_id, actor_user_id=actor_user_id,
                       id=file_id)["storage_path"]
