import os
from contextlib import asynccontextmanager
from importlib import import_module

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.logging import setup_logging
from app.middlewares.errors import register_error_handlers
from app.middlewares.request_log import request_log
from app.routers.health import router as health_router

setup_logging()

# One router per module, all under /api (the frontend's VITE_API_BASE_URL).
ROUTERS = ("auth", "files", "access", "integrations", "organisation", "employees", "dashboard", "inbox", "attendance",
           "roster", "scheduling", "warning", "requests", "leaves", "loans", "payroll", "assets", "offboarding",
           "manpower", "recruitment", "performance", "training", "benefits", "engagement", "projects")



@asynccontextmanager
async def lifespan(_: FastAPI):
    """Starts the webhook worker with the API (settings.webhook_worker), and stops it on shutdown."""
    worker = None
    if settings.webhook_worker:
        from app.services.webhook_dispatcher import Worker

        worker = Worker()
        worker.start()
    yield
    if worker:
        worker.close()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-Id"],
)
app.middleware("http")(request_log)
register_error_handlers(app)

app.include_router(health_router)
app.include_router(health_router, prefix="/api")
# HRANGO_ROUTERS=auth,payroll loads only those routers (parallel development and focused tests).
_only = {n.strip() for n in os.environ.get("HRANGO_ROUTERS", "").split(",") if n.strip()}
for name in ROUTERS:
    if not _only or name in _only:
        app.include_router(import_module(f"app.routers.{name}").router, prefix="/api")


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="127.0.0.1", port=settings.port)
