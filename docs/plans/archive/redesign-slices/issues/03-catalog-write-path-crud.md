# 03 — Catalog write path: Environment / Component CRUD

> Status: archived
> Scope: original redesign implementation slice
> Archived: 2026-09-06

Historical handoff evidence only. Status and test results below describe the original work,
not verification performed during documentation cleanup. Current sources: [documentation index](../../../../README.md).

Historical status: done

## Parent

[docs/plans/archive/env-dashboard-redesign.md](../../env-dashboard-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Add the curation write path to the Environment Catalog context: create, update, and delete
Environments and their Components end-to-end. Backend gains `POST /api/environments`,
`PUT /api/environments/{id}`, `DELETE /api/environments/{id}`, and the equivalent nested Component
operations; the client gains edit UI to drive them through the anti-corruption layer.

Deleting an Environment removes its owned Components but must **not** touch any shared resources — those
are referenced by ID and owned elsewhere (ADR-0003; their linkage lands in slice 04).

## Acceptance criteria

- [x] Backend supports create / update / delete for Environments and their Components with validation
- [x] Deleting an Environment cascades to its Components only; no shared-resource rows are affected
- [x] Client edit UI can create, edit, and delete Environments and Components against the live backend
- [x] Integration tests cover create / update / delete, including the cascade boundary
- [x] Client tests cover the edit flows; `flutter analyze` clean

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
- 02 — Thin client reads Environments (for the client edit UI)
