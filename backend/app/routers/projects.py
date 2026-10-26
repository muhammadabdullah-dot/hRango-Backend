"""Project management under /api/projects. The endpoints are split by area; this router includes them."""
from fastapi import APIRouter

from app.routers import projects_collab, projects_tasks, projects_workspaces

router = APIRouter(prefix="/projects", tags=["projects"])
router.include_router(projects_workspaces.router)
router.include_router(projects_tasks.router)
router.include_router(projects_collab.router)
