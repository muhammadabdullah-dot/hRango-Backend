"""HTTP shape for external file sources."""
from app.middlewares.auth import RequestContext
from app.schemas.integrations_storage import StorageConnectionOut, StorageConnectOut, StorageFileOut, StorageFilesOut
from app.services import integrations_storage_service as s


def list_connections(ctx: RequestContext) -> dict:
    return {"data": [StorageConnectionOut(**r) for r in s.list_connections(ctx)]}


def connect(ctx: RequestContext, provider: str, redirect_path: str) -> dict:
    return {"data": StorageConnectOut(**s.connect(ctx, provider, redirect_path))}


def callback(provider: str, code: str | None, state: str | None) -> None:
    s.callback(provider, code, state)


def disconnect(ctx: RequestContext, provider: str) -> None:
    s.disconnect(ctx, provider)


def list_files(ctx: RequestContext, provider: str, path: str | None, q: str | None,
               page_token: str | None) -> StorageFilesOut:
    out = s.list_files(ctx, provider, path, q, page_token)
    return StorageFilesOut(data=[StorageFileOut(**f) for f in out["data"]], next_page_token=out.get("next_page_token"))
