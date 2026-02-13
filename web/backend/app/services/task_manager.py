"""Task manager service for handling task state and storage"""
import uuid
import json
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Dict
import logging

from app.config import config
from app.models.schemas import TaskInfo, TaskStatus, DownloadOptions

logger = logging.getLogger(__name__)


class TaskManager:
    """Manages task lifecycle and storage"""

    def __init__(self):
        self.tasks: Dict[str, TaskInfo] = {}
        config.ensure_dirs()

    def create_task(self, files: list[str], options: DownloadOptions) -> TaskInfo:
        """Create a new task"""
        task_id = str(uuid.uuid4())
        task_info = TaskInfo(
            task_id=task_id,
            status=TaskStatus.CREATED,
            files=files,
            options=options,
            created_at=datetime.now()
        )

        # Create task directory
        task_dir = self.get_task_dir(task_id)
        task_dir.mkdir(parents=True, exist_ok=True)
        (task_dir / "uploads").mkdir(exist_ok=True)
        (task_dir / "npm-packages").mkdir(exist_ok=True)
        (task_dir / "python-packages").mkdir(exist_ok=True)

        self.tasks[task_id] = task_info
        self._save_task_info(task_id)

        logger.info(f"Created task {task_id}")
        return task_info

    def get_task(self, task_id: str) -> Optional[TaskInfo]:
        """Get task information"""
        if task_id not in self.tasks:
            self._load_task_info(task_id)
        return self.tasks.get(task_id)

    def update_task(self, task_id: str, **kwargs) -> Optional[TaskInfo]:
        """Update task information"""
        task = self.get_task(task_id)
        if not task:
            return None

        for key, value in kwargs.items():
            if hasattr(task, key):
                setattr(task, key, value)

        self._save_task_info(task_id)
        logger.info(f"Updated task {task_id}: {kwargs}")
        return task

    def list_tasks(self, page: int = 1, size: int = 20) -> tuple[list[TaskInfo], int]:
        """List all tasks with pagination"""
        all_tasks = list(self.tasks.values())
        all_tasks.sort(key=lambda t: t.created_at, reverse=True)

        start = (page - 1) * size
        end = start + size

        return all_tasks[start:end], len(all_tasks)

    def delete_task(self, task_id: str) -> bool:
        """Delete a task and its files"""
        task_dir = self.get_task_dir(task_id)
        if task_dir.exists():
            shutil.rmtree(task_dir)

        if task_id in self.tasks:
            del self.tasks[task_id]

        logger.info(f"Deleted task {task_id}")
        return True

    def cleanup_expired_tasks(self):
        """Clean up expired tasks"""
        expiry_time = datetime.now() - timedelta(hours=config.TASK_EXPIRE_HOURS)

        for task_dir in config.TASKS_BASE_DIR.iterdir():
            if not task_dir.is_dir():
                continue

            info_file = task_dir / "task_info.json"
            if not info_file.exists():
                continue

            try:
                with open(info_file, "r") as f:
                    task_data = json.load(f)
                    created_at = datetime.fromisoformat(task_data["created_at"])

                    if created_at < expiry_time:
                        task_id = task_data["task_id"]
                        self.delete_task(task_id)
                        logger.info(f"Cleaned up expired task {task_id}")
            except Exception as e:
                logger.error(f"Error cleaning up task {task_dir.name}: {e}")

    def get_task_dir(self, task_id: str) -> Path:
        """Get task directory path"""
        return config.TASKS_BASE_DIR / task_id

    def get_upload_dir(self, task_id: str) -> Path:
        """Get upload directory path"""
        return self.get_task_dir(task_id) / "uploads"

    def get_npm_dir(self, task_id: str) -> Path:
        """Get NPM packages directory path"""
        return self.get_task_dir(task_id) / "npm-packages"

    def get_pypi_dir(self, task_id: str) -> Path:
        """Get Python packages directory path"""
        return self.get_task_dir(task_id) / "python-packages"

    def get_archive_path(self, task_id: str) -> Path:
        """Get archive file path"""
        return self.get_task_dir(task_id) / f"packages-{task_id}.zip"

    def _save_task_info(self, task_id: str):
        """Save task information to disk"""
        task = self.tasks.get(task_id)
        if not task:
            return

        task_dir = self.get_task_dir(task_id)
        task_dir.mkdir(parents=True, exist_ok=True)

        info_file = task_dir / "task_info.json"
        with open(info_file, "w") as f:
            json.dump(task.model_dump(mode="json"), f, indent=2, default=str)

    def _load_task_info(self, task_id: str) -> Optional[TaskInfo]:
        """Load task information from disk"""
        info_file = self.get_task_dir(task_id) / "task_info.json"
        if not info_file.exists():
            return None

        try:
            with open(info_file, "r") as f:
                data = json.load(f)
                task = TaskInfo(**data)
                self.tasks[task_id] = task
                return task
        except Exception as e:
            logger.error(f"Error loading task info for {task_id}: {e}")
            return None


task_manager = TaskManager()
