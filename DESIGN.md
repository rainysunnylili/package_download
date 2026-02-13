# Package Download Web 平台设计方案

## 1. 项目概述

将现有的 shell 脚本工具改造为 Web 应用，用户可通过浏览器上传依赖配置文件（`package.json`、`requirements.txt` 等），可视化展示依赖树，后端自动下载所有依赖包，最终打包成压缩文件供用户下载。

### 核心目标

- **可视化上传**：拖拽或点击上传依赖配置文件
- **依赖树展示**：交互式可视化依赖关系图
- **后端自动下载**：异步下载全部依赖包，支持 NPM + PyPI
- **实时进度**：WebSocket 推送下载进度
- **一键打包下载**：下载完成后自动打压缩包，浏览器端直接下载

---

## 2. 技术栈选型

| 层级             | 技术                                | 理由                                          |
| ---------------- | ----------------------------------- | --------------------------------------------- |
| **前端框架**     | React 18 + TypeScript               | 成熟生态，组件化开发                          |
| **构建工具**     | Vite                                | 快速开发体验                                  |
| **UI 组件库**    | Ant Design 5                        | 丰富的组件（Upload、Tree、Progress等）        |
| **依赖树可视化** | @ant-design/charts 或 react-d3-tree | 交互式树形图渲染                              |
| **后端框架**     | FastAPI (Python)                    | 异步支持好、WebSocket 原生支持、自动 API 文档 |
| **任务队列**     | 内置 asyncio + 后台任务             | 轻量级，无需额外中间件                        |
| **实时通信**     | WebSocket                           | 服务端推送下载进度                            |
| **打包**         | Python zipfile / tarfile            | 标准库即可                                    |
| **进程调度**     | subprocess + asyncio                | 复用现有 shell 脚本逻辑                       |

### 为什么选 FastAPI 而非 Node.js 后端？

- 现有 PyPI 下载逻辑用 `pip download` 命令，Python 后端调用更自然
- FastAPI 原生支持异步、WebSocket、后台任务
- 自动生成 OpenAPI 文档，方便联调
- NPM 下载部分通过 `subprocess` 调用 Node.js 脚本（复用现有逻辑）

---

## 3. 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                     浏览器 (React)                       │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ 文件上传  │  │  依赖树可视化  │  │  下载进度 & 控制  │  │
│  └─────┬────┘  └──────┬───────┘  └─────────┬─────────┘  │
│        │              │                    │             │
│        └──────────────┴────────────────────┘             │
│                        │ HTTP + WebSocket                │
└────────────────────────┼────────────────────────────────┘
                         │
┌────────────────────────┼────────────────────────────────┐
│                  FastAPI 后端                            │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │  文件解析器  │ │ 依赖分析引擎  │ │   下载管理器     │  │
│  │ (parse)     │ │ (analyze)    │ │  (download)      │  │
│  └──────┬──────┘ └──────┬───────┘ └────────┬─────────┘  │
│         │               │                  │             │
│  ┌──────┴───────────────┴──────────────────┴─────────┐  │
│  │              任务调度器 (asyncio)                    │  │
│  └──────────────────────┬────────────────────────────┘  │
│                         │                                │
│  ┌──────────────────────┴────────────────────────────┐  │
│  │           subprocess 调用                          │  │
│  │   ┌─────────────┐    ┌──────────────────┐         │  │
│  │   │  npm pack    │    │  pip download    │         │  │
│  │   └─────────────┘    └──────────────────┘         │  │
│  └───────────────────────────────────────────────────┘  │
│                                                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │  文件系统: /tmp/tasks/{task_id}/                    │  │
│  │    ├── uploads/          # 上传的配置文件           │  │
│  │    ├── npm-packages/     # NPM 下载产物            │  │
│  │    ├── python-packages/  # PyPI 下载产物           │  │
│  │    └── output.zip        # 最终压缩包              │  │
│  └───────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## 4. 目录结构

