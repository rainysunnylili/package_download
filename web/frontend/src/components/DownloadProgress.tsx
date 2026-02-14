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

const formatTimestamp = (ts: string | undefined): string => {
  if (!ts) return "";
  const d = new Date(ts);
  if (isNaN(d.getTime())) return "";
  return `[${d.toLocaleTimeString()}]`;
};

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

  // 只显示下载和打包阶段的日志
  const downloadLogs = logs.filter(
    (log) => log.phase === "downloading" || log.phase === "packing"
  );

  return (
    <Card title="下载进度">
      <Space direction="vertical" style={{ width: "100%" }} size="large">
        {/* 状态提示 */}
        {isDownloading && (
          <Text type="secondary">
            {task.status === "packing" ? "正在打包压缩..." : "正在下载依赖包..."}
          </Text>
        )}

        {task.options.npm && (
          <div>
            <Space>
              <Text strong>NPM 包：</Text>
              <Text>
                {task.npm_progress.completed}/{task.npm_progress.total || "—"}
              </Text>
              {task.npm_progress.failed > 0 && (
                <Tag color="error">失败：{task.npm_progress.failed}</Tag>
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

        {task.options.pypi && (
          <div>
            <Space>
              <Text strong>Python 包：</Text>
              <Text>
                {task.pypi_progress.completed}/{task.pypi_progress.total || "—"}
              </Text>
              {task.pypi_progress.failed > 0 && (
                <Tag color="error">失败：{task.pypi_progress.failed}</Tag>
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
                下载完成！
                </Title>
              </Space>
              <Text>
                包大小： <Text strong>{formatSize(task.archive_size)}</Text>
              </Text>
              <Button
                type="primary"
                icon={<DownloadOutlined />}
                size="large"
                onClick={onDownload}
                block
              >
                下载压缩包
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
                  下载失败
                </Title>
                <Text type="danger">{task.error}</Text>
              </div>
            </Space>
          </Card>
        )}

        {/* 失败包列表 */}
        {(task.npm_progress.failed_packages.length > 0 ||
          task.pypi_progress.failed_packages.length > 0) && (
          <Card title="失败包列表" size="small">
            <Space wrap>
              {task.npm_progress.failed_packages.map((pkg) => (
                <Tag color="error" key={`npm-${pkg}`}>
                  NPM: {pkg}
                </Tag>
              ))}
              {task.pypi_progress.failed_packages.map((pkg) => (
                <Tag color="error" key={`pypi-${pkg}`}>
                  PyPI: {pkg}
                </Tag>
              ))}
            </Space>
          </Card>
        )}

        {downloadLogs.length > 0 && (
          <Card title="下载日志" size="small">
            <List
              size="small"
              dataSource={downloadLogs.slice(-50).reverse()}
              style={{ maxHeight: 300, overflow: "auto" }}
              renderItem={(log) => (
                <List.Item>
                  <Space>
                    {formatTimestamp(log.timestamp) && (
                      <Text type="secondary">{formatTimestamp(log.timestamp)}</Text>
                    )}
                    {log.type === "error" && <Tag color="error">错误</Tag>}
                    {log.type === "complete" && <Tag color="success">完成</Tag>}
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
