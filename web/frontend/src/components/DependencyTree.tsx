/**
 * Dependency tree visualization component
 */
import React, { useEffect, useRef } from "react";
import { Card, Tree, Empty, Spin, Space, Typography, Tag, Timeline } from "antd";
import {
  LoadingOutlined,
  CheckCircleOutlined,
  CodeOutlined,
  SearchOutlined,
  CloseCircleOutlined,
} from "@ant-design/icons";
import { DependencyNode, PackageInfo, WSMessage } from "../types";
import type { DataNode } from "antd/es/tree";

const { Text } = Typography;

interface DependencyTreeProps {
  npmTree?: DependencyNode;
  pypiPackages?: PackageInfo[];
  loading?: boolean;
  logs?: WSMessage[];
  taskStatus?: string;
}

const buildTreeData = (node: DependencyNode): DataNode => {
  return {
    title: `${node.name}@${node.version}`,
    key: `${node.name}-${node.version}`,
    children: node.children.map(buildTreeData),
  };
};

const getLogIcon = (log: WSMessage) => {
  if (log.type === "error") return <CloseCircleOutlined style={{ color: "#ff4d4f" }} />;
  if (log.type === "complete") return <CheckCircleOutlined style={{ color: "#52c41a" }} />;
  if (log.type === "status") return <SearchOutlined style={{ color: "#1890ff" }} />;
  return <CodeOutlined style={{ color: "#8c8c8c" }} />;
};

const getLogColor = (log: WSMessage) => {
  if (log.type === "error") return "red";
  if (log.type === "complete") return "green";
  if (log.type === "status") return "blue";
  return "gray";
};

export const DependencyTree: React.FC<DependencyTreeProps> = ({
  npmTree,
  pypiPackages = [],
  loading = false,
  logs = [],
  taskStatus,
}) => {
  const logEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [logs.length]);

  const parsingLogs = logs.filter(
    (log) => log.phase === "parsing" || log.type === "status" || log.type === "complete" || log.type === "error"
  );

  if (loading) {
    const steps = [
      { label: "上传文件", done: true },
      { label: "解析配置文件", done: parsingLogs.length > 0 },
      { label: "分析 NPM 依赖树", done: parsingLogs.some((l) => l.message?.includes("NPM") || l.message?.includes("npm")) },
      { label: "解析 Python 依赖", done: parsingLogs.some((l) => l.message?.includes("Python") || l.message?.includes("python")) },
      { label: "完成分析", done: taskStatus === "parsed" },
    ];

    return (
      <Card title="依赖分析">
        <Space direction="vertical" style={{ width: "100%" }} size="large">
          {/* 分析进度步骤 */}
          <div style={{ padding: "16px 0" }}>
            <Timeline
              items={steps.map((step, idx) => {
                const isActive = step.done && !steps[idx + 1]?.done;
                return {
                  color: step.done ? (isActive ? "blue" : "green") : "gray",
                  dot: step.done
                    ? isActive
                      ? <LoadingOutlined style={{ fontSize: 16 }} />
                      : <CheckCircleOutlined style={{ fontSize: 16 }} />
                    : undefined,
                  children: (
                    <Text
                      strong={isActive}
                      type={step.done ? undefined : "secondary"}
                    >
                      {step.label}
                    </Text>
                  ),
                };
              })}
            />
          </div>

          {/* 实时日志 */}
          {parsingLogs.length > 0 && (
            <Card
              title={
                <Space>
                  <Spin size="small" />
                  <span>分析日志</span>
                </Space>
              }
              size="small"
            >
              <div style={{ maxHeight: 240, overflow: "auto", fontFamily: "monospace", fontSize: 13 }}>
                {parsingLogs.map((log, idx) => (
                  <div
                    key={idx}
                    style={{
                      padding: "4px 8px",
                      background: idx % 2 === 0 ? "#fafafa" : "#fff",
                      borderLeft: `3px solid ${
                        log.type === "error" ? "#ff4d4f" : log.type === "complete" ? "#52c41a" : "#1890ff"
                      }`,
                      marginBottom: 2,
                    }}
                  >
                    <Space size={8}>
                      {getLogIcon(log)}
                      {log.timestamp && (
                        <Text type="secondary" style={{ fontSize: 12 }}>
                          {new Date(log.timestamp).toLocaleTimeString()}
                        </Text>
                      )}
                      <Text style={{ color: log.type === "error" ? "#ff4d4f" : undefined }}>
                        {log.message}
                      </Text>
                    </Space>
                  </div>
                ))}
                <div ref={logEndRef} />
              </div>
            </Card>
          )}

          {/* 无日志时显示默认 loading */}
          {parsingLogs.length === 0 && (
            <div style={{ textAlign: "center", padding: "20px 0" }}>
              <Spin size="large" />
              <div style={{ marginTop: 16 }}>
                <Text type="secondary">正在连接并准备分析...</Text>
              </div>
            </div>
          )}
        </Space>
      </Card>
    );
  }

  if (!npmTree && pypiPackages.length === 0) {
    return (
      <Card title="依赖分析">
        <Empty description="未找到依赖" />
      </Card>
    );
  }

  const countPackages = (node: DependencyNode): number => {
    let count = 1;
    node.children.forEach((child) => {
      count += countPackages(child);
    });
    return count;
  };

  const npmCount = npmTree ? countPackages(npmTree) : 0;
  const pypiCount = pypiPackages.length;

  return (
    <Card title="依赖分析">
      <Space direction="vertical" style={{ width: "100%" }} size="large">
        {npmTree && (
          <Card
            type="inner"
            title={
              <Space>
                <span>NPM 依赖</span>
                <Tag color="blue">{npmCount} 个包</Tag>
              </Space>
            }
          >
            <Tree
              showLine
              defaultExpandAll
              treeData={[buildTreeData(npmTree)]}
              height={400}
              style={{ overflow: "auto" }}
            />
          </Card>
        )}

        {pypiPackages.length > 0 && (
          <Card
            type="inner"
            title={
              <Space>
                <span>Python 依赖</span>
                <Tag color="green">{pypiCount} 个包</Tag>
              </Space>
            }
          >
            <div style={{ maxHeight: 400, overflow: "auto" }}>
              <Space direction="vertical" style={{ width: "100%" }}>
                {pypiPackages.map((pkg) => (
                  <Card key={`${pkg.name}-${pkg.version}`} size="small">
                    <Text strong>{pkg.name}</Text>
                    <Text type="secondary"> v{pkg.version}</Text>
                  </Card>
                ))}
              </Space>
            </div>
          </Card>
        )}

        <Card size="small" style={{ background: "#f5f5f5" }}>
          <Space>
            <Text strong>总计：</Text>
            {npmCount > 0 && <Text>NPM：{npmCount} 个包</Text>}
            {pypiCount > 0 && <Text>Python：{pypiCount} 个包</Text>}
          </Space>
        </Card>
      </Space>
    </Card>
  );
};
