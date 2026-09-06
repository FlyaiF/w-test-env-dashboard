# 脚本索引

> Status: current
> Scope: repository scripts

下列命令均从仓库根目录执行。脚本用自身位置定位工程，可从其他目录调用。
开发前提和验证命令见[开发指南](../docs/guides/development.md)。

## 当前开发、构建和发布

| 入口 | 用途 |
| --- | --- |
| [dev_backend.sh](dev_backend.sh) | `run` 启动本地后端，`test` 执行 Maven 测试 |
| [dev_env_viewer.sh](dev_env_viewer.sh) | 准备客户端依赖；`run` 启动，不代替后端进程 |
| [dev_zipr_tool.sh](dev_zipr_tool.sh) | 准备依赖和 Rust 子模块；`run` 启动归档应用 |
| [run_zipr_macos.sh](run_zipr_macos.sh) | `dev_zipr_tool.sh run -d macos` 的便捷入口 |
| [sync_assets.sh](sync_assets.sh) | 将根字体源同步到两个应用的构建资源目录 |
| [build_release.sh](build_release.sh) | 按 `macos/windows/linux` 构建后端与两个桌面应用 |
| [publish_update.sh](publish_update.sh) | 将已完成的 tagged release 同步到后端更新目录；见[发布流程](../docs/guides/client-update.md) |
| [import_tenvinfo.sh](import_tenvinfo.sh) | 旧数据导入新后端的迁移工具，默认 dry-run，`--apply` 写入 |

`import_tenvinfo.sh` 虽然处理旧数据，仍属于当前后端迁移入口。

## 独立开发工具

[tools/build_zipr_cli.sh](tools/build_zipr_cli.sh) 构建 zipr 子模块的独立 CLI。
原路径为 `scripts/build_zipr.sh`，已迁入工具目录。先初始化子模块并准备 Rust 工具链：

```bash
git submodule update --init zipr
./scripts/tools/build_zipr_cli.sh
```

输出到 `build/zipr/`。`all` 参数构建两个 macOS 架构，需要对应 Rust target 和链接工具链。
桌面应用通过 FFI 使用 Rust 引擎，不使用此 CLI 产物。

## 遗留工具

[legacy/build_sidecar.sh](legacy/build_sidecar.sh) 保留旧 Go sidecar 和 JDBC helper 的构建方法，
原路径为 `scripts/build_sidecar.sh`。仅供历史实现验证，需要 Go，以及构建 helper 所需的
JDK；`all` 构建脚本列出的旧平台产物。
它不参与当前开发、CI 或发布。当前后端使用 [dev_backend.sh](dev_backend.sh)。

新增脚本按用途归类；移动脚本时同步相对工程路径、文档和调用点，保留可执行权限。