```
package_download/
├── web/                          # Web 应用根目录
│   ├── frontend/                 # 前端 React 应用
│   │   ├── src/
│   │   │   ├── App.tsx           # 主应用
│   │   │   ├── main.tsx          # 入口
│   │   │   ├── components/
│   │   │   │   ├── FileUpload.tsx       # 文件上传组件
│   │   │   │   ├── DependencyTree.tsx   # 依赖树可视化
│   │   │   │   ├── DownloadProgress.tsx # 下载进度面板
│   │   │   │   ├── TaskList.tsx         # 任务列表
│   │   │   │   └── PackageStats.tsx     # 包统计信息
│   │   │   ├── hooks/
│   │   │   │   ├── useWebSocket.ts      # WebSocket 连接管理
│   │   │   │   └── useTask.ts           # 任务状态管理
│   │   │   ├── services/
│   │   │   │   └── api.ts               # API 调用封装
│   │   │   └── types/
│   │   │       └── index.ts             # TypeScript 类型定义
│   │   ├── index.html
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── vite.config.ts
│   │
│   ├── backend/                  # 后端 FastAPI 应用
│   │   ├── app/
│   │   │   ├── __init__.py
│   │   │   ├── main.py           # FastAPI 入口
│   │   │   ├── config.py         # 配置
│   │   │   ├── routers/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── upload.py     # 文件上传路由
│   │   │   │   ├── tasks.py      # 任务管理路由
│   │   │   │   └── download.py   # 下载路由
│   │   │   ├── services/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── parser.py     # 依赖文件解析
│   │   │   │   ├── npm_downloader.py    # NPM 下载器
│   │   │   │   ├── pypi_downloader.py   # PyPI 下载器
│   │   │   │   ├── task_manager.py      # 任务管理
│   │   │   │   └── packager.py          # 压缩打包
│   │   │   ├── models/
│   │   │   │   ├── __init__.py
│   │   │   │   └── schemas.py    # Pydantic 数据模型
│   │   │   └── ws/
│   │   │       ├── __init__.py
│   │   │       └── manager.py    # WebSocket 管理
│   │   └── requirements.txt      # 后端依赖
│   │
│   ├── scripts/                  # 复用的下载脚本
│   │   ├── download_npm.mjs      # 从 download_all.sh 提取的 NPM 下载逻辑
│   │   └── download_pypi.sh      # PyPI 下载逻辑
│   │
│   ├── docker-compose.yml        # 生产部署
│   └── docker-compose.dev.yml   # 开发环境
│
├── download_all.sh               # 保留原始脚本
├── upload_all.sh
├── DESIGN.md
└── README.md
```

---

## 5. API 设计

### 5.1 RESTful API

#### 上传配置文件并创建任务

```
POST /api/tasks
Content-Type: multipart/form-data

参数:
  files: File[]              # package.json, requirements.txt 等
  options: {
    npm: boolean             # 是否下载 NPM 依赖
    pypi: boolean            # 是否下载 Python 依赖
    node_version: string     # Node.js 版本 "18" | "20" | "22"
    python_version: string   # Python 版本 "3.11" | "3.12" | "3.13"
    platforms: string[]      # Python 目标平台 ["win_amd64", "manylinux2014_x86_64"]
  }

响应: {
  task_id: string,
  status: "created",
  files: string[],
  created_at: string
}
```

#### 获取依赖树（解析阶段）

```
GET /api/tasks/{task_id}/dependencies

响应: {
  task_id: string,
  npm: {
    total: number,
    tree: DependencyNode       # 嵌套树形结构
  },
  pypi: {
    total: number,
    packages: Package[]        # 扁平列表（pip 不提供树）
  }
}
```

#### 开始下载

```
POST /api/tasks/{task_id}/download

响应: {
  task_id: string,
  status: "downloading"
}
```

#### 查询任务状态

```
GET /api/tasks/{task_id}

响应: {
  task_id: string,
  status: "created" | "parsing" | "parsed" | "downloading" | "packing" | "completed" | "failed",
  progress: {
    npm: { total: number, completed: number, failed: number },
    pypi: { total: number, completed: number, failed: number }
  },
  download_url: string | null,   # 完成后生成
  error: string | null,
  created_at: string,
  completed_at: string | null
}
```

#### 下载压缩包

```
GET /api/tasks/{task_id}/archive

响应: application/zip (StreamingResponse)
```

#### 任务列表

