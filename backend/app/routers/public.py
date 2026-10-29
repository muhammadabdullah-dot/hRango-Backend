"""Routes that work without signing in (shared project links). Each one checks its own token; there is no
auth dependency here. 404 SHARE_NOT_FOUND, 410 SHARE_EXPIRED / SHARE_EXHAUSTED."""
from fastapi import APIRouter, Depends, Path

from app.controllers import public_controller as c
from app.core.db import Db, get_db
from app.schemas.common import Item
from app.schemas.public import PublicShareOut, PublicTaskOut

router = APIRouter(prefix="/public", tags=["public"])
REFUSED = {404: {"description": "SHARE_NOT_FOUND"}, 410: {"description": "SHARE_EXPIRED or SHARE_EXHAUSTED"}}


@router.get("/shares/{token}", response_model=Item[PublicShareOut], responses=REFUSED)
def open_share(token: str = Path(min_length=8, max_length=100), db: Db = Depends(get_db)) -> dict:
    return c.open_share(db, token)


@router.get("/shares/{token}/tasks/{task_id}", response_model=Item[PublicTaskOut], responses=REFUSED)
def share_task(task_id: int, token: str = Path(min_length=8, max_length=100), db: Db = Depends(get_db)) -> dict:
    return c.share_task(db, token, task_id)
