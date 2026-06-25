# Context Map

Bounded contexts for the test-environment dashboard product. Shared vocabulary lives in
[CONTEXT.md](./CONTEXT.md). Per-context `CONTEXT.md` files will be added under each context's code
directory as the redesign is laid out; this map records the intended boundaries first.

`zipr_tool` is a **separate product** (archive viewer) and an unrelated bounded context — out of
scope for this map.

## Contexts

Server-side (the new Spring Boot backend):

- **Environment Catalog** — *Core.* Owns the `Environment` aggregate and its `Component`s; CRUD and
  curation. The reason the product exists.
- **Version Collection** — *Core capability.* The scheduled/manual Collector, the Version probes, and
  the live Version / deploy-time / status data it produces.
- **Resource Inventory** — *Supporting.* Owns the shared `Server` and `Database` aggregates that
  Components reference by ID.
- **Access Brokering** — *Supporting.* Encrypted secret storage and on-demand credential delivery;
  connection descriptors for client tool launches.

Client-side (the thin `env_viewer` Flutter app):

- **Local Desktop Integration** — *Supporting.* The one genuinely client-side domain: launch the
  user's own SSH and DB tools, fed by brokered credentials.
- **Presentation** — the thin UI over the backend API, with an anti-corruption layer translating API
  DTOs into view models.

Generic / plumbing (server): persistence, scheduling, the auth seam, API transport, and a reserved
seam for future server-held log sessions.

## Relationships

- **Environment Catalog → Resource Inventory**: Components reference `Server`s and `Database`s by ID
  only; the Catalog never owns them.
- **Version Collection → Environment Catalog**: Collection writes live Version / deploy-time / status
  back onto Components; it reads Components to know what to probe.
- **Version Collection → Machine Access**: probes obtain live data via the shared Machine Access
  capability.
- **Access Brokering → Resource Inventory**: secrets attach to the `Server`/`Database` resources.
- **Presentation / Local Desktop Integration → backend**: the client is a downstream consumer of a
  published API; an anti-corruption layer keeps backend DTOs from leaking into the UI model.
- **Access Brokering → Local Desktop Integration**: the backend brokers credentials to the client on
  demand so the user can launch their own tools; the client holds no durable secrets.