```
GET /api/tasks?page=1&size=20

响应: {
  tasks: Task[],
  total: number
}
```

### 5.2 WebSocket

```
WS /ws/tasks/{task_id}

服务端推送消息格式:
{
  type: "progress" | "log" | "status" | "error" | "complete",
  data: {
    phase: "parsing" | "downloading" | "packing",
    current: number,
    total: number,
    message: string,
    package_name?: string,
    timestamp: string
  }
}
```

---

## 6. 核心流程

### 6.1 完整用户流程

```
用户上传文件 → 后端解析依赖 → 前端展示依赖树
     │                              │
     └──── 用户确认 ─→ 启动下载 ←───┘
                          │
              ┌───────────┴───────────┐
              │                       │
         NPM 下载                PyPI 下载
         (node子进程)             (pip subprocess)
              │                       │
              └───────────┬───────────┘
                          │
                    打包成 .zip
                          │
                  WebSocket 通知完成
                          │
                  用户点击下载压缩包
```

### 6.2 后端任务状态机

```
created → parsing → parsed → downloading → packing → completed
                        ↘         ↘            ↘
                       failed    failed       failed
```

---

## 7. 前端页面设计

### 7.1 页面布局（单页应用，Steps 步骤条引导）

```
┌─────────────────────────────────────────────────────┐
│  📦 Package Download Platform                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Steps: [① 上传文件] → [② 依赖分析] → [③ 下载打包]  │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │                                             │    │
│  │        当前步骤内容区域（动态切换）            │    │
│  │                                             │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  📋 下载日志 (实时滚动)                      │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### 7.2 Step 1 - 文件上传区

```
┌────────────────────────────────────────────────────┐
│                                                    │
│     ┌──────────────────────────────────────┐       │
│     │          📁 拖拽文件到此处            │       │
│     │     或 点击选择文件                   │       │
│     │                                      │       │
│     │  支持: package.json                  │       │
│     │        package-lock.json             │       │
│     │        requirements.txt              │       │
│     │        Pipfile / pyproject.toml      │       │
│     └──────────────────────────────────────┘       │
│                                                    │
│  已上传文件:                                        │
│  ┌──────────────────────────┐                      │
│  │ 📄 package.json    ✕     │                      │
│  │ 📄 requirements.txt ✕   │                      │
│  └──────────────────────────┘                      │
│                                                    │
│  下载选项:                                          │
│  ┌──────────────────────────────────────────┐      │
│  │ ☑ NPM 依赖    ☑ Python 依赖              │      │
│  │                                          │      │
│  │ Node.js版本: [18] [20✓] [22]             │      │
│  │ Python版本:  [3.11] [3.12] [3.13✓]       │      │
│  │ 目标平台: [win_amd64] [manylinux_x86_64] │      │
│  └──────────────────────────────────────────┘      │
│                                                    │
│                    [ 🚀 开始分析 ]                   │
└────────────────────────────────────────────────────┘
```

### 7.3 Step 2 - 依赖树可视化

```
┌────────────────────────────────────────────────────────────┐
│  依赖分析结果                                               │
│                                                            │
│  ┌─ NPM 依赖 (1,234 个包) ────────────────────────────┐   │
│  │                                                     │   │
│  │  📦 package_download@1.0.0                          │   │
│  │  ├── @anthropic-ai/claude-code@2.1.38              │   │
│  │  │   ├── some-dep@1.0.0                            │   │
│  │  │   │   └── sub-dep@2.0.0                         │   │
│  │  │   └── another-dep@3.0.0                         │   │
│  │  └── opencode-ai@1.1.53                            │   │
│  │      ├── dep-a@1.0.0                               │   │
│  │      └── dep-b@2.0.0                               │   │
│  │                                                     │   │
│  │  [展开全部] [收起全部] [搜索依赖...]                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  ┌─ Python 依赖 (86 个包) ────────────────────────────┐   │
│  │                                                     │   │
│  │  📦 jupyterlab                                      │   │
│  │  📦 aider-chat                                      │   │
│  │  ... (递归解析出的子依赖列表)                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
│  统计: NPM 1,234 包 ≈ 450MB  |  PyPI 86 包 ≈ 120MB       │
│                                                            │
│                   [ ⬇️ 开始下载 ]                           │
└────────────────────────────────────────────────────────────┘
```

### 7.4 Step 3 - 下载进度 & 打包

```
┌────────────────────────────────────────────────────────┐
│  下载进度                                               │
│                                                        │
│  NPM 依赖:  [██████████████████░░░░░░░░░░] 68%        │
│             已下载 840/1,234  失败 3                    │
│                                                        │
│  Python 依赖: [████████████████████████████] 100% ✅    │
│              已下载 86/86  失败 0                       │
│                                                        │
│  ─────────────────────────────────────────────         │
│                                                        │
│  📋 实时日志:                                           │
│  ┌──────────────────────────────────────────────┐      │
│  │ [14:23:01] ✅ Downloaded react@18.2.0        │      │
│  │ [14:23:01] ✅ Downloaded lodash@4.17.21      │      │
│  │ [14:23:02] ❌ Failed: some-pkg@1.0.0         │      │
│  │ [14:23:02] ✅ Downloaded express@4.18.2      │      │
│  │ ...                                          │      │
│  └──────────────────────────────────────────────┘      │
│                                                        │
│  ── 下载完成后 ──                                       │
│                                                        │
│  📦 压缩包: all-packages.zip (570MB)                    │
│                                                        │
│         [ ⬇️ 下载压缩包 ]  [ 📋 查看失败列表 ]           │
└────────────────────────────────────────────────────────┘
```

---

## 8. 关键数据模型

### 8.1 后端 Pydantic Models

```python
from pydantic import BaseModel
from enum import Enum
from datetime import datetime

