# 01 — Walking skeleton: read Environments (backend)

> Status: archived
> Scope: original redesign implementation slice
> Archived: 2026-09-06

Historical handoff evidence only. Status and test results below describe the original work,
not verification performed during documentation cleanup. Current sources: [documentation index](../../../../README.md).

Historical status: done

## Parent

[docs/plans/archive/env-dashboard-redesign.md](../../env-dashboard-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Stand up the new Spring Boot / Java backend (ADR-0002) as a walking skeleton that proves the
client-server architecture end-to-end on the read path. The backend boots, owns a fresh **normalized
schema** for the `Environment` aggregate root and its `Component`s (ADR-0004 — greenfield, `TENVINFO`
is not involved), and serves them over an HTTP API.

A `Component` carries: role, a single `Version` (or blank) + deploy time, log location, reachability
(listen port / protocol / URL), and collection status + last-collected time as nullable fields (not
yet populated — that is slice 05). `Server`/`Database` references are out of scope here (slice 04).

Endpoints:

- `GET /api/environments` — list Environments with their Components.
- `GET /api/environments/{id}` — one Environment with its Components.

JVM mode is the default; do not let GraalVM native-image concerns block the build (ADR-0002).

**Decisions (settled):**

- **Location:** the backend lives **inside this monorepo** as a new top-level module (alongside
  `apps/`, `go_sidecar/`, `zipr/`), not a separate repo.
- **Persistence:** **H2** for local development, **Oracle** in production, targeting **Oracle 11g**.
  Driver: `com.oracle.database.jdbc:ojdbc8:19.21.0.0` (Maven Central, 19.x connects to 11g). Keep
  schema/migrations dialect-portable across H2 and Oracle 11g.
- **Ops:** the deployed backend is owned/operated by the product maintainer.

## Acceptance criteria

- [x] Spring Boot backend boots locally and serves a `GET /health` (or equivalent) check
- [x] Backend module added inside this monorepo (not a separate repo)
- [x] Local dev runs on H2; production profile targets Oracle 11g via `ojdbc8:19.21.0.0`; migrations run on both
- [x] Normalized schema (migrations) exists for `Environment` and `Component` with the fields above; `TENVINFO` is not referenced
- [x] `GET /api/environments` returns seeded Environments each with their Components
- [x] `GET /api/environments/{id}` returns a single Environment with its Components, and 404s for an unknown id
- [x] Integration tests cover both endpoints against a real (or testcontainer) database
- [x] API field names use glossary vocabulary (Environment, Component, Version, deploy time) — not legacy terms

## Blocked by

None — can start immediately.
