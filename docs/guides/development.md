# 开发与验证

> Status: current
> Scope: repository change and verification entry points
> Reviewed: 2026-09-06 (against CI configuration; commands not executed by this documentation change)

先读各模块 README 获取环境前提；脚本用途见[脚本索引](../../scripts/README.md)。本页记录按修改范围选择检查的规则，
CI 实际执行内容以[工作流](../../.github/workflows/build.yml)为准。

## 验证矩阵

| 修改范围 | 本地检查 | 当前 CI |
| --- | --- | --- |
| backend | Maven verify；发布相关用 probe-drivers profile | probe-drivers clean verify，加驱动打包检查 |
| env_viewer | flutter analyze、flutter test | analyze、test，加 macOS/Windows 构建 |
| updater | 独立 Dart analyze、test | 独立 analyze、test，按平台打包 |
| zipr_tool | flutter analyze、flutter test；FFI 修改需验证真实 Rust 构建 | 独立 analyze/test，加 macOS/Windows 构建；发布等待检查通过 |
| shared_ui | 两个应用的 analyze/test；视觉修改检查两应用的亮暗主题 | 通过应用作业间接覆盖，没有独立测试作业 |
| 纯文档 | diff、仓库链接、状态与当前代码的一致性 | 没有独立文档检查作业 |

涉及真实 SSH、数据库、桌面工具启动或更新替换时，单元测试不等同于目标环境验收；
按改动能力补相应手工验证，并记录实际平台与结果。

## 常用命令

在仓库根目录准备字体；按需启动后端：

```bash
./scripts/sync_assets.sh
./scripts/dev_backend.sh run
```

Flutter 检查前在同一终端清除代理变量，避免 WebSocket upgrade 失败。
以下以 env_viewer 为例，zipr_tool 替换工作目录：

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
cd apps/env_viewer
flutter pub get
flutter analyze
flutter test
```

更新助手单独执行（从仓库根目录开始）：

```bash
cd apps/env_viewer/updater
dart pub get
dart analyze
dart test
```

后端检查在仓库根目录执行：

```bash
mvn -f backend/pom.xml verify
mvn -f backend/pom.xml -Pprobe-drivers verify
```

默认检查使用 H2。Oracle 11g 兼容性需要具备容器测试环境时额外执行：

```bash
mvn -f backend/pom.xml test -Dgroups=oracle-it -DexcludedGroups=
```

## 编辑范围

- `zipr/` 是独立子模块，修改时遵循其中的说明；env_viewer/backend 开发无需初始化它。
- `apps/zipr_tool/lib/src/rust/` 为 FFI 生成代码，修改 Rust interface 后按
  [zipr_tool README](../../apps/zipr_tool/README.md)重新生成并一同提交。
- `go_sidecar/`、`scripts/legacy/build_sidecar.sh` 仅供历史参考。
- `apps/*/assets/` 是同步产物；字体源文件在根 `assets/fonts/`。
- 发布涉及独立后端 jar、桌面包和 updater；具体契约见[更新与发布指南](client-update.md)。
