# 06 — Access Brokering + tool launching

> Status: archived
> Scope: original redesign implementation slice
> Archived: 2026-09-06

Historical handoff evidence only. Status and test results below describe the original work,
not verification performed during documentation cleanup. Current sources: [documentation index](../../../../README.md).

Historical status: done

## Parent

[docs/plans/archive/env-dashboard-redesign.md](../../env-dashboard-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Build the Access Brokering context and wire the client's Local Desktop Integration to it (ADR-0005).
The backend stores `Server`/`Database` secrets **encrypted at rest** and delivers them to a client
**on demand**; the client never stores secrets durably. There is deliberately **no** in-app DB browser
and no in-app SSH log viewer — the first-class path is launching the user's own tool.

- Backend: attach encrypted secrets to the Server/Database resources from slice 04; expose an
  on-demand credential-delivery endpoint that returns a connection descriptor + credentials for a
  given resource.
- Client: the tool registry launches the user's own **SSH and DB** tools (e.g. XShell, DBeaver), fed
  by the brokered credentials; nothing durable is persisted client-side.

Credential delivery is the main security-sensitive path (PRD §9) — encryption at rest plus
on-demand-only delivery.

## Acceptance criteria

- [x] Server/Database secrets are stored encrypted at rest, not in plaintext
- [x] An on-demand endpoint delivers credentials + connection descriptor for a resource; nothing is cached durably on the client
- [x] Client launches the user's own SSH tool and DB tool, fed by brokered credentials
- [x] No in-app DB browser or SSH log viewer is introduced
- [x] Tests cover encryption-at-rest and the on-demand delivery path; client tests cover tool launching

## Blocked by

- 04 — Resource Inventory (secrets attach to Server/Database resources)
