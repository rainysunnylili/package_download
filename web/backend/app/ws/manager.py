"""WebSocket connection manager"""
from fastapi import WebSocket
from typing import Dict
import json
import logging
import datetime

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages WebSocket connections for tasks"""

    def __init__(self):
        self.active_connections: Dict[str, list[WebSocket]] = {}

    async def connect(self, task_id: str, websocket: WebSocket):
        """Connect a WebSocket to a task"""
        await websocket.accept()
        if task_id not in self.active_connections:
            self.active_connections[task_id] = []
        self.active_connections[task_id].append(websocket)
        logger.info(f"WebSocket connected to task {task_id}")

    def disconnect(self, task_id: str, websocket: WebSocket):
        """Disconnect a WebSocket from a task"""
        if task_id in self.active_connections:
            if websocket in self.active_connections[task_id]:
                self.active_connections[task_id].remove(websocket)
            if not self.active_connections[task_id]:
                del self.active_connections[task_id]
        logger.info(f"WebSocket disconnected from task {task_id}")

    async def send_message(self, task_id: str, message: dict):
        """Send a message to all WebSocket connections for a task"""
        if task_id not in self.active_connections:
            return

        disconnected = []
        for connection in self.active_connections[task_id]:
            try:
                await connection.send_json(message)
            except Exception as e:
                logger.error(f"Error sending message to WebSocket: {e}")
                disconnected.append(connection)

        for connection in disconnected:
            self.disconnect(task_id, connection)

    async def broadcast(self, task_id: str, message_type: str, data: dict):
        """Broadcast a message to all connections for a task"""
        message = {
            "type": message_type,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            **data
        }
        await self.send_message(task_id, message)


manager = ConnectionManager()
