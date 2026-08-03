# PRD — Test Environment Dashboard Redesign

> Status: implementation / cutover stabilization · Scope: `env_viewer` client + Spring backend · Out of scope: `zipr_tool`
> Companion docs: [CONTEXT.md](../CONTEXT.md) (glossary), [CONTEXT-MAP.md](../CONTEXT-MAP.md)
> (bounded contexts), [docs/adr/](./adr) (decisions 0001–0008).

## 1. Problem & goals

The dashboard aggregates information about company test environments. It grew organically: a single
flat `TENVINFO` row per environment, a 260-line god-object service, composite-string columns
(`E_WEBSERVERADDR` = `"host:port&user/password"`), and domain logic scattered across Dart, Go, and
Oracle. Adding anything means threading changes through every layer, and the model is too weak to hold
what an environment actually is.

This redesign re-carves the product around a rich domain model and a client-server architecture.

**Goals, in priority order** (drives where we spend design effort):

1. **Feature velocity** — adding a capability should touch one well-bounded context, not all of them.
2. **Correctness** — kill the scattered parsing / timezone / merge bugs.
3. **AI/agent navigability** — deep, well-named modules an agent can reason about in isolation.
4. **Comprehension** — the owner can keep the whole thing in their head as it grows.
5. **Testability** — a welcome side effect, *not* a goal we pay extra for (no speculative test seams).

**Success looks like:** dev/QA open the shared dashboard, find an environment, and immediately see —
per component — which machine runs it, where its logs are, what version is live, when that version
metadata was updated, and when it was last collected; and can launch their own SSH/DB tool against
it. Everyone sees the same, freshly-collected data.

## 2. Scope

**In:** the `env_viewer` Flutter client and a new backend service.
**Out:** `zipr_tool` (separate product, untouched). RBAC. In-app DB browsing. In-app SSH log viewer.
A web client (future; we only reserve seams for it).

## 3. Domain model

See [CONTEXT.md](../CONTEXT.md) for definitions. Aggregates:

```
Environment (aggregate root) ── owns ──► Component (1..N)
                                          ├─ role (gateway | ui | app | private-proto | …)
                                          ├─ version (single, or blank) + versionUpdatedAt
                                          ├─ lastCollectedAt + collection status
                                          ├─ logLocation, listenPort, protocol, url
                                          ├─ runs-on  → Server   (by ID)
                                          ├─ uses     → Database (by ID, 0..N)
                                          └─ versionProbe (db | ssh-file | http | command | none)

Server   (shared aggregate, by ID): host, os (linux | windows), ssh access
Database (shared aggregate, by ID): role, type (oracle | dameng | oceanbase | …), connection
```

Key rules (ADR-0003): `Server` and `Database` are **shared** — one machine/DB may back several
environments — so Components reference them by ID; they are never owned by an Environment. This makes
"which environments run on machine X / use database Y?" a first-class lookup.

There is **no** expected/target version (ADR scope: decision (c)). "Up to date" is a human eyeball
comparison of live versions across environments, not a stored flag. No subsystem concept — each
Component has one version or blank.

## 4. Bounded contexts

Full map in [CONTEXT-MAP.md](../CONTEXT-MAP.md). Summary:

| Context | Type | Side | Responsibility |
|---|---|---|---|
| Environment Catalog | **Core** | backend | `Environment`/`Component` CRUD & curation |
| Version Collection | **Core capability** | backend | scheduled/manual collector, version probes, status |
| Resource Inventory | Supporting | backend | shared `Server`/`Database` aggregates |
| Access Brokering | Supporting | backend | encrypted secrets, on-demand credential delivery |
| Local Desktop Integration | Supporting | **client** | launch user's SSH/DB tools |
| Presentation | — | client | thin UI + anti-corruption layer over the API |

**Machine Access** is one shared backend capability — "obtain something from a machine, method depends
on OS." It backs version probes now and (future) server-held log sessions.

## 5. Architecture

A move from a **local desktop tool** to a **client-server system** (ADR-0001).

- **Backend** — fresh **Spring Boot / Java** service (ADR-0002), JDBC for all databases. Owns the
  canonical data in a **new normalized schema** (ADR-0004; `TENVINFO` discarded). Runs the collector.
  Stores secrets encrypted at rest. Publishes an API; reserves a WebSocket/SSE seam for future log
  sessions and a thin auth seam for a future web client. JVM mode default; GraalVM native-image is an
  optional, per-driver-validated optimisation, never a build blocker.
