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
four kinds above or **unspecified** (未指定) — "not yet classified", e.g. for a component imported from
legacy data that carried no role; a human assigns the real role later.
_Avoid_: service, subsystem, app, web server

**Server**:
A physical or virtual machine (Linux or Windows) that Components run on. A **shared** resource —
one Server can host Components from several Environments — so it is referenced by ID, never owned by
an Environment.
_Avoid_: web server, host string, node, machine

**Database**:
A database instance (Oracle, Dameng, OceanBase, …) that Components connect to. A **shared** resource,
not necessarily dedicated to one Environment, so it is referenced by ID, never owned.
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
The single server-side capability for "obtain something from a machine, by a method that depends on
the machine's OS." Today it backs Version probes; later it will back server-held log sessions. One
concept, two uses.

**Credential brokering**:
The server holding Server/Database secrets encrypted at rest and delivering them to a client on
demand — to launch the user's own SSH or DB tool, or to reveal/copy a credential the user explicitly
asks for. The client fetches each secret just-in-time and never stores it durably. The TENVINFO
migration populates the broker from the legacy plaintext, so brokered credentials exist from day one
(see ADR-0008).
