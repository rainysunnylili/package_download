"""NPM package downloader service"""
import asyncio
import json
import logging
import os
import glob
from pathlib import Path
from typing import Optional

from app.config import config
from app.models.schemas import DependencyNode, DownloadProgress
from app.ws.manager import manager as ws_manager

logger = logging.getLogger(__name__)


class NPMDownloader:
    """Download NPM packages"""

    def get_node_env(self, version: str) -> dict:
        """Get environment variables for specific Node.js version"""
        nvm_dir = config.NVM_DIR

        # Get the full version number
        full_version = config.NODE_VERSION_MAP.get(version, version)

        # Find node path with glob to handle patch versions
        node_pattern = f"{nvm_dir}/versions/node/v{full_version}*/bin"
        matches = glob.glob(node_pattern)

        env = os.environ.copy()

        if matches:
            node_path = matches[0]
            env["PATH"] = f"{node_path}:{env.get('PATH', '')}"
            logger.info(f"Using Node.js from {node_path}")
        else:
            # Fallback: try without patch version
            node_pattern = f"{nvm_dir}/versions/node/v{version}.*/bin"
            matches = glob.glob(node_pattern)
            if matches:
                node_path = matches[-1]  # Use latest patch version
                env["PATH"] = f"{node_path}:{env.get('PATH', '')}"
                logger.info(f"Using Node.js from {node_path}")
            else:
                logger.warning(f"Node.js {version} not found, using system default")

        return env

    async def parse_dependencies(
        self,
        task_id: str,
        upload_dir: Path,
        node_version: str
    ) -> Optional[DependencyNode]:
        """Parse NPM dependencies and build dependency tree"""
        try:
            await ws_manager.broadcast(task_id, "status", {
                "phase": "parsing",
                "message": "Parsing NPM dependencies..."
            })

            # Check for package.json
            package_json = upload_dir / "package.json"
            if not package_json.exists():
                logger.info(f"No package.json found for task {task_id}")
                return None

            # Get Node.js environment
            env = self.get_node_env(node_version)

            # Install lock file if needed
            package_lock = upload_dir / "package-lock.json"
            if not package_lock.exists():
                logger.info(f"Generating package-lock.json for task {task_id}")
                await ws_manager.broadcast(task_id, "log", {
                    "phase": "parsing",
                    "message": "Generating package-lock.json..."
                })

                process = await asyncio.create_subprocess_exec(
                    "npm", "install", "--package-lock-only",
                    cwd=str(upload_dir),
                    env=env,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                stdout, stderr = await process.communicate()

                if process.returncode != 0:
                    error_msg = stderr.decode() if stderr else "Unknown error"
                    logger.error(f"Failed to generate package-lock.json: {error_msg}")
                    raise Exception(f"Failed to generate package-lock.json: {error_msg}")

            # Get dependency tree
            logger.info(f"Fetching dependency tree for task {task_id}")
            await ws_manager.broadcast(task_id, "log", {
                "phase": "parsing",
                "message": "Analyzing dependency tree..."
            })

            process = await asyncio.create_subprocess_exec(
                "npm", "list", "--all", "--json",
                cwd=str(upload_dir),
                env=env,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await process.communicate()

            if stdout:
                tree_data = json.loads(stdout.decode())
                return self._build_dependency_tree(tree_data)

            return None

        except Exception as e:
            logger.error(f"Error parsing NPM dependencies: {e}")
            await ws_manager.broadcast(task_id, "error", {
                "phase": "parsing",
                "message": f"Error parsing NPM dependencies: {str(e)}"
            })
            raise

    def _build_dependency_tree(self, npm_data: dict) -> Optional[DependencyNode]:
        """Build dependency tree from npm list output"""
        if not npm_data:
            return None

        name = npm_data.get("name", "root")
        version = npm_data.get("version", "0.0.0")
        dependencies = npm_data.get("dependencies", {})

        children = []
        for dep_name, dep_data in dependencies.items():
            if isinstance(dep_data, dict):
                child_node = DependencyNode(
                    name=dep_name,
                    version=dep_data.get("version", "unknown"),
                    children=[]
                )
                # Recursively build child dependencies
                if "dependencies" in dep_data:
                    child_tree = self._build_dependency_tree({
                        "name": dep_name,
                        "version": dep_data.get("version", "unknown"),
                        "dependencies": dep_data.get("dependencies", {})
                    })
                    if child_tree:
                        child_node.children = child_tree.children
                children.append(child_node)

        return DependencyNode(name=name, version=version, children=children)

    async def download_packages(
        self,
        task_id: str,
        upload_dir: Path,
        download_dir: Path,
        node_version: str,
        progress: DownloadProgress
    ) -> DownloadProgress:
        """Download NPM packages"""
        try:
            await ws_manager.broadcast(task_id, "status", {
                "phase": "downloading",
                "message": "Downloading NPM packages..."
            })

            package_json = upload_dir / "package.json"
            if not package_json.exists():
                logger.info(f"No package.json found for task {task_id}")
                return progress

            # Ensure download directory exists
            download_dir.mkdir(parents=True, exist_ok=True)

            # Get Node.js environment
            env = self.get_node_env(node_version)

            # First, install packages to get all dependencies
            logger.info(f"Installing NPM packages for task {task_id}")
            await ws_manager.broadcast(task_id, "log", {
                "phase": "downloading",
                "message": "Installing NPM packages..."
            })

            # Create a temporary node_modules directory
            temp_install_dir = download_dir.parent / "temp-npm-install"
            temp_install_dir.mkdir(parents=True, exist_ok=True)

            # Copy package.json and package-lock.json to temp directory
            import shutil
            shutil.copy(package_json, temp_install_dir / "package.json")
            package_lock = upload_dir / "package-lock.json"
            if package_lock.exists():
                shutil.copy(package_lock, temp_install_dir / "package-lock.json")

            # Install packages
            process = await asyncio.create_subprocess_exec(
                "npm", "install", "--production",
                cwd=str(temp_install_dir),
                env=env,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            # Stream output
            async for line in process.stdout:
                line_str = line.decode().strip()
                if line_str:
                    logger.debug(f"NPM install: {line_str}")
                    await ws_manager.broadcast(task_id, "log", {
                        "phase": "downloading",
                        "message": line_str
                    })

            await process.wait()

            if process.returncode != 0:
                stderr = await process.stderr.read()
                error_msg = stderr.decode() if stderr else "Unknown error"
                logger.error(f"Failed to install NPM packages: {error_msg}")
                raise Exception(f"Failed to install NPM packages: {error_msg}")

            # Now pack each package
            node_modules = temp_install_dir / "node_modules"
            if node_modules.exists():
                packages = [d for d in node_modules.iterdir() if d.is_dir()]
                progress.total = len(packages)

                await ws_manager.broadcast(task_id, "progress", {
                    "phase": "downloading",
                    "current": 0,
                    "total": progress.total,
                    "message": f"Packing {progress.total} packages..."
                })

                for package_dir in packages:
                    try:
                        package_name = package_dir.name

                        # Skip scoped packages parent directories
                        if package_name.startswith("@"):
                            continue

                        # Pack the package
                        process = await asyncio.create_subprocess_exec(
                            "npm", "pack", str(package_dir),
                            cwd=str(download_dir),
                            env=env,
                            stdout=asyncio.subprocess.PIPE,
                            stderr=asyncio.subprocess.PIPE
                        )
                        await process.wait()

                        if process.returncode == 0:
                            progress.completed += 1
                            await ws_manager.broadcast(task_id, "progress", {
                                "phase": "downloading",
                                "current": progress.completed,
                                "total": progress.total,
                                "package_name": package_name,
                                "message": f"Packed {package_name}"
                            })
                        else:
                            progress.failed += 1
                            progress.failed_packages.append(package_name)
                            logger.warning(f"Failed to pack {package_name}")

                    except Exception as e:
                        logger.error(f"Error packing package {package_dir.name}: {e}")
                        progress.failed += 1
                        progress.failed_packages.append(package_dir.name)

            # Cleanup temp directory
            shutil.rmtree(temp_install_dir, ignore_errors=True)

            await ws_manager.broadcast(task_id, "status", {
                "phase": "downloading",
                "message": f"NPM download complete: {progress.completed}/{progress.total} packages"
            })

            return progress

        except Exception as e:
            logger.error(f"Error downloading NPM packages: {e}")
            await ws_manager.broadcast(task_id, "error", {
                "phase": "downloading",
                "message": f"Error downloading NPM packages: {str(e)}"
            })
            raise


npm_downloader = NPMDownloader()
