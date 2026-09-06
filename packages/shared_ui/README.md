# shared_ui

> Status: current
> Scope: shared Flutter presentation package

env_viewer 与 zipr_tool 共享的通用展示模块，公共导出位于
[shared_ui.dart](lib/shared_ui.dart)。这里维护主题、导航框架、About 展示和通用输入组件，
业务目录、凭证和应用工具调用留在各应用中。

## 修改入口

| 内容 | 代码 |
| --- | --- |
| 主题和状态语义 | [theme.dart](lib/src/theme.dart) |
| 通用展示组件 | [primitives.dart](lib/src/primitives.dart) |
| 导航框架 | [app_scaffold.dart](lib/src/app_scaffold.dart) |
| 主题与侧栏偏好 | [theme_mode_controller.dart](lib/src/theme_mode_controller.dart) |
| 历史筛选输入 | [filter_history_text_field.dart](lib/src/filter_history_text_field.dart) |

## 验证

该包当前没有独立测试目录。相关用例位于应用测试中，例如
[筛选输入测试](../../apps/env_viewer/test/widgets/filter_history_text_field_test.dart) 和
[导航测试](../../apps/env_viewer/test/main_navigation_test.dart)。修改公共接口、主题或导航后，
按[开发验证指南](../../docs/guides/development.md)检查两个应用；视觉修改还应检查两种主题
和侧栏展开/折叠状态。源码字体统一放在根 `assets/fonts/`，通过同步脚本准备应用资源。
