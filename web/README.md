# Package Download Web Platform

A web-based platform for downloading NPM and PyPI packages with dependency visualization.

## Features

- **File Upload**: Upload package.json, requirements.txt, and other dependency files
- **Dependency Analysis**: Visualize dependency trees for NPM and Python packages
- **Multi-Version Support**: Download packages for different Node.js (18, 20, 22) and Python (3.11, 3.12, 3.13) versions
- **Real-Time Progress**: WebSocket-based real-time download progress tracking
- **Archive Download**: Download all packages as a single ZIP file

## Quick Start

### Development Mode

```bash
cd web
docker-compose -f docker-compose.dev.yml up --build
```

- Frontend: http://localhost:5173
- Backend: http://localhost:8000
- API Docs: http://localhost:8000/docs

### Production Mode

```bash
cd web
docker-compose up --build
```

- Application: http://localhost
- Backend API: http://localhost:8000

## Project Structure

```
web/
├── backend/              # FastAPI backend
│   ├── app/
│   │   ├── main.py       # FastAPI application entry
│   │   ├── config.py     # Configuration
│   │   ├── models/       # Pydantic data models
│   │   ├── routers/      # API routes
│   │   ├── services/     # Business logic
│   │   └── ws/           # WebSocket management
│   ├── tests/            # Backend tests
│   ├── Dockerfile        # Production backend image
│   └── requirements.txt  # Python dependencies
├── frontend/             # React frontend
│   ├── src/
│   │   ├── App.tsx       # Main application
│   │   ├── components/   # React components
│   │   ├── hooks/        # Custom React hooks
│   │   ├── services/     # API services
│   │   └── types/        # TypeScript types
│   ├── Dockerfile        # Production frontend image
│   └── package.json      # Node.js dependencies
└── docker-compose.yml    # Production deployment
```

## Development

### Backend Development

```bash
cd web/backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### Frontend Development

```bash
cd web/frontend
npm install
npm run dev
```

### Running Tests

Backend tests:
```bash
cd web/backend
pytest
```

## API Documentation

When running the backend, access the auto-generated API documentation at:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Environment Variables

### Backend

- `MAX_CONCURRENT_TASKS`: Maximum concurrent download tasks (default: 5)
- `TASK_EXPIRE_HOURS`: Hours before old tasks are cleaned up (default: 24)
- `TASKS_BASE_DIR`: Directory for task files (default: /tmp/pkg-download-tasks)

### Frontend

- `VITE_API_BASE_URL`: Backend API URL (default: http://localhost:8000)

## Architecture

The platform consists of:

1. **Backend (FastAPI)**:
   - RESTful API for task management
   - WebSocket for real-time updates
   - Async package downloaders for NPM and PyPI
   - Task queue management

2. **Frontend (React + TypeScript)**:
   - Step-by-step wizard interface
   - Real-time progress visualization
   - Dependency tree display using Ant Design components

3. **Docker**:
   - Multi-stage builds for optimization
   - Development and production configurations
   - Volume management for task data
