"""Test configuration"""
import pytest
from fastapi.testclient import TestClient
from pathlib import Path
import tempfile
import shutil

from app.main import app
from app.config import config


@pytest.fixture
def client():
    """Create test client"""
    return TestClient(app)


@pytest.fixture
def temp_dir():
    """Create temporary directory for tests"""
    temp_path = Path(tempfile.mkdtemp())
    yield temp_path
    shutil.rmtree(temp_path, ignore_errors=True)


@pytest.fixture
def sample_package_json():
    """Sample package.json content"""
    return {
        "name": "test-package",
        "version": "1.0.0",
        "dependencies": {
            "express": "^4.18.0",
            "lodash": "^4.17.21"
        }
    }


@pytest.fixture
def sample_requirements_txt():
    """Sample requirements.txt content"""
    return """flask==3.0.0
requests>=2.31.0
pytest==7.4.0
"""