class TaskStatus(str, Enum):
    CREATED = "created"
    PARSING = "parsing"
    PARSED = "parsed"
    DOWNLOADING = "downloading"
    PACKING = "packing"
    COMPLETED = "completed"
    FAILED = "failed"

class DownloadOptions(BaseModel):
    npm: bool = True
    pypi: bool = True
    node_version: str = "20"          # "18" | "20" | "22"
    python_version: str = "3.13"      # "3.11" | "3.12" | "3.13"
    platforms: list[str] = ["win_amd64", "manylinux2014_x86_64"]

class DependencyNode(BaseModel):
    name: str
    version: str
    children: list["DependencyNode"] = []

class PackageInfo(BaseModel):
    name: str
    version: str
    size: int | None = None

class DownloadProgress(BaseModel):
    total: int = 0
    completed: int = 0
    failed: int = 0
    failed_packages: list[str] = []

class TaskInfo(BaseModel):
    task_id: str
    status: TaskStatus
    files: list[str]
    options: DownloadOptions
    npm_dependencies: DependencyNode | None = None
    pypi_dependencies: list[PackageInfo] = []
    npm_progress: DownloadProgress = DownloadProgress()
    pypi_progress: DownloadProgress = DownloadProgress()
    archive_url: str | None = None
    archive_size: int | None = None
    error: str | None = None
    created_at: datetime
    completed_at: datetime | None = None

class WSMessage(BaseModel):
    type: str       # "progress" | "log" | "status" | "error" | "complete"
    phase: str      # "parsing" | "downloading" | "packing"
    current: int = 0
    total: int = 0
    message: str = ""
    package_name: str | None = None
    timestamp: datetime
