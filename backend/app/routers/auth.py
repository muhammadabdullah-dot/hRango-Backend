from fastapi import APIRouter, Depends, Request, Response, status

from app.controllers import auth_controller
from app.core.db import Db, get_db
from app.middlewares.auth import RequestContext, get_context
from app.schemas.auth import AuthSession, AuthUser, LoginIn
from app.schemas.common import Item

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=Item[AuthSession])
def login(body: LoginIn, request: Request, db: Db = Depends(get_db)) -> dict:
    device = (request.headers.get("User-Agent") or "")[:200] or None
    ip = request.client.host if request.client else None
    return auth_controller.login(db, body, device, ip)


@router.get("/me", response_model=Item[AuthUser])
def me(db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> dict:
    return auth_controller.me(db, ctx)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(db: Db = Depends(get_db), ctx: RequestContext = Depends(get_context)) -> Response:
    auth_controller.logout(db, ctx)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
