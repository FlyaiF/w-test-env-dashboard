# 04 — Resource Inventory: shared Server / Database aggregates + linking

Status: backend done — client Server/Database management UI outstanding (see AC 5)

## Parent

[docs/PRD-redesign.md](../../../docs/PRD-redesign.md) — Test Environment Dashboard Redesign.

## What to build

Introduce the Resource Inventory context: the shared `Server` and `Database` aggregates that
Components reference **by ID** (ADR-0003), with independent lifecycle so deleting an Environment can
never orphan or destroy a resource another Environment still uses.

- `Server`: host, os (linux | windows), ssh access descriptor.
- `Database`: role, type (oracle | dameng | oceanbase | …), connection descriptor.
- Secrets are **not** modeled here yet — encryption + brokering is slice 06; store only non-secret
  connection metadata for now.

Add CRUD for both aggregates, link Components to them (a Component runs-on one Server and uses 0..N
Databases, all by ID), and expose the reverse lookups: "which Environments run on Server X?" and
"which Environments use Database Y?" — a first-class query per ADR-0003. Client UI manages Servers and
Databases and links them from a Component.

## Acceptance criteria

- [x] Schema + CRUD for `Server` and `Database` as independent aggregates referenced by ID
- [x] A Component can be linked to one Server (runs-on) and 0..N Databases (uses)
- [x] Deleting a Server/Database is independent of Environment lifecycle (and is blocked or surfaced when still referenced — not silently cascaded)
- [x] Reverse-lookup endpoints return Environments by Server id and by Database id
- [ ] Client UI manages Servers/Databases and links them from a Component — ⚠️ OUTSTANDING: backend endpoints exist (`/api/servers`, `/api/databases` full CRUD + `/{id}/environments`), but the thin client has no Server/Database management page (nav is only 总览 + 关于). Components currently show Server/DB only as `#id` references. Needs a client UI slice.
- [x] Integration tests cover linking and both reverse lookups; vocabulary matches the glossary (`InventoryApiIntegrationTest`)

## Blocked by

- 01 — Walking skeleton: read Environments (backend)
