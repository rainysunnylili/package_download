"""File parser service for dependency configuration files"""
import json
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class FileParser:
    """Parse dependency configuration files"""

    @staticmethod
    def is_npm_file(filename: str) -> bool:
        """Check if file is an NPM dependency file"""
        return filename in ["package.json", "package-lock.json"]

    @staticmethod
    def is_python_file(filename: str) -> bool:
        """Check if file is a Python dependency file"""
        return filename in [
            "requirements.txt",
            "requirements-dev.txt",
            "requirements-test.txt",
            "Pipfile",
            "Pipfile.lock",
            "pyproject.toml",
            "setup.py",
            "setup.cfg"
        ]

    @staticmethod
    def get_file_type(filename: str) -> Optional[str]:
        """Determine file type"""
        if FileParser.is_npm_file(filename):
            return "npm"
        elif FileParser.is_python_file(filename):
            return "python"
        return None

    @staticmethod
    def validate_npm_file(file_path: Path) -> bool:
        """Validate NPM dependency file"""
        if not file_path.exists():
            return False

        if file_path.name == "package.json":
            try:
                with open(file_path, "r") as f:
                    data = json.load(f)
                    # Check if it has dependencies or devDependencies
                    return "dependencies" in data or "devDependencies" in data
            except json.JSONDecodeError:
                logger.error(f"Invalid JSON in {file_path}")
                return False
        elif file_path.name == "package-lock.json":
            try:
                with open(file_path, "r") as f:
                    data = json.load(f)
                    return "packages" in data or "dependencies" in data
            except json.JSONDecodeError:
                logger.error(f"Invalid JSON in {file_path}")
                return False

        return True

    @staticmethod
    def validate_python_file(file_path: Path) -> bool:
        """Validate Python dependency file"""
        if not file_path.exists():
            return False

        if file_path.name.startswith("requirements"):
            # Requirements file should have at least one non-comment line
            try:
                with open(file_path, "r") as f:
                    lines = f.readlines()
                    for line in lines:
                        line = line.strip()
                        if line and not line.startswith("#"):
                            return True
                return False
            except Exception as e:
                logger.error(f"Error reading {file_path}: {e}")
                return False

        elif file_path.name == "Pipfile":
            try:
                # Simple validation - just check if file is readable
                with open(file_path, "r") as f:
                    content = f.read()
                    return "[packages]" in content or "[dev-packages]" in content
            except Exception as e:
                logger.error(f"Error reading {file_path}: {e}")
                return False

        elif file_path.name == "pyproject.toml":
            try:
                with open(file_path, "r") as f:
                    content = f.read()
                    return "[project]" in content or "[tool.poetry" in content
            except Exception as e:
                logger.error(f"Error reading {file_path}: {e}")
                return False

        return True

    @staticmethod
    def categorize_files(files: list[str]) -> dict:
        """Categorize files by type"""
        npm_files = []
        python_files = []
        unknown_files = []

        for file in files:
            file_type = FileParser.get_file_type(file)
            if file_type == "npm":
                npm_files.append(file)
            elif file_type == "python":
                python_files.append(file)
            else:
                unknown_files.append(file)

        return {
            "npm": npm_files,
            "python": python_files,
            "unknown": unknown_files
        }


file_parser = FileParser()
