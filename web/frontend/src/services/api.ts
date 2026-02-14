/**
 * API service for interacting with the backend
 */
import {
  Task,
  TaskCreateResponse,
  DependenciesResponse,
  TaskListResponse,
  DownloadOptions,
} from "../types";

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";

class ApiService {
  private baseUrl: string;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * Create a new task by uploading files
   */
  async createTask(
    files: File[],
    options: DownloadOptions
  ): Promise<TaskCreateResponse> {
    const formData = new FormData();

    files.forEach((file) => {
      formData.append("files", file);
    });

    formData.append("options", JSON.stringify(options));

    const response = await fetch(`${this.baseUrl}/api/tasks`, {
      method: "POST",
      body: formData,
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to create task");
    }

    return response.json();
  }

  /**
   * Get task information
   */
  async getTask(taskId: string): Promise<Task> {
    const response = await fetch(`${this.baseUrl}/api/tasks/${taskId}`);

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to get task");
    }

    return response.json();
  }

  /**
   * Get task dependencies
   */
  async getDependencies(taskId: string): Promise<DependenciesResponse> {
    const response = await fetch(
      `${this.baseUrl}/api/tasks/${taskId}/dependencies`
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to get dependencies");
    }

    return response.json();
  }

  /**
   * Start parsing dependencies
   */
  async parseTask(taskId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/tasks/${taskId}/parse`, {
      method: "POST",
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to start parsing");
    }
  }

  /**
   * Start downloading packages
   */
  async startDownload(taskId: string): Promise<void> {
    const response = await fetch(
      `${this.baseUrl}/api/tasks/${taskId}/download`,
      {
        method: "POST",
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to start download");
    }
  }

  /**
   * List all tasks
   */
  async listTasks(page: number = 1, size: number = 20): Promise<TaskListResponse> {
    const response = await fetch(
      `${this.baseUrl}/api/tasks?page=${page}&size=${size}`
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to list tasks");
    }

    return response.json();
  }

  /**
   * Delete a task
   */
  async deleteTask(taskId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/tasks/${taskId}`, {
      method: "DELETE",
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || "Failed to delete task");
    }
  }

  /**
   * Get download URL for archive
   */
  getArchiveUrl(taskId: string): string {
    return `${this.baseUrl}/api/tasks/${taskId}/archive`;
  }

  /**
   * Get WebSocket URL for task
   */
  getWebSocketUrl(taskId: string): string {
    const wsProtocol = this.baseUrl.startsWith("https") ? "wss" : "ws";
    const wsBaseUrl = this.baseUrl.replace(/^https?/, wsProtocol);
    return `${wsBaseUrl}/api/ws/tasks/${taskId}`;
  }
}

export const api = new ApiService();
