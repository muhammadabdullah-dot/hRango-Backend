"""External file sources (Backend Dependencies T9) under /integrations/storage: Google Drive, Dropbox, Box
and OneDrive, connected per person to attach files to tasks as links
(POST /api/projects/tasks/{taskId}/attachments/link). Not configured yet: see the service.

Register in app/main.py ROUTERS as "integrations_storage"."""
from fastapi import APIRouter, Depends, Query, Response, status

from app.controllers import integrations_storage_controller as c
from app.middlewares.auth import RequestContext, require
from app.schemas.common import Item
from app.schemas.integrations_storage import (Provider, StorageConnectIn, StorageConnectionOut, StorageConnectOut,
                                              StorageFilesOut)

router = APIRouter(prefix="/integrations/storage", tags=["integrations"])
NO_CONTENT = status.HTTP_204_NO_CONTENT
NOT_CONFIGURED = {503: {"description": "STORAGE_NOT_CONFIGURED: no OAuth app is set up for the provider"}}


@router.get("", response_model=Item[list[StorageConnectionOut]])
def list_connections(ctx: RequestContext = Depends(require("projects.storage.view"))) -> dict:
    return c.list_connections(ctx)


@router.post("/{provider}/connect", response_model=Item[StorageConnectOut], responses=NOT_CONFIGURED)
def connect(provider: Provider, body: StorageConnectIn,
            ctx: RequestContext = Depends(require("projects.storage.create"))) -> dict:
    return c.connect(ctx, provider, body.redirect_path)


@router.get("/{provider}/callback", status_code=status.HTTP_302_FOUND, responses=NOT_CONFIGURED)
def callback(provider: Provider, code: str | None = None, state: str | None = None) -> Response:
    """The provider's redirect after sign-in (no Authorization header: the state parameter identifies the person)."""
    c.callback(provider, code, state)
    return Response(status_code=status.HTTP_302_FOUND)


@router.delete("/{provider}", status_code=NO_CONTENT)
def disconnect(provider: Provider, ctx: RequestContext = Depends(require("projects.storage.delete"))) -> Response:
    c.disconnect(ctx, provider)
    return Response(status_code=NO_CONTENT)


@router.get("/{provider}/files", response_model=StorageFilesOut, responses=NOT_CONFIGURED)
def list_files(provider: Provider, path: str | None = Query(None, max_length=1000),
               q: str | None = Query(None, max_length=200), page_token: str | None = Query(None, alias="pageToken"),
               ctx: RequestContext = Depends(require("projects.storage.view"))) -> StorageFilesOut:
    return c.list_files(ctx, provider, path, q, page_token)
