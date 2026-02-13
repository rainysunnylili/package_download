"""Test upload router"""
import pytest
import json
from io import BytesIO


def test_health_check(client):
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_root_endpoint(client):
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "name" in data
    assert "version" in data


def test_create_task_with_package_json(client, sample_package_json):
    """Test creating a task with package.json"""
    # Prepare file
    package_json_content = json.dumps(sample_package_json).encode()
    files = {
        "files": ("package.json", BytesIO(package_json_content), "application/json")
    }
    data = {
        "options": json.dumps({
            "npm": True,
            "pypi": False,
            "node_version": "20"
        })
    }

    response = client.post("/api/tasks", files=files, data=data)
    assert response.status_code == 200
    result = response.json()
    assert "task_id" in result
    assert result["status"] == "created"
    assert "package.json" in result["files"]


def test_create_task_with_requirements_txt(client, sample_requirements_txt):
    """Test creating a task with requirements.txt"""
    # Prepare file
    files = {
        "files": ("requirements.txt", BytesIO(sample_requirements_txt.encode()), "text/plain")
    }
    data = {
        "options": json.dumps({
            "npm": False,
            "pypi": True,
            "python_version": "3.13"
        })
    }

    response = client.post("/api/tasks", files=files, data=data)
    assert response.status_code == 200
    result = response.json()
    assert "task_id" in result
    assert result["status"] == "created"
    assert "requirements.txt" in result["files"]


def test_create_task_no_files(client):
    """Test creating a task without files"""
    response = client.post("/api/tasks", files={})
    assert response.status_code == 422  # Validation error


def test_create_task_invalid_extension(client):
    """Test creating a task with invalid file extension"""
    files = {
        "files": ("invalid.exe", BytesIO(b"malicious content"), "application/octet-stream")
    }

    response = client.post("/api/tasks", files=files)
    assert response.status_code == 400
