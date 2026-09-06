# Allow client-side SSH/SFTP for read-only remote files

> Status: accepted
> Scope: env_viewer remote file access and credential lifetime
> Decision: 2026-07-31 (existing implemented design)
> Recorded: 2026-09-06
> Partially supersedes: [ADR-0005](0005-thin-client-brokers-creds-no-inapp-access.md)

The desktop needs one-click log following and arbitrary remote file viewing using the catalog's
existing Server links and log locations. The implemented design opens SSH/SFTP sessions directly
in env_viewer using brokered credentials. Backend-relayed SSE/WebSocket streaming was considered
and rejected as heavier for the same desktop experience; the existing broker supplies what the
client needs without adding a backend streaming lifecycle.

This replaces ADR-0005's prohibition on an in-app SSH log viewer. The backend remains canonical for
catalog, inventory, collection and encrypted secrets. Server-held log sessions remain deferred;
the mention of a future seam does not promise a currently implemented endpoint.

## Consequences

- The desktop must be able to reach the selected Server's SSH endpoint, in addition to the backend.
- Remote access is read-only: follow, view, list and download. Remote editing stays in external tools;
  in-app database browsing and bundled database drivers remain out of scope.
- Each open brokers credentials on demand; absent secrets may be supplied for that session only.
  The session may retain credentials in memory to reconnect, never persist them durably. This
  complements [ADR-0008](0008-migrate-and-surface-brokered-credentials.md)'s reveal/copy behavior.
- Tabs survive navigation while the process runs; they do not survive app restart.

The [remote file guide](../guides/remote-file-viewer.md) owns current UI behavior, limits and code
navigation. This ADR records the already-made transport decision, not a new feature approval.
