"""FastAPI main application"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
import asyncio

from app.config import config
from app.routers import upload, tasks, download
from app.services.task_manager import task_manager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


async def cleanup_task_loop():
    """Periodic task cleanup"""
    while True:
        try:
            await asyncio.sleep(3600)  # Run every hour
            logger.info("Running scheduled task cleanup")
            task_manager.cleanup_expired_tasks()
        except Exception as e:
            logger.error(f"Error in cleanup task: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    # Startup
    logger.info("Starting Package Download Web Platform")
    config.ensure_dirs()
    task_manager.cleanup_expired_tasks()

    # Start cleanup task
    cleanup_task = asyncio.create_task(cleanup_task_loop())

    yield

    # Shutdown
    logger.info("Shutting down Package Download Web Platform")
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass


# Create FastAPI app
app = FastAPI(
    title="Package Download Web Platform",
    description="Download NPM and PyPI packages via web interface",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(upload.router)
app.include_router(tasks.router)
app.include_router(download.router)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "name": "Package Download Web Platform",
        "version": "1.0.0",
        "docs": "/docs"
    }
