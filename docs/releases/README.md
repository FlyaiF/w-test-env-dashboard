# Release notes（可选）

每个 env_viewer 发布可以在这里放一个 `<version>.md`（例如 `1.2.0.md`），内容为面向
使用者的中文更新说明。CI 会把它以 `env_viewer-<version>.notes.md` 附到 GitHub
Release，`scripts/publish_update.sh` 再同步到后端，最终显示在客户端的更新弹窗里。

没有该文件也可以发布——弹窗只显示版本号（docs/client-update.md）。
