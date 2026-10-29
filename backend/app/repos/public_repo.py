"""Data access for the pages that work without signing in (public share links)."""
from typing import Any

from app.core.db import Db

Rows = list[dict[str, Any]]


def open_share(db: Db, token: str) -> list[Rows]:
    """1 the link's state and settings, then (state ok) 2 its tasks."""
    return db.call_sets("pm.usp_public_share_open", token=token)


def share_task(db: Db, token: str, task_id: int) -> list[Rows]:
    """1 the link's state and settings, then (state ok) 2 the task, 3 subtasks, 4 checklist, 5 comments,
    6 attachments, 7 custom field values."""
    return db.call_sets("pm.usp_public_share_task", token=token, task_id=task_id)
