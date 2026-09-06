# 08 — Real db-query probe (legacy version source) + client "refresh now"

> Status: archived
> Scope: original redesign implementation slice
> Archived: 2026-09-06

Historical handoff evidence only. Status and test results below describe the original work,
not verification performed during documentation cleanup. Current sources: [documentation index](../../../../README.md).

Historical status: implemented 2026-07-07 — backend verified (107 tests); client tests written, CI is the gate (no local Flutter SDK)

## Parent

[docs/plans/archive/env-dashboard-redesign.md](../../env-dashboard-redesign.md) — completes slice 05's outstanding client AC and
replaces its placeholder db-query probe with the real legacy mechanism.

## Why

The slice-05 `DbVersionProbe` runs an invented query (`SELECT version FROM app_version`) against
whichever linked Database happens to be first, and never yields a timestamp. Against real
environments it produces nothing. The proven mechanism lives on `main`
(`go_sidecar/db/runtime.go`): connect to the environment's business DB (业务库, legacy `E_YWDB`) and read

1. `select param_value from tsys_parameter where param_code = 'SystemVersion'` → **Version**
2. `select * from (select begin_time, subsystem_ver from jres_subsystem_rc order by begin_time desc)
   where rownum = 1` → `begin_time` → **版本更新时间**

## Decisions (grilling session, 2026-07-07)

- **Term**: the collected timestamp is **Version update time (版本更新时间)** — written only when a
  schema change runs against the business DB; it says nothing about app deploys or restarts.
  Rename `deployTime` → `versionUpdatedAt` across `Component` / `ProbeResult` / DTOs / client, and
  the card label 部署时间 → 版本更新时间. Glossary updated in CONTEXT.md. The importer's
  `E_UPDATETIME` → this field mapping is already semantically correct.
- **Target selection**: the probe picks the linked Database with role `业务库`; falls back to the
  first linked Database; fails with a self-explaining detail if none is linked. (Importer stamps
  migrated business DBs with exactly `业务库`, linked first.)
- **`subsystem_ver`**: ignored entirely — no fallback, no storage.
- **Failure strictness**: connection/SQL error → `FAILED` (detail names the failing step); no/blank
  `SystemVersion` row → `FAILED`; empty `jres_subsystem_rc` → `OK` with version and null
  版本更新时间 (append-only table; empty means "no schema change yet").
- **No review/publish step**: legacy's diff-then-publish flow is deliberately dropped; collection
  auto-writes (machine-owned read-model fields, failure keeps known-good values).
- **Client "refresh now"**: per-environment icon button in the environment card header (before
  编辑), tooltip **立即采集** — deliberately not another 刷新, which re-fetches without probing.
  Spinner + disabled while in flight; swaps the returned `EnvironmentDto` into the store in place;
  snackbar on error. Toolbar 刷新 unchanged.

## Acceptance criteria

- [x] `DbVersionProbe` runs the two legacy queries against the role-selected business DB and returns
      version + `versionUpdatedAt` per the strictness rules above (role constant shared via
      `Database.BUSINESS_ROLE`; note the importer's role string is `business`, shown as 业务库)
- [x] `MachineAccess` grows `queryInstant` alongside `queryScalar`; both now return null on no rows
      (was: throw), so probes can tell "data absent" from "unreachable"; still `java.sql` only
- [x] `deployTime` renamed to `versionUpdatedAt` end-to-end (entity via V4 Flyway rename, `ProbeResult`,
      DTOs, Dart DTO/input/view), card + editor label 版本更新时间
- [x] `BackendClient.refreshEnvironment(id)` + `EnvironmentStore.collectNow` wired to
      `POST /api/environments/{id}/refresh`, swapping the fresh view in place (no full re-fetch)
- [x] 立即采集 button on the environment detail header with spinner/disabled in-flight state; success
      and error surfaced via snackbar (transient — deliberately not parked in `store.error`)
- [x] Backend tests: role selection (业务库 / case-insensitive / fallback / none), each strictness
      branch, timestamp write-through (`DbVersionProbeTest`, `CollectionServiceTest`) — 107 green
- [x] Client tests: in-place swap + no re-fetch, in-flight state, error path
      (`environment_store_collect_test.dart`), button tap → POST + snackbar (`catalog_page_test.dart`)
- [ ] `flutter analyze` / `flutter test` via CI — ⚠️ NOT RUN here (no Flutter SDK); tests written by
      inspection, CI is the gate

## Notes

- Oracle `DATE` has no zone: read `begin_time` via JDBC in the backend JVM's zone → `Instant`;
  client must `.toLocal()` before formatting (AGENTS.md gotcha).
- Dameng / OceanBase drivers sit in the off-by-default `probe-drivers` Maven profile; a default build
  probes Oracle business DBs only. Legacy also supported Dameng + OceanBase-Oracle with the same two
  queries — enable the profile for release builds when those environments matter.
