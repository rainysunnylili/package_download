/**
 * TypeScript type definitions for the Package Download Web Platform
 */

export type TaskStatus =
  | "created"
  | "parsing"
  | "parsed"
  | "downloading"
  | "packing"
  | "completed"
  | "failed";

export interface DownloadOptions {
  npm: boolean;
  pypi: boolean;
  node_version: string;
  python_version: string;
  platforms: string[];
}

export interface DependencyNode {
  name: string;
  version: string;
  children: DependencyNode[];
}

export interface PackageInfo {
  name: string;
  version: string;
  size?: number;
}

export interface DownloadProgress {
  total: number;
  completed: number;
  failed: number;
  failed_packages: string[];
}

export interface Task {
  task_id: string;
  status: TaskStatus;
  files: string[];
  options: DownloadOptions;
  npm_dependencies?: DependencyNode;
  pypi_dependencies?: PackageInfo[];
  npm_progress: DownloadProgress;
  pypi_progress: DownloadProgress;
  archive_url?: string;
  archive_size?: number;
  error?: string;
  created_at: string;
  completed_at?: string;
}

export interface TaskCreateResponse {
  task_id: string;
  status: TaskStatus;
  files: string[];
  created_at: string;
}

export interface DependenciesResponse {
  task_id: string;
  npm?: {
    total: number;
    tree: DependencyNode;
  };
  pypi?: {
    total: number;
    packages: PackageInfo[];
  };
}

export interface WSMessage {
  type: "progress" | "log" | "status" | "error" | "complete";
  phase: "parsing" | "downloading" | "packing";
  current: number;
  total: number;
  message: string;
  package_name?: string;
  timestamp: string;
}

export interface TaskListResponse {
  tasks: Task[];
  total: number;
}