```

### 8.2 前端 TypeScript Types

```typescript
interface Task {
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

interface DependencyNode {
  name: string;
  version: string;
  children: DependencyNode[];
}

interface DownloadProgress {
  total: number;
  completed: number;
  failed: number;
  failed_packages: string[];
}

interface WSMessage {
  type: "progress" | "log" | "status" | "error" | "complete";
  phase: "parsing" | "downloading" | "packing";
  current: number;
  total: number;
  message: string;
  package_name?: string;
  timestamp: string;
}
```

---

## 9. 关键实现细节

### 9.1 依赖解析策略

#### NPM 依赖解析

1. 用户上传 `package.json`（可选 `package-lock.json`）
2. 后端根据用户选择的 Node.js 版本，调用对应版本的 `npm` 执行解析
3. 执行 `npm install --package-lock-only` → `npm list --all --json` 获取完整依赖树
4. 解析 JSON 输出构建树形结构返回前端
5. 下载阶段复用现有的 `download_npm_temp.mjs` 脚本逻辑（通过 subprocess 调用）

#### PyPI 依赖解析

1. 用户上传 `requirements.txt`
2. 后端根据用户选择的 Python 版本，使用对应 `--python-version` 参数
3. 使用 `pip install --dry-run --report` (PEP 665) 解析依赖，或使用 `pipdeptree` 获取依赖树
4. 下载阶段调用 `pip download --python-version <ver> --abi cp<ver>` 命令

#### 多版本运行时管理

backend 容器内预装多个 Node.js 和 Python 版本，通过 **nvm** 和 **pyenv** 管理切换：

```dockerfile
# backend Dockerfile 示例
FROM python:3.13-slim

# 安装 nvm + 多版本 Node.js
ENV NVM_DIR=/root/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install 18 && nvm install 20 && nvm install 22 && \
    nvm alias default 20

# 安装多版本 Python (用于 pip download --python-version)
# pip download 的 --python-version 参数不需要实际安装目标 Python，
# 只需指定版本号即可下载对应 wheel，但如需 sdist 构建则需要对应 Python
RUN pip install pyenv  # 可选，按需安装额外 Python
```

```python
# 后端：根据选择的版本调用对应的 npm
import os

def get_node_env(version: str) -> dict:
    """返回使用指定 Node.js 版本的环境变量"""
    nvm_dir = os.environ.get('NVM_DIR', '/root/.nvm')
    node_path = f"{nvm_dir}/versions/node/v{version}/bin"
    env = os.environ.copy()
    env['PATH'] = f"{node_path}:{env['PATH']}"
    return env

async def run_npm_with_version(node_version: str, args: list[str], cwd: str):
    full_version = NODE_VERSION_MAP[node_version]  # "18" → "18.20.4"
    env = get_node_env(full_version)
    process = await asyncio.create_subprocess_exec(
        'npm', *args, cwd=cwd, env=env,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    return process

def get_pip_python_version_args(python_version: str) -> list[str]:
    """返回 pip download 的 Python 版本相关参数"""
    ver_short = python_version.replace('.', '')  # "3.13" → "313"
    return [
        '--python-version', ver_short,
        '--implementation', 'cp',
        '--abi', f'cp{ver_short}'
    ]
```

### 9.2 下载进度追踪

```python
# 后端：通过解析 subprocess 输出流实时推送进度
async def download_with_progress(task_id: str, ws_manager: WSManager):
    process = await asyncio.create_subprocess_exec(
        'node', 'download_npm.mjs',
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env={...}
    )

    async for line in process.stdout:
        # 解析进度信息
        progress = parse_progress(line.decode())
        if progress:
            await ws_manager.send(task_id, {
                "type": "progress",
                "phase": "downloading",
                **progress
            })
```

### 9.3 多版本运行时管理

后端容器通过 [nvm](https://github.com/nvm-sh/nvm) 和 [pyenv](https://github.com/pyenv/pyenv) 预装多版本运行时，根据用户选择动态切换：

```python
# 支持的版本
SUPPORTED_NODE_VERSIONS = ["18", "20", "22"]
SUPPORTED_PYTHON_VERSIONS = ["3.11", "3.12", "3.13"]

def get_node_bin(version: str) -> str:
    """获取指定版本 Node.js 的 binary 路径"""
    nvm_dir = os.environ.get("NVM_DIR", os.path.expanduser("~/.nvm"))
    # nvm 安装的 node 路径
    node_path = f"{nvm_dir}/versions/node/v{version}.*/bin/node"
    matches = glob.glob(node_path)
    if not matches:
        raise ValueError(f"Node.js {version} not installed")
    return os.path.dirname(matches[-1])  # 返回 bin 目录

def get_python_bin(version: str) -> str:
    """获取指定版本 Python 的 binary 路径"""
    pyenv_root = os.environ.get("PYENV_ROOT", os.path.expanduser("~/.pyenv"))
    python_path = f"{pyenv_root}/versions/{version}.*/bin/python"
    matches = glob.glob(python_path)
    if not matches:
        raise ValueError(f"Python {version} not installed")
    return matches[-1]

async def download_npm_packages(task: TaskInfo):
    """使用用户指定的 Node.js 版本下载 NPM 包"""
    node_bin_dir = get_node_bin(task.options.node_version)
    env = {
        **os.environ,
        "PATH": f"{node_bin_dir}:{os.environ['PATH']}",
        "NPM_DOWNLOAD_DIR": task.npm_download_dir,
    }
    process = await asyncio.create_subprocess_exec(
        f"{node_bin_dir}/node", "download_npm.mjs",
        env=env, stdout=PIPE, stderr=PIPE
    )
    ...

async def download_pypi_packages(task: TaskInfo):
    """使用用户指定的 Python 版本下载 PyPI 包"""
    python_bin = get_python_bin(task.options.python_version)
    # pip download 的 --python-version 参数
    py_ver_short = task.options.python_version.replace(".", "")  # "3.13" → "313"
    for platform in task.options.platforms:
        process = await asyncio.create_subprocess_exec(
            python_bin, "-m", "pip", "download",
            "-r", requirements_path,
            "--dest", task.pypi_download_dir,
            "--only-binary=:all:",
            "--platform", platform,
            "--python-version", py_ver_short,
            stdout=PIPE, stderr=PIPE
        )
        ...
```

**版本选择对下载的影响：**

| 选项         | 影响                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------- |
| Node.js 版本 | 决定 `npm install` 和 `npm pack` 时的依赖解析行为，不同大版本可能解析出不同的依赖树            |
| Python 版本  | 传递给 `pip download --python-version`，下载兼容该版本的 wheel 包（如 cp311/cp312/cp313 标签） |

### 9.3 压缩包生成

```python
import zipfile

async def create_archive(task_dir: str, task_id: str) -> str:
    output_path = os.path.join(task_dir, f"packages-{task_id}.zip")

    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(os.path.join(task_dir, 'npm-packages')):
            for file in files:
                filepath = os.path.join(root, file)
                arcname = os.path.join('npm-packages', file)
                zf.write(filepath, arcname)

        for root, dirs, files in os.walk(os.path.join(task_dir, 'python-packages')):
            for file in files:
                filepath = os.path.join(root, file)
                arcname = os.path.join('python-packages', file)
                zf.write(filepath, arcname)

    return output_path
```

### 9.4 文件清理策略

- 任务文件存储在 `/tmp/pkg-download-tasks/{task_id}/`
- 压缩包生成后保留 **24 小时**，后台定时清理
- 提供手动清理 API `/api/tasks/{task_id}` (DELETE)
- 服务启动时清理超过 24 小时的任务目录

---

## 10. 安全考量

| 风险         | 措施                                                              |
| ------------ | ----------------------------------------------------------------- |
| 恶意文件上传 | 限制文件类型（.json / .txt / .toml / .cfg），限制大小（最大 1MB） |
| 命令注入     | 不直接拼接用户输入到 shell 命令，使用参数列表形式调用 subprocess  |
| 资源耗尽     | 限制并发任务数（最多 5 个），单任务超时 30 分钟                   |
| 磁盘空间     | 限制单任务最大 2GB，定时清理旧任务                                |
| 路径穿越     | 校验上传文件名，使用 `secure_filename()`                          |

---

## 11. 部署方案（Docker Compose）

### 开发环境

```bash
# 一键启动开发环境
docker compose -f docker-compose.dev.yml up --build
# 前端: http://localhost:5173 (Vite dev server, HMR)
# 后端: http://localhost:8000 (FastAPI, auto-reload)
# API 文档: http://localhost:8000/docs
```

```yaml
# docker-compose.dev.yml
services:
  backend:
    build:
      context: ./web/backend
      dockerfile: Dockerfile.dev
    ports: ["8000:8000"]
    volumes:
      - ./web/backend/app:/app/app # 代码热重载
      - ./web/scripts:/app/scripts
      - task-data:/tmp/pkg-download-tasks
    environment:
      - MAX_CONCURRENT_TASKS=5
      - TASK_EXPIRE_HOURS=24
    command: uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

  frontend:
    build:
      context: ./web/frontend
      dockerfile: Dockerfile.dev
    ports: ["5173:5173"]
    volumes:
      - ./web/frontend/src:/app/src # 代码热重载
    depends_on: [backend]
    command: npm run dev -- --host 0.0.0.0

volumes:
  task-data:
```

### 生产环境

```yaml
# docker-compose.yml
services:
  backend:
    build: ./web/backend
    restart: always
    ports: ["8000:8000"]
    volumes:
      - task-data:/tmp/pkg-download-tasks
    environment:
      - MAX_CONCURRENT_TASKS=5
      - TASK_EXPIRE_HOURS=24
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  frontend:
    build: ./web/frontend # 多阶段构建：Vite build → Nginx 托管
    restart: always
    ports: ["80:80"]
    depends_on: [backend]

volumes:
  task-data:
```

### 容器说明

| 容器         | 基础镜像                                           | 说明                                                                                  |
| ------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **backend**  | `python:3.13-slim` + nvm + pyenv                   | 预装 Node.js 18/20/22 (nvm) + Python 3.11/3.12/3.13 (pyenv)，根据用户选择动态切换版本 |
| **frontend** | 构建阶段 `node:20-alpine`，运行阶段 `nginx:alpine` | 多阶段构建，Nginx 托管静态文件并反向代理 `/api` → backend:8000                        |

---

## 12. 开发计划（分期）

### Phase 1 - MVP（3-4天）

- [x] 设计方案
- [ ] FastAPI 后端骨架：路由、数据模型
- [ ] 文件上传 API + 依赖解析（NPM + PyPI）
- [ ] 基础前端：文件上传、依赖列表展示
- [ ] 下载功能（复用现有脚本）
- [ ] 压缩包生成 + 下载 API

### Phase 2 - 体验优化（2-3天）

- [ ] WebSocket 实时进度推送
- [ ] 依赖树交互式可视化（展开/收起/搜索）
- [ ] 下载日志实时展示
- [ ] 错误处理 & 重试机制
- [ ] 任务历史列表

### Phase 3 - 生产就绪（2天）

- [ ] 任务清理定时器
- [ ] 并发限制和排队机制
- [ ] 支持更多格式（pyproject.toml、Pipfile）

### Phase 4 - 增强功能（可选）

- [ ] 用户认证
- [ ] 上传到 Nexus 私有仓库的集成（复用 upload_all.sh）
- [ ] 依赖版本冲突检测
- [ ] 包大小预估
- [ ] 多 Registry 源配置（国内镜像等）

---

## 13. 接口交互时序图

```
用户            前端(React)          后端(FastAPI)         文件系统
 │                │                     │                    │
 │  上传文件       │                     │                    │
 │───────────────>│  POST /api/tasks    │                    │
 │                │────────────────────>│  保存文件           │
 │                │                     │──────────────────>│
 │                │   { task_id }       │                    │
 │                │<────────────────────│                    │
 │                │                     │                    │
 │                │  WS /ws/{task_id}   │                    │
 │                │════════════════════>│                    │
 │                │                     │                    │
 │  点击「分析」   │                     │                    │
 │───────────────>│  自动触发解析        │                    │
 │                │                     │  npm install       │
 │                │                     │  npm list --json   │
 │                │  ws: 依赖树数据      │                    │
 │                │<════════════════════│                    │
 │ 展示依赖树      │                     │                    │
 │<───────────────│                     │                    │
 │                │                     │                    │
 │  点击「下载」   │                     │                    │
 │───────────────>│ POST .../download   │                    │
 │                │────────────────────>│  npm pack          │
 │                │                     │  pip download      │
 │                │  ws: progress       │──────────────────>│
 │                │<════════════════════│                    │
 │  看到进度条     │                     │                    │
 │<───────────────│                     │                    │
 │                │  ws: complete       │  zip 打包           │
 │                │<════════════════════│──────────────────>│
 │                │                     │                    │
 │  点击「下载zip」│                     │                    │
 │───────────────>│ GET .../archive     │                    │
 │                │────────────────────>│  StreamingResponse │
 │  浏览器下载     │  ← zip file ←      │<──────────────────│
 │<───────────────│<────────────────────│                    │
```
