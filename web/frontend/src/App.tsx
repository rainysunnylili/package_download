/**
 * Main application component
 */
import React, { useState, useEffect } from "react";
import { Layout, Steps, Button, Space, Typography, message } from "antd";
import { FileUpload } from "./components/FileUpload";
import { DependencyTree } from "./components/DependencyTree";
import { DownloadProgress } from "./components/DownloadProgress";
import { useTask } from "./hooks/useTask";
import { api } from "./services/api";
import { DependenciesResponse } from "./types";

const { Header, Content, Footer } = Layout;
const { Title } = Typography;

const App: React.FC = () => {
  const [currentStep, setCurrentStep] = useState(0);
  const [taskId, setTaskId] = useState<string | null>(null);
  const [dependencies, setDependencies] = useState<DependenciesResponse | null>(null);
  const [loadingDeps, setLoadingDeps] = useState(false);

  const { task, logs, parseTask, startDownload } = useTask(taskId);

  useEffect(() => {
    if (!task) return;

    switch (task.status) {
      case "created":
        setCurrentStep(0);
        break;
      case "parsing":
      case "parsed":
        setCurrentStep(1);
        break;
      case "downloading":
      case "packing":
      case "completed":
      case "failed":
        setCurrentStep(2);
        break;
    }
  }, [task?.status]);

  const handleUploadComplete = async (newTaskId: string) => {
    setTaskId(newTaskId);
    setCurrentStep(1);

    try {
      await api.parseTask(newTaskId);
    } catch (error) {
      message.error("解析启动失败");
    }
  };

  const handleLoadDependencies = async () => {
    if (!taskId) return;

    setLoadingDeps(true);
    try {
      const deps = await api.getDependencies(taskId);
      setDependencies(deps);
    } catch (error) {
      message.error("加载依赖信息失败");
    } finally {
      setLoadingDeps(false);
    }
  };

  useEffect(() => {
    if (task?.status === "parsed") {
      handleLoadDependencies();
    }
  }, [task?.status]);

  const handleStartDownload = async () => {
    if (!taskId) return;

    try {
      await startDownload();
      setCurrentStep(2);
    } catch (error) {
      message.error("下载启动失败");
    }
  };

  const handleDownloadArchive = () => {
    if (!taskId) return;
    const url = api.getArchiveUrl(taskId);
    window.open(url, "_blank");
  };

  const handleReset = () => {
    setTaskId(null);
    setDependencies(null);
    setCurrentStep(0);
  };

  const steps = [
    {
      title: "上传文件",
      description: "上传依赖配置文件",
    },
    {
      title: "分析依赖",
      description: "查看依赖树",
    },
    {
      title: "下载打包",
      description: "下载所有依赖包",
    },
  ];

  return (
    <Layout style={{ minHeight: "100vh" }}>
      <Header style={{ background: "#001529", padding: "0 50px" }}>
        <Title level={3} style={{ color: "white", margin: "16px 0" }}>
          📦 离线包下载平台
        </Title>
      </Header>

      <Content style={{ padding: "50px" }}>
        <div style={{ maxWidth: 1200, margin: "0 auto" }}>
          <Steps current={currentStep} items={steps} style={{ marginBottom: 40 }} />

          {currentStep === 0 && <FileUpload onUploadComplete={handleUploadComplete} />}

          {currentStep === 1 && (
            <Space direction="vertical" style={{ width: "100%" }} size="large">
              <DependencyTree
                npmTree={dependencies?.npm?.tree}
                pypiPackages={dependencies?.pypi?.packages}
                loading={loadingDeps || task?.status === "parsing"}
                logs={logs}
                taskStatus={task?.status}
              />

              {task?.status === "parsed" && (
                <Button
                  type="primary"
                  size="large"
                  onClick={handleStartDownload}
                  block
                >
                  开始下载
                </Button>
              )}
            </Space>
          )}

          {currentStep === 2 && task && (
            <Space direction="vertical" style={{ width: "100%" }} size="large">
              <DownloadProgress
                task={task}
                logs={logs}
                onDownload={handleDownloadArchive}
              />

              {(task.status === "completed" || task.status === "failed") && (
                <Button onClick={handleReset} block>
                  新建任务
                </Button>
              )}
            </Space>
          )}
        </div>
      </Content>

      <Footer style={{ textAlign: "center" }}>
        离线包下载平台 ©2026
      </Footer>
    </Layout>
  );
};

export default App;
