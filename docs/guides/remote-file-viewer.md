# Remote log/file viewer (日志文件)

> Status: current
> Scope: env_viewer remote file access
> Reviewed: 2026-09-06 (code and documentation; no runtime acceptance test)

Implemented from the 2026-07-31 design. The transport decision is recorded in
[ADR-0009](../adr/0009-client-side-read-only-remote-files.md); this guide describes current behavior.
See the [documentation index](../README.md) for other capabilities.

## Behavior and constraints

1. **Transport is client-side SSH** (`dartssh2` in `env_viewer`). No backend changes: the backend
   already owns `Component.logLocation`, Server links, and credential brokering. Backend-relayed
   streaming (SSE/WebSocket) was considered and rejected as heavier for the same UX.
2. **Read-only.** Two modes: 跟随 (`tail -n 200 -f`) and 查看 (static SFTP read, refreshable,
   capped at 2 MB with a truncation notice). Editing stays in the user's own SSH tools.
3. **Placement** (validated by prototype, branch `prototype/log-viewer-placement`): a dedicated
   「日志文件」 sidebar page with tabs, plus a one-click 查看日志 action on each catalog component
   row that jumps there and opens the component's 日志位置 in follow mode. An embedded
   catalog-bottom pane was prototyped and rejected.
4. **Credentials**: silent broker via the component's linked Server; a session-only credential
   dialog appears only when the broker holds no secret; the row action is disabled when no Server is
   linked. Nothing typed or brokered is ever persisted ([ADR-0009](../adr/0009-client-side-read-only-remote-files.md); ADR-0005’s no-durable-secrets constraint remains in force).
5. **Encoding**: UTF-8 default (matches the fleet), per-tab GBK switch; raw bytes stay buffered so
   switching re-decodes in place (`fast_gbk`).
6. **History**: ~10,000-line in-memory ring buffer per tab, no disk spill; a 下载 action SFTPs the
   complete file to a user-chosen location instead.
   Lines render as 64-line paragraphs (not one Text per line) so a drag-selection copies with its
   line breaks — `SelectionArea` joins per-widget selections without `\n`; a 复制全部 action copies
   the visible buffer with the platform's EOL (`\r\n` on Windows).
   Paragraphs are anchored to absolute line numbers and the ring evicts in whole 64-line chunks, so
   a filled paragraph's text never changes and selections survive the streaming rebuilds; during a
   selection drag the rendered tail freezes and eviction is held ([selection research](../research/log-viewer-selection.md) records the original analysis). Known limits, accepted for now: a selection scrolled far out of the
   viewport's cache is dropped (item disposal), and native select-all only covers laid-out items —
   复制全部 is the bulk-copy path.
7. **清空 (follow mode)**: a toolbar action hides everything currently shown — a view marker, not a
   buffer wipe; the remote file and 下载 are untouched. Typical flow: 清空 → trigger the operation →
   the view (and 复制全部) now holds exactly the fresh output.
8. **Free path opens**: server dropdown (from the Resource Inventory) + path field + mode toggle on
   the page; presets stay one `logLocation` per component — no extra schema fields. The path field
   tracks the active tab's path (without clobbering hand edits) and autocompletes from two sources:
   keyword matches over known paths (open tabs + component 日志位置), and live SFTP directory
   listings borrowed from a connected session on the selected server (per-directory cached;
   best-effort — no session, no remote suggestions, never a new connection just to complete).
9. Tabs keep streaming while the user navigates elsewhere but do not survive app restart; dropped
   connections offer manual 重连.

## Key code

- `apps/env_viewer/lib/services/remote_file/` — `RemoteFileSession` (SSH tail / SFTP read +
  download) and the encoding-aware `LineBuffer`.
- `apps/env_viewer/lib/remote_files/remote_file_store.dart` — tab state + brokered open flow
  (`RemoteOpenNeedsSecret` drives the fallback dialog).
- `apps/env_viewer/lib/pages/remote_files/` — the 日志文件 page, viewer widget, and the shared
  `openRemoteFile` flow used by the catalog row action.

## Verification entry points

Automated behavior checks live in [page/viewer tests](../../apps/env_viewer/test/pages/remote_files/),
[state/path logic tests](../../apps/env_viewer/test/remote_files/)
and [session/buffer tests](../../apps/env_viewer/test/services/remote_file/). Run the client checks
listed in the [development guide](development.md). For transport changes, also exercise a reachable
SSH Server: brokered open, missing-secret fallback, follow/view, reconnect, clear/copy and download.
These are verification instructions, not a record that live SSH acceptance was run during this cleanup.
