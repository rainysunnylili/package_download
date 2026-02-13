/**
 * Task hook for managing task state
 */
import { useState, useEffect, useCallback } from "react";
import { Task, WSMessage } from "../types";
import { api } from "../services/api";
import { useWebSocket } from "./useWebSocket";

export const useTask = (taskId: string | null) => {
  const [task, setTask] = useState<Task | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [logs, setLogs] = useState<WSMessage[]>([]);

  const wsUrl = taskId ? api.getWebSocketUrl(taskId) : "";

  const handleWebSocketMessage = useCallback((message: WSMessage) => {
    setLogs((prev) => [...prev, message]);

    if (message.type === "status" && taskId) {
      fetchTask();
    }
  }, [taskId]);

  const { isConnected } = useWebSocket(wsUrl, {
    onMessage: handleWebSocketMessage,
    autoConnect: !!taskId,
  });

  const fetchTask = useCallback(async () => {
    if (!taskId) return;

    try {
      setLoading(true);
      const data = await api.getTask(taskId);
      setTask(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to fetch task");
    } finally {
      setLoading(false);
    }
  }, [taskId]);

  useEffect(() => {
    if (taskId) {
      fetchTask();
    }
  }, [taskId, fetchTask]);

  const parseTask = useCallback(async () => {
    if (!taskId) return;

    try {
      await api.parseTask(taskId);
      await fetchTask();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to parse task");
    }
  }, [taskId, fetchTask]);

  const startDownload = useCallback(async () => {
    if (!taskId) return;

    try {
      await api.startDownload(taskId);
      await fetchTask();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to start download");
    }
  }, [taskId, fetchTask]);

  const deleteTask = useCallback(async () => {
    if (!taskId) return;

    try {
      await api.deleteTask(taskId);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to delete task");
      throw err;
    }
  }, [taskId]);

  return {
    task,
    loading,
    error,
    logs,
    isConnected,
    fetchTask,
    parseTask,
    startDownload,
    deleteTask,
  };
};
