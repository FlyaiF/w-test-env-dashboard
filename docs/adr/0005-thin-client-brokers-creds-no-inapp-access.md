# Thin client brokers credentials for user-launched tools; no in-app DB/log access; server log sessions deferred

> Status: partially-superseded
> Scope: desktop access and credential lifetime
> Superseded in part by: [ADR-0008](0008-migrate-and-surface-brokered-credentials.md), [ADR-0009](0009-client-side-read-only-remote-files.md)

Current rules: on-demand reveal/copy and client-side read-only SSH/SFTP file viewing are allowed.
Credentials must never be stored durably by the client; in-app database browsing remains out of
scope. Server-held log sessions remain deferred; a future seam is design intent, not an existing
streaming endpoint. The original rationale below is preserved as history.

## Original decision

The client deliberately does **not** build in-app database access or its own SSH log viewer. All DB
connectivity stays server-side (no DB drivers shipped to the desktop), and for shell/log/DB access the
first-class path is launching the **user's own tool** (XShell, DBeaver, etc.) — a built-in viewer
"can't be more convenient than the user's choice." The backend therefore brokers Server/Database
credentials (stored encrypted at rest) to the client on demand; the client holds no durable secrets.
This is a deliberate deviation a reader might otherwise try to "fix" by adding in-app browsing.

Server-held log sessions are explicitly **deferred** until a future web client exists (a browser
cannot launch local tools, so only then must the server hold the session). A WebSocket/SSE seam is
reserved in the API so this is additive, not a re-architecture. Likewise, there is no RBAC: this is a
trusted internal test-environment tool whose purpose is to *grant* dev/QA access, with a thin auth
seam left for the future web client.
