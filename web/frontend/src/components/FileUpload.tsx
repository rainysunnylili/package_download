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
      message.error("Please select files to upload");
      return;
    }

    setUploading(true);

    try {
      const formData = new FormData();
      fileList.forEach((file) => {
        if (file.originFileObj) {
          formData.append("files", file.originFileObj);
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
      message.success("Files uploaded successfully!");
      onUploadComplete(result.task_id);
      setFileList([]);
    } catch (error) {
      message.error("Upload failed. Please try again.");
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
        message.error(`${file.name} is not a valid dependency file`);
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
    <Card title="Upload Dependency Files">
      <Space direction="vertical" style={{ width: "100%" }} size="large">
        <Dragger {...uploadProps}>
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">Click or drag files to upload</p>
          <p className="ant-upload-hint">
            Supported files: package.json, requirements.txt, Pipfile, pyproject.toml
          </p>
        </Dragger>

        {fileList.length > 0 && (
          <div>
            <h4>Uploaded Files:</h4>
            <Space wrap>
              {fileList.map((file) => (
                <Tag
                  key={file.uid}
                  closable
                  onClose={() => {
                    setFileList((prev) => prev.filter((f) => f.uid !== file.uid));
                  }}
                >
                  {file.name}
                </Tag>
              ))}
            </Space>
          </div>
        )}

        <Card title="Download Options" size="small">
          <Space direction="vertical" style={{ width: "100%" }}>
            <Checkbox
              checked={options.npm}
              onChange={(e) => setOptions({ ...options, npm: e.target.checked })}
            >
              Download NPM packages
            </Checkbox>

            {options.npm && (
              <div style={{ marginLeft: 24 }}>
                <span>Node.js version: </span>
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
              Download Python packages
            </Checkbox>

            {options.pypi && (
              <div style={{ marginLeft: 24 }}>
                <div>
                  <span>Python version: </span>
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
                  <span>Target platforms: </span>
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
          {uploading ? "Uploading..." : "Start Analysis"}
        </Button>
      </Space>
    </Card>
  );
};
