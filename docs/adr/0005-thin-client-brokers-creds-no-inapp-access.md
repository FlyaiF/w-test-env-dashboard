# Thin client brokers credentials for user-launched tools; no in-app DB/log access; server log sessions deferred

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
