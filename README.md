# Test Environment Dashboard

测试环境速查与归档处理的桌面工具工程，两个应用的界面均为中文。

> Status: current
> Scope: repository entry point

## 工程组成

| 模块 | 职责 | 开发入口 |
| --- | --- | --- |
| env_viewer | 测试环境目录、资源管理、版本查看、工具启动与只读远程文件查看 | [客户端说明](apps/env_viewer/README.md) |
| backend | 共享目录、资源、加密凭证、版本采集与客户端更新分发 | [后端说明](backend/README.md) |
| zipr_tool | 独立的归档查看、比较和补丁应用，通过 FFI 使用 Rust 引擎 | [归档工具说明](apps/zipr_tool/README.md) |
| shared_ui | 两个应用共享的主题、导航与通用展示组件 | [共享 UI 说明](packages/shared_ui/README.md) |
| env_viewer/updater | 随客户端分发的独立 Dart 更新助手，执行替换与回滚 | [更新流程](docs/guides/client-update.md) |

`zipr/` 是 zipr_tool 使用的 Git 子模块。`go_sidecar/` 仅保留为历史实现和迁移参考，
不参与当前 env_viewer 的运行、构建或发布。

## 本地启动环境速查

需要 Java 21、Maven、Flutter 和目标平台桌面工具链；Flutter 版本以
[CI 配置](.github/workflows/build.yml)为准。分别在两个终端、仓库根目录执行：

```bash
./scripts/dev_backend.sh run
```

```bash
./scripts/dev_env_viewer.sh run
```

客户端脚本会准备字体和依赖；后端单独运行，默认地址为 `http://localhost:8080`。
详细前提、其他平台和故障排查见各模块 README。

## 阅读入口

- [文档索引](docs/README.md)：当前指南、决策、研究与历史计划。
- [领域词汇](CONTEXT.md)与[上下文地图](CONTEXT-MAP.md)：术语、数据归属和模块关系。
- [开发验证](docs/guides/development.md)：按修改范围选择检查。
- [AI 协作约定](AGENTS.md)：修改前需要知道的工程约束。
- [文档维护规范](docs/CONTRIBUTING.md)：文档放在哪里、如何标记状态、何时更新。
