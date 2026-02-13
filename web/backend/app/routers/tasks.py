"""Tasks router for task management and operations"""
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, BackgroundTasks
from fastapi.responses import JSONResponse
import logging
import asyncio

from app.models.schemas import (
    TaskInfo,
    DependenciesResponse,
    TaskListResponse,
    TaskStatus
)
from app.services.task_manager import task_manager
from app.services.parser import file_parser
from app.services.npm_downloader import npm_downloader
from app.services.pypi_downloader import pypi_downloader
from app.services.packager import packager
from app.ws.manager import manager as ws_manager

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["tasks"])


@router.get("/tasks", response_model=TaskListResponse)
async def list_tasks(page: int = 1, size: int = 20):
    """List all tasks with pagination"""
    try:
        tasks, total = task_manager.list_tasks(page, size)
        return TaskListResponse(tasks=tasks, total=total)
    except Exception as e:
        logger.error(f"Error listing tasks: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/tasks/{task_id}", response_model=TaskInfo)
async def get_task(task_id: str):
    """Get task information"""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.get("/tasks/{task_id}/dependencies", response_model=DependenciesResponse)
async def get_dependencies(task_id: str):
    """Get parsed dependencies for a task"""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    response = DependenciesResponse(task_id=task_id)

    if task.npm_dependencies:
        # Count total NPM packages
        def count_packages(node):
            count = 1
            for child in node.children:
                count += count_packages(child)
            return count

        npm_total = count_packages(task.npm_dependencies) if task.npm_dependencies else 0
        response.npm = {
            "total": npm_total,
            "tree": task.npm_dependencies
        }

    if task.pypi_dependencies:
        response.pypi = {
            "total": len(task.pypi_dependencies),
            "packages": task.pypi_dependencies
        }

    return response


@router.post("/tasks/{task_id}/parse")
async def parse_task(task_id: str, background_tasks: BackgroundTasks):
    """Parse dependencies for a task"""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.status != TaskStatus.CREATED:
        raise HTTPException(
            status_code=400,
            detail=f"Task is in {task.status} status, cannot parse"
        )

    # Start parsing in background
    background_tasks.add_task(parse_dependencies_background, task_id)

    return JSONResponse({"task_id": task_id, "status": "parsing"})


@router.post("/tasks/{task_id}/download")
async def start_download(task_id: str, background_tasks: BackgroundTasks):
    """Start downloading packages for a task"""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.status not in [TaskStatus.CREATED, TaskStatus.PARSED]:
        raise HTTPException(
            status_code=400,
            detail=f"Task is in {task.status} status, cannot download"
        )

    # Start download in background
    background_tasks.add_task(download_packages_background, task_id)

    return JSONResponse({"task_id": task_id, "status": "downloading"})


@router.delete("/tasks/{task_id}")
async def delete_task(task_id: str):
    """Delete a task and its files"""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    task_manager.delete_task(task_id)
    return JSONResponse({"message": "Task deleted successfully"})


@router.websocket("/ws/tasks/{task_id}")
async def websocket_endpoint(websocket: WebSocket, task_id: str):
    """WebSocket endpoint for real-time task updates"""
    task = task_manager.get_task(task_id)
    if not task:
        await websocket.close(code=1008)
        return

    await ws_manager.connect(task_id, websocket)
    try:
        while True:
            # Keep connection alive and wait for messages
            data = await websocket.receive_text()
            # Echo back or handle client messages if needed
    except WebSocketDisconnect:
        ws_manager.disconnect(task_id, websocket)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        ws_manager.disconnect(task_id, websocket)


async def parse_dependencies_background(task_id: str):
    """Background task to parse dependencies"""
    try:
        task = task_manager.get_task(task_id)
        if not task:
            return

        # Update status
        task_manager.update_task(task_id, status=TaskStatus.PARSING)

        upload_dir = task_manager.get_upload_dir(task_id)

        # Parse NPM dependencies
        if task.options.npm:
            npm_tree = await npm_downloader.parse_dependencies(
                task_id,
                upload_dir,
                task.options.node_version
            )
            task_manager.update_task(task_id, npm_dependencies=npm_tree)

        # Parse Python dependencies
        if task.options.pypi:
            pypi_packages = await pypi_downloader.parse_dependencies(
                task_id,
                upload_dir,
                task.options.python_version
            )
            task_manager.update_task(task_id, pypi_dependencies=pypi_packages)

        # Update status
        task_manager.update_task(task_id, status=TaskStatus.PARSED)

        await ws_manager.broadcast(task_id, "complete", {
            "phase": "parsing",
            "message": "Dependency parsing complete"
        })

    except Exception as e:
        logger.error(f"Error parsing dependencies for task {task_id}: {e}")
        task_manager.update_task(task_id, status=TaskStatus.FAILED, error=str(e))
        await ws_manager.broadcast(task_id, "error", {
            "phase": "parsing",
            "message": f"Parsing failed: {str(e)}"
        })


async def download_packages_background(task_id: str):
    """Background task to download packages"""
    try:
        task = task_manager.get_task(task_id)
        if not task:
            return

        # Update status
        task_manager.update_task(task_id, status=TaskStatus.DOWNLOADING)

        upload_dir = task_manager.get_upload_dir(task_id)
        npm_dir = task_manager.get_npm_dir(task_id)
        pypi_dir = task_manager.get_pypi_dir(task_id)

        # Download NPM packages
        if task.options.npm:
            npm_progress = await npm_downloader.download_packages(
                task_id,
                upload_dir,
                npm_dir,
                task.options.node_version,
                task.npm_progress
            )
            task_manager.update_task(task_id, npm_progress=npm_progress)

        # Download Python packages
        if task.options.pypi:
            pypi_progress = await pypi_downloader.download_packages(
                task_id,
                upload_dir,
                pypi_dir,
                task.options.python_version,
                task.options.platforms,
                task.pypi_progress
            )
            task_manager.update_task(task_id, pypi_progress=pypi_progress)

        # Create archive
        task_manager.update_task(task_id, status=TaskStatus.PACKING)
        archive_path = task_manager.get_archive_path(task_id)
        task_dir = task_manager.get_task_dir(task_id)

        archive_path, archive_size = await packager.create_archive(
            task_id,
            task_dir,
            npm_dir,
            pypi_dir,
            archive_path
        )

        # Update task with archive info
        import datetime
        task_manager.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            archive_url=f"/api/tasks/{task_id}/archive",
            archive_size=archive_size,
            completed_at=datetime.datetime.now()
        )

        await ws_manager.broadcast(task_id, "complete", {
            "phase": "packing",
            "message": "Download and packaging complete"
        })

    except Exception as e:
        logger.error(f"Error downloading packages for task {task_id}: {e}")
        task_manager.update_task(task_id, status=TaskStatus.FAILED, error=str(e))
        await ws_manager.broadcast(task_id, "error", {
            "phase": "downloading",
            "message": f"Download failed: {str(e)}"
        })
