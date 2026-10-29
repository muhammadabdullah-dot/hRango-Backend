"""External file sources (Backend Dependencies T9). No OAuth client is configured yet, so nothing is
connected: the list shows the four providers as not connected, and connecting, the OAuth callback and
browsing files answer 503 STORAGE_NOT_CONFIGURED.

TODO(storage): per provider an OAuth app (client id / secret in settings), a table of connections per
user (tokens encrypted at rest, refresh), the callback that stores them and redirects to redirectPath,
file browsing through each provider's API, and revoking on disconnect."""
from typing import Any

from app.core.errors import AppError
from app.middlewares.auth import RequestContext
from app.schemas.integrations_storage import PROVIDERS


def _not_configured(provider: str) -> AppError:
    name = {"google_drive": "Google Drive", "onedrive": "OneDrive"}.get(provider, provider.title())
    return AppError(503, "STORAGE_NOT_CONFIGURED", f"{name} is not set up on this server.")


def list_connections(ctx: RequestContext) -> list[dict[str, Any]]:
    return [{"provider": p, "connected": False, "account_email": None, "connected_at": None} for p in PROVIDERS]


def connect(ctx: RequestContext, provider: str, redirect_path: str) -> dict[str, Any]:
    raise _not_configured(provider)


def callback(provider: str, code: str | None, state: str | None) -> None:
    raise _not_configured(provider)


def disconnect(ctx: RequestContext, provider: str) -> None:
    """Nothing is stored yet, so there is nothing to remove."""


def list_files(ctx: RequestContext, provider: str, path: str | None, q: str | None,
               page_token: str | None) -> dict[str, Any]:
    raise _not_configured(provider)
