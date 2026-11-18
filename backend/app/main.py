import os
from contextlib import asynccontextmanager
from importlib import import_module

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import check_startup, settings
from app.core.logging import setup_logging
from app.middlewares.body_limit import BodyLimit
from app.middlewares.errors import register_error_handlers
from app.middlewares.request_log import request_log
from app.middlewares.security_headers import SecurityHeaders
from app.routers.health import router as health_router

# Before anything else: no API with a forgeable signing secret or an open CORS policy in production.
check_startup(settings)
setup_logging()

# One router per module, all under /api (the frontend's VITE_API_BASE_URL).
ROUTERS = ("auth", "files", "access", "integrations", "organisation", "employees", "dashboard", "inbox", "attendance",
           "roster", "scheduling", "warning", "requests", "leaves", "loans", "payroll", "assets", "offboarding",
           "manpower", "recruitment", "performance", "training", "benefits", "engagement", "projects", "forms",
           "public", "integrations_storage", "platform")



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


# The interactive docs list every route and field: on in development, off in production unless API_DOCS=true.
_docs = settings.docs_enabled
app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan,
              docs_url="/docs" if _docs else None, redoc_url="/redoc" if _docs else None,
              openapi_url="/openapi.json" if _docs else None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
    # Content-Disposition: a browser on another origin can then read a download's file name (bank files,
    # exports); without it every file falls back to the name the screen guesses.
    expose_headers=["X-Request-Id", "Content-Disposition"],
)
app.middleware("http")(request_log)
# Added last = outermost: oversized bodies are refused before any other layer reads them, and every
# response, errors included, carries the security headers.
app.add_middleware(SecurityHeaders)
app.add_middleware(BodyLimit)
register_error_handlers(app)

app.include_router(health_router)
app.include_router(health_router, prefix="/api")
# HRANGO_ROUTERS=auth,payroll loads only those routers (parallel development and focused tests).
_only = {n.strip() for n in os.environ.get("HRANGO_ROUTERS", "").split(",") if n.strip()}
for name in ROUTERS:
    if not _only or name in _only:
        app.include_router(import_module(f"app.routers.{name}").router, prefix="/api")


if __name__ == "__main__":
    uvicorn.run("app.main:app", host=settings.host, port=settings.port, proxy_headers=True,
                forwarded_allow_ips=settings.forwarded_allow_ips)
