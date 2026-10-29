"""Project management under /api/projects. The endpoints are split by area; this router includes them.
The public share page is routers/public.py (/api/public, no sign-in)."""
from fastapi import APIRouter

from app.routers import (projects_ai, projects_collab, projects_docs, projects_extras, projects_tasks,
                         projects_workspaces)

router = APIRouter(prefix="/projects", tags=["projects"])
router.include_router(projects_workspaces.router)
router.include_router(projects_tasks.router)
router.include_router(projects_collab.router)
router.include_router(projects_docs.router)
router.include_router(projects_extras.router)
router.include_router(projects_ai.router)