- **Client** — the Flutter `env_viewer` app **slims to a thin client**: presentation + Local Desktop
  Integration only. It sheds sidecar spawning, the local JSON canonical store, sync/merge, and *all*
  DB access. It keeps the tool registry (launch SSH/DB tools).
- **Single backend, no separate agents** — the test network is open, so one backend reaches every
  Database/Server. Split out collector agents only if segmentation later forces it.

## 6. Capabilities

1. **Catalog management** — CRUD on Environments and their Components; manage shared Servers and
   Databases; link Components to Servers (runs-on) and Databases (uses).
2. **Collection** — scheduled poll (configurable interval) **plus** manual "refresh now" per
   environment (decision (c)). Per-component status (ok / failed / unsupported) so one unreachable
   probe degrades gracefully instead of blanking the environment. Records `lastCollectedAt`.
3. **Version probes** — pluggable per component/OS (db query, ssh-file/command, http, none). A clean
   named extension point — new component types add a probe without touching existing ones.
4. **Credential brokering** (ADR-0005) — backend delivers Server/Database credentials to the client on
   demand; client holds no durable secrets.
5. **Tool launching** (client) — launch the user's own SSH **and** DB tools, fed by brokered creds.
6. **One-time data import** — scripted migration of legacy `TENVINFO` into the new schema, run once the
   schema is ready (ADR-0004).

## 7. Non-goals (explicit)

- **No RBAC** — trusted internal tool whose purpose is to *grant* dev/QA access.
- **No in-app DB browser and no in-app SSH log viewer** — launching the user's own tool is first-class.
- **No server-side log streaming in v1** — deferred until a web client exists; only a seam is reserved.
- **No component-to-component topology graph** — capture each component's reachability, not the wiring.
- **No expected/target version tracking.**

## 8. Migration & rollout

Backend cutover is necessarily **big-bang** (Go→Java, new schema). Approach (ADR-0004):

1. Build the new backend + normalized schema.
2. Run the **one-time import** script (`TENVINFO` → new rows; parse composite strings & fixed slots).
   The import doubles as proof the model represents reality.
3. Stand the new backend up **alongside** the old setup; point a refactored client at it; validate.
4. Cut over the active client runtime and delivery path; retain `go_sidecar/` only as a legacy/import
   reference until rollout validation is complete. Retire the per-desktop canonical data store.

## 9. Risks & open questions

- **Native-image / JDBC driver compatibility** — Dameng/OceanBase drivers may need reachability config
  or may not be native-image-clean. Mitigation: JVM default. _Resolved (drivers):_ all three are on
  Maven Central — `com.oracle.database.jdbc:ojdbc8:19.21.0.0`, `com.dameng:DmJdbcDriver18:8.1.3.140`,
  `com.oceanbase:oceanbase-client:2.4.7.1`. Backend's own store: H2 local, Oracle 11g prod.
- **Import edge cases** — dirty composite strings, missing creds, ambiguous DB roles in legacy data.
  The import script must surface (not silently drop) rows it can't parse.
- **Credential delivery surface** — brokering secrets to clients is the main security-sensitive path;
  encryption at rest + on-demand-only delivery, but the threat model deserves a focused review.
- **Backend deployment/ops** — a service to run now exists where none did. _Resolved:_ owned/operated
  by the product maintainer.
- **OceanBase via JDBC** — confirm a clean JDBC path replaces the current Go→Java-helper shellout.
  _Resolved:_ `com.oceanbase:oceanbase-client:2.4.7.1` (Maven Central) provides the JDBC path.

## 10. Current delivery status

The redesign was split into implementation slices 01–08 under
`.scratch/env-dashboard-redesign/issues/`. The walking skeleton, thin-client catalog, catalog writes,
backend Resource Inventory, collection/probes, access brokering/tool launching, one-time import, and
manual “collect now” path are implemented. The `env_viewer` Resource Inventory UI now manages shared
Servers and Databases, links them from Components, and surfaces reverse Environment references.

The remaining work is cutover validation rather than a missing product slice: production-shaped
probe/import rehearsal, backend deployment and rollback instructions, and environment-specific
validation of credential handling and network policy.

The active delivery model is now explicit: desktop clients contain no sidecar or JDBC helper; release
backend jars include the `probe-drivers` profile; tagged releases publish that backend jar beside the
macOS/Windows desktop archives. `go_sidecar/` remains source-only as a pre-redesign reference and is
not an active deployable.
