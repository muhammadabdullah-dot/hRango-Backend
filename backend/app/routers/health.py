from fastapi import APIRouter

from app.controllers import health_controller
from app.schemas.health import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return health_controller.get_health()
