/**
 * Dependency tree visualization component
 */
import React from "react";
import { Card, Tree, Empty, Spin, Space, Typography, Tag } from "antd";
import { DependencyNode, PackageInfo } from "../types";
import type { DataNode } from "antd/es/tree";

const { Text } = Typography;

interface DependencyTreeProps {
  npmTree?: DependencyNode;
  pypiPackages?: PackageInfo[];
  loading?: boolean;
}

const buildTreeData = (node: DependencyNode): DataNode => {
  return {
    title: `${node.name}@${node.version}`,
    key: `${node.name}-${node.version}`,
    children: node.children.map(buildTreeData),
  };
};

export const DependencyTree: React.FC<DependencyTreeProps> = ({
  npmTree,
  pypiPackages = [],
  loading = false,
}) => {
  if (loading) {
    return (
      <Card title="Dependency Analysis">
        <div style={{ textAlign: "center", padding: "40px 0" }}>
          <Spin size="large" />
          <div style={{ marginTop: 16 }}>
            <Text type="secondary">Analyzing dependencies...</Text>
          </div>
        </div>
      </Card>
    );
  }

  if (!npmTree && pypiPackages.length === 0) {
    return (
      <Card title="Dependency Analysis">
        <Empty description="No dependencies found" />
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
    <Card title="Dependency Analysis">
      <Space direction="vertical" style={{ width: "100%" }} size="large">
        {npmTree && (
          <Card
            type="inner"
            title={
              <Space>
                <span>NPM Dependencies</span>
                <Tag color="blue">{npmCount} packages</Tag>
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
                <span>Python Dependencies</span>
                <Tag color="green">{pypiCount} packages</Tag>
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
            <Text strong>Total:</Text>
            {npmCount > 0 && <Text>NPM: {npmCount} packages</Text>}
            {pypiCount > 0 && <Text>Python: {pypiCount} packages</Text>}
          </Space>
        </Card>
      </Space>
    </Card>
  );
};
