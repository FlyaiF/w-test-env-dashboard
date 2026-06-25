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
service). Has a role, a single version (or blank), a deploy time, a log location, a reachability
(port/protocol/URL); runs on a Server and uses Databases, both by reference.
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
**deploy time** so devops can judge whether a deploy took effect. There is no recorded "expected"
version — environments are eyeball-compared against each other.

**Up to date**:
A human judgement, not a stored flag — made by comparing live Versions across Environments. The
dashboard's job is to make that comparison legible, not to enforce a target.
_Avoid_: reconciliation, drift (no target version exists to reconcile against)

## Server-side capabilities

**Collection**:
The act of refreshing Components' live data (Version, deploy time) from the running system. Runs on a
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
demand, so the user can launch their own SSH or DB tool. The client never stores secrets durably.
