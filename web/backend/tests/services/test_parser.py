"""Test file parser service"""
import pytest
from pathlib import Path
import json

from app.services.parser import file_parser


def test_is_npm_file():
    """Test NPM file detection"""
    assert file_parser.is_npm_file("package.json") == True
    assert file_parser.is_npm_file("package-lock.json") == True
    assert file_parser.is_npm_file("requirements.txt") == False


def test_is_python_file():
    """Test Python file detection"""
    assert file_parser.is_python_file("requirements.txt") == True
    assert file_parser.is_python_file("Pipfile") == True
    assert file_parser.is_python_file("pyproject.toml") == True
    assert file_parser.is_python_file("package.json") == False


def test_get_file_type():
    """Test file type detection"""
    assert file_parser.get_file_type("package.json") == "npm"
    assert file_parser.get_file_type("requirements.txt") == "python"
    assert file_parser.get_file_type("unknown.txt") == None


def test_categorize_files():
    """Test file categorization"""
    files = [
        "package.json",
        "requirements.txt",
        "Pipfile",
        "package-lock.json",
        "unknown.md"
    ]

    result = file_parser.categorize_files(files)

    assert len(result["npm"]) == 2
    assert len(result["python"]) == 2
    assert len(result["unknown"]) == 1
    assert "package.json" in result["npm"]
    assert "requirements.txt" in result["python"]


def test_validate_npm_file(temp_dir, sample_package_json):
    """Test NPM file validation"""
    # Create valid package.json
    package_json = temp_dir / "package.json"
    with open(package_json, "w") as f:
        json.dump(sample_package_json, f)

    assert file_parser.validate_npm_file(package_json) == True

    # Test invalid JSON
    invalid_json = temp_dir / "invalid.json"
    with open(invalid_json, "w") as f:
        f.write("invalid json content")

    assert file_parser.validate_npm_file(invalid_json) == False


def test_validate_python_file(temp_dir, sample_requirements_txt):
    """Test Python file validation"""
    # Create valid requirements.txt
    requirements = temp_dir / "requirements.txt"
    with open(requirements, "w") as f:
        f.write(sample_requirements_txt)

    assert file_parser.validate_python_file(requirements) == True

    # Test empty requirements.txt
    empty_req = temp_dir / "empty_requirements.txt"
    with open(empty_req, "w") as f:
        f.write("# Only comments\n")

    assert file_parser.validate_python_file(empty_req) == False
