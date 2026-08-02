# env_viewer 自动更新（client self-update）

env_viewer 从后端检查并下载新版本，由随包分发的更新助手完成替换与回滚。仅覆盖
env_viewer（不含 zipr_tool 与后端）；支持 Windows 与 macOS；更新永远由用户主动触发，
没有强制升级机制。

## 总体流程

```
发布者                     后端                          客户端
────────                  ─────────────                ───────────────────────
git tag v1.2.0     CI →   （无动作）                    启动时 GET /latest?platform=…
publish_update.sh  scp →  client-updates/ 目录           有新版本 → 侧栏出现下载图标
                          扫描目录、算 SHA-256           用户点击 → 下载、校验 SHA-256
                                                        启动更新助手、应用退出
                                                        助手替换安装目录并重启新版本
                                                        新版本首帧后写入 marker → 提交
                                                        （否则恢复 .backup 并回滚）
```

## 后端（`backend/.../clientupdate/`）

- 配置 `envdashboard.client-updates.dir`（环境变量 `CLIENT_UPDATES_DIR`）。留空 =
  功能关闭，`/latest` 返回 204，客户端保持安静。
- 目录即发布契约：`env_viewer-<version>-<platform>.zip`（platform ∈ windows/macos），
  可选 `env_viewer-<version>.notes.md`（更新弹窗中显示的中文说明）。
- `GET /api/client-updates/env_viewer/latest?platform=…` → 每个平台的最高版本 +
  SHA-256 + notes；`GET …/download?platform=…&version=…` → 下载客户端在 latest 中
  看到的那个版本（避免元数据与下载之间换包导致校验失败语义混乱）。
- SHA-256 按 (路径, mtime, size) 缓存，目录每次请求重扫（文件很少）。

## 客户端（`apps/env_viewer/lib/services/update/`）

- `AppUpdateStore` 启动时静默检查一次；仅 release 构建执行（调试构建跳过，
  `ENV_VIEWER_FORCE_UPDATE_CHECK=1` 可强制，便于端到端联调）。
- 有新版本时唯一的 UI 是侧栏头部的强调色下载图标（`UpdateButton`）——不弹窗、
  不强制。点击后弹出版本 + 说明，用户确认才下载。
- 下载到临时目录后校验 SHA-256；不符则报错可重试，绝不把可疑包交给助手。
- 助手先被复制到临时目录再启动（安装目录马上要被改名，不能从里面运行），随后
  应用 `exit(0)`。

## 更新助手（`apps/env_viewer/updater/`，纯 Dart，`dart compile exe`）

打包位置:macOS `env_viewer.app/Contents/Resources/env_viewer_updater`；Windows 安装
目录下 `env_viewer_updater.exe`。CI 与 `build_release.sh` 都会编译并放入。

流程：等待应用退出 → 安装目录改名为 `.backup` → 解压新包（macOS 用 `ditto`、
Windows 用 `Expand-Archive`，保留 .app 内符号链接与执行位）→ 启动新版本并传入
`ENV_VIEWER_UPDATE_MARKER` → 新版本渲染首帧后写 marker → 助手删除 `.backup` 与
zip。15 秒内没有 marker 视为坏版本：杀掉新进程、恢复 `.backup`、重启旧版本。
日志在 `~/.test-env-dashboard/updater.log`。

已知限制：macOS 助手按 CI runner 架构编译（arm64）；Intel Mac 上助手无法启动时
更新会报错但应用照常运行，需手动更新。

## 发布流程（版本真源 = pubspec）

1. 改 `apps/env_viewer/pubspec.yaml` 的 `version:`，需要说明时写
   `docs/releases/<version>.md`（中文，可选），提交。
2. 打 tag `v<version>` 并推送。CI 校验 tag 与 pubspec 一致（不一致直接失败），
   产物命名 `env_viewer-<version>-<platform>.zip`，notes 以
   `env_viewer-<version>.notes.md` 附在 GitHub Release。
3. CI 完成后执行：

   ```bash
   UPDATE_SSH_TARGET=user@backend-host \
   UPDATE_REMOTE_DIR=/opt/env-dashboard/client-updates \
   BACKEND_URL=http://backend-host:8080 \
   scripts/publish_update.sh v1.2.0
   ```

   脚本从 GitHub Release 下载、检查两个平台的 zip 齐全、scp 到后端目录，最后回读
   `/latest` 打印客户端将看到的内容。

回滚一个已发布版本：把它的 zip 从目录里删掉即可，客户端会看到上一个最高版本。
