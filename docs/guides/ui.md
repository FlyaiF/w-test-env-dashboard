# env_viewer UI 约定与代码导航

> Status: current
> Scope: env_viewer UI and shared_ui usage
> Reviewed: 2026-09-06 (code structure; no visual acceptance run)

环境速查以快速找到环境、读取版本和采集状态、启动访问工具为核心。
历史设计过程见[归档计划](../plans/archive/ui-redesign.md)；
[方向 D 原型](../prototypes/ui-redesign-visual-directions.html)是设计参考，实际 token 以代码为准。

## 当前约定

- 导航为环境目录、资源清单、日志文件，以及设置、关于；侧栏展开状态和主题偏好单独保存。
- 环境目录采用列表与详情，组件行展开显示字段和访问操作；资源清单使用服务器/数据库表格。
- 环境健康由可采集组件的状态汇总，UNSUPPORTED 不参与；陈旧提示根据最新采集时间计算。
  具体规则集中在 `catalog_acl.dart`，页面不重复计算。
- UI 字体使用 Sarasa Gothic SC，机器数据使用 Sarasa Mono SC；共享主题定义颜色和展示组件。
  状态颜色用于表达含义，亮暗主题均需要检查。
- 日志查看与凭证生命周期见[远程文件指南](remote-file-viewer.md)，发布入口见
  [更新指南](client-update.md)。

## 修改路径

以下代码路径相对于仓库根目录。

| 能力 | 页面与状态入口 | 执行/映射入口 | 测试入口 |
| --- | --- | --- | --- |
| 环境目录 | `apps/env_viewer/lib/pages/catalog/`、`lib/catalog/environment_store.dart` | `lib/catalog/catalog_acl.dart`、`lib/api/backend_client.dart` | `apps/env_viewer/test/catalog/`、`test/pages/catalog_page_test.dart` |
| 资源清单 | `apps/env_viewer/lib/pages/inventory/`、`lib/inventory/inventory_store.dart` | `lib/inventory/inventory_acl.dart`、后端 inventory | `apps/env_viewer/test/inventory/`、`test/pages/inventory/` |
| 工具启动 | `apps/env_viewer/lib/pages/catalog/component_access.dart` | `lib/services/access/`、`lib/services/ssh_tools/`、`lib/services/db_tools/` | `apps/env_viewer/test/access/`、`test/ssh_tools/`、`test/db_tools/` |
| 日志文件 | `apps/env_viewer/lib/pages/remote_files/`、`lib/remote_files/` | `lib/services/remote_file/` | `apps/env_viewer/test/remote_files/`、`test/services/remote_file/` |
| 主题与导航 | `apps/env_viewer/lib/widgets/app_scaffold.dart` | `packages/shared_ui/lib/src/` | `apps/env_viewer/test/main_navigation_test.dart`，以及两个应用的页面用例 |

表中缩写 `lib/`、`test/` 均相对于该行的应用根目录。操作和展示规则应沿现有模块修改，
不要从归档计划重新实现。检查范围见[开发验证](development.md)。
