"""Routes that work without signing in: shared project links (each checks its own token; 404 SHARE_NOT_FOUND,
410 SHARE_EXPIRED / SHARE_NOT_STARTED / SHARE_EXHAUSTED; a task: 404 NOT_FOUND, 403 SHARE_TASKS_CLOSED), and
self-service sign-up with the plans on offer. The web app's page for a link is /shared/{token}."""
from fastapi import APIRouter, Depends, Path, Request, status

from app.controllers import public_controller as c
from app.core.db import Db, get_db
from app.core.errors import invalid
from app.schemas.common import Item
from app.schemas.public import PublicPlanOut, PublicShareOut, PublicTaskOut, SignUpIn, SignUpOut
from app.services import signup_service

router = APIRouter(prefix="/public", tags=["public"])
REFUSED = {404: {"description": "SHARE_NOT_FOUND"},
           410: {"description": "SHARE_EXPIRED, SHARE_NOT_STARTED or SHARE_EXHAUSTED"}}


@router.get("/shares/{token}", response_model=Item[PublicShareOut], responses=REFUSED)
def open_share(token: str = Path(min_length=8, max_length=100), db: Db = Depends(get_db)) -> dict:
    return c.open_share(db, token)


@router.get("/shares/{token}/tasks/{task_id}", response_model=Item[PublicTaskOut], responses=REFUSED)
def share_task(task_id: int, token: str = Path(min_length=8, max_length=100), db: Db = Depends(get_db)) -> dict:
    return c.share_task(db, token, task_id)


# ---------------------------------------------------------------- self-service sign-up (roadmap 1.1)

@router.get("/plans", response_model=Item[list[PublicPlanOut]])
def list_plans(db: Db = Depends(get_db)) -> dict:
    """The plans on offer, for the sign-up page."""
    return {"data": [PublicPlanOut(**row) for row in signup_service.public_plans(db)]}


@router.post("/signup", response_model=Item[SignUpOut], status_code=status.HTTP_202_ACCEPTED)
def sign_up(body: SignUpIn, request: Request, db: Db = Depends(get_db)) -> dict:
    """Creates an organisation on a 14-day trial and e-mails its owner a link to choose a password. The same
    answer when the e-mail already has an account (that person is told by e-mail instead).
    503 SIGNUP_UNAVAILABLE without e-mail; 429 after too many attempts."""
    if not body.accept_terms:
        raise invalid("Agree to the Terms of Service and Privacy Policy to continue.", "acceptTerms")
    signup_service.sign_up(db, body.model_dump(by_alias=False), request.client.host if request.client else None)
    return {"data": SignUpOut(message=signup_service.ANSWER)}
