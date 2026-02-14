"""Packager service for creating archive files"""
import asyncio
import zipfile
import logging
from pathlib import Path

from app.ws.manager import manager as ws_manager

logger = logging.getLogger(__name__)


class Packager:
    """Create archive files from downloaded packages"""

    async def create_archive(
        self,
        task_id: str,
        task_dir: Path,
        npm_dir: Path,
        pypi_dir: Path,
        output_path: Path
    ) -> tuple[Path, int]:
        """Create a zip archive of all downloaded packages"""
        try:
            await ws_manager.broadcast(task_id, "status", {
                "phase": "packing",
                "message": "正在创建压缩包..."
            })

            total_files = 0
            processed_files = 0

            # Count total files
            if npm_dir.exists():
                total_files += sum(1 for _ in npm_dir.rglob("*") if _.is_file())
            if pypi_dir.exists():
                total_files += sum(1 for _ in pypi_dir.rglob("*") if _.is_file())

            await ws_manager.broadcast(task_id, "progress", {
                "phase": "packing",
                "current": 0,
                "total": total_files,
                "message": f"正在打包 {total_files} 个文件..."
            })

            with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zf:
                # Add NPM packages
                if npm_dir.exists():
                    for file_path in npm_dir.rglob("*"):
                        if file_path.is_file():
                            arcname = f"npm-packages/{file_path.relative_to(npm_dir)}"
                            zf.write(file_path, arcname)
                            processed_files += 1

                            if processed_files % 10 == 0:
                                await ws_manager.broadcast(task_id, "progress", {
                                    "phase": "packing",
                                    "current": processed_files,
                                    "total": total_files,
                                    "message": f"已打包 {processed_files}/{total_files} 个文件..."
                                })

                # Add Python packages
                if pypi_dir.exists():
                    for file_path in pypi_dir.rglob("*"):
                        if file_path.is_file():
                            arcname = f"python-packages/{file_path.relative_to(pypi_dir)}"
                            zf.write(file_path, arcname)
                            processed_files += 1

                            if processed_files % 10 == 0:
                                await ws_manager.broadcast(task_id, "progress", {
                                    "phase": "packing",
                                    "current": processed_files,
                                    "total": total_files,
                                    "message": f"已打包 {processed_files}/{total_files} 个文件..."
                                })

            # Get archive size
            archive_size = output_path.stat().st_size

            await ws_manager.broadcast(task_id, "status", {
                "phase": "packing",
                "message": f"压缩包已创建: {archive_size / (1024*1024):.2f} MB"
            })

            logger.info(f"Archive created for task {task_id}: {output_path} ({archive_size} bytes)")
            return output_path, archive_size

        except Exception as e:
            logger.error(f"Error creating archive: {e}")
            await ws_manager.broadcast(task_id, "error", {
                "phase": "packing",
                "message": f"创建压缩包失败: {str(e)}"
            })
            raise


packager = Packager()
