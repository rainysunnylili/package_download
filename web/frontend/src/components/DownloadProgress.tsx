/**
 * Download progress component
 */
import React from "react";
import { Card, Progress, Space, Typography, Button, List, Tag } from "antd";
import { DownloadOutlined, CheckCircleOutlined, CloseCircleOutlined } from "@ant-design/icons";
import { Task, WSMessage } from "../types";

const { Text, Title } = Typography;

interface DownloadProgressProps {
  task: Task;
  logs: WSMessage[];
  onDownload?: () => void;
}

export const DownloadProgress: React.FC<DownloadProgressProps> = ({
  task,
  logs,
  onDownload,
}) => {
  const npmPercent =
    task.npm_progress.total > 0
      ? Math.round((task.npm_progress.completed / task.npm_progress.total) * 100)
      : 0;

  const pypiPercent =
    task.pypi_progress.total > 0
      ? Math.round((task.pypi_progress.completed / task.pypi_progress.total) * 100)
      : 0;

  const isDownloading = task.status === "downloading" || task.status === "packing";
  const isCompleted = task.status === "completed";
  const isFailed = task.status === "failed";

  const getStatusColor = () => {
    if (isCompleted) return "success";
    if (isFailed) return "exception";
    return "active";
  };

  const formatSize = (bytes?: number) => {
    if (!bytes) return "N/A";
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(2)} MB`;
  };

  return (
    <Card title="Download Progress">
      <Space direction="vertical" style={{ width: "100%" }} size="large">
        {task.options.npm && task.npm_progress.total > 0 && (
          <div>
            <Space>
              <Text strong>NPM Packages:</Text>
              <Text>
                {task.npm_progress.completed}/{task.npm_progress.total}
              </Text>
              {task.npm_progress.failed > 0 && (
                <Tag color="error">Failed: {task.npm_progress.failed}</Tag>
              )}
            </Space>
            <Progress
              percent={npmPercent}
              status={getStatusColor()}
              strokeColor={{
                "0%": "#108ee9",
                "100%": "#87d068",
              }}
            />
          </div>
        )}

        {task.options.pypi && task.pypi_progress.total > 0 && (
          <div>
            <Space>
              <Text strong>Python Packages:</Text>
              <Text>
                {task.pypi_progress.completed}/{task.pypi_progress.total}
              </Text>
              {task.pypi_progress.failed > 0 && (
                <Tag color="error">Failed: {task.pypi_progress.failed}</Tag>
              )}
            </Space>
            <Progress
              percent={pypiPercent}
              status={getStatusColor()}
              strokeColor={{
                "0%": "#52c41a",
                "100%": "#389e0d",
              }}
            />
          </div>
        )}

        {isCompleted && task.archive_size && (
          <Card style={{ background: "#f6ffed", border: "1px solid #b7eb8f" }}>
            <Space direction="vertical" style={{ width: "100%" }}>
              <Space>
                <CheckCircleOutlined style={{ color: "#52c41a", fontSize: 24 }} />
                <Title level={4} style={{ margin: 0 }}>
                  Download Complete!
                </Title>
              </Space>
              <Text>
                Archive size: <Text strong>{formatSize(task.archive_size)}</Text>
              </Text>
              <Button
                type="primary"
                icon={<DownloadOutlined />}
                size="large"
                onClick={onDownload}
                block
              >
                Download Archive
              </Button>
            </Space>
          </Card>
        )}

        {isFailed && (
          <Card style={{ background: "#fff2e8", border: "1px solid #ffbb96" }}>
            <Space>
              <CloseCircleOutlined style={{ color: "#ff4d4f", fontSize: 24 }} />
              <div>
                <Title level={4} style={{ margin: 0 }}>
                  Download Failed
                </Title>
                <Text type="danger">{task.error}</Text>
              </div>
            </Space>
          </Card>
        )}

        {logs.length > 0 && (
          <Card title="Download Logs" size="small">
            <List
              size="small"
              dataSource={logs.slice(-50).reverse()}
              style={{ maxHeight: 300, overflow: "auto" }}
              renderItem={(log) => (
                <List.Item>
                  <Space>
                    <Text type="secondary">[{new Date(log.timestamp).toLocaleTimeString()}]</Text>
                    {log.type === "error" && <Tag color="error">ERROR</Tag>}
                    {log.type === "complete" && <Tag color="success">SUCCESS</Tag>}
                    <Text>{log.message}</Text>
                    {log.package_name && <Tag>{log.package_name}</Tag>}
                  </Space>
                </List.Item>
              )}
            />
          </Card>
        )}
      </Space>
    </Card>
  );
};
