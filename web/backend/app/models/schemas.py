"""Pydantic data models for the Package Download Web Platform"""
from pydantic import BaseModel, Field
from enum import Enum
from datetime import datetime
from typing import Optional


class TaskStatus(str, Enum):
    """Task status enumeration"""
    CREATED = "created"
    PARSING = "parsing"
    PARSED = "parsed"
    DOWNLOADING = "downloading"
    PACKING = "packing"
    COMPLETED = "completed"
    FAILED = "failed"


class DownloadOptions(BaseModel):
    """Download options configuration"""
    npm: bool = True
    pypi: bool = True
    node_version: str = "20"
    python_version: str = "3.13"
    platforms: list[str] = Field(default_factory=lambda: ["win_amd64", "manylinux2014_x86_64"])


class DependencyNode(BaseModel):
    """Dependency tree node"""
    name: str
    version: str
    children: list["DependencyNode"] = Field(default_factory=list)


class PackageInfo(BaseModel):
    """Package information"""
    name: str
    version: str
    size: Optional[int] = None


class DownloadProgress(BaseModel):
    """Download progress tracker"""
    total: int = 0
    completed: int = 0
    failed: int = 0
    failed_packages: list[str] = Field(default_factory=list)


class TaskInfo(BaseModel):
    """Task information"""
    task_id: str
    status: TaskStatus
    files: list[str]
    options: DownloadOptions
    npm_dependencies: Optional[DependencyNode] = None
    pypi_dependencies: list[PackageInfo] = Field(default_factory=list)
    npm_progress: DownloadProgress = Field(default_factory=DownloadProgress)
    pypi_progress: DownloadProgress = Field(default_factory=DownloadProgress)
    archive_url: Optional[str] = None
    archive_size: Optional[int] = None
    error: Optional[str] = None
    created_at: datetime
    completed_at: Optional[datetime] = None


class TaskCreateRequest(BaseModel):
    """Task creation request"""
    options: DownloadOptions = Field(default_factory=DownloadOptions)


class TaskCreateResponse(BaseModel):
    """Task creation response"""
    task_id: str
    status: TaskStatus
    files: list[str]
    created_at: datetime


class DependenciesResponse(BaseModel):
    """Dependencies response"""
    task_id: str
    npm: Optional[dict] = None
    pypi: Optional[dict] = None


class WSMessage(BaseModel):
    """WebSocket message"""
    type: str
    phase: str = ""
    current: int = 0
    total: int = 0
    message: str = ""
    package_name: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.now)


class TaskListResponse(BaseModel):
    """Task list response"""
    tasks: list[TaskInfo]
    total: int
