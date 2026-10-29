"""HTTP shape for the pages that work without signing in."""
from app.core.db import Db
from app.schemas.public import PublicShareOut, PublicTaskOut
from app.services import public_service


def open_share(db: Db, token: str) -> dict:
    return {"data": PublicShareOut(**public_service.open_share(db, token))}


def share_task(db: Db, token: str, task_id: int) -> dict:
    return {"data": PublicTaskOut(**public_service.share_task(db, token, task_id))}
