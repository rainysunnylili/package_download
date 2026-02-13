"""Download router for serving archive files"""
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
import logging

from app.services.task_manager import task_manager
from app.models.schemas import TaskStatus

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["download"])


@router.get("/tasks/{task_id}/archive")
async def download_archive(task_id: str):
    """Download the archive file for a completed task"""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.status != TaskStatus.COMPLETED:
        raise HTTPException(
            status_code=400,
            detail=f"Task is in {task.status} status, archive not ready"
        )

    archive_path = task_manager.get_archive_path(task_id)
    if not archive_path.exists():
        raise HTTPException(status_code=404, detail="Archive file not found")

    return FileResponse(
        path=str(archive_path),
        media_type="application/zip",
        filename=f"packages-{task_id}.zip"
    )
