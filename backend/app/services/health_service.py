"""Services hold the business logic and the database calls."""
from datetime import datetime, timezone

from app.core.config import settings
from app.schemas.health import HealthResponse


def check_health() -> HealthResponse:
    return HealthResponse(status="ok", service=settings.app_name, time=datetime.now(timezone.utc))
