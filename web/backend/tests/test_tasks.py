"""Test task management"""
import pytest


def test_list_tasks(client):
    """Test listing tasks"""
    response = client.get("/api/tasks")
    assert response.status_code == 200
    data = response.json()
    assert "tasks" in data
    assert "total" in data
    assert isinstance(data["tasks"], list)


def test_get_task_not_found(client):
    """Test getting non-existent task"""
    response = client.get("/api/tasks/nonexistent-task-id")
    assert response.status_code == 404


def test_get_dependencies_not_found(client):
    """Test getting dependencies for non-existent task"""
    response = client.get("/api/tasks/nonexistent-task-id/dependencies")
    assert response.status_code == 404


def test_delete_task_not_found(client):
    """Test deleting non-existent task"""
    response = client.delete("/api/tasks/nonexistent-task-id")
    assert response.status_code == 404
