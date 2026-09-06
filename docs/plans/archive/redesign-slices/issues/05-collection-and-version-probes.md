# 05 — Collection + Version probes

> Status: archived
> Scope: original redesign implementation slice
> Archived: 2026-09-06

Historical handoff evidence only. Status and test results below describe the original work,
not verification performed during documentation cleanup. Current sources: [documentation index](../../../../README.md).

Historical status: backend done — client "refresh now" action outstanding (see AC 6; picked up by issue 08,
along with replacing the placeholder db-query probe with the real legacy version source)

## Parent

[docs/plans/archive/env-dashboard-redesign.md](../../env-dashboard-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Build the Version Collection core capability. A Collector refreshes each Component's live `Version` and
deploy time from the running system, on a **configurable schedule** and on a **manual "refresh now"**
per Environment. Each Component's Collection records a status (ok / failed / unsupported) and a
last-collected time, so one unreachable probe degrades that Component gracefully instead of blanking
the whole Environment.

Version probes are a **pluggable, named extension point**: which probe applies depends on the
Component/Server — query a Database, read a file or run a command over SSH, hit an HTTP endpoint, or
none. Adding a new Component type adds a probe without touching existing ones. Probes obtain live data
through the single shared **Machine Access** capability ("obtain something from a machine, method
depends on OS"), which connects using the Server/Database descriptors from slice 04.

Client surfaces a "refresh now" action per Environment and shows each Component's Version, deploy time,
collection status, and last-collected time (apply `.toLocal()` before formatting per AGENTS.md).

**Probe driver coordinates (settled, all on Maven Central):** db-query probes connect to target
Databases using `com.oracle.database.jdbc:ojdbc8:19.21.0.0` (Oracle),
`com.dameng:DmJdbcDriver18:8.1.3.140` (Dameng), and `com.oceanbase:oceanbase-client:2.4.7.1`
(OceanBase). This retires the legacy Go→Java-helper shellout for OceanBase (ADR-0002). JVM mode first;
do not gate on native-image driver compatibility.

## Acceptance criteria

- [x] Scheduled Collection runs on a configurable interval and writes Version / deploy time / status / last-collected onto Components
- [x] Manual "refresh now" per Environment triggers Collection on demand (`POST /api/environments/{id}/refresh`)
- [x] Per-Component status is one of ok / failed / unsupported; a failing probe does not blank sibling Components
- [x] At least two probe strategies exist behind one named extension point (e.g. db-query + http), pluggable without editing existing probes
- [x] Probes reach machines via the shared Machine Access capability using slice-04 descriptors
- [x] Client shows "refresh now" and per-Component Version / 版本更新时间 / status / last-collected — closed by issue 08 (立即采集 button on the environment detail header → `POST /{id}/refresh`, in-place swap; "deploy time" renamed 版本更新时间).
- [x] Tests cover the probe extension point and graceful per-Component degradation (`VersionProbeRegistryTest`, `CollectionServiceTest`)

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
- 04 — Resource Inventory (probes need Server/Database connection descriptors)

## Implementation notes — scope landed & deferrals

Backend implemented in a new `collection` bounded context: a pluggable `VersionProbe` extension point
(HTTP + db-query strategies) discovered via `VersionProbeRegistry`, a shared `MachineAccess` capability
as the single network seam, a `CollectionService` (scheduled `refreshAll` + manual `refresh`), a
property-gated `CollectionScheduler`, and `POST /api/environments/{id}/refresh`.

Three things are intentionally deferred (each recorded so it is not silently dropped):

- **Client "refresh now" UI** (AC bullet 6) — the client is the pre-redesign Flutter app; its thin-client
  rewrite is slice 02. The backend fully exposes the needed data (`ComponentDto` version / deployTime /
  collectionStatus / lastCollectedAt + the refresh endpoint), so slice 02 only wires the UI.
- **Dameng / OceanBase JDBC drivers** — settled coordinates ship as the off-by-default `probe-drivers`
  Maven profile (this build environment cannot reach Maven Central). `MachineAccess` uses `java.sql`
  only, so the extension point compiles and is fully tested without them.
- **Deploy-time *output*** — `ProbeResult` carries a `deployTime` slot and `CollectionService` writes it
  when present, but neither shipped probe (an HTTP `/version` body, a single-scalar DB query) has a
  deploy-time source to fill it. The write path is wired; a richer probe whose source carries a deploy
  timestamp populates it without touching existing code.
