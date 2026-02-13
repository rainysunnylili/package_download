"""PyPI package downloader service"""
import asyncio
import logging
import os
import glob
import re
from pathlib import Path
from typing import Optional

from app.config import config
from app.models.schemas import PackageInfo, DownloadProgress
from app.ws.manager import manager as ws_manager

logger = logging.getLogger(__name__)


class PyPIDownloader:
    """Download PyPI packages"""

    def get_python_env(self, version: str) -> dict:
        """Get environment variables for specific Python version"""
        pyenv_root = config.PYENV_ROOT

        # Get the full version number
        full_version = config.PYTHON_VERSION_MAP.get(version, version)

        # Find python path
        python_pattern = f"{pyenv_root}/versions/{full_version}*/bin"
        matches = glob.glob(python_pattern)

        env = os.environ.copy()

        if matches:
            python_path = matches[0]
            env["PATH"] = f"{python_path}:{env.get('PATH', '')}"
            logger.info(f"Using Python from {python_path}")
        else:
            # Fallback: try without patch version
            python_pattern = f"{pyenv_root}/versions/{version}.*/bin"
            matches = glob.glob(python_pattern)
            if matches:
                python_path = matches[-1]  # Use latest patch version
                env["PATH"] = f"{python_path}:{env.get('PATH', '')}"
                logger.info(f"Using Python from {python_path}")
            else:
                logger.warning(f"Python {version} not found, using system default")

        return env

    async def parse_dependencies(
        self,
        task_id: str,
        upload_dir: Path,
        python_version: str
    ) -> list[PackageInfo]:
        """Parse Python dependencies"""
        try:
            await ws_manager.broadcast(task_id, "status", {
                "phase": "parsing",
                "message": "Parsing Python dependencies..."
            })

            # Check for requirements.txt
            requirements_files = list(upload_dir.glob("requirements*.txt"))
            if not requirements_files:
                logger.info(f"No requirements.txt found for task {task_id}")
                return []

            packages = []

            for req_file in requirements_files:
                with open(req_file, "r") as f:
                    lines = f.readlines()

                    for line in lines:
                        line = line.strip()
                        # Skip empty lines and comments
                        if not line or line.startswith("#"):
                            continue

                        # Parse package name and version
                        # Handle formats like: package==1.0.0, package>=1.0.0, package
                        match = re.match(r"^([a-zA-Z0-9_-]+)([>=<~!]+)?(.+)?$", line)
                        if match:
                            name = match.group(1)
                            version = match.group(3) if match.group(3) else "latest"
                            packages.append(PackageInfo(name=name, version=version))

            await ws_manager.broadcast(task_id, "log", {
                "phase": "parsing",
                "message": f"Found {len(packages)} Python packages"
            })

            return packages

        except Exception as e:
            logger.error(f"Error parsing Python dependencies: {e}")
            await ws_manager.broadcast(task_id, "error", {
                "phase": "parsing",
                "message": f"Error parsing Python dependencies: {str(e)}"
            })
            raise

    async def download_packages(
        self,
        task_id: str,
        upload_dir: Path,
        download_dir: Path,
        python_version: str,
        platforms: list[str],
        progress: DownloadProgress
    ) -> DownloadProgress:
        """Download PyPI packages"""
        try:
            await ws_manager.broadcast(task_id, "status", {
                "phase": "downloading",
                "message": "Downloading Python packages..."
            })

            requirements_files = list(upload_dir.glob("requirements*.txt"))
            if not requirements_files:
                logger.info(f"No requirements.txt found for task {task_id}")
                return progress

            # Ensure download directory exists
            download_dir.mkdir(parents=True, exist_ok=True)

            # Get Python environment
            env = self.get_python_env(python_version)

            # Calculate Python version tag for pip
            py_ver_short = python_version.replace(".", "")  # "3.13" -> "313"

            # Count total packages
            total_packages = 0
            for req_file in requirements_files:
                with open(req_file, "r") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#"):
                            total_packages += 1

            progress.total = total_packages

            await ws_manager.broadcast(task_id, "progress", {
                "phase": "downloading",
                "current": 0,
                "total": progress.total,
                "message": f"Downloading {progress.total} Python packages..."
            })

            # Download packages for each platform
            for platform in platforms:
                logger.info(f"Downloading packages for platform: {platform}")
                await ws_manager.broadcast(task_id, "log", {
                    "phase": "downloading",
                    "message": f"Downloading for platform: {platform}"
                })

                # Create platform-specific directory
                platform_dir = download_dir / platform
                platform_dir.mkdir(exist_ok=True)

                for req_file in requirements_files:
                    try:
                        # Download packages
                        process = await asyncio.create_subprocess_exec(
                            "python", "-m", "pip", "download",
                            "-r", str(req_file),
                            "--dest", str(platform_dir),
                            "--only-binary=:all:",
                            "--platform", platform,
                            "--python-version", py_ver_short,
                            "--implementation", "cp",
                            "--abi", f"cp{py_ver_short}",
                            env=env,
                            stdout=asyncio.subprocess.PIPE,
                            stderr=asyncio.subprocess.PIPE
                        )

                        # Stream output and track progress
                        current_package = None
                        async for line in process.stdout:
                            line_str = line.decode().strip()
                            if not line_str:
                                continue

                            logger.debug(f"pip download: {line_str}")

                            # Parse progress from pip output
                            if "Collecting" in line_str or "Downloading" in line_str:
                                # Extract package name
                                match = re.search(r"(Collecting|Downloading)\s+([a-zA-Z0-9_-]+)", line_str)
                                if match:
                                    current_package = match.group(2)
                                    await ws_manager.broadcast(task_id, "log", {
                                        "phase": "downloading",
                                        "message": line_str,
                                        "package_name": current_package
                                    })

                            if "Successfully downloaded" in line_str or "Saved" in line_str:
                                if current_package:
                                    progress.completed += 1
                                    await ws_manager.broadcast(task_id, "progress", {
                                        "phase": "downloading",
                                        "current": progress.completed,
                                        "total": progress.total,
                                        "package_name": current_package,
                                        "message": f"Downloaded {current_package}"
                                    })

                        await process.wait()

                        if process.returncode != 0:
                            stderr = await process.stderr.read()
                            error_msg = stderr.decode() if stderr else "Unknown error"
                            logger.error(f"Failed to download packages: {error_msg}")

                            # Try to extract failed package names
                            failed_packages = re.findall(r"Could not find.*?([a-zA-Z0-9_-]+)", error_msg)
                            for pkg in failed_packages:
                                if pkg not in progress.failed_packages:
                                    progress.failed_packages.append(pkg)
                                    progress.failed += 1

                    except Exception as e:
                        logger.error(f"Error downloading from {req_file}: {e}")
                        await ws_manager.broadcast(task_id, "error", {
                            "phase": "downloading",
                            "message": f"Error downloading packages: {str(e)}"
                        })

            await ws_manager.broadcast(task_id, "status", {
                "phase": "downloading",
                "message": f"Python download complete: {progress.completed}/{progress.total} packages"
            })

            return progress

        except Exception as e:
            logger.error(f"Error downloading Python packages: {e}")
            await ws_manager.broadcast(task_id, "error", {
                "phase": "downloading",
                "message": f"Error downloading Python packages: {str(e)}"
            })
            raise


pypi_downloader = PyPIDownloader()
