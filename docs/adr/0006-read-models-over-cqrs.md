# API DTOs are read models; cross-aggregate display joins happen client-side for now — no CQRS

The dashboard needs to show a Component's referenced Server and Databases as human labels (host,
`业务库 · Oracle · host:port/service`) rather than the bare IDs that ADR-0003 stores. We considered
full **CQRS** (separate read store + projections) and rejected it: there is no event log
(ADR-0004 chose a normalized relational schema), the write side is plain CRUD, and the scale is
dozens of entities and a handful of internal users — the consistency machinery would be pure
ceremony. Instead we treat the existing API DTOs (`EnvironmentDto`/`ComponentDto`) as **read models**:
ADR-0003's "reference by ID, never owned" constrains the *write aggregates*, while a read projection
is free to join across aggregates and denormalize for display. For now that join is done
**client-side** — the thin client fetches `GET /api/servers` + `GET /api/databases` once and resolves
references in its anti-corruption layer (least code, no API change, degrades to `#id` if inventory is
unreachable). The sanctioned escalation, when a second API consumer (web UI, CLI, reports) or read
scale appears, is to move the join **server-side into the read DTO** rather than re-implement it per
consumer — still without a separate store.

## Considered options

- **Client-side join (chosen, for now)** — endpoints already exist; the join lives in the client ACL.
- **Server-side read-model projection** — enrich `ComponentDto` via a server join; deferred until a
  second consumer or read-scale justifies it.
- **Full CQRS with a projected read store** — rejected: no event sourcing, trivial scale, CRUD writes.
