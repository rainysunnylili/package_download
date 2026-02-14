/**
 * File upload component
 */
import React, { useState, useCallback } from "react";
import { Upload, Button, Card, Checkbox, Select, Tag, Space, message } from "antd";
import { InboxOutlined, DeleteOutlined } from "@ant-design/icons";
import type { UploadFile } from "antd";
import { DownloadOptions } from "../types";

const { Dragger } = Upload;
const { Option } = Select;

interface FileUploadProps {
  onUploadComplete: (taskId: string) => void;
}

export const FileUpload: React.FC<FileUploadProps> = ({ onUploadComplete }) => {
  const [fileList, setFileList] = useState<UploadFile[]>([]);
  const [uploading, setUploading] = useState(false);
  const [options, setOptions] = useState<DownloadOptions>({
    npm: true,
    pypi: true,
    node_version: "20",
    python_version: "3.13",
    platforms: ["win_amd64", "manylinux2014_x86_64"],
  });

  const handleUpload = useCallback(async () => {
    if (fileList.length === 0) {
      message.error("请选择要上传的文件");
      return;
    }

    setUploading(true);

    try {
      const formData = new FormData();
      fileList.forEach((file) => {
        const rawFile = file.originFileObj || file;
        if (rawFile instanceof File) {
          formData.append("files", rawFile);
        }
      });
      formData.append("options", JSON.stringify(options));

      const response = await fetch("http://localhost:8000/api/tasks", {
        method: "POST",
        body: formData,
      });

      if (!response.ok) {
        throw new Error("Upload failed");
      }

      const result = await response.json();
      message.success("文件上传成功！");
      onUploadComplete(result.task_id);
      setFileList([]);
    } catch (error) {
      message.error("上传失败，请重试。");
      console.error(error);
    } finally {
      setUploading(false);
    }
  }, [fileList, options, onUploadComplete]);

  const uploadProps = {
    multiple: true,
    fileList,
    beforeUpload: (file: File) => {
      const allowedExtensions = [".json", ".txt", ".toml", ".lock"];
      const isAllowed = allowedExtensions.some((ext) => file.name.endsWith(ext));

      if (!isAllowed) {
        message.error(`${file.name} 不是有效的依赖文件`);
        return Upload.LIST_IGNORE;
      }

      setFileList((prev) => [...prev, file as any]);
      return false;
    },
    onRemove: (file: UploadFile) => {
      setFileList((prev) => prev.filter((f) => f.uid !== file.uid));
    },
  };

  return (
    <Card title="上传依赖文件">
      <Space direction="vertical" style={{ width: "100%" }} size="large">
        <Dragger {...uploadProps}>
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">点击或拖拽文件到此区域上传</p>
          <p className="ant-upload-hint">
            支持的文件：package.json、requirements.txt、Pipfile、pyproject.toml
          </p>
        </Dragger>

        <Card title="下载选项" size="small">
          <Space direction="vertical" style={{ width: "100%" }}>
            <Checkbox
              checked={options.npm}
              onChange={(e) => setOptions({ ...options, npm: e.target.checked })}
            >
              下载 NPM 包
            </Checkbox>

            {options.npm && (
              <div style={{ marginLeft: 24 }}>
                <span>Node.js 版本：</span>
                <Select
                  value={options.node_version}
                  onChange={(value) =>
                    setOptions({ ...options, node_version: value })
                  }
                  style={{ width: 120 }}
                >
                  <Option value="18">18</Option>
                  <Option value="20">20</Option>
                  <Option value="22">22</Option>
                </Select>
              </div>
            )}

            <Checkbox
              checked={options.pypi}
              onChange={(e) => setOptions({ ...options, pypi: e.target.checked })}
            >
              下载 Python 包
            </Checkbox>

            {options.pypi && (
              <div style={{ marginLeft: 24 }}>
                <div>
                  <span>Python 版本：</span>
                  <Select
                    value={options.python_version}
                    onChange={(value) =>
                      setOptions({ ...options, python_version: value })
                    }
                    style={{ width: 120 }}
                  >
                    <Option value="3.11">3.11</Option>
                    <Option value="3.12">3.12</Option>
                    <Option value="3.13">3.13</Option>
                  </Select>
                </div>
                <div style={{ marginTop: 8 }}>
                  <span>目标平台：</span>
                  <Select
                    mode="multiple"
                    value={options.platforms}
                    onChange={(value) =>
                      setOptions({ ...options, platforms: value })
                    }
                    style={{ width: "100%", maxWidth: 400 }}
                  >
                    <Option value="win_amd64">Windows (amd64)</Option>
                    <Option value="manylinux2014_x86_64">Linux (x86_64)</Option>
                    <Option value="macosx_10_9_x86_64">macOS (x86_64)</Option>
                    <Option value="macosx_11_0_arm64">macOS (arm64)</Option>
                  </Select>
                </div>
              </div>
            )}
          </Space>
        </Card>

        <Button
          type="primary"
          onClick={handleUpload}
          loading={uploading}
          disabled={fileList.length === 0}
          size="large"
          block
        >
          {uploading ? "上传中..." : "开始分析"}
        </Button>
      </Space>
    </Card>
  );
};
