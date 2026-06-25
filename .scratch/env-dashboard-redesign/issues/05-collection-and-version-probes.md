# 05 — Collection + Version probes

Status: ready-for-agent

## Parent

[docs/PRD-redesign.md](../../../docs/PRD-redesign.md) — Test Environment Dashboard Redesign.

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

- [ ] Scheduled Collection runs on a configurable interval and writes Version / deploy time / status / last-collected onto Components
- [ ] Manual "refresh now" per Environment triggers Collection on demand
- [ ] Per-Component status is one of ok / failed / unsupported; a failing probe does not blank sibling Components
- [ ] At least two probe strategies exist behind one named extension point (e.g. db-query + http), pluggable without editing existing probes
- [ ] Probes reach machines via the shared Machine Access capability using slice-04 descriptors
- [ ] Client shows "refresh now" and per-Component Version / deploy time / status / last-collected
- [ ] Tests cover the probe extension point and graceful per-Component degradation

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
- 04 — Resource Inventory (probes need Server/Database connection descriptors)
