"""Upload router for handling file uploads and task creation"""
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
import logging
from pathlib import Path
from typing import Optional
import json

from app.models.schemas import (
    TaskCreateResponse,
    DownloadOptions,
    TaskStatus
)
from app.services.task_manager import task_manager
from app.services.parser import file_parser
from app.config import config

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["upload"])


@router.post("/tasks", response_model=TaskCreateResponse)
async def create_task(
    files: list[UploadFile] = File(...),
    options: Optional[str] = Form(None)
):
    """Create a new download task by uploading dependency files"""
    try:
        # Parse options
        download_options = DownloadOptions()
        if options:
            try:
                options_data = json.loads(options)
                download_options = DownloadOptions(**options_data)
            except json.JSONDecodeError:
                raise HTTPException(status_code=400, detail="Invalid options format")

        # Validate files
        if not files:
            raise HTTPException(status_code=400, detail="No files provided")

        uploaded_files = []
        valid_files = []

        for file in files:
            # Validate file extension
            file_ext = Path(file.filename).suffix
            if file_ext not in config.ALLOWED_EXTENSIONS:
                logger.warning(f"Invalid file extension: {file.filename}")
                continue

            # Validate file size
            content = await file.read()
            if len(content) > config.MAX_UPLOAD_SIZE:
                logger.warning(f"File too large: {file.filename}")
                continue

            uploaded_files.append((file.filename, content))
            valid_files.append(file.filename)

        if not valid_files:
            raise HTTPException(
                status_code=400,
                detail="No valid files provided"
            )

        # Create task
        task = task_manager.create_task(valid_files, download_options)

        # Save uploaded files
        upload_dir = task_manager.get_upload_dir(task.task_id)
        for filename, content in uploaded_files:
            file_path = upload_dir / filename
            with open(file_path, "wb") as f:
                f.write(content)
            logger.info(f"Saved file: {file_path}")

        logger.info(f"Created task {task.task_id} with {len(valid_files)} files")

        return TaskCreateResponse(
            task_id=task.task_id,
            status=task.status,
            files=task.files,
            created_at=task.created_at
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating task: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")
