# Test Environment Dashboard — Ubiquitous Language

The shared glossary for the test-environment dashboard product (the `env_viewer` client + its
backend). This is a glossary only — no implementation details. The bounded contexts that use these
terms are listed in [CONTEXT-MAP.md](./CONTEXT-MAP.md). `zipr_tool` is a separate product and is not
covered here.

## Core model

**Environment**:
One test deployment of the system — a small distributed application (gateway, UI, main service,
private-protocol service) that dev and QA work against. The aggregate root; it owns its Components.
_Avoid_: env record, TENVINFO row, instance

**Component**:
One deployable part of an Environment (e.g. nginx gateway, UI, main service, private-protocol
service). Has a role, a single version (or blank), a version update time, a log location, a reachability
(port/protocol/URL); runs on a Server and uses Databases, both by reference. The role is one of the
four kinds above or **unspecified** (未指定) — "not yet classified", e.g. a manually added component
whose role has not been assigned.
_Avoid_: service, subsystem, app, web server

**Server**:
A physical or virtual machine (Linux or Windows) that Components run on. A **shared** resource —
one Server can host Components from several Environments — so it is referenced by ID, never owned by
an Environment.
_Avoid_: web server, host string, node, machine

**Database**:
A role-specific access profile for a database instance (Oracle, Dameng, OceanBase, …) that
Components connect to. Its role and login profile are part of its identity, so one physical endpoint
may have separate Database IDs for business/intermediate roles or distinct logins. A **shared**
resource, not necessarily dedicated to one Environment, so it is referenced by ID, never owned.
_Avoid_: YWDB, ZJDB, DSN slot

## Version & freshness

**Version**:
The single version string currently live for a Component (or blank if unknown). Paired with a
**Version update time** so devops can judge whether an update took effect. There is no recorded
"expected" version — environments are eyeball-compared against each other.

**Version update time** (版本更新时间):
When the Component's database last had a schema change applied — the moment its Version last moved.
Written by the upgrade process in the environment's business database, alongside the Version itself.
It says nothing about app restarts or code deployments.
_Avoid_: deploy time (the value tracks database upgrades, not app deployments), update time (ambiguous
with last-collected time)

**Up to date**:
A human judgement, not a stored flag — made by comparing live Versions across Environments. The
dashboard's job is to make that comparison legible, not to enforce a target.
_Avoid_: reconciliation, drift (no target version exists to reconcile against)

## Server-side capabilities

**Collection**:
The act of refreshing Components' live data (Version, Version update time) from the running system. Runs on a
schedule and on manual "refresh now". Each Component's Collection carries a status (ok / failed /
unsupported) and a last-collected time.

**Version probe**:
The pluggable strategy used to obtain a Component's live Version. Which probe applies depends on the
Component/Server (query a Database, read a file or run a command over SSH, hit an HTTP endpoint, or
none). New Component types bring new probes.

**Machine Access**:
The capability to obtain live data from a remote system for Version Collection, using the access
method supported by that system.

**Credential brokering**:
On-demand delivery of resource credentials for an explicitly requested access action: tool launch,
credential reveal/copy, or a read-only remote file session. Brokered credentials are never retained
as durable client data.

**Remote file session**:
A temporary read-only connection to one file on a Server, opened to follow appended content or view
its contents. It may remain open while the user navigates elsewhere, but ends with the application.
