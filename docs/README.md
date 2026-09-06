# 文档索引

> Status: current
> Scope: repository documentation navigation

从[工程首页](../README.md)开始运行项目；修改前阅读 [AGENTS.md](../AGENTS.md)。
文档归档与更新规则见[维护规范](CONTRIBUTING.md)。

## 当前事实与操作指南

| 主题 | 文档 |
| --- | --- |
| 术语定义 | [CONTEXT.md](../CONTEXT.md) |
| 当前领域与代码归属 | [CONTEXT-MAP.md](../CONTEXT-MAP.md) |
| 开发与验证范围 | [development.md](guides/development.md) |
| 当前 UI 规则与修改入口 | [ui.md](guides/ui.md) |
| 只读远程文件与日志 | [remote-file-viewer.md](guides/remote-file-viewer.md) |
| 客户端更新、首次安装与发布 | [client-update.md](guides/client-update.md) |
| 应用与共享包 | [env_viewer](../apps/env_viewer/README.md)、[backend](../backend/README.md)、[zipr_tool](../apps/zipr_tool/README.md)、[shared_ui](../packages/shared_ui/README.md) |
| 用户可见的版本变化 | [发布说明](releases/README.md) |

## 架构决策

| ADR | 状态 | 主题 |
| --- | --- | --- |
| [0001](adr/0001-client-server-with-central-backend.md) | accepted | 中央后端与共享数据 |
| [0002](adr/0002-spring-boot-java-backend.md) | accepted | Spring Boot / Java 与退役 sidecar |
| [0003](adr/0003-server-and-database-as-shared-aggregates.md) | accepted | Server / Database 独立生命周期与引用 |
| [0004](adr/0004-greenfield-schema-retire-tenvinfo.md) | accepted | 新 schema 与一次性导入 |
| [0005](adr/0005-thin-client-brokers-creds-no-inapp-access.md) | partially-superseded | 凭证代理与访问范围；部分由 0008、0009 替代 |
| [0006](adr/0006-read-models-over-cqrs.md) | accepted | 客户端展示关联与读模型 |
| [0007](adr/0007-migration-leaves-role-unspecified.md) | superseded | 导入角色规则；修订规则见该文档顶部 |
| [0008](adr/0008-migrate-and-surface-brokered-credentials.md) | accepted | 导入凭证、按需显示与复制 |
| [0009](adr/0009-client-side-read-only-remote-files.md) | accepted | 客户端 SSH/SFTP 只读文件访问 |

## 研究、原型与历史计划

以下内容保留当时的上下文，不作为新的实施指令或当前产品承诺。

| 材料 | 状态 | 当前承接文档 |
| --- | --- | --- |
| [日志选择行为研究](research/log-viewer-selection.md) | snapshot | [远程文件指南](guides/remote-file-viewer.md) |
| [后端与客户端重设计 PRD](plans/archive/env-dashboard-redesign.md) | archived | [上下文地图](../CONTEXT-MAP.md) |
| [重设计实施切片](plans/archive/redesign-slices/README.md) | archived | [开发验证指南](guides/development.md) |
| [UI 重设计交接计划](plans/archive/ui-redesign.md) | archived | [UI 指南](guides/ui.md) |
| [视觉方向原型](prototypes/ui-redesign-visual-directions.html) | 历史设计参考，方向 D 获采纳 | [UI 指南](guides/ui.md) |

`plans/` 当前没有进行中的计划。归档不代表生产切换或所有人工验收已经完成。
