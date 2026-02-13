"""Application configuration"""
import os
from pathlib import Path


class Config:
    """Application configuration"""

    # Server
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))

    # Tasks
    TASKS_BASE_DIR: Path = Path(os.getenv("TASKS_BASE_DIR", "/tmp/pkg-download-tasks"))
    MAX_CONCURRENT_TASKS: int = int(os.getenv("MAX_CONCURRENT_TASKS", "5"))
    TASK_EXPIRE_HOURS: int = int(os.getenv("TASK_EXPIRE_HOURS", "24"))
    TASK_TIMEOUT_MINUTES: int = int(os.getenv("TASK_TIMEOUT_MINUTES", "30"))

    # Upload
    MAX_UPLOAD_SIZE: int = int(os.getenv("MAX_UPLOAD_SIZE", str(1024 * 1024)))  # 1MB
    ALLOWED_EXTENSIONS: set = {
        ".json", ".txt", ".toml", ".cfg", ".lock"
    }

    # Downloads
    MAX_TASK_SIZE_GB: int = int(os.getenv("MAX_TASK_SIZE_GB", "2"))

    # Node.js versions
    SUPPORTED_NODE_VERSIONS: list[str] = ["18", "20", "22"]
    NODE_VERSION_MAP: dict[str, str] = {
        "18": "18.20.4",
        "20": "20.11.1",
        "22": "22.11.0",
    }

    # Python versions
    SUPPORTED_PYTHON_VERSIONS: list[str] = ["3.11", "3.12", "3.13"]
    PYTHON_VERSION_MAP: dict[str, str] = {
        "3.11": "3.11.9",
        "3.12": "3.12.3",
        "3.13": "3.13.0",
    }

    # Paths
    NVM_DIR: str = os.getenv("NVM_DIR", os.path.expanduser("~/.nvm"))
    PYENV_ROOT: str = os.getenv("PYENV_ROOT", os.path.expanduser("~/.pyenv"))

    @classmethod
    def ensure_dirs(cls):
        """Ensure required directories exist"""
        cls.TASKS_BASE_DIR.mkdir(parents=True, exist_ok=True)


config = Config()
