from fastapi import APIRouter, Depends, Request, Response, status

from app.controllers import auth_controller
from app.core.db import Db, get_db
from app.middlewares.auth import RequestContext, get_context
from app.schemas.auth import (AcceptedOut, AuthSession, AuthUser, ForgotPasswordIn, LinkOut, LoginIn, MessageOut,
                              SetPasswordIn, TokenIn)
from app.schemas.common import Item
from app.services import account_links_service as links

router = APIRouter(prefix="/auth", tags=["auth"])
_FORGOT_ANSWER = "If an account uses that address, we have sent it a link to choose a new password."


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


# ---------------------------------------------------------------- e-mail links (no sign-in)

@router.post("/password/forgot", response_model=Item[MessageOut], status_code=status.HTTP_202_ACCEPTED)
def forgot_password(body: ForgotPasswordIn, request: Request, db: Db = Depends(get_db)) -> dict:
    """E-mails a reset link when the address has an active account. The answer is the same either way.
    503 MAIL_UNAVAILABLE when e-mail is not set up; 429 after too many requests."""
    links.request_reset(db, body.email, request.client.host if request.client else None)
    return {"data": MessageOut(message=_FORGOT_ANSWER)}


@router.post("/links/inspect", response_model=Item[LinkOut])
def inspect_link(body: TokenIn, db: Db = Depends(get_db)) -> dict:
    """What a reset or invitation link is for and whose account it is, without using it.
    404 LINK_NOT_FOUND, 410 LINK_EXPIRED or LINK_USED."""
    return {"data": LinkOut(**links.inspect(db, body.token))}


@router.post("/password/reset", response_model=Item[AcceptedOut])
def reset_password(body: SetPasswordIn, db: Db = Depends(get_db)) -> dict:
    """Sets the new password from a reset link; every open session of the account ends."""
    return {"data": AcceptedOut(email=links.reset_password(db, body.token, body.password))}


@router.post("/invite/accept", response_model=Item[AcceptedOut])
def accept_invite(body: SetPasswordIn, db: Db = Depends(get_db)) -> dict:
    """Sets the first password from an invitation link; the user then signs in with it."""
    return {"data": AcceptedOut(email=links.accept_invite(db, body.token, body.password))}
